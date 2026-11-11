import 'dart:async';
import 'package:flutter/material.dart';

import 'auth/auth_session.dart';
import 'auth/auth_session_manager.dart';
import 'network/authenticated_http_client.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/prayer_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/worship_screen.dart';
import 'services/celebration_api_client.dart';
import 'services/offering_api_client.dart';
import 'services/announcement_api_client.dart';
import 'services/fellowship_api_client.dart';
import 'services/member_api_client.dart';
import 'services/prayer_api_client.dart';

void main() {
  runApp(const ChurchMobileApp());
}

class ChurchMobileApp extends StatelessWidget {
  final AuthService? authService;
  final String? apiBaseUrl;

  const ChurchMobileApp({
    super.key,
    this.authService,
    this.apiBaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Church Digital Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF385A80),
        ),
        useMaterial3: true,
      ),
      home: MainNavigationScreen(
        authService: authService,
        apiBaseUrl: apiBaseUrl,
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final AuthService? authService;
  final String? apiBaseUrl;

  const MainNavigationScreen({
    super.key,
    this.authService,
    this.apiBaseUrl,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  StreamSubscription<AuthSession?>? _sessionSubscription;
  AuthSession? _currentSession;

  HttpFellowshipApiClient? _cachedFellowshipClient;
  HttpPrayerApiClient? _cachedPrayerClient;
  HttpMemberApiClient? _cachedMemberClient;
  HttpCelebrationApiClient? _cachedCelebrationClient;
  HttpOfferingApiClient? _cachedOfferingClient;
  DefaultAnnouncementApiClient? _cachedAnnouncementClient;
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

  @override
  void initState() {
    super.initState();
    _currentSession = widget.authService?.currentSession;
    _updateClients();
    _sessionSubscription = widget.authService?.sessionStateStream.listen((session) {
      if (mounted) {
        setState(() {
          _currentSession = session;
          _updateClients();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService || oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _sessionSubscription?.cancel();
      _currentSession = widget.authService?.currentSession;
      _updateClients();
      _sessionSubscription = widget.authService?.sessionStateStream.listen((session) {
        if (mounted) {
          setState(() {
            _currentSession = session;
            _updateClients();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
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
    final canRefresh = session.refreshToken != null && session.refreshToken!.trim().isNotEmpty;
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

  bool get _canManageOfferings {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'pastor' || r.toLowerCase() == 'admin');
  }

  void _updateClients() {
    final authService = widget.authService;
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
      } else {
        _cachedFellowshipClient = null;
        _cachedPrayerClient = null;
        _cachedMemberClient = null;
        _cachedCelebrationClient = null;
        _cachedOfferingClient = null;
        _cachedAnnouncementClient = null;
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
      authService: widget.authService,
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
    const WorshipScreen(),
    _buildProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    _updateClients();
    return Scaffold(
      appBar: AppBar(title: Text(_tabNames[_selectedIndex])),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
