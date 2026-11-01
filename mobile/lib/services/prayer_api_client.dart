import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/prayer_models.dart';

/// Exception thrown when prayer API communication fails.
///
/// Guardrail: Privacy-safe. Does not echo confidential prayer request content
/// into exception message, stack trace, or crash logging.
class PrayerApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const PrayerApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'PrayerApiException ($statusCode): $message';
    }
    return 'PrayerApiException: $message';
  }
}

/// Abstract contract for the prayer requests API client.
abstract class PrayerApiClient {
  /// Fetches prayer requests authored by the authenticated member.
  Future<List<PrayerRequestData>> getMyPrayerRequests();

  /// Fetches all prayer requests across the tenant (requires Pastor authorization).
  Future<List<PrayerRequestData>> getAllPrayerRequests();

  /// Submits a new confidential prayer request.
  Future<PrayerRequestData> createPrayerRequest(CreatePrayerRequestInput input);

  /// Updates the status of an existing prayer request (requires Pastor authorization).
  Future<PrayerRequestData> updatePrayerRequestStatus(
    String id,
    UpdatePrayerRequestStatusInput input,
  );
}

/// HTTP implementation of [PrayerApiClient].
///
/// Requires an injected [http.Client] (such as AuthenticatedHttpClient) and [baseUrl].
/// Fails closed if not provided: no mock anonymous production client or insecure
/// localhost fallback.
class HttpPrayerApiClient implements PrayerApiClient {
  final http.Client _client;
  final String baseUrl;
  final int maxRetries;

  HttpPrayerApiClient({
    required http.Client client,
    required String baseUrl,
    this.maxRetries = 2,
  })  : _client = client,
        baseUrl = _normalizeBaseUrl(baseUrl);

  static String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _buildUri(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$cleanPath');
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<http.Response> _executeWithRetry(Future<http.Response> Function() action) async {
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await action();
        return response;
      } on SocketException catch (e) {
        if (attempts > maxRetries) {
          throw PrayerApiException(
            'Network connection error. Please check your internet connection.',
            endpoint: e.address?.host,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on http.ClientException catch (e) {
        if (attempts > maxRetries) {
          throw PrayerApiException(
            'Network request failed: ${e.message}',
            endpoint: e.uri?.path,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on TimeoutException {
        if (attempts > maxRetries) {
          throw const PrayerApiException('Request timed out. Please try again.');
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      }
    }
  }

  PrayerApiException _handleHttpError(http.Response response, String endpoint) {
    final statusCode = response.statusCode;
    String errorMessage;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
        errorMessage = decoded['error']?.toString() ?? 'Request failed';
      } else if (decoded is Map<String, dynamic> && decoded.containsKey('message')) {
        errorMessage = decoded['message']?.toString() ?? 'Request failed';
      } else {
        errorMessage = 'Server returned status $statusCode';
      }
    } catch (_) {
      errorMessage = 'Server returned status $statusCode';
    }

    switch (statusCode) {
      case 400:
        return PrayerApiException('Invalid request: $errorMessage', statusCode: 400, endpoint: endpoint);
      case 401:
        return PrayerApiException('Authentication required. Please sign in.', statusCode: 401, endpoint: endpoint);
      case 403:
        return PrayerApiException('Access denied. You do not have permission for this prayer action.', statusCode: 403, endpoint: endpoint);
      case 404:
        return PrayerApiException('The requested prayer request was not found.', statusCode: 404, endpoint: endpoint);
      case 500:
      default:
        return PrayerApiException('A server error occurred. Please try again later.', statusCode: statusCode, endpoint: endpoint);
    }
  }

  @override
  Future<List<PrayerRequestData>> getMyPrayerRequests() async {
    const endpoint = '/api/v1/prayer-requests/my';
    final uri = _buildUri(endpoint);

    final response = await _executeWithRetry(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const PrayerApiException('Unexpected response format from server.');
      }
      return decoded
          .map((item) => PrayerRequestData.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<List<PrayerRequestData>> getAllPrayerRequests() async {
    const endpoint = '/api/v1/prayer-requests';
    final uri = _buildUri(endpoint);

    final response = await _executeWithRetry(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const PrayerApiException('Unexpected response format from server.');
      }
      return decoded
          .map((item) => PrayerRequestData.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<PrayerRequestData> createPrayerRequest(CreatePrayerRequestInput input) async {
    const endpoint = '/api/v1/prayer-requests';
    final uri = _buildUri(endpoint);

    final response = await _executeWithRetry(
      () => _client.post(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const PrayerApiException('Unexpected response format from server.');
      }
      return PrayerRequestData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<PrayerRequestData> updatePrayerRequestStatus(
    String id,
    UpdatePrayerRequestStatusInput input,
  ) async {
    final endpoint = '/api/v1/prayer-requests/$id/status';
    final uri = _buildUri(endpoint);

    final response = await _executeWithRetry(
      () => _client.patch(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const PrayerApiException('Unexpected response format from server.');
      }
      return PrayerRequestData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }
}
