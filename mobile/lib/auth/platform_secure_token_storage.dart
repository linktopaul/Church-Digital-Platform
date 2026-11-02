import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_session.dart';
import 'oidc_configuration.dart';
import 'secure_token_storage.dart';

/// Android Keystore-backed encryption / iOS device-local Keychain only.
/// Platform/keychain errors propagate; there is no memory/plaintext fallback.
class PlatformSecureTokenStorage implements SecureTokenStorage {
  final FlutterSecureStorage _storage;
  final String _key;

  PlatformSecureTokenStorage({
    required OidcConfiguration configuration,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(
         aOptions: AndroidOptions(resetOnError: false),
         iOptions: IOSOptions(
           accessibility: KeychainAccessibility.unlocked_this_device,
           synchronizable: false,
         ),
       ),
       _key = 'church.auth.v1.${base64Url.encode(utf8.encode(jsonEncode([
         configuration.issuer.toString(), configuration.clientId,
         configuration.redirectUri.toString(),
       ])))}';

  void _checkPlatform() {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('Native credential storage supports Android and iOS only');
    }
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    _checkPlatform();
    await _storage.write(key: _key, value: session.serialize());
  }

  @override
  Future<AuthSession?> getSession() async {
    _checkPlatform();
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    // Reject corrupt/partial records instead of constructing an empty identity.
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        ['accessToken', 'userId', 'tenantId', 'expiresAt'].any((key) =>
          decoded[key] is! String || (decoded[key] as String).isEmpty) ||
        DateTime.tryParse(decoded['expiresAt'] as String) == null ||
        decoded['roles'] is! List ||
        (decoded['roles'] as List).any((role) => role is! String) ||
        (decoded['refreshToken'] != null && decoded['refreshToken'] is! String)) {
      throw const FormatException('Invalid stored authentication record');
    }
    return AuthSession.fromJson(decoded);
  }

  @override
  Future<void> clearSession() async {
    _checkPlatform();
    // Never deleteAll: other application secrets and issuer registrations survive.
    await _storage.delete(key: _key);
  }

  @override
  Future<bool> hasValidSession() async {
    final session = await getSession();
    return session != null && !session.isExpired;
  }
}
