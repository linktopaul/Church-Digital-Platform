import 'dart:async';
import 'package:http/http.dart' as http;
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

    // 3. Attach Bearer token from active session if present
    final currentSession = _authService.currentSession;
    if (currentSession != null && currentSession.accessToken.isNotEmpty) {
      initialRequest.headers['Authorization'] = 'Bearer ${currentSession.accessToken}';
    }

    // 4. Send request
    http.StreamedResponse response = await _inner.send(initialRequest);

    // 5. If 401 Unauthorized received and we have a session with a refresh token, attempt refresh & retry once
    if (response.statusCode == 401 && canRetry) {
      final session = _authService.currentSession;
      if (session != null && session.refreshToken != null && session.refreshToken!.isNotEmpty) {
        try {
          final refreshedSession = await _authService.refresh();

          // Prepare retry request with fresh access token
          final retryRequest = _cloneRequest(request);
          retryRequest.headers['Authorization'] = 'Bearer ${refreshedSession.accessToken}';

          response = await _inner.send(retryRequest);
        } catch (e) {
          // Token refresh failed or session was revoked; let 401 response pass or propagate AuthExpiredException
          throw AuthExpiredException('Session refresh failed: $e');
        }
      }
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
  }
}
