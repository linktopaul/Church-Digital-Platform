import '../support/in_memory_secure_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';

void main() {
  group('SecureTokenStorage Tests', () {
    test('InMemorySecureTokenStorage persists, retrieves, and clears sessions', () async {
      final storage = InMemorySecureTokenStorage();
      expect(await storage.getSession(), isNull);
      expect(await storage.hasValidSession(), isFalse);

      final session = AuthSession(
        accessToken: 'access_secret',
        refreshToken: 'refresh_secret',
        userId: 'user_1',
        tenantId: 'tenant_1',
        roles: const ['Member'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await storage.saveSession(session);
      expect(await storage.getSession(), equals(session));
      expect(await storage.hasValidSession(), isTrue);

      await storage.clearSession();
      expect(await storage.getSession(), isNull);
      expect(await storage.hasValidSession(), isFalse);
    });

    test('hasValidSession returns false when session is expired', () async {
      final expiredSession = AuthSession(
        accessToken: 'expired_access_secret',
        userId: 'user_1',
        tenantId: 'tenant_1',
        roles: const ['Member'],
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final storage = InMemorySecureTokenStorage(expiredSession);
      expect(await storage.hasValidSession(), isFalse);
    });
  });
}
