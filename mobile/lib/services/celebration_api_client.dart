import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/celebration_models.dart';

/// Exception thrown when celebration API communication fails.
class CelebrationApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const CelebrationApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'CelebrationApiException ($statusCode): $message';
    }
    return 'CelebrationApiException: $message';
  }
}

/// Abstract contract for the celebrations and blessings API client.
abstract class CelebrationApiClient {
  /// Fetches celebrations happening today (or as of the specified date).
  Future<List<CelebrationEvent>> getTodayCelebrations({DateTime? date});

  /// Fetches upcoming celebrations for the specified day window (default 7 days).
  Future<List<CelebrationEvent>> getUpcomingCelebrations({int days = 7, DateTime? startDate});

  /// Fetches pre-approved scripture blessing templates.
  Future<List<BlessingTemplate>> getBlessingTemplates();

  /// Triggers a daily scan for celebrations (Pastor/Admin privilege required).
  Future<Map<String, dynamic>> triggerDailyScan({DateTime? date});
}

/// HTTP implementation of [CelebrationApiClient].
class HttpCelebrationApiClient implements CelebrationApiClient {
  final http.Client _client;
  final String baseUrl;
  final int maxRetries;

  HttpCelebrationApiClient({
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

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    final parsed = Uri.parse(fullUrl);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      return parsed.replace(queryParameters: queryParameters);
    }
    return parsed;
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<http.Response> _executeWithRetry(
    String endpoint,
    Future<http.Response> Function() requestFn,
  ) async {
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await requestFn();
        if (response.statusCode >= 500 && attempts <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 100 * attempts));
          continue;
        }
        return response;
      } on SocketException catch (e) {
        if (attempts > maxRetries) {
          throw CelebrationApiException(
            'Network connection error: ${e.message}',
            endpoint: endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on TimeoutException {
        if (attempts > maxRetries) {
          throw CelebrationApiException(
            'Request timed out',
            endpoint: endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      }
    }
  }

  @override
  Future<List<CelebrationEvent>> getTodayCelebrations({DateTime? date}) async {
    const endpoint = '/api/v1/celebrations/today';
    final queryParams = <String, String>{};
    if (date != null) {
      queryParams['date'] = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }

    final uri = _buildUri(endpoint, queryParams);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded
            .map((item) => CelebrationEvent.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    }

    throw CelebrationApiException(
      'Failed to load today celebrations: ${response.body}',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<List<CelebrationEvent>> getUpcomingCelebrations({int days = 7, DateTime? startDate}) async {
    const endpoint = '/api/v1/celebrations/upcoming';
    final queryParams = <String, String>{'days': days.toString()};
    if (startDate != null) {
      queryParams['startDate'] = '${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    }

    final uri = _buildUri(endpoint, queryParams);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded
            .map((item) => CelebrationEvent.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    }

    throw CelebrationApiException(
      'Failed to load upcoming celebrations: ${response.body}',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<List<BlessingTemplate>> getBlessingTemplates() async {
    const endpoint = '/api/v1/celebrations/templates';
    final uri = _buildUri(endpoint);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded
            .map((item) => BlessingTemplate.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    }

    throw CelebrationApiException(
      'Failed to load blessing templates: ${response.body}',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<Map<String, dynamic>> triggerDailyScan({DateTime? date}) async {
    const endpoint = '/api/v1/celebrations/scan-daily';
    final queryParams = <String, String>{};
    if (date != null) {
      queryParams['date'] = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }

    final uri = _buildUri(endpoint, queryParams);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.post(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw CelebrationApiException(
      'Failed to run daily celebration scan: ${response.body}',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }
}
