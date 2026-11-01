/// Base class for all network and API exceptions.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException ($statusCode): $message';
    }
    return 'ApiException: $message';
  }
}

/// Thrown when an HTTP request fails with 401 Unauthorized and
/// token refresh fails or is impossible because the session is expired.
class AuthExpiredException extends ApiException {
  const AuthExpiredException([String message = 'Session has expired. Please sign in again.'])
      : super(message, statusCode: 401);
}

/// Thrown when access is forbidden (HTTP 403 Forbidden).
class ForbiddenException extends ApiException {
  const ForbiddenException([String message = 'Access denied.'])
      : super(message, statusCode: 403);
}

/// Thrown when a client attempted to supply forged identity/tenant headers
/// that are strictly prohibited by Codex and repository security guidelines.
class ProhibitedHeaderException extends ApiException {
  final String headerName;

  ProhibitedHeaderException(this.headerName)
      : super(
          'Security violation: Screens must not invent role or tenant headers ("$headerName"). '
          'Identity and permissions must come strictly from server-validated tokens.',
          statusCode: 400,
        );
}
