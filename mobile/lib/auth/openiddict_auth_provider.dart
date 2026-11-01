import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'auth_provider.dart';
import 'auth_session.dart';
import 'auth_session_manager.dart';
import 'oidc_configuration.dart';
import 'secure_token_storage.dart';

/// Sanitized transport/protocol failure. Provider bodies/tokens are never logged.
class OidcRequestException implements Exception {
  final int statusCode;
  const OidcRequestException(this.statusCode);
}

/// Public native OIDC client. Browser, state, nonce and PKCE are managed by
/// AppAuth; no password grant, client secret, WebView or custom token format.
class OpenIddictAuthProvider implements AuthProvider {
  final OidcConfiguration configuration;
  final SecureTokenStorage _storage;
  final FlutterAppAuth _appAuth;
  final http.Client _http;
  Future<Map<String, dynamic>>? _discovery;
  AuthorizationResponse? _pending;
  DateTime? _pendingAt;
  int _authorizationAttempt = 0;
  bool _closed = false;

  OpenIddictAuthProvider({
    required this.configuration,
    required SecureTokenStorage storage,
    FlutterAppAuth appAuth = const FlutterAppAuth(),
    http.Client? httpClient,
  }) : _storage = storage, _appAuth = appAuth, _http = httpClient ?? http.Client();

  void _checkPlatform() {
    if (_closed) throw StateError('OIDC provider is closed');
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('Native OIDC supports Android and iOS only');
    }
  }

  Future<http.Response> _send(http.Request request) async {
    // Never forward a bearer token, code or refresh token through a redirect.
    request.followRedirects = false;
    return http.Response.fromStream(await _http.send(request));
  }

  Future<Map<String, dynamic>> _metadata() {
    _checkPlatform();
    return _discovery ??= _loadMetadata();
  }

  Future<Map<String, dynamic>> _loadMetadata() async {
    try {
      final response = await _send(http.Request('GET', configuration.discoveryUri));
      if (response.statusCode != 200) throw OidcRequestException(response.statusCode);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['issuer'] != configuration.issuer.toString() ||
          data['code_challenge_methods_supported'] is! List ||
          !(data['code_challenge_methods_supported'] as List).contains('S256')) {
        throw const FormatException('Discovery issuer or PKCE S256 support mismatch');
      }
      // OpenIddict is served by the configured issuer. Fail closed if discovery
      // points credential-bearing traffic at another origin or insecure URL.
      for (final key in ['authorization_endpoint', 'token_endpoint', 'userinfo_endpoint', 'revocation_endpoint']) {
        _endpoint(data, key);
      }
      return data;
    } catch (_) {
      _discovery = null; // A temporary discovery failure must be retryable.
      rethrow;
    }
  }

  Uri _endpoint(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String) throw FormatException('Discovery is missing $key');
    final uri = Uri.parse(value);
    OidcConfiguration.requireHttps(uri);
    if (uri.origin != configuration.issuer.origin) {
      throw const FormatException('Discovered endpoint must share the configured issuer origin');
    }
    return uri;
  }

  /// Safe navigation integration seam: lifecycle changes while the native
  /// browser is open invalidate the eventual result before code exchange.
  Future<AuthSession> authorizeAndSignIn(AuthService manager) async {
    final identity = manager.sessionIdentity;
    final response = await authorize();
    if (!identical(identity, manager.sessionIdentity)) {
      _pending = null;
      throw StateError('Session changed while authorization was pending');
    }
    return manager.signInWithAuthorizationCode(
      code: response.authorizationCode!, codeVerifier: response.codeVerifier!,
      redirectUri: configuration.redirectUri.toString(),
    );
  }

  /// Advanced split-flow callers must also guard their session lifecycle.
  /// Only a matching, unexpired AppAuth-produced response may be exchanged.
  Future<AuthorizationResponse> authorize() async {
    _checkPlatform();
    final attempt = ++_authorizationAttempt;
    _pending = null;
    await _metadata();
    final response = await _appAuth.authorize(AuthorizationRequest(
      configuration.clientId, configuration.redirectUri.toString(),
      discoveryUrl: configuration.discoveryUri.toString(), scopes: configuration.scopes,
    ));
    if (_closed || attempt != _authorizationAttempt) {
      throw StateError('Authorization was superseded');
    }
    if (response.authorizationCode?.isNotEmpty != true ||
        response.codeVerifier?.isNotEmpty != true || response.nonce?.isNotEmpty != true) {
      throw const FormatException('Native authorization response is incomplete');
    }
    _pending = response;
    _pendingAt = DateTime.now();
    return response;
  }

  @override
  Future<AuthSession> exchangeAuthorizationCode({required String code,
    required String codeVerifier, required String redirectUri}) async {
    _checkPlatform();
    final pending = _pending;
    _pending = null; // Single use, including failures and mismatched callbacks.
    if (pending == null || pending.authorizationCode != code ||
        pending.codeVerifier != codeVerifier ||
        redirectUri != configuration.redirectUri.toString() ||
        _pendingAt == null || DateTime.now().difference(_pendingAt!) > const Duration(minutes: 5)) {
      throw StateError('A matching native PKCE authorization is required');
    }
    final result = await _appAuth.token(TokenRequest(
      configuration.clientId, redirectUri,
      discoveryUrl: configuration.discoveryUri.toString(), scopes: configuration.scopes,
      authorizationCode: code, codeVerifier: codeVerifier, nonce: pending.nonce,
    ));
    final token = _accessToken(result);
    final claims = await fetchUserInfo(accessToken: token);
    // AppAuth validates the native OIDC exchange; enforce the OIDC UserInfo
    // subject binding too. No JWT claim is used as a local authorization grant.
    final idToken = result.idToken;
    if (idToken == null || _idTokenSubject(idToken) != claims['sub']) {
      throw const FormatException('UserInfo subject does not match the OIDC exchange');
    }
    final roles = claims[configuration.rolesClaim];
    if (roles is! List || roles.any((r) => r is! String || r.isEmpty)) {
      throw const FormatException('Configured roles claim must be a string array');
    }
    return AuthSession(
      accessToken: token, refreshToken: result.refreshToken,
      userId: _claim(claims, configuration.memberIdClaim),
      tenantId: _claim(claims, configuration.tenantIdClaim),
      roles: List<String>.from(roles), expiresAt: result.accessTokenExpirationDateTime!,
      email: claims['email'] is String ? claims['email'] as String : null,
      displayName: claims['name'] is String ? claims['name'] as String : null,
    );
  }

  String _claim(Map<String, dynamic> claims, String key) {
    final value = claims[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('UserInfo is missing configured claim $key');
    }
    return value;
  }

  String _idTokenSubject(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('Malformed native ID token');
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    return _claim(payload, 'sub');
  }

  String _accessToken(TokenResponse response) {
    if (response.accessToken?.isNotEmpty != true ||
        response.tokenType?.toLowerCase() != 'bearer' ||
        response.accessTokenExpirationDateTime == null ||
        !response.accessTokenExpirationDateTime!.isAfter(DateTime.now())) {
      throw const FormatException('Native token response is incomplete or expired');
    }
    return response.accessToken!;
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    _checkPlatform();
    // Read the same secure record used by the manager. Preserve the established
    // identity snapshot without another network call after refresh rotation:
    // a transient UserInfo failure must not discard the newly rotated token.
    final previous = await _storage.getSession();
    if (previous == null || previous.refreshToken != refreshToken || refreshToken.isEmpty) {
      throw StateError('Refresh must belong to the persisted native session');
    }
    await _metadata();
    try {
      final result = await _appAuth.token(TokenRequest(
        configuration.clientId, configuration.redirectUri.toString(),
        discoveryUrl: configuration.discoveryUri.toString(), scopes: configuration.scopes,
        refreshToken: refreshToken,
      ));
      return previous.copyWith(
        accessToken: _accessToken(result), expiresAt: result.accessTokenExpirationDateTime,
        refreshToken: result.refreshToken?.isNotEmpty == true ? result.refreshToken : refreshToken,
      );
    } on FlutterAppAuthPlatformException catch (error) {
      // Only a confirmed token rejection clears credentials. Client config,
      // connectivity, discovery, cancellation and 5xx failures are not rejection.
      if (error.platformErrorDetails.error == FlutterAppAuthOAuthError.invalidGrant) {
        throw const TerminalAuthException();
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchUserInfo({required String accessToken}) async {
    final metadata = await _metadata();
    final request = http.Request('GET', _endpoint(metadata, 'userinfo_endpoint'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Accept'] = 'application/json';
    final response = await _send(request);
    if (response.statusCode != 200) throw OidcRequestException(response.statusCode);
    final claims = jsonDecode(response.body) as Map<String, dynamic>;
    _claim(claims, 'sub');
    return claims;
  }

  @override
  Future<void> revokeSession({required String token}) async {
    ++_authorizationAttempt;
    _pending = null;
    final metadata = await _metadata();
    final request = http.Request('POST', _endpoint(metadata, 'revocation_endpoint'));
    request.bodyFields = {'client_id': configuration.clientId, 'token': token};
    final response = await _send(request);
    if (response.statusCode != 200) throw OidcRequestException(response.statusCode);
  }

  void close() {
    _closed = true;
    ++_authorizationAttempt;
    _pending = null;
    _http.close();
  }
}
