import 'dart:async';
import 'package:http/http.dart' as http;
import '../auth/auth_session.dart';
import '../auth/auth_session_manager.dart';
import 'api_exceptions.dart';

/// Headers that screens and feature code are strictly prohibited from forging
/// per AGENTS.md codex rules and task requirements:
/// "Use a shared API client; screens must not invent role or tenant headers."
const Set<String> _prohibitedHeaders = {
  'x-tenant-id',
  'x-church-id',
  'x-user-role',
  'x-user-id',
};

/// A shared, secure HTTP client that automatically attaches standard OAuth2 bearer
/// tokens from the active [AuthService], prevents caller header forgery,
/// and automatically negotiates token refresh and retry when receiving HTTP 401 Unauthorized.
class AuthenticatedHttpClient extends http.BaseClient {
  final AuthService _authService;
  final http.Client _inner;

  AuthenticatedHttpClient({
    required AuthService authService,
    http.Client? inner,
  })  : _authService = authService,
        _inner = inner ?? http.Client();

  /// Validates that callers do not pass forbidden client-supplied identity or tenant headers.
  static void validateHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return;
    for (final key in headers.keys) {
      if (_prohibitedHeaders.contains(key.toLowerCase())) {
        throw ProhibitedHeaderException(key);
      }
    }
  }

  /// Copies a [http.BaseRequest] so it can be re-sent on a 401 retry.
  http.BaseRequest _cloneRequest(http.BaseRequest request) {
    http.BaseRequest copy;
    if (request is http.Request) {
      copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..encoding = request.encoding
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
    } else {
      // For MultipartRequest or general StreamedRequest
      throw UnsupportedError('Streaming requests do not support automatic retry.');
    }
    return copy;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Audit and reject client-forged tenant/role headers
    validateHeaders(request.headers);

    // 2. Clone request in case retry is required
    final canRetry = request is http.Request;
    final initialRequest = canRetry ? _cloneRequest(request) : request;

    // 3. Attach Bearer token from active session if present and capture originating session context
    final originatingSession = _authService.currentSession;
    final originatingGeneration = _authService.sessionGeneration;
    if (originatingSession != null && originatingSession.accessToken.isNotEmpty) {
      initialRequest.headers['Authorization'] = 'Bearer ${originatingSession.accessToken}';
    }

    // 4. Send request
    http.StreamedResponse response = await _inner.send(initialRequest);

    // 5. If 401 Unauthorized received and eligible for retry
    if (response.statusCode == 401 && canRetry) {
      // Finding: Consume the unauthorized response stream before retrying or exiting to release resources
      await response.stream.drain().catchError((_) {});

      // Finding: Bind retry to originating session context
      // If user signed out or switched account while initial request was in flight, abort retry
      final currentSession = _authService.currentSession;
      final preRefreshGeneration = _authService.sessionGeneration;

      final isSameSession = originatingSession != null &&
          currentSession != null &&
          originatingGeneration == preRefreshGeneration &&
          originatingSession.userId == currentSession.userId &&
          originatingSession.tenantId == currentSession.tenantId;

      if (isSameSession &&
          currentSession.refreshToken != null &&
          currentSession.refreshToken!.isNotEmpty) {
        final AuthSession refreshedSession;
        try {
          refreshedSession = await _authService.refresh();
        } catch (e) {
          // Token refresh failed or session expired
          throw AuthExpiredException('Session refresh failed: $e');
        }

        // Verify again before sending retry that session has not switched during refresh
        final postRefreshCurrent = _authService.currentSession;
        if (postRefreshCurrent == null) {
          throw AuthExpiredException('Session changed during token refresh; aborting retry.');
        }
        if (originatingSession.userId.isNotEmpty &&
            postRefreshCurrent.userId.isNotEmpty &&
            postRefreshCurrent.userId != originatingSession.userId) {
          throw AuthExpiredException(
              'User account changed during token refresh (orig: ${originatingSession.userId}, current: ${postRefreshCurrent.userId}); aborting retry.');
        }
        if (originatingSession.tenantId.isNotEmpty &&
            postRefreshCurrent.tenantId.isNotEmpty &&
            postRefreshCurrent.tenantId != originatingSession.tenantId) {
          throw AuthExpiredException(
              'Tenant changed during token refresh (orig: ${originatingSession.tenantId}, current: ${postRefreshCurrent.tenantId}); aborting retry.');
        }

        // Finding: Preserve transport errors from the retried request (do NOT catch and convert to AuthExpiredException)
        final retryRequest = _cloneRequest(request);
        retryRequest.headers['Authorization'] = 'Bearer ${refreshedSession.accessToken}';
        response = await _inner.send(retryRequest);
      }
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
  }
}
