import '../support/in_memory_secure_token_storage.dart';
import '../support/mock_auth_provider.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/network/api_exceptions.dart';
import 'package:church_digital_platform_mobile/network/authenticated_http_client.dart';

void main() {
  group('AuthenticatedHttpClient Tests', () {
    late MockAuthProvider mockAuthProvider;
    late InMemorySecureTokenStorage mockStorage;
    late AuthSessionManager sessionManager;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockStorage = InMemorySecureTokenStorage();
      sessionManager = AuthSessionManager(
        provider: mockAuthProvider,
        storage: mockStorage,
      );
    });

    tearDown(() {
      sessionManager.dispose();
    });

    test('Attaches Authorization header with bearer token when session is active', () async {
      await sessionManager.setSession(
        AuthSession(
          accessToken: 'active_valid_jwt',
          refreshToken: 'refresh_tok',
          userId: 'user_1',
          tenantId: 'tenant_1',
          roles: const ['Member'],
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      String? capturedAuthHeader;
      final mockInner = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = AuthenticatedHttpClient(
        authService: sessionManager,
        inner: mockInner,
      );

      final response = await client.get(Uri.parse('https://church.api/v1/fellowships'));

      expect(response.statusCode, 200);
      expect(capturedAuthHeader, 'Bearer active_valid_jwt');
    });

    test('Sends unauthenticated request without Authorization header when no session exists', () async {
      String? capturedAuthHeader;
      final mockInner = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = AuthenticatedHttpClient(
        authService: sessionManager,
        inner: mockInner,
      );

      final response = await client.get(Uri.parse('https://church.api/v1/public/announcements'));

      expect(response.statusCode, 200);
      expect(capturedAuthHeader, isNull);
    });

    test('Rejects request and throws ProhibitedHeaderException if caller tries to forge tenant or role headers', () async {
      final client = AuthenticatedHttpClient(
        authService: sessionManager,
        inner: MockClient((request) async => http.Response('ok', 200)),
      );

      // Attempting to forge X-Tenant-Id
      expect(
        () => client.get(
          Uri.parse('https://church.api/v1/fellowships'),
          headers: {'X-Tenant-Id': '00000000-0000-0000-0000-000000000001'},
        ),
        throwsA(isA<ProhibitedHeaderException>()),
      );

      // Attempting to forge X-User-Role
      expect(
        () => client.get(
          Uri.parse('https://church.api/v1/fellowships'),
          headers: {'X-User-Role': 'Admin'},
        ),
        throwsA(isA<ProhibitedHeaderException>()),
      );

      // Attempting to forge X-User-Id
      expect(
        () => client.get(
          Uri.parse('https://church.api/v1/fellowships'),
          headers: {'X-User-Id': 'victim-guid'},
        ),
        throwsA(isA<ProhibitedHeaderException>()),
      );

      // Attempting to forge X-Church-Id
      expect(
        () => client.get(
          Uri.parse('https://church.api/v1/fellowships'),
          headers: {'X-Church-Id': 'tenant-guid'},
        ),
        throwsA(isA<ProhibitedHeaderException>()),
      );
    });

    test('On 401 Unauthorized, automatically refreshes token and retries request once', () async {
      await sessionManager.setSession(
        AuthSession(
          accessToken: 'stale_jwt',
          refreshToken: 'valid_refresh_token',
          userId: 'user_1',
          tenantId: 'tenant_1',
          roles: const ['Member'],
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

      mockAuthProvider.mockSessionToReturn = sessionManager.currentSession!.copyWith(
        accessToken: 'refreshed_access_token_1');
      int requestCount = 0;
      final tokensReceived = <String?>[];

      final mockInner = MockClient((request) async {
        requestCount++;
        tokensReceived.add(request.headers['Authorization']);
        if (requestCount == 1) {
          // First call: simulate 401 expired token
          return http.Response(jsonEncode({'error': 'token_expired'}), 401);
        }
        // Second call: succeed with retried fresh token
        return http.Response(jsonEncode({'status': 'retried_success'}), 200);
      });

      final client = AuthenticatedHttpClient(
        authService: sessionManager,
        inner: mockInner,
      );

      final response = await client.post(
        Uri.parse('https://church.api/v1/fellowships/1/join'),
        body: jsonEncode({'memberName': 'Test'}),
      );

      expect(response.statusCode, 200);
      expect(requestCount, 2);
      expect(tokensReceived[0], 'Bearer stale_jwt');
      expect(tokensReceived[1], startsWith('Bearer refreshed_access_token_'));
      expect(mockAuthProvider.refreshCount, 1);
    });

    test('On 401 Unauthorized, throws AuthExpiredException if refresh fails', () async {
      await sessionManager.setSession(
        AuthSession(
          accessToken: 'stale_jwt',
          refreshToken: 'revoked_refresh_token',
          userId: 'user_1',
          tenantId: 'tenant_1',
          roles: const ['Member'],
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

      mockAuthProvider.refreshException = const TerminalAuthException();

      final mockInner = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
      });

      final client = AuthenticatedHttpClient(
        authService: sessionManager,
        inner: mockInner,
      );

      await expectLater(
        client.get(Uri.parse('https://church.api/v1/fellowships')),
        throwsA(isA<AuthExpiredException>()),
      );

      // Verify session was cleared on refresh failure
      await pumpEventQueue();
      expect(sessionManager.currentSession, isNull);
    });
  });
}
