import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';

void main() {
  group('AuthSession Model Tests', () {
    test('Calculates isExpired correctly based on expiration time', () {
      final validSession = AuthSession(
        accessToken: 'valid_token',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      expect(validSession.isExpired, isFalse);

      final expiredSession = AuthSession(
        accessToken: 'expired_token',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(expiredSession.isExpired, isTrue);
    });

    test('hasRole and willExpireWithin work as expected', () {
      final session = AuthSession(
        accessToken: 'token_123',
        userId: 'user-guid',
        tenantId: 'tenant-guid',
        roles: const ['Pastor', 'Admin'],
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(session.hasRole('Pastor'), isTrue);
      expect(session.hasRole('Admin'), isTrue);
      expect(session.hasRole('WorshipLeader'), isFalse);

      // Will expire within 10 minutes? Yes (expires in 5 min)
      expect(session.willExpireWithin(const Duration(minutes: 10)), isTrue);
      // Will expire within 2 minutes? No (expires in 5 min)
      expect(session.willExpireWithin(const Duration(minutes: 2)), isFalse);
    });

    test('Serializes to and from JSON faithfully', () {
      final original = AuthSession(
        accessToken: 'test_access_jwt',
        refreshToken: 'test_refresh_token',
        userId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        tenantId: '7ca85f64-5717-4562-b3fc-2c963f66afa7',
        roles: const ['Member', 'FellowshipLeader'],
        expiresAt: DateTime.utc(2026, 11, 1, 12, 0, 0),
        email: 'member@testchurch.com',
        displayName: 'John Congregant',
      );

      final json = original.toJson();
      final restored = AuthSession.fromJson(json);

      expect(restored, equals(original));
      expect(restored.accessToken, 'test_access_jwt');
      expect(restored.refreshToken, 'test_refresh_token');
      expect(restored.userId, '3fa85f64-5717-4562-b3fc-2c963f66afa6');
      expect(restored.tenantId, '7ca85f64-5717-4562-b3fc-2c963f66afa7');
      expect(restored.roles, ['Member', 'FellowshipLeader']);
      expect(restored.email, 'member@testchurch.com');
      expect(restored.displayName, 'John Congregant');
    });

    test('Handles null/missing fields during deserialization safely', () {
      final session = AuthSession.fromJson(const {});
      expect(session.accessToken, '');
      expect(session.refreshToken, isNull);
      expect(session.roles, isEmpty);
      expect(session.isExpired, isTrue);
    });

    test('copyWith updates properties properly', () {
      final initial = AuthSession(
        accessToken: 'tok_1',
        userId: 'u1',
        tenantId: 't1',
        roles: const ['Member'],
        expiresAt: DateTime.utc(2026, 11, 1, 12, 0, 0),
      );

      final updated = initial.copyWith(
        accessToken: 'tok_2',
        roles: const ['Member', 'Pastor'],
      );

      expect(updated.accessToken, 'tok_2');
      expect(updated.roles, ['Member', 'Pastor']);
      expect(updated.userId, 'u1');
      expect(updated.tenantId, 't1');
    });
  });
}
