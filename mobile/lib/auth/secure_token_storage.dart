import 'dart:async';
import 'auth_session.dart';

/// Contract for persisting authentication tokens and session data.
///
/// In accordance with project security requirements and AGENTS.md guidelines,
/// credentials and access tokens must reside only in platform-secure storage
/// (e.g. Keychain on iOS, KeyStore/EncryptedSharedPreferences on Android).
/// Plaintext SharedPreferences must never be used for raw tokens.
abstract class SecureTokenStorage {
  /// Persists the active session.
  Future<void> saveSession(AuthSession session);

  /// Retrieves the persisted session if available.
  Future<AuthSession?> getSession();

  /// Clears the stored session on sign-out or revocation.
  Future<void> clearSession();

  /// Quick check whether a non-empty session exists.
  Future<bool> hasValidSession();
}

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
