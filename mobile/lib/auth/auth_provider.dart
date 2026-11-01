import 'auth_session.dart';

/// Provider-neutral interface for authentication operations.
///
/// In accordance with the church owner's approved identity architecture
/// (ASP.NET Core Identity / OpenIddict with standard Authorization Code + PKCE),
/// authentication tokens are obtained via standard authorization grant exchange
/// and refreshed via token endpoints, rather than custom vendor SDKs or password grants.
abstract class AuthProvider {
  /// Exchanges an authorization code and PKCE code verifier for an [AuthSession].
  Future<AuthSession> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  });

  /// Refreshes an expired or expiring session using the refresh token.
  Future<AuthSession> refreshSession({
    required String refreshToken,
  });

  /// Revokes an active session token on the identity provider.
  Future<void> revokeSession({
    required String token,
  });

  /// Retrieves validated claims and user info for the current token from server.
  Future<Map<String, dynamic>> fetchUserInfo({
    required String accessToken,
  });
}

/// Only an explicit provider rejection (for example OAuth invalid_grant) is
/// terminal. Transport errors, timeouts and temporary server errors must remain
/// ordinary exceptions so a later refresh can retry the stored credentials.
class TerminalAuthException implements Exception {
  const TerminalAuthException();
}
