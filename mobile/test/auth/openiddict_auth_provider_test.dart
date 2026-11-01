import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/auth/oidc_configuration.dart';
import 'package:church_digital_platform_mobile/auth/openiddict_auth_provider.dart';
import '../support/in_memory_secure_token_storage.dart';

// Native calls are fixtures. These tests establish adapter behavior, not native
// PKCE, signature validation, browser redirects or device keychain behavior.
class NativeFixture extends FlutterAppAuth {
  AuthorizationRequest? authorizationRequest;
  TokenRequest? tokenRequest;
  int tokenCalls = 0;
  Future<AuthorizationResponse> Function()? authorizeHandler;
  Future<TokenResponse> Function()? tokenHandler;
  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) async {
    authorizationRequest = request;
    return authorizeHandler == null ? authorization : authorizeHandler!();
  }
  @override
  Future<TokenResponse> token(TokenRequest request) async {
    tokenCalls++;
    tokenRequest = request;
    return tokenHandler == null ? tokenResult() : tokenHandler!();
  }
  TokenResponse tokenResult() => TokenResponse('access', 'rotated',
    DateTime.now().add(const Duration(hours: 1)), idToken('subject'), 'Bearer', null, null);
}
const authorization = AuthorizationResponse(authorizationCode: 'code', codeVerifier: 'native-verifier', nonce: 'native-nonce');
String idToken(String subject) => '${base64Url.encode(utf8.encode('{"alg":"fixture"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': subject})))}.fixture';
OidcConfiguration config() => OidcConfiguration(issuer: 'https://id.example.test',
  clientId: 'fixture-client', redirectUri: 'test.church:/callback',
  scopes: ['openid', 'offline_access', 'fixture-api'], memberIdClaim: 'member_id', tenantIdClaim: 'tenant_id', rolesClaim: 'roles');
Map<String, dynamic> metadata() => {
  'issuer': 'https://id.example.test', 'code_challenge_methods_supported': ['S256'],
  'authorization_endpoint': 'https://id.example.test/discovered/authorize',
  'token_endpoint': 'https://id.example.test/discovered/token',
  'userinfo_endpoint': 'https://id.example.test/discovered/userinfo',
  'revocation_endpoint': 'https://id.example.test/discovered/revoke',
};
Map<String, dynamic> claims() => {'sub': 'subject', 'member_id': 'member', 'tenant_id': 'tenant', 'roles': ['Member']};
AuthSession previous() => AuthSession(accessToken: 'old-access', refreshToken: 'old-refresh', userId: 'member', tenantId: 'tenant', roles: ['Member'], expiresAt: DateTime.now().subtract(const Duration(hours: 1)));

void main() {
  setUp(() { debugDefaultTargetPlatformOverride = TargetPlatform.android; });
  tearDown(() { debugDefaultTargetPlatformOverride = null; });
  late NativeFixture native;
  late InMemorySecureTokenStorage storage;
  late OpenIddictAuthProvider provider;
  late List<http.Request> requests;
  late Map<String, dynamic> document;
  late Map<String, dynamic> userInfo;
  setUp(() {
    native = NativeFixture();
    storage = InMemorySecureTokenStorage(previous());
    requests = [];
    document = metadata();
    userInfo = claims();
    provider = OpenIddictAuthProvider(configuration: config(), storage: storage, appAuth: native,
      httpClient: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, isFalse);
        if (request.url.path.endsWith('openid-configuration')) return http.Response(jsonEncode(document), 200);
        if (request.url.path.endsWith('userinfo')) return http.Response(jsonEncode(userInfo), 200);
        if (request.url.path.endsWith('revoke')) return http.Response('', 200);
        throw StateError('Guessed endpoint or unexpected network request');
      }));
  });
  tearDown(() { provider.close(); });

  Future<AuthSession> exchange() => provider.exchangeAuthorizationCode(code: 'code', codeVerifier: 'native-verifier', redirectUri: config().redirectUri.toString());

  test('native authorize and exchange preserve discovery, PKCE verifier and nonce', () async {
    await provider.authorize();
    final result = await exchange();
    final auth = native.authorizationRequest!;
    expect(auth.clientId, 'fixture-client');
    expect(auth.discoveryUrl, config().discoveryUri.toString());
    expect(auth.serviceConfiguration, isNull);
    expect(auth.allowInsecureConnections, isFalse);
    expect(auth.scopes, config().scopes);
    final request = native.tokenRequest!;
    expect(request.authorizationCode, 'code');
    expect(request.codeVerifier, 'native-verifier');
    expect(request.nonce, 'native-nonce');
    expect(request.clientSecret, isNull);
    expect(request.refreshToken, isNull);
    expect(result.userId, 'member');
    expect(result.tenantId, 'tenant');
    expect(result.roles, ['Member']);
    expect(requests.last.headers['Authorization'], 'Bearer access');
    await expectLater(exchange(), throwsStateError); // single-use callback
  });
  test('external or mismatched callbacks never reach the native token endpoint', () async {
    await expectLater(exchange(), throwsStateError);
    await provider.authorize();
    await expectLater(provider.exchangeAuthorizationCode(code: 'code', codeVerifier: 'different', redirectUri: config().redirectUri.toString()), throwsStateError);
    expect(native.tokenCalls, 0);
  });
  for (final corruption in ['issuer', 'pkce', 'cross-origin', 'missing-endpoint']) {
    test('discovery rejects $corruption before opening a browser', () async {
      switch (corruption) {
        case 'issuer': document['issuer'] = 'https://other.example.test';
        case 'pkce': document['code_challenge_methods_supported'] = ['plain'];
        case 'cross-origin': document['token_endpoint'] = 'https://other.example.test/token';
        case 'missing-endpoint': document.remove('userinfo_endpoint');
      }
      await expectLater(provider.authorize(), throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())));
      expect(native.authorizationRequest, isNull);
    });
  }
  test('temporary discovery failure can be retried', () async {
    var calls = 0;
    final retryProvider = OpenIddictAuthProvider(configuration: config(), storage: storage, appAuth: native,
      httpClient: MockClient((_) async => ++calls == 1 ? http.Response('', 503) : http.Response(jsonEncode(metadata()), 200)));
    addTearDown(retryProvider.close);
    await expectLater(retryProvider.authorize(), throwsA(isA<OidcRequestException>()));
    await retryProvider.authorize();
    expect(calls, 2);
  });
  test('refresh retains identity and rotated credentials with no post-rotation UserInfo request', () async {
    final result = await provider.refreshSession(refreshToken: 'old-refresh');
    expect(native.tokenRequest!.refreshToken, 'old-refresh');
    expect(native.tokenRequest!.authorizationCode, isNull);
    expect(result.refreshToken, 'rotated');
    expect(result.userId, 'member');
    expect(result.tenantId, 'tenant');
    expect(requests.length, 1); // only discovery
  });
  test('omitted refresh token preserves the previous token', () async {
    native.tokenHandler = () async => TokenResponse('access', null, DateTime.now().add(const Duration(hours: 1)), null, 'Bearer', null, null);
    expect((await provider.refreshSession(refreshToken: 'old-refresh')).refreshToken, 'old-refresh');
  });
  for (final error in ['invalid_grant', 'invalid_client', 'temporarily_unavailable', 'server_error', 'network_error']) {
    test('native refresh maps only invalid_grant to terminal rejection: $error', () async {
      final failure = FlutterAppAuthPlatformException(code: 'token_failed', platformErrorDetails: FlutterAppAuthPlatformErrorDetails(error: error));
      native.tokenHandler = () async { throw failure; };
      await expectLater(provider.refreshSession(refreshToken: 'old-refresh'),
        throwsA(error == 'invalid_grant' ? isA<TerminalAuthException>() : same(failure)));
      expect((await storage.getSession())!.refreshToken, 'old-refresh'); // manager owns clearing
    });
  }
  test('a refresh token from another stored session is rejected before native work', () async {
    await expectLater(provider.refreshSession(refreshToken: 'another-account'), throwsStateError);
    expect(native.tokenCalls, 0);
    expect(requests, isEmpty);
  });
  for (final malformed in ['subject', 'member', 'tenant', 'roles']) {
    test('UserInfo $malformed mismatch does not construct a session', () async {
      switch (malformed) {
        case 'subject': userInfo['sub'] = 'another-subject';
        case 'member': userInfo.remove('member_id');
        case 'tenant': userInfo.remove('tenant_id');
        case 'roles': userInfo['roles'] = 'Admin';
      }
      await provider.authorize();
      await expectLater(exchange(), throwsFormatException);
    });
  }
  test('revocation uses discovered URL and public client only without redirects', () async {
    await provider.revokeSession(token: 'fictional-revocation');
    final request = requests.last;
    expect(request.url.toString(), document['revocation_endpoint']);
    expect(request.method, 'POST');
    expect(request.bodyFields, {'client_id': 'fixture-client', 'token': 'fictional-revocation'});
    expect(request.headers.containsKey('Authorization'), isFalse);
  });
  test('browser cancellation propagates without exchanging or deleting credentials', () async {
    final cancellation = FlutterAppAuthUserCancelledException(code: 'cancelled', platformErrorDetails: FlutterAppAuthPlatformErrorDetails());
    native.authorizeHandler = () async { throw cancellation; };
    await expectLater(provider.authorize(), throwsA(same(cancellation)));
    expect(native.tokenCalls, 0);
    expect(await storage.getSession(), isNotNull);
  });
  test('signout during native browser flow prevents late exchange', () async {
    final entered = Completer<void>();
    final result = Completer<AuthorizationResponse>();
    native.authorizeHandler = () { entered.complete(); return result.future; };
    final manager = AuthSessionManager(provider: provider, storage: storage);
    addTearDown(manager.dispose);
    await manager.setSession(previous());
    final pending = provider.authorizeAndSignIn(manager);
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    await manager.signOut();
    result.complete(authorization);
    await rejected;
    expect(native.tokenCalls, 0);
    expect(await storage.getSession(), isNull);
  });
}
