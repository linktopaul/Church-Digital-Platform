import 'dart:async';
import 'package:flutter/material.dart';

import 'auth/auth_provider.dart';
import 'auth/auth_session.dart';
import 'network/authenticated_http_client.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/prayer_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/worship_screen.dart';
import 'services/fellowship_api_client.dart';
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
    _sessionSubscription = widget.authService?.sessionStateStream.listen((session) {
      if (mounted) {
        setState(() {
          _currentSession = session;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService) {
      _sessionSubscription?.cancel();
      _currentSession = widget.authService?.currentSession;
      _sessionSubscription = widget.authService?.sessionStateStream.listen((session) {
        if (mounted) {
          setState(() {
            _currentSession = session;
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
      return provided.trim();
    }
    return const String.fromEnvironment(
      'CHURCH_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5178',
    );
  }

  bool get _isAuthenticated {
    final session = _currentSession;
    return session != null && !session.isExpired && session.accessToken.isNotEmpty;
  }

  bool get _isPastor {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'pastor');
  }

  Widget _buildMessagesScreen() {
    final authService = widget.authService;
    if (authService != null && _isAuthenticated) {
      final authClient = AuthenticatedHttpClient(authService: authService);
      final client = HttpFellowshipApiClient(
        client: authClient,
        baseUrl: _effectiveBaseUrl,
        currentUserId: _currentSession?.userId,
        currentMemberName: _currentSession?.displayName,
      );
      return MessagesScreen(apiClient: client);
    }
    return const MessagesScreen();
  }

  Widget _buildPrayerScreen() {
    final authService = widget.authService;
    if (authService != null && _isAuthenticated) {
      final authClient = AuthenticatedHttpClient(authService: authService);
      final prayerClient = HttpPrayerApiClient(
        client: authClient,
        baseUrl: _effectiveBaseUrl,
      );
      return PrayerScreen(
        apiClient: prayerClient,
        isPastor: _isPastor,
      );
    }
    return const PrayerScreen();
  }

  List<Widget> get _screens => [
    const HomeScreen(),
    _buildMessagesScreen(),
    _buildPrayerScreen(),
    const WorshipScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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