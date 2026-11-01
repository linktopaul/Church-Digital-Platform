import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/auth/secure_token_storage.dart';

void main() {
  group('AuthSessionManager Lifecycle Tests', () {
    late MockAuthProvider mockProvider;
    late InMemorySecureTokenStorage mockStorage;
    late AuthSessionManager sessionManager;

    setUp(() {
      mockProvider = MockAuthProvider();
      mockStorage = InMemorySecureTokenStorage();
      sessionManager = AuthSessionManager(
        provider: mockProvider,
        storage: mockStorage,
      );
    });

    tearDown(() {
      sessionManager.dispose();
    });

    test('Initializes with null when secure storage is empty', () async {
      final session = await sessionManager.initialize();
      expect(session, isNull);
      expect(sessionManager.currentSession, isNull);
      expect(sessionManager.isAuthenticated, isFalse);
    });

    test('Initializes with stored session when not expired', () async {
      final savedSession = AuthSession(
        accessToken: 'saved_token',
        refreshToken: 'saved_refresh',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
      await mockStorage.saveSession(savedSession);

      final session = await sessionManager.initialize();
      expect(session, equals(savedSession));
      expect(sessionManager.currentSession, equals(savedSession));
      expect(sessionManager.isAuthenticated, isTrue);
    });

    test('Initializes and refreshes automatically if stored session is expired but has refresh token', () async {
      final expiredSession = AuthSession(
        accessToken: 'expired_token',
        refreshToken: 'valid_refresh',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      await mockStorage.saveSession(expiredSession);

      final session = await sessionManager.initialize();
      expect(session, isNotNull);
      expect(session!.accessToken, startsWith('refreshed_access_token_'));
      expect(mockProvider.refreshCount, 1);
      expect(sessionManager.isAuthenticated, isTrue);
    });

    test('Initializes and clears storage if refresh fails', () async {
      final expiredSession = AuthSession(
        accessToken: 'expired_token',
        refreshToken: 'bad_refresh',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      await mockStorage.saveSession(expiredSession);
      mockProvider.refreshException = Exception('Invalid refresh token');

      final session = await sessionManager.initialize();
      expect(session, isNull);
      expect(sessionManager.currentSession, isNull);
      expect(await mockStorage.getSession(), isNull);
    });

    test('signInWithAuthorizationCode updates session, storage, and emits event', () async {
      final emissions = <AuthSession?>[];
      final sub = sessionManager.sessionStateStream.listen(emissions.add);

      final session = await sessionManager.signInWithAuthorizationCode(
        code: 'auth_code_123',
        codeVerifier: 'pkce_verifier_xyz',
        redirectUri: 'com.churchdigital://callback',
      );

      expect(session.accessToken, startsWith('mock_access_token_'));
      expect(sessionManager.currentSession, equals(session));
      expect(await mockStorage.getSession(), equals(session));
      expect(emissions.length, 1);
      expect(emissions.first, equals(session));

      await sub.cancel();
    });

    test('refresh() updates session and storage', () async {
      await sessionManager.signInWithAuthorizationCode(
        code: 'code',
        codeVerifier: 'verifier',
        redirectUri: 'uri',
      );

      final refreshed = await sessionManager.refresh();
      expect(refreshed.accessToken, startsWith('refreshed_access_token_'));
      expect(sessionManager.currentSession, equals(refreshed));
      expect(await mockStorage.getSession(), equals(refreshed));
      expect(mockProvider.refreshCount, 1);
    });

    test('refresh() clears session and storage on failure and throws', () async {
      await sessionManager.signInWithAuthorizationCode(
        code: 'code',
        codeVerifier: 'verifier',
        redirectUri: 'uri',
      );

      mockProvider.refreshException = Exception('Revoked token');

      expect(() => sessionManager.refresh(), throwsException);
      // Wait for async error processing
      await pumpEventQueue();

      expect(sessionManager.currentSession, isNull);
      expect(await mockStorage.getSession(), isNull);
      expect(sessionManager.isAuthenticated, isFalse);
    });

    test('signOut() revokes token, clears storage, and emits null', () async {
      await sessionManager.signInWithAuthorizationCode(
        code: 'code',
        codeVerifier: 'verifier',
        redirectUri: 'uri',
      );

      final emissions = <AuthSession?>[];
      final sub = sessionManager.sessionStateStream.listen(emissions.add);

      await sessionManager.signOut();

      expect(mockProvider.revokeCount, 1);
      expect(sessionManager.currentSession, isNull);
      expect(await mockStorage.getSession(), isNull);
      expect(emissions.contains(null), isTrue);

      await sub.cancel();
    });
  });
}
