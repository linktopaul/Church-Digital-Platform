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

  /// Changes on sign-out/replacement, but remains stable during token refresh.
  /// Implementations must invalidate this identity before awaiting external work.
  Object? get sessionIdentity;

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

/// Coordinates provider work with a lifecycle generation and ordered storage
/// writes. A superseded operation can neither emit nor overwrite newer state.
class AuthSessionManager implements AuthService {
  final AuthProvider _provider;
  final SecureTokenStorage _storage;
  final _sessionController = StreamController<AuthSession?>.broadcast();
  AuthSession? _currentSession;
  Object _identity = Object();
  int _generation = 0;
  bool _disposed = false;
  bool _isInitialized = false;
  Future<AuthSession?>? _initializing;
  Future<AuthSession>? _refreshing;
  Future<void> _storageTail = Future<void>.value();

  AuthSessionManager({required AuthProvider provider, required SecureTokenStorage storage})
      : _provider = provider, _storage = storage;

  @override
  Stream<AuthSession?> get sessionStateStream => _sessionController.stream;
  @override
  AuthSession? get currentSession => _currentSession;
  @override
  Object get sessionIdentity => _identity;
  bool get isAuthenticated => _currentSession != null && !_currentSession!.isExpired;

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Authentication operation was superseded');
    }
  }

  int _invalidate() {
    if (_disposed) throw StateError('Authentication service is disposed');
    _identity = Object();
    _currentSession = null;
    _refreshing = null;
    _initializing = null;
    _isInitialized = true;
    return ++_generation;
  }

  // Serialize storage mutations, including writes already awaiting the platform.
  // Newer writes/clears run last; failures do not poison the queue.
  Future<void> _persist(int generation, AuthSession? session) {
    final operation = _storageTail.then((_) async {
      _check(generation);
      if (session == null) {
        await _storage.clearSession();
      } else {
        await _storage.saveSession(session);
      }
    });
    _storageTail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> _apply(int generation, AuthSession session) async {
    _check(generation);
    await _persist(generation, session);
    _check(generation);
    _currentSession = session;
    _sessionController.add(session);
  }

  @override
  Future<AuthSession?> initialize() {
    if (_isInitialized) return Future.value(_currentSession);
    return _initializing ??= _initialize(_generation);
  }

  Future<AuthSession?> _initialize(int generation) async {
    try {
      await _storageTail;
      final stored = await _storage.getSession();
      _check(generation);
      if (stored == null) {
        _sessionController.add(null);
      } else if (!stored.isExpired) {
        _currentSession = stored;
        _sessionController.add(stored);
      } else if (stored.refreshToken?.isNotEmpty == true) {
        // Keep expired credentials available for an explicit retry when offline.
        _currentSession = stored;
        try {
          await refresh();
        } on TerminalAuthException {
          // refresh already cleared the rejected credentials.
        } catch (_) {
          _check(generation);
          // Transient failures retain credentials, but isAuthenticated stays false.
        }
      } else {
        await _persist(generation, null);
        _check(generation);
        _currentSession = null;
        _sessionController.add(null);
      }
      _check(generation);
      _isInitialized = true;
      return _currentSession;
    } finally {
      if (generation == _generation) _initializing = null;
    }
  }

  @override
  Future<AuthSession> signInWithAuthorizationCode({
    required String code, required String codeVerifier, required String redirectUri,
  }) async {
    final generation = _invalidate();
    final session = await _provider.exchangeAuthorizationCode(
      code: code, codeVerifier: codeVerifier, redirectUri: redirectUri,
    );
    await _apply(generation, session);
    return session;
  }

  @override
  Future<void> setSession(AuthSession session) {
    final generation = _invalidate();
    return _apply(generation, session);
  }

  @override
  Future<AuthSession> refresh() {
    if (_disposed) return Future.error(StateError('Authentication service is disposed'));
    final generation = _generation;
    return _refreshing ??= Future.microtask(() => _refresh(generation));
  }

  Future<AuthSession> _refresh(int generation) async {
    try {
      _check(generation);
      // Never reload storage here: sign-out must not resurrect persisted state.
      final token = _currentSession?.refreshToken;
      if (token == null || token.isEmpty) {
        throw StateError('Cannot refresh session: no refresh token available');
      }
      final updated = await _provider.refreshSession(refreshToken: token);
      await _apply(generation, updated);
      return updated;
    } on TerminalAuthException {
      _check(generation);
      await _persist(generation, null);
      _check(generation);
      _currentSession = null;
      _identity = Object();
      _sessionController.add(null);
      rethrow;
    } finally {
      if (generation == _generation) _refreshing = null;
    }
  }

  @override
  Future<void> signOut() async {
    final token = _currentSession?.refreshToken ?? _currentSession?.accessToken;
    final generation = _invalidate();
    _currentSession = null;
    _sessionController.add(null);
    // Clear before awaiting remote revocation; a later sign-in owns newer writes.
    await _persist(generation, null);
    if (token != null && token.isNotEmpty) {
      try {
        await _provider.revokeSession(token: token);
      } catch (_) {
        // Local sign-out succeeds even when revocation is unreachable.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _identity = Object();
    _sessionController.close();
  }
}
