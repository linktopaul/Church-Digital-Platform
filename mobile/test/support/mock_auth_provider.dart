import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';

/// A mock/fictional provider implementation for unit testing and parallel development
/// while backend endpoints are being finalized in Child Task #24.
class MockAuthProvider implements AuthProvider {
  AuthSession? mockSessionToReturn;
  Exception? exchangeException;
  Exception? refreshException;
  int exchangeCount = 0;
  int refreshCount = 0;
  int revokeCount = 0;

  MockAuthProvider({this.mockSessionToReturn});

  @override
  Future<AuthSession> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    exchangeCount++;
    if (exchangeException != null) {
      throw exchangeException!;
    }
    return mockSessionToReturn ??
        AuthSession(
          accessToken: 'mock_access_token_$exchangeCount',
          refreshToken: 'mock_refresh_token_$exchangeCount',
          userId: '00000000-0000-0000-0000-000000000001',
          tenantId: '11111111-1111-1111-1111-111111111111',
          roles: const ['Member'],
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          email: 'member@church.local',
          displayName: 'Test Member',
        );
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    refreshCount++;
    if (refreshException != null) {
      throw refreshException!;
    }
    return mockSessionToReturn ??
        AuthSession(
          accessToken: 'refreshed_access_token_$refreshCount',
          refreshToken: 'refreshed_refresh_token_$refreshCount',
          userId: '00000000-0000-0000-0000-000000000001',
          tenantId: '11111111-1111-1111-1111-111111111111',
          roles: const ['Member'],
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          email: 'member@church.local',
          displayName: 'Test Member',
        );
  }

  @override
  Future<void> revokeSession({required String token}) async {
    revokeCount++;
  }

  @override
  Future<Map<String, dynamic>> fetchUserInfo({required String accessToken}) async {
    return {
      'sub': '00000000-0000-0000-0000-000000000001',
      'tenant_id': '11111111-1111-1111-1111-111111111111',
      'roles': ['Member'],
      'email': 'member@church.local',
    };
  }
}
