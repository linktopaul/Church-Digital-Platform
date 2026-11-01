import 'dart:async';
import 'package:http/http.dart' as http;
import '../auth/auth_session_manager.dart';
import '../auth/auth_provider.dart';
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
    final identity = _authService.sessionIdentity;
    final currentSession = _authService.currentSession;
    if (currentSession != null && currentSession.accessToken.isNotEmpty) {
      initialRequest.headers['Authorization'] = 'Bearer ${currentSession.accessToken}';
    }

    // 4. Send request
    http.StreamedResponse response = await _inner.send(initialRequest);

    // Only discard responses we cannot return or will replace. Cancellation
    // releases streaming resources without waiting for an unbounded error body.
    if (response.statusCode == 401 && canRetry && currentSession != null) {
      if (!identical(identity, _authService.sessionIdentity)) {
        await response.stream.listen(null).cancel();
        throw const AuthExpiredException('Session changed during request');
      }
      if (currentSession.refreshToken?.isNotEmpty == true) {
        await response.stream.listen(null).cancel();
        if (!identical(identity, _authService.sessionIdentity)) {
          throw const AuthExpiredException('Session changed during request');
        }
        final refreshedSession = await (() async {
          try {
            return await _authService.refresh();
          } on TerminalAuthException {
            throw const AuthExpiredException();
          }
        })();
        if (!identical(identity, _authService.sessionIdentity) ||
            refreshedSession.userId != currentSession.userId ||
            refreshedSession.tenantId != currentSession.tenantId) {
          throw const AuthExpiredException('Session changed during refresh');
        }
        final retryRequest = _cloneRequest(request);
        retryRequest.headers['Authorization'] = 'Bearer ${refreshedSession.accessToken}';
        // Transport errors here remain transport errors, not authentication errors.
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
