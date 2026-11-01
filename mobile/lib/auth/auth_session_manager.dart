import 'dart:async';
import 'auth_provider.dart';
import 'auth_session.dart';
import 'secure_token_storage.dart';

/// Defines the contract for managing authentication lifecycle within the Flutter app.
abstract class AuthService {
  /// Stream emitting active session changes (or null when unauthenticated).
  Stream<AuthSession?> get sessionStateStream;

  /// Retrieves the current active session.
  AuthSession? get currentSession;

  /// Loads and restores any persisted session from secure storage.
  Future<AuthSession?> initialize();

  /// Exchanges an authorization code and code verifier for an active session.
  Future<AuthSession> signInWithAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  });

  /// Explicitly sets an authenticated session (e.g. from token exchange).
  Future<void> setSession(AuthSession session);

  /// Attempts to refresh the current access token.
  Future<AuthSession> refresh();

  /// Signs the user out, revoking remote tokens and purging secure storage.
  Future<void> signOut();

  /// Disposes resources.
  void dispose();
}

/// Central manager orchestrating session persistence, background expiration,
/// and reactive session state notifications.
class AuthSessionManager implements AuthService {
  final AuthProvider _provider;
  final SecureTokenStorage _storage;
  final StreamController<AuthSession?> _sessionController =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _currentSession;
  Completer<AuthSession>? _activeRefreshCompleter;
  bool _isInitialized = false;

  AuthSessionManager({
    required AuthProvider provider,
    required SecureTokenStorage storage,
  })  : _provider = provider,
        _storage = storage;

  @override
  Stream<AuthSession?> get sessionStateStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  bool get isAuthenticated => _currentSession != null && !_currentSession!.isExpired;

  @override
  Future<AuthSession?> initialize() async {
    if (_isInitialized) return _currentSession;

    final stored = await _storage.getSession();
    if (stored != null) {
      if (!stored.isExpired) {
        _currentSession = stored;
        _sessionController.add(_currentSession);
      } else if (stored.refreshToken != null && stored.refreshToken!.isNotEmpty) {
        // Attempt automatic refresh on startup if refresh token is present
        try {
          final refreshed = await _provider.refreshSession(
            refreshToken: stored.refreshToken!,
          );
          _currentSession = refreshed;
          await _storage.saveSession(refreshed);
          _sessionController.add(_currentSession);
        } catch (_) {
          // Refresh failed - purge invalid credentials
          await _storage.clearSession();
          _currentSession = null;
          _sessionController.add(null);
        }
      } else {
        await _storage.clearSession();
        _currentSession = null;
        _sessionController.add(null);
      }
    } else {
      _currentSession = null;
      _sessionController.add(null);
    }

    _isInitialized = true;
    return _currentSession;
  }

  @override
  Future<AuthSession> signInWithAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final session = await _provider.exchangeAuthorizationCode(
      code: code,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
    );

    _currentSession = session;
    await _storage.saveSession(session);
    _sessionController.add(session);
    return session;
  }

  @override
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    await _storage.saveSession(session);
    _sessionController.add(session);
  }

  @override
  Future<AuthSession> refresh() async {
    // If a refresh is already in flight, reuse the same future to avoid thundering herd
    if (_activeRefreshCompleter != null) {
      return _activeRefreshCompleter!.future;
    }

    final completer = Completer<AuthSession>();
    // Prevent unhandled async errors on the internal completer when no concurrent caller is listening
    completer.future.ignore();
    _activeRefreshCompleter = completer;

    try {
      final session = _currentSession ?? await _storage.getSession();
      final refreshToken = session?.refreshToken;

      if (refreshToken == null || refreshToken.isEmpty) {
        throw StateError('Cannot refresh session: no refresh token available');
      }

      final updatedSession = await _provider.refreshSession(
        refreshToken: refreshToken,
      );

      _currentSession = updatedSession;
      await _storage.saveSession(updatedSession);
      _sessionController.add(updatedSession);

      completer.complete(updatedSession);
      return updatedSession;
    } catch (e) {
      // Expiration / refresh failure: clear invalid credentials and notify
      await _storage.clearSession();
      _currentSession = null;
      _sessionController.add(null);

      completer.completeError(e);
      rethrow;
    } finally {
      _activeRefreshCompleter = null;
    }
  }

  @override
  Future<void> signOut() async {
    final tokenToRevoke = _currentSession?.refreshToken ?? _currentSession?.accessToken;
    if (tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
      try {
        await _provider.revokeSession(token: tokenToRevoke);
      } catch (_) {
        // Continue clearing local state even if remote revocation fails
      }
    }

    await _storage.clearSession();
    _currentSession = null;
    _sessionController.add(null);
  }

  @override
  void dispose() {
    _sessionController.close();
  }
}
