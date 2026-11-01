import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/secure_token_storage.dart';

/// In-memory implementation of [SecureTokenStorage] intended for unit tests,
/// mocks, and headless/mock environments where platform secure storage is absent.
class InMemorySecureTokenStorage implements SecureTokenStorage {
  AuthSession? _currentSession;

  InMemorySecureTokenStorage([AuthSession? initialSession])
      : _currentSession = initialSession;

  @override
  Future<void> saveSession(AuthSession session) async {
    _currentSession = session;
  }

  @override
  Future<AuthSession?> getSession() async {
    return _currentSession;
  }

  @override
  Future<void> clearSession() async {
    _currentSession = null;
  }

  @override
  Future<bool> hasValidSession() async {
    return _currentSession != null && !_currentSession!.isExpired;
  }
}
