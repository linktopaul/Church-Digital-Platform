import 'dart:async';
import 'auth_provider.dart';
import 'auth_session.dart';
import 'secure_token_storage.dart';

/// Indicates that an authentication failure is terminal (e.g. invalid/revoked credentials).
/// Transient failures (network timeout, socket exception, 5xx server error) do not
/// implement this interface and should preserve stored credentials.
class TerminalAuthException implements Exception {
  final String message;
  const TerminalAuthException(this.message);

  @override
  String toString() => 'TerminalAuthException: $message';
}

/// Defines the contract for managing authentication lifecycle within the Flutter app.
abstract class AuthService {
  /// Stream emitting active session changes (or null when unauthenticated).
  Stream<AuthSession?> get sessionStateStream;

  /// Retrieves the current active session.
  AuthSession? get currentSession;

  /// Monotonically increasing generation number tracking the active session identity.
  int get sessionGeneration;

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
  int _sessionGeneration = 0;

  AuthSessionManager({
    required AuthProvider provider,
    required SecureTokenStorage storage,
  })  : _provider = provider,
        _storage = storage;

  @override
  Stream<AuthSession?> get sessionStateStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  int get sessionGeneration => _sessionGeneration;

  bool get isAuthenticated => _currentSession != null && !_currentSession!.isExpired;

  bool _isTerminalAuthError(Object error) {
    if (error is TerminalAuthException) return true;
    final msg = error.toString().toLowerCase();
    // Transient socket/network exceptions
    if (msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('connection refused') ||
        msg.contains('clientexception') ||
        msg.contains('network is unreachable')) {
      return false;
    }
    return msg.contains('invalid') ||
        msg.contains('revoked') ||
        msg.contains('expired') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden') ||
        msg.contains('auth');
  }

  @override
  Future<AuthSession?> initialize() async {
    if (_isInitialized) return _currentSession;

    final stored = await _storage.getSession();
    if (stored != null) {
      if (!stored.isExpired) {
        _currentSession = stored;
        _sessionGeneration++;
        _sessionController.add(_currentSession);
      } else if (stored.refreshToken != null && stored.refreshToken!.isNotEmpty) {
        // Attempt automatic refresh on startup if refresh token is present
        try {
          final refreshed = await _provider.refreshSession(
            refreshToken: stored.refreshToken!,
          );
          _currentSession = refreshed;
          _sessionGeneration++;
          await _storage.saveSession(refreshed);
          _sessionController.add(_currentSession);
        } catch (e) {
          if (_isTerminalAuthError(e)) {
            // Terminal failure - purge invalid credentials
            await _storage.clearSession();
            _currentSession = null;
            _sessionGeneration++;
            _sessionController.add(null);
          } else {
            // Transient failure (network offline, server 5xx) - keep stored session for later retry
            _currentSession = stored;
            _sessionGeneration++;
            _sessionController.add(stored);
          }
        }
      } else {
        await _storage.clearSession();
        _currentSession = null;
        _sessionGeneration++;
        _sessionController.add(null);
      }
    } else {
      _currentSession = null;
      _sessionGeneration++;
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

    _sessionGeneration++;
    _currentSession = session;
    await _storage.saveSession(session);
    _sessionController.add(session);
    return session;
  }

  @override
  Future<void> setSession(AuthSession session) async {
    _sessionGeneration++;
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

    final originatingGeneration = _sessionGeneration;
    final originatingUserId = _currentSession?.userId;
    final originatingTenantId = _currentSession?.tenantId;

    final completer = Completer<AuthSession>();
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

      // Verify that the active session has not changed or been signed out during refresh
      if (_sessionGeneration == originatingGeneration && _currentSession != null) {
        final preservedSession = updatedSession.copyWith(
          userId: updatedSession.userId.isNotEmpty ? updatedSession.userId : originatingUserId,
          tenantId: updatedSession.tenantId.isNotEmpty ? updatedSession.tenantId : originatingTenantId,
        );
        _currentSession = preservedSession;
        await _storage.saveSession(preservedSession);
        _sessionController.add(preservedSession);
      }

      completer.complete(updatedSession);
      return updatedSession;
    } catch (e) {
      // Check if session changed while awaiting provider
      if (_sessionGeneration == originatingGeneration) {
        if (_isTerminalAuthError(e)) {
          // Terminal refresh failure: clear credentials and notify
          await _storage.clearSession();
          _currentSession = null;
          _sessionGeneration++;
          _sessionController.add(null);
        }
        // If transient error, do not purge storage
      }

      completer.completeError(e);
      rethrow;
    } finally {
      _activeRefreshCompleter = null;
    }
  }

  @override
  Future<void> signOut() async {
    // Increment generation immediately so in-flight refreshes are discarded
    _sessionGeneration++;

    final tokenToRevoke = _currentSession?.refreshToken ?? _currentSession?.accessToken;

    // Finding: Clear local session state and persisted credentials before awaiting best-effort remote revocation,
    // so an unavailable identity provider cannot block local logout.
    _currentSession = null;
    _sessionController.add(null);
    await _storage.clearSession();

    if (tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
      try {
        await _provider.revokeSession(token: tokenToRevoke);
      } catch (_) {
        // Best-effort remote revocation
      }
    }
  }

  @override
  void dispose() {
    _sessionController.close();
  }
}
