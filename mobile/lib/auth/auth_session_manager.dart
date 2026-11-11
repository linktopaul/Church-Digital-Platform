import 'dart:async';
import 'auth_provider.dart';
import 'auth_session.dart';
import 'oidc_configuration.dart';
import 'openiddict_auth_provider.dart';
import 'platform_secure_token_storage.dart';
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
  final bool _ownsProvider;
  final _sessionController = StreamController<AuthSession?>.broadcast();
  AuthSession? _currentSession;
  AuthSession? _pendingRotatedSession;
  Object _identity = Object();
  int _generation = 0;
  bool _disposed = false;
  bool _isInitialized = false;
  Future<AuthSession?>? _initializing;
  Future<AuthSession>? _refreshing;
  Future<void> _storageTail = Future<void>.value();

  AuthSessionManager({
    required AuthProvider provider,
    required SecureTokenStorage storage,
    bool ownsProvider = false,
  })  : _provider = provider,
        _storage = storage,
        _ownsProvider = ownsProvider;

  /// Creates the default production [AuthSessionManager] wired with
  /// [OpenIddictAuthProvider] and [PlatformSecureTokenStorage].
  factory AuthSessionManager.production({
    OidcConfiguration? configuration,
  }) {
    final resolvedConfig = configuration ?? OidcConfiguration.fromEnvironment();
    final storage = PlatformSecureTokenStorage(configuration: resolvedConfig);
    final provider = OpenIddictAuthProvider(
      configuration: resolvedConfig,
      storage: storage,
    );
    return AuthSessionManager(
      provider: provider,
      storage: storage,
      ownsProvider: true,
    );
  }

  /// Exposes the underlying [AuthProvider].
  AuthProvider get provider => _provider;

  /// Exposes the underlying [SecureTokenStorage].
  SecureTokenStorage get storage => _storage;

  /// Returns the active [OidcConfiguration] when backed by [OpenIddictAuthProvider].
  OidcConfiguration? get oidcConfiguration {
    final provider = _provider;
    if (provider is OpenIddictAuthProvider) {
      return provider.configuration;
    }
    return null;
  }

  /// Indicates whether the underlying provider supports interactive native OIDC sign-in.
  bool get supportsInteractiveSignIn => _provider is OpenIddictAuthProvider;

  /// Launches the interactive OIDC Authorization Code + PKCE sign-in flow
  /// when backed by [OpenIddictAuthProvider].
  Future<AuthSession> signInInteractively() {
    if (_disposed) {
      return Future.error(StateError('Authentication service is disposed'));
    }
    final provider = _provider;
    if (provider is OpenIddictAuthProvider) {
      return provider.authorizeAndSignIn(this);
    }
    return Future.error(
      UnsupportedError('Configured authentication provider does not support interactive OIDC sign-in'),
    );
  }

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

  int _invalidate({bool cancelPendingAuthorization = true}) {
    if (_disposed) throw StateError('Authentication service is disposed');
    _identity = Object();
    _currentSession = null;
    _pendingRotatedSession = null;
    _refreshing = null;
    _initializing = null;
    _isInitialized = true;
    if (cancelPendingAuthorization && _provider is CancelableAuthProvider) {
      (_provider as CancelableAuthProvider).cancelPendingAuthorization();
    }
    return ++_generation;
  }

  // Serialize storage mutations, including writes already awaiting the platform.
  // Newer writes/clears run last; failures do not poison the queue.
  Future<void> _persist(int generation, AuthSession? session, {bool signOutClear = false}) {
    final operation = _storageTail.then((_) async {
      // A sign-out clear remains ordered before later writes even when a new
      // sign-in merely starts. Otherwise a failed replacement could leave the
      // signed-out user's in-flight save on disk and skip remote revocation.
      if (!signOutClear) _check(generation);
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
    final generation = _invalidate(cancelPendingAuthorization: false);
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
      final pending = _pendingRotatedSession;
      if (pending != null) {
        if (!pending.isExpired) {
          await _apply(generation, pending);
          _pendingRotatedSession = null;
          return pending;
        }
        // If the unpersisted rotated session has since expired, persist it
        // first so storage and memory hold the rotated refresh token before
        // attempting another token exchange.
        await _persist(generation, pending);
        _check(generation);
        _currentSession = pending;
        _pendingRotatedSession = null;
      }
      // Never reload storage here: sign-out must not resurrect persisted state.
      final token = _currentSession?.refreshToken;
      if (token == null || token.isEmpty) {
        throw StateError('Cannot refresh session: no refresh token available');
      }
      final updated = await _provider.refreshSession(refreshToken: token);
      _check(generation);
      _pendingRotatedSession = updated;
      await _apply(generation, updated);
      _pendingRotatedSession = null;
      return updated;
    } on TerminalAuthException {
      _check(generation);
      _pendingRotatedSession = null;
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
    final token = (_pendingRotatedSession ?? _currentSession)?.refreshToken ??
        (_pendingRotatedSession ?? _currentSession)?.accessToken;
    final generation = _invalidate();
    _currentSession = null;
    _sessionController.add(null);
    // Clear before awaiting remote revocation; a later sign-in owns newer writes.
    await _persist(generation, null, signOutClear: true);
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
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _pendingRotatedSession = null;
    _identity = Object();
    if (_provider is CancelableAuthProvider) {
      (_provider as CancelableAuthProvider).cancelPendingAuthorization();
    }
    if (_ownsProvider && _provider is OpenIddictAuthProvider) {
      _provider.close();
    }
    _sessionController.close();
  }
}
