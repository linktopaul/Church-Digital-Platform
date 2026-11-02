/// Non-secret operator configuration. There are deliberately no demo identities,
/// issuer URLs, client registrations, redirect URIs, scopes or claim mappings.
class OidcConfiguration {
  final Uri issuer;
  final String clientId;
  final Uri redirectUri;
  final List<String> scopes;
  final String memberIdClaim;
  final String tenantIdClaim;
  final String rolesClaim;

  OidcConfiguration({
    required String issuer,
    required this.clientId,
    required String redirectUri,
    required List<String> scopes,
    required this.memberIdClaim,
    required this.tenantIdClaim,
    required this.rolesClaim,
  }) : issuer = Uri.parse(issuer),
       redirectUri = Uri.parse(redirectUri),
       scopes = List.unmodifiable(scopes) {
    requireHttps(this.issuer);
    if (this.issuer.hasQuery || this.issuer.hasFragment) {
      throw ArgumentError('Issuer must not contain query or fragment');
    }
    for (final value in [clientId, memberIdClaim, tenantIdClaim, rolesClaim]) {
      if (value.trim().isEmpty || value != value.trim()) {
        throw ArgumentError('Client registration and claim mappings are required');
      }
    }
    final redirect = this.redirectUri;
    if (!redirect.isAbsolute || redirect.hasFragment || redirect.hasQuery ||
        redirect.userInfo.isNotEmpty || redirect.scheme == 'http' ||
        redirect.scheme == 'file' || redirect.scheme == 'javascript' ||
        redirect.scheme == 'data' || redirect.path.isEmpty) {
      throw ArgumentError('An explicitly registered native redirect URI is required');
    }
    if (redirect.scheme == 'https') {
      requireHttps(redirect);
    } else if (!RegExp(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$').hasMatch(redirect.scheme)) {
      throw ArgumentError('Private redirect scheme must use reverse-domain notation');
    }
    if (!scopes.contains('openid') || !scopes.contains('offline_access') ||
        scopes.any((scope) => scope.isEmpty || scope.contains(RegExp(r'\s')))) {
      throw ArgumentError('Explicit scopes must include openid and offline_access');
    }
  }

  factory OidcConfiguration.fromEnvironment() => OidcConfiguration(
    issuer: const String.fromEnvironment('CHURCH_AUTH_ISSUER'),
    clientId: const String.fromEnvironment('CHURCH_AUTH_CLIENT_ID'),
    redirectUri: const String.fromEnvironment('CHURCH_AUTH_REDIRECT_URI'),
    scopes: const String.fromEnvironment('CHURCH_AUTH_SCOPES').split(' '),
    memberIdClaim: const String.fromEnvironment('CHURCH_AUTH_MEMBER_ID_CLAIM'),
    tenantIdClaim: const String.fromEnvironment('CHURCH_AUTH_TENANT_ID_CLAIM'),
    rolesClaim: const String.fromEnvironment('CHURCH_AUTH_ROLES_CLAIM'),
  );

  // OIDC discovery's standardized location; no backend endpoint paths are guessed.
  Uri get discoveryUri => Uri.parse(
    '${issuer.toString().replaceFirst(RegExp(r'/$'), '')}/.well-known/openid-configuration',
  );

  static void requireHttps(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw ArgumentError('OIDC endpoints must be absolute HTTPS URLs without credentials');
    }
  }
}
