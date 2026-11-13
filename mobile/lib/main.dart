import 'dart:async';
import 'package:flutter/material.dart';

import 'auth/auth_provider.dart';
import 'auth/auth_session.dart';
import 'auth/auth_session_manager.dart';
import 'auth/oidc_configuration.dart';
import 'auth/openiddict_auth_provider.dart';
import 'network/authenticated_http_client.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/prayer_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/worship_screen.dart';
import 'services/announcement_api_client.dart';
import 'services/celebration_api_client.dart';
import 'services/fellowship_api_client.dart';
import 'services/member_api_client.dart';
import 'services/offering_api_client.dart';
import 'services/prayer_api_client.dart';
import 'services/worship_api_client.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChurchMobileApp());
}

class ChurchMobileApp extends StatelessWidget {
  final AuthService? authService;
  final OidcConfiguration? oidcConfiguration;
  final String? apiBaseUrl;
  final Future<void> Function(AuthService authService)? onSignIn;

  const ChurchMobileApp({
    super.key,
    this.authService,
    this.oidcConfiguration,
    this.apiBaseUrl,
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Church Digital Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MainNavigationScreen(
        authService: authService,
        oidcConfiguration: oidcConfiguration,
        apiBaseUrl: apiBaseUrl,
        onSignIn: onSignIn,
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final AuthService? authService;
  final OidcConfiguration? oidcConfiguration;
  final String? apiBaseUrl;
  final Future<void> Function(AuthService authService)? onSignIn;

  const MainNavigationScreen({
    super.key,
    this.authService,
    this.oidcConfiguration,
    this.apiBaseUrl,
    this.onSignIn,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  StreamSubscription<AuthSession?>? _sessionSubscription;
  AuthSessionManager? _ownedAuthService;
  OidcConfiguration? _activeOidcConfiguration;
  AuthSession? _currentSession;

  String? _configErrorMessage;
  String? _authErrorMessage;
  bool _isInitializingSession = false;
  bool _isSigningIn = false;
  bool _lastFailureWasSignIn = false;
  int _authInitGeneration = 0;
  int _signInGeneration = 0;

  HttpFellowshipApiClient? _cachedFellowshipClient;
  HttpPrayerApiClient? _cachedPrayerClient;
  HttpMemberApiClient? _cachedMemberClient;
  HttpCelebrationApiClient? _cachedCelebrationClient;
  HttpOfferingApiClient? _cachedOfferingClient;
  DefaultAnnouncementApiClient? _cachedAnnouncementClient;
  HttpWorshipApiClient? _cachedWorshipClient;
  String? _cachedSessionKey;
  AuthService? _cachedAuthService;
  String? _cachedBaseUrl;

  static const _tabNames = [
    'Home',
    'Messages',
    'Prayer',
    'Worship',
    'Profile',
  ];

  AuthService? get _effectiveAuthService => widget.authService ?? _ownedAuthService;

  @override
  void initState() {
    super.initState();
    _setupAuthService(fromLifecycleHook: true);
  }

  @override
  void didUpdateWidget(covariant MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService ||
        oldWidget.oidcConfiguration != widget.oidcConfiguration) {
      _setupAuthService(fromLifecycleHook: true);
    } else if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _updateClients();
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _ownedAuthService?.dispose();
    super.dispose();
  }

  void _dismissAuthenticatedRoutes() {
    if (!mounted || _isAuthenticated) return;
    final homeRoute = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAuthenticated) return;
      Navigator.maybeOf(context)?.popUntil(
        (route) =>
            (homeRoute != null && identical(route, homeRoute)) || route.isFirst,
      );
    });
  }

  void _setupAuthService({required bool fromLifecycleHook}) {
    final wasAuthenticated = _isAuthenticated;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _ownedAuthService?.dispose();
    _ownedAuthService = null;
    _configErrorMessage = null;
    _authErrorMessage = null;
    _isSigningIn = false;
    _lastFailureWasSignIn = false;
    _signInGeneration++;

    if (widget.authService == null) {
      try {
        final config = widget.oidcConfiguration ?? OidcConfiguration.fromEnvironment();
        _activeOidcConfiguration = config;
        _ownedAuthService = AuthSessionManager.production(configuration: config);
      } catch (error) {
        _activeOidcConfiguration = null;
        _ownedAuthService = null;
        _configErrorMessage = _formatConfigError(error);
      }
    } else {
      final injected = widget.authService!;
      _activeOidcConfiguration = widget.oidcConfiguration ??
          (injected is AuthSessionManager ? injected.oidcConfiguration : null);
    }

    final authService = _effectiveAuthService;
    _currentSession = authService?.currentSession;
    _updateClients();
    if (wasAuthenticated && !_isAuthenticated) {
      _selectedIndex = 0;
      _dismissAuthenticatedRoutes();
    }

    _sessionSubscription = authService?.sessionStateStream.listen((session) {
      if (!mounted) return;
      var lostAuthentication = false;
      setState(() {
        final wasAuthBeforeUpdate = _isAuthenticated;
        if (session != null || wasAuthBeforeUpdate) {
          _authInitGeneration++;
          _isInitializingSession = false;
          _isSigningIn = false;
          _authErrorMessage = null;
        }
        _currentSession = session;
        if (wasAuthBeforeUpdate && !_isAuthenticated) {
          lostAuthentication = true;
          _signInGeneration++;
          _selectedIndex = 0;
        }
        _updateClients();
      });
      if (lostAuthentication) {
        _dismissAuthenticatedRoutes();
      }
    });

    if (authService != null && !_isAuthenticated) {
      _initializeSession(authService, fromLifecycleHook: fromLifecycleHook);
    } else {
      _isInitializingSession = false;
    }
  }

  Future<void> _initializeSession(
    AuthService authService, {
    required bool fromLifecycleHook,
  }) async {
    final generation = ++_authInitGeneration;
    _lastFailureWasSignIn = false;
    if (fromLifecycleHook) {
      _isInitializingSession = true;
      _authErrorMessage = null;
    } else if (mounted) {
      setState(() {
        _isInitializingSession = true;
        _authErrorMessage = null;
      });
    }

    try {
      final restored = await authService.initialize();
      if (!mounted ||
          generation != _authInitGeneration ||
          !identical(authService, _effectiveAuthService)) {
        return;
      }
      setState(() {
        _currentSession = restored ?? authService.currentSession;
        _isInitializingSession = false;
        _updateClients();
      });
    } catch (error) {
      if (!mounted ||
          generation != _authInitGeneration ||
          !identical(authService, _effectiveAuthService)) {
        return;
      }
      setState(() {
        _currentSession = null;
        _isInitializingSession = false;
        _authErrorMessage = _formatAuthError(error);
        _updateClients();
      });
    }
  }

  Future<void> _handleSignIn() async {
    if (_isSigningIn || _isInitializingSession) return;
    final authService = _effectiveAuthService;
    if (authService == null) {
      setState(() {
        _lastFailureWasSignIn = true;
        _authErrorMessage =
            _configErrorMessage ?? 'OIDC configuration is required before signing in.';
      });
      return;
    }

    final generation = ++_signInGeneration;
    _lastFailureWasSignIn = true;
    setState(() {
      _isSigningIn = true;
      _authErrorMessage = null;
    });

    try {
      if (widget.onSignIn != null) {
        await widget.onSignIn!(authService);
      } else if (authService is AuthSessionManager &&
          authService.supportsInteractiveSignIn) {
        await authService.signInInteractively();
      } else {
        final restored = await authService.initialize();
        if (restored == null && authService.currentSession == null) {
          throw StateError(
            'Interactive OIDC sign-in requires a configured OpenIddict provider.',
          );
        }
      }
      if (!mounted ||
          generation != _signInGeneration ||
          !identical(authService, _effectiveAuthService)) {
        return;
      }
      setState(() {
        _currentSession = authService.currentSession;
        _isSigningIn = false;
        _updateClients();
      });
    } catch (error) {
      if (!mounted ||
          generation != _signInGeneration ||
          !identical(authService, _effectiveAuthService)) {
        return;
      }
      setState(() {
        _isSigningIn = false;
        _authErrorMessage = _formatAuthError(error);
        _updateClients();
      });
    }
  }

  Future<void> _retryAuth() async {
    if (_isSigningIn || _isInitializingSession) return;
    final authService = _effectiveAuthService;
    if (_lastFailureWasSignIn || authService == null) {
      await _handleSignIn();
    } else {
      await _initializeSession(authService, fromLifecycleHook: false);
    }
  }

  Future<void> _handleSignOut() async {
    final authService = _effectiveAuthService;
    if (authService == null) return;
    final wasAuthenticated = _isAuthenticated;
    try {
      await authService.signOut();
    } finally {
      if (mounted && identical(authService, _effectiveAuthService)) {
        setState(() {
          _currentSession = authService.currentSession;
          if (!_isAuthenticated) {
            _isSigningIn = false;
            _selectedIndex = 0;
          }
          _updateClients();
        });
        if (wasAuthenticated && !_isAuthenticated) {
          _dismissAuthenticatedRoutes();
        }
      }
    }
  }

  String _formatConfigError(Object error) {
    if (error is ArgumentError && error.message != null) {
      return 'OIDC configuration incomplete: ${error.message}';
    }
    if (error is FormatException && error.message.isNotEmpty) {
      return 'OIDC configuration invalid: ${error.message}';
    }
    return 'OIDC configuration is required to connect to the church identity server.';
  }

  String _formatAuthError(Object error) {
    if (error is UnsupportedError) {
      return error.message ??
          'Native OIDC authentication is supported on Android and iOS devices only.';
    }
    if (error is ArgumentError && error.message != null) {
      return error.message.toString();
    }
    if (error is FormatException && error.message.isNotEmpty) {
      return error.message;
    }
    if (error is OidcRequestException) {
      return 'Identity provider request failed (HTTP ${error.statusCode}).';
    }
    if (error is TerminalAuthException) {
      return 'Your session has expired or was revoked. Please sign in again.';
    }
    if (error is StateError) {
      return error.message;
    }
    return 'Unable to complete authentication. Please verify your connection and try again.';
  }

  String get _effectiveBaseUrl {
    final provided = widget.apiBaseUrl;
    if (provided != null && provided.trim().isNotEmpty) {
      final trimmed = provided.trim().replaceAll(RegExp(r'/+$'), '');
      return trimmed;
    }
    return const String.fromEnvironment(
      'CHURCH_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5178',
    );
  }

  bool get _isAuthenticated {
    final session = _currentSession;
    if (session == null) return false;
    final hasActiveToken = !session.isExpired && session.accessToken.isNotEmpty;
    final canRefresh =
        session.refreshToken != null && session.refreshToken!.trim().isNotEmpty;
    return hasActiveToken || canRefresh;
  }

  bool get _isPastor {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'pastor');
  }

  bool get _isAdmin {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'admin');
  }

  bool get _canManageWorship {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any(
      (r) =>
          r.toLowerCase() == 'pastor' ||
          r.toLowerCase() == 'admin' ||
          r.toLowerCase() == 'worshipleader',
    );
  }

  bool get _canManageOfferings {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any(
      (r) => r.toLowerCase() == 'pastor' || r.toLowerCase() == 'admin',
    );
  }

  void _updateClients() {
    final authService = _effectiveAuthService;
    final sessionKey = _isAuthenticated && authService != null
        ? '${_currentSession!.userId}:${_currentSession!.tenantId}'
        : null;
    final effectiveBase = _effectiveBaseUrl;

    if (sessionKey != _cachedSessionKey ||
        authService != _cachedAuthService ||
        effectiveBase != _cachedBaseUrl) {
      _cachedSessionKey = sessionKey;
      _cachedAuthService = authService;
      _cachedBaseUrl = effectiveBase;

      if (sessionKey != null && authService != null) {
        final authClient = AuthenticatedHttpClient(authService: authService);
        _cachedFellowshipClient = HttpFellowshipApiClient(
          client: authClient,
          baseUrl: '$effectiveBase/api/v1',
        );
        _cachedPrayerClient = HttpPrayerApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedMemberClient = HttpMemberApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedCelebrationClient = HttpCelebrationApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedOfferingClient = HttpOfferingApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedAnnouncementClient = DefaultAnnouncementApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedWorshipClient = HttpWorshipApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
      } else {
        _cachedFellowshipClient = null;
        _cachedPrayerClient = null;
        _cachedMemberClient = null;
        _cachedCelebrationClient = null;
        _cachedOfferingClient = null;
        _cachedAnnouncementClient = null;
        _cachedWorshipClient = null;
      }
    }
  }

  Widget _buildMessagesScreen() {
    return MessagesScreen(apiClient: _cachedFellowshipClient);
  }

  Widget _buildPrayerScreen() {
    return PrayerScreen(
      apiClient: _cachedPrayerClient,
      isPastor: _isPastor,
    );
  }

  Widget _buildProfileScreen() {
    return ProfileScreen(
      apiClient: _cachedMemberClient,
      authService: _effectiveAuthService,
      isPastor: _isPastor,
    );
  }

  List<Widget> get _screens => [
    HomeScreen(
      announcementClient: _cachedAnnouncementClient,
      celebrationClient: _cachedCelebrationClient,
      offeringClient: _cachedOfferingClient,
      isPastor: _isPastor,
      isAdmin: _isAdmin,
      canManageOfferings: _canManageOfferings,
    ),
    _buildMessagesScreen(),
    _buildPrayerScreen(),
    WorshipScreen(
      apiClient: _cachedWorshipClient,
      canManageWorship: _canManageWorship,
    ),
    _buildProfileScreen(),
  ];

  Widget _buildSignInGate(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final oidcConfig = _activeOidcConfiguration;
    final isBusy = _isInitializingSession || _isSigningIn;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.church_outlined, color: BasilicaColors.burgundy, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Church Digital Platform',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: BasilicaColors.stoneLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: BasilicaColors.borderSoft),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: BasilicaColors.burgundy,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: BasilicaColors.gold,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Sign In Required',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'serif',
                          color: BasilicaColors.burgundy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in with your church member account to access announcements, fellowship messages, confidential prayer, worship setlists, and the member directory.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: BasilicaColors.inkMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          SanctuaryStatusBadge(
                            label: 'Announcements',
                            icon: Icons.campaign_outlined,
                            foregroundColor: BasilicaColors.burgundy,
                            backgroundColor: BasilicaColors.stone,
                          ),
                          SanctuaryStatusBadge(
                            label: 'Prayer',
                            icon: Icons.favorite_border,
                            foregroundColor: BasilicaColors.burgundy,
                            backgroundColor: BasilicaColors.stone,
                          ),
                          SanctuaryStatusBadge(
                            label: 'Worship',
                            icon: Icons.library_music_outlined,
                            foregroundColor: BasilicaColors.gold,
                            backgroundColor: BasilicaColors.stone,
                          ),
                        ],
                      ),
                      if (_isInitializingSession) ...[
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            key: Key('session_restoration_spinner'),
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Restoring session...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: SanctuaryColors.inkMuted,
                          ),
                        ),
                      ],
                      if (_authErrorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          key: const Key('auth_error_banner'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: colorScheme.onErrorContainer,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _authErrorMessage!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  key: const Key('retry_auth_button'),
                                  onPressed: isBusy ? null : _retryAuth,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Retry'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('sign_in_button'),
                          onPressed: isBusy ? null : _handleSignIn,
                          icon: const Icon(Icons.login),
                          label: Text(_isSigningIn ? 'Signing In...' : 'Sign In'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        key: const Key('auth_discovery_status'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: SanctuaryColors.stone,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SanctuaryColors.borderSoft),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 14,
                                  color: SanctuaryColors.inkMuted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Secure Church Connection',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: SanctuaryColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Server: $_effectiveBaseUrl',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: SanctuaryColors.inkMuted,
                              ),
                            ),
                            if (oidcConfig != null) ...[
                              Text(
                                'Identity Provider: ${oidcConfig.issuer}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: SanctuaryColors.inkMuted,
                                ),
                              ),
                              Text(
                                'Discovery: ${oidcConfig.discoveryUri}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: SanctuaryColors.inkMuted.withValues(alpha: 0.85),
                                ),
                              ),
                            ] else if (_effectiveAuthService != null) ...[
                              Text(
                                'Identity Provider: Configured',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: SanctuaryColors.inkMuted,
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Identity Provider: Not configured',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: SanctuaryColors.inkMuted,
                                ),
                              ),
                              if (_configErrorMessage != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _configErrorMessage!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: SanctuaryColors.inkMuted,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _updateClients();
    if (!_isAuthenticated) {
      return _buildSignInGate(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabNames[_selectedIndex]),
        actions: [
          if (_effectiveAuthService != null)
            IconButton(
              key: const Key('app_bar_sign_out_button'),
              icon: const Icon(Icons.logout_outlined),
              tooltip: 'Sign Out',
              onPressed: _handleSignOut,
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < _screens.length; i++)
            HeroMode(
              enabled: i == _selectedIndex,
              child: _screens[i],
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: SanctuaryColors.borderSoft, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Messages',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Prayer',
            ),
            NavigationDestination(
              icon: Icon(Icons.music_note_outlined),
              selectedIcon: Icon(Icons.music_note),
              label: 'Worship',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
