import 'dart:async';
import 'dart:convert';

import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/auth/oidc_configuration.dart';
import 'package:church_digital_platform_mobile/auth/openiddict_auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/secure_token_storage.dart';
import 'package:church_digital_platform_mobile/main.dart';
import 'package:church_digital_platform_mobile/screens/home_screen.dart';
import 'package:church_digital_platform_mobile/screens/messages_screen.dart';
import 'package:church_digital_platform_mobile/screens/prayer_screen.dart';
import 'package:church_digital_platform_mobile/screens/profile_screen.dart';
import 'package:church_digital_platform_mobile/screens/worship_screen.dart';
import 'package:church_digital_platform_mobile/services/worship_api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/in_memory_secure_token_storage.dart';
import 'support/mock_auth_provider.dart';

OidcConfiguration _testOidcConfig({
  String issuer = 'https://issuer.example.test',
}) =>
    OidcConfiguration(
      issuer: issuer,
      clientId: 'mobile-client',
      redirectUri: 'test.church:/oauthredirect',
      scopes: const ['openid', 'offline_access', 'church_api'],
      memberIdClaim: 'member_id',
      tenantIdClaim: 'tenant_id',
      rolesClaim: 'roles',
    );

AuthSession _buildSession({
  String accessToken = 'token-1',
  String? refreshToken = 'refresh-1',
  String userId = 'user-1',
  String tenantId = 'tenant-1',
  List<String> roles = const ['Member'],
  Duration expiresIn = const Duration(hours: 1),
}) =>
    AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
      tenantId: tenantId,
      roles: roles,
      expiresAt: DateTime.now().add(expiresIn),
      email: 'member@church.test',
      displayName: 'Grace Member',
    );

class _ControllableStorage implements SecureTokenStorage {
  AuthSession? session;
  Completer<AuthSession?>? pendingRead;
  Object? errorOnRead;
  int readCalls = 0;

  _ControllableStorage({this.session});

  @override
  Future<void> saveSession(AuthSession value) async {
    session = value;
  }

  @override
  Future<AuthSession?> getSession() async {
    readCalls++;
    if (errorOnRead != null) {
      final err = errorOnRead!;
      errorOnRead = null;
      throw err;
    }
    if (pendingRead != null) {
      return pendingRead!.future;
    }
    return session;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<bool> hasValidSession() async {
    return session != null && !session!.isExpired;
  }
}

class _FakeAppAuth extends FlutterAppAuth {
  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) async {
    return const AuthorizationResponse(
      authorizationCode: 'auth-code-1',
      codeVerifier: 'pkce-verifier-1',
      nonce: 'nonce-1',
    );
  }

  @override
  Future<TokenResponse> token(TokenRequest request) async {
    final header = base64Url.encode(utf8.encode('{"alg":"RS256"}'));
    final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': 'sub-1'})));
    return TokenResponse(
      'oidc-access-token',
      'oidc-refresh-token',
      DateTime.now().add(const Duration(hours: 1)),
      '$header.$payload.sig',
      'Bearer',
      null,
      null,
    );
  }
}

void main() {
  group('ChurchMobileApp startup & Sign-In gate', () {
    testWidgets(
      'unauthenticated startup gates all main tabs behind Sign-In view and handles missing OIDC config cleanly',
      (tester) async {
        await tester.pumpWidget(
          const ChurchMobileApp(apiBaseUrl: 'https://api.gracechurch.test'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sign In Required'), findsOneWidget);
        expect(find.text('Server: https://api.gracechurch.test'), findsOneWidget);
        expect(find.text('Identity Provider: Not configured'), findsOneWidget);
        expect(find.byKey(const Key('sign_in_button')), findsOneWidget);

        // Main navigation bar and tab screens are not mounted when unauthenticated
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.byType(MessagesScreen), findsNothing);
        expect(find.byType(PrayerScreen), findsNothing);
        expect(find.byType(WorshipScreen), findsNothing);
        expect(find.byType(ProfileScreen), findsNothing);

        // Tapping Sign In when unconfigured surfaces clear error feedback and Retry button
        await tester.tap(find.byKey(const Key('sign_in_button')));
        await tester.pump();

        expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
        expect(find.byKey(const Key('retry_auth_button')), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      },
    );

    testWidgets(
      'default production AuthService restores session from PlatformSecureTokenStorage when no authService is injected',
      (tester) async {
        const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
        final secureStore = <String, String>{};
        final methodCalls = <MethodCall>[];

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        try {
          final oidcConfig = _testOidcConfig();
          final expectedKey = 'church.auth.v1.${base64Url.encode(utf8.encode(jsonEncode([
                oidcConfig.issuer.toString(),
                oidcConfig.clientId,
                oidcConfig.redirectUri.toString(),
              ])))}';
          final storedSession = _buildSession(
            userId: 'restored-member',
            tenantId: 'restored-tenant',
            roles: const ['WorshipLeader'],
          );
          secureStore[expectedKey] = storedSession.serialize();

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            final args = call.arguments as Map;
            final key = args['key'] as String;
            switch (call.method) {
              case 'read':
                return secureStore[key];
              case 'write':
                secureStore[key] = args['value'] as String;
                return null;
              case 'delete':
                secureStore.remove(key);
                return null;
              default:
                throw StateError('Unexpected method ${call.method}');
            }
          });

          await tester.pumpWidget(
            ChurchMobileApp(
              oidcConfiguration: oidcConfig,
              apiBaseUrl: 'https://api.gracechurch.test',
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(methodCalls.any((c) => c.method == 'read'), isTrue);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('Sign In Required'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'default production AuthService stays gated on Sign-In screen when PlatformSecureTokenStorage is empty',
      (tester) async {
        const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        try {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async => null);

          final oidcConfig = _testOidcConfig();
          await tester.pumpWidget(
            ChurchMobileApp(
              oidcConfiguration: oidcConfig,
              apiBaseUrl: 'https://api.gracechurch.test',
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('Sign In Required'), findsOneWidget);
          expect(
            find.text('Identity Provider: https://issuer.example.test'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Discovery: https://issuer.example.test/.well-known/openid-configuration',
            ),
            findsOneWidget,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'default production AuthService fails closed cleanly on unsupported platform without memory fallback',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await tester.pumpWidget(
            ChurchMobileApp(
              oidcConfiguration: _testOidcConfig(),
              apiBaseUrl: 'https://api.gracechurch.test',
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('Sign In Required'), findsOneWidget);
          expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
          expect(
            find.textContaining('Native credential storage supports Android and iOS only'),
            findsOneWidget,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'displays session restoration spinner while initialize is pending and retries on transient failure',
      (tester) async {
        final storage = _ControllableStorage(
          session: _buildSession(roles: const ['Member']),
        );
        storage.errorOnRead = StateError('Keystore temporarily unavailable');

        final manager = AuthSessionManager(
          provider: MockAuthProvider(),
          storage: storage,
        );
        addTearDown(manager.dispose);

        await tester.pumpWidget(ChurchMobileApp(authService: manager));
        await tester.pump();

        // First attempt failed -> error banner and Retry button are shown
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
        expect(find.text('Keystore temporarily unavailable'), findsOneWidget);

        // Make next attempt pend on a Completer so we can verify the restoration spinner
        final completer = Completer<AuthSession?>();
        storage.pendingRead = completer;

        await tester.tap(find.byKey(const Key('retry_auth_button')));
        await tester.pump();

        expect(find.byKey(const Key('session_restoration_spinner')), findsOneWidget);
        expect(find.text('Restoring session...'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);

        // Complete restoration with valid session
        completer.complete(_buildSession(roles: const ['Member']));
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('session_restoration_spinner')), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
      },
    );

    testWidgets(
      'interactive OIDC Sign-In button surfaces discovery error, supports retry, and transitions to main tabs',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final oidcConfig = _testOidcConfig();
          final storage = InMemorySecureTokenStorage();
          var failDiscovery = true;

          final provider = OpenIddictAuthProvider(
            configuration: oidcConfig,
            storage: storage,
            appAuth: _FakeAppAuth(),
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('openid-configuration')) {
                if (failDiscovery) {
                  return http.Response('', 503);
                }
                return http.Response(
                  jsonEncode({
                    'issuer': oidcConfig.issuer.toString(),
                    'code_challenge_methods_supported': ['S256'],
                    'authorization_endpoint':
                        '${oidcConfig.issuer}/connect/authorize',
                    'token_endpoint': '${oidcConfig.issuer}/connect/token',
                    'userinfo_endpoint': '${oidcConfig.issuer}/connect/userinfo',
                    'revocation_endpoint': '${oidcConfig.issuer}/connect/revocation',
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('userinfo')) {
                return http.Response(
                  jsonEncode({
                    'sub': 'sub-1',
                    'member_id': 'member-1',
                    'tenant_id': 'tenant-1',
                    'roles': ['Member'],
                    'email': 'member@church.test',
                    'name': 'Test Member',
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('revocation')) {
                return http.Response('', 200);
              }
              throw StateError('Unexpected URL ${request.url}');
            }),
          );
          addTearDown(provider.close);

          final manager = AuthSessionManager(provider: provider, storage: storage);
          addTearDown(manager.dispose);

          await tester.pumpWidget(ChurchMobileApp(authService: manager));
          await tester.pump();

          expect(find.text('Sign In Required'), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);

          // First Sign-In tap fails with HTTP 503
          await tester.tap(find.byKey(const Key('sign_in_button')));
          await tester.pump();
          await tester.pump();

          expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
          expect(
            find.text('Identity provider request failed (HTTP 503).'),
            findsOneWidget,
          );
          expect(find.byType(NavigationBar), findsNothing);

          // Allow discovery to succeed and tap Retry
          failDiscovery = false;
          await tester.tap(find.byKey(const Key('retry_auth_button')));
          await tester.pump();
          await tester.pump();

          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('Sign In Required'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'supports full interactive Sign-In -> Sign-Out -> Sign-In cycle without leaving Sign-In button busy',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final oidcConfig = _testOidcConfig();
          final storage = InMemorySecureTokenStorage();

          final provider = OpenIddictAuthProvider(
            configuration: oidcConfig,
            storage: storage,
            appAuth: _FakeAppAuth(),
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('openid-configuration')) {
                return http.Response(
                  jsonEncode({
                    'issuer': oidcConfig.issuer.toString(),
                    'code_challenge_methods_supported': ['S256'],
                    'authorization_endpoint':
                        '${oidcConfig.issuer}/connect/authorize',
                    'token_endpoint': '${oidcConfig.issuer}/connect/token',
                    'userinfo_endpoint': '${oidcConfig.issuer}/connect/userinfo',
                    'revocation_endpoint': '${oidcConfig.issuer}/connect/revocation',
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('userinfo')) {
                return http.Response(
                  jsonEncode({
                    'sub': 'sub-1',
                    'member_id': 'member-1',
                    'tenant_id': 'tenant-1',
                    'roles': ['Member'],
                    'email': 'member@church.test',
                    'name': 'Test Member',
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('revocation')) {
                return http.Response('', 200);
              }
              throw StateError('Unexpected URL ${request.url}');
            }),
          );
          addTearDown(provider.close);

          final manager = AuthSessionManager(provider: provider, storage: storage);
          addTearDown(manager.dispose);

          await tester.pumpWidget(ChurchMobileApp(authService: manager));
          await tester.pump();

          // First interactive Sign-In
          await tester.tap(find.byKey(const Key('sign_in_button')));
          await tester.pump();
          await tester.pump();

          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('Sign In Required'), findsNothing);

          // Sign out back to gate
          await tester.tap(find.byKey(const Key('app_bar_sign_out_button')));
          await tester.pumpAndSettle();

          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('Sign In Required'), findsOneWidget);
          expect(find.text('Signing In...'), findsNothing);
          expect(find.text('Sign In'), findsOneWidget);

          final signInButton = tester.widget<FilledButton>(
            find.byKey(const Key('sign_in_button')),
          );
          expect(signInButton.onPressed, isNotNull);

          // Second interactive Sign-In succeeds cleanly
          await tester.tap(find.byKey(const Key('sign_in_button')));
          await tester.pump();
          await tester.pump();

          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('Sign In Required'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('Authenticated navigation, session switch, Sign-Out & WorshipScreen wiring', () {
    testWidgets('main navigation exposes all five tabs and supports Sign-Out back to gate', (
      tester,
    ) async {
      final manager = AuthSessionManager(
        provider: MockAuthProvider(),
        storage: InMemorySecureTokenStorage(),
      );
      addTearDown(manager.dispose);
      await manager.setSession(_buildSession(roles: const ['Member']));

      await tester.pumpWidget(ChurchMobileApp(authService: manager));

      final navigationFinder = find.byType(NavigationBar);
      expect(navigationFinder, findsOneWidget);

      final navigation = tester.widget<NavigationBar>(navigationFinder);
      expect(navigation.destinations, hasLength(5));
      expect(navigation.selectedIndex, 0);

      await tester.tap(find.byIcon(Icons.music_note_outlined));
      await tester.pump();

      final updatedNavigation = tester.widget<NavigationBar>(navigationFinder);
      expect(updatedNavigation.selectedIndex, 3);
      expect(find.text('Worship'), findsWidgets);

      // Sign out via AppBar action button
      await tester.tap(find.byKey(const Key('app_bar_sign_out_button')));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(WorshipScreen, skipOffstage: false), findsNothing);
      expect(find.text('Sign In Required'), findsOneWidget);
    });

    testWidgets(
      'wires HttpWorshipApiClient and role-gates canManageWorship for Member, WorshipLeader, Pastor, and Admin',
      (tester) async {
        final manager = AuthSessionManager(
          provider: MockAuthProvider(),
          storage: InMemorySecureTokenStorage(),
        );
        addTearDown(manager.dispose);

        // 1. Regular Member session -> canManageWorship is false
        await manager.setSession(
          _buildSession(
            userId: 'member-1',
            tenantId: 'tenant-a',
            roles: const ['Member'],
          ),
        );

        await tester.pumpWidget(
          ChurchMobileApp(
            authService: manager,
            apiBaseUrl: 'https://api.gracechurch.test',
          ),
        );

        // Switch to Worship tab (index 3)
        await tester.tap(find.byIcon(Icons.music_note_outlined));
        await tester.pump();

        var worshipScreen = tester.widget<WorshipScreen>(find.byType(WorshipScreen));
        expect(worshipScreen.apiClient, isA<HttpWorshipApiClient>());
        expect(worshipScreen.canManageWorship, isFalse);
        expect(find.byKey(const Key('addSongFab')), findsNothing);

        final memberClient = worshipScreen.apiClient;

        // 2. Same-session token refresh preserves the HttpWorshipApiClient instance
        await manager.setSession(
          _buildSession(
            accessToken: 'refreshed-member-token',
            userId: 'member-1',
            tenantId: 'tenant-a',
            roles: const ['Member'],
          ),
        );
        await tester.pump();

        worshipScreen = tester.widget<WorshipScreen>(find.byType(WorshipScreen));
        expect(identical(worshipScreen.apiClient, memberClient), isTrue);

        // 3. Session switch to WorshipLeader in another tenant replaces client and enables management
        await manager.setSession(
          _buildSession(
            userId: 'leader-1',
            tenantId: 'tenant-b',
            roles: const ['WorshipLeader'],
          ),
        );
        await tester.pump();

        worshipScreen = tester.widget<WorshipScreen>(find.byType(WorshipScreen));
        expect(worshipScreen.apiClient, isA<HttpWorshipApiClient>());
        expect(identical(worshipScreen.apiClient, memberClient), isFalse);
        expect(worshipScreen.canManageWorship, isTrue);
        expect(find.byKey(const Key('addSongFab')), findsOneWidget);

        // Switch to Sunday Setlists sub-tab inside WorshipScreen and verify Add Setlist FAB
        await tester.tap(find.text('Sunday Setlists'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('addSetlistFab')), findsOneWidget);

        // 4. Pastor role also enables canManageWorship
        await manager.setSession(
          _buildSession(
            userId: 'pastor-1',
            tenantId: 'tenant-b',
            roles: const ['Pastor'],
          ),
        );
        await tester.pump();
        worshipScreen = tester.widget<WorshipScreen>(find.byType(WorshipScreen));
        expect(worshipScreen.canManageWorship, isTrue);

        // 5. Admin role also enables canManageWorship
        await manager.setSession(
          _buildSession(
            userId: 'admin-1',
            tenantId: 'tenant-b',
            roles: const ['Admin'],
          ),
        );
        await tester.pump();
        worshipScreen = tester.widget<WorshipScreen>(find.byType(WorshipScreen));
        expect(worshipScreen.canManageWorship, isTrue);

        // 6. Sign-Out clears client and unmounts WorshipScreen behind Sign-In gate
        await manager.signOut();
        await tester.pumpAndSettle();

        expect(find.byType(WorshipScreen, skipOffstage: false), findsNothing);
        expect(find.text('Sign In Required'), findsOneWidget);
      },
    );

    testWidgets(
      'dismisses open worship detail route and modal sheet when session refresh is rejected',
      (tester) async {
        final mockProvider = MockAuthProvider();
        mockProvider.refreshException = const TerminalAuthException();
        final manager = AuthSessionManager(
          provider: mockProvider,
          storage: InMemorySecureTokenStorage(),
        );
        addTearDown(manager.dispose);

        await manager.setSession(
          _buildSession(
            userId: 'leader-1',
            tenantId: 'tenant-a',
            roles: const ['WorshipLeader'],
          ),
        );

        await tester.pumpWidget(
          ChurchMobileApp(
            authService: manager,
            apiBaseUrl: 'https://api.gracechurch.test',
          ),
        );

        // Navigate to Worship tab and open a pushed detail route + modal sheet
        await tester.tap(find.byIcon(Icons.music_note_outlined));
        await tester.pump();

        final worshipContext = tester.element(find.byType(WorshipScreen));
        unawaited(
          Navigator.of(worshipContext).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('Worship Setlist Detail Overlay')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Worship Setlist Detail Overlay'), findsOneWidget);

        unawaited(
          showModalBottomSheet<void>(
            context: tester.element(find.text('Worship Setlist Detail Overlay')),
            builder: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Worship Song Detail Overlay'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Worship Song Detail Overlay'), findsOneWidget);

        // Token refresh rejection clears the session asynchronously on sessionStateStream
        await expectLater(
          manager.refresh(),
          throwsA(isA<TerminalAuthException>()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Worship Song Detail Overlay'), findsNothing);
        expect(find.text('Worship Setlist Detail Overlay'), findsNothing);
        expect(find.byType(WorshipScreen, skipOffstage: false), findsNothing);
        expect(find.text('Sign In Required'), findsOneWidget);
      },
    );
  });
}
