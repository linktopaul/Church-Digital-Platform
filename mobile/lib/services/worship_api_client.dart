import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/worship_models.dart';
import '../network/api_exceptions.dart';

/// Exception thrown when worship API communication fails.
class WorshipApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const WorshipApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'WorshipApiException ($statusCode): $message';
    }
    return 'WorshipApiException: $message';
  }
}

/// Abstract contract for the worship songs and Sunday setlists API client.
abstract class WorshipApiClient {
  /// Fetches all songs in the tenant's worship library.
  Future<List<SongItem>> getSongs();

  /// Fetches a single song by ID.
  Future<SongItem> getSong(String id);

  /// Creates a new song in the worship library (requires Admin, Pastor, or WorshipLeader role).
  Future<SongItem> createSong(SongInput input);

  /// Updates an existing song in the worship library (requires Admin, Pastor, or WorshipLeader role).
  Future<SongItem> updateSong(String id, SongInput input);

  /// Deletes a song from the worship library (requires Admin, Pastor, or WorshipLeader role).
  Future<void> deleteSong(String id);

  /// Fetches all Sunday service setlists in the tenant's worship library.
  Future<List<SetlistItemData>> getSetlists();

  /// Fetches a single Sunday service setlist with its ordered song items.
  Future<SetlistItemData> getSetlist(String id);

  /// Creates a new Sunday service setlist (requires Admin, Pastor, or WorshipLeader role).
  Future<SetlistItemData> createSetlist(SetlistInput input);

  /// Updates an existing Sunday service setlist (requires Admin, Pastor, or WorshipLeader role).
  Future<SetlistItemData> updateSetlist(String id, SetlistInput input);

  /// Deletes a Sunday service setlist (requires Admin, Pastor, or WorshipLeader role).
  Future<void> deleteSetlist(String id);
}

/// HTTP implementation of [WorshipApiClient].
///
/// Requires an injected [http.Client] (such as [AuthenticatedHttpClient]) and [baseUrl].
/// Fails closed if not provided: no mock anonymous production client or insecure
/// localhost fallback.
class HttpWorshipApiClient implements WorshipApiClient {
  final http.Client _client;
  final String baseUrl;
  final int maxRetries;

  HttpWorshipApiClient({
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
    if (baseUrl.endsWith('/api/v1') && cleanPath.startsWith('/api/v1/')) {
      final suffix = cleanPath.substring('/api/v1'.length);
      return Uri.parse('$baseUrl$suffix');
    }
    return Uri.parse('$baseUrl$cleanPath');
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<http.Response> _executeRequest(
    Future<http.Response> Function() action, {
    required String endpoint,
    bool retryable = true,
  }) async {
    int attempts = 0;
    final maxAttempts = retryable ? maxRetries + 1 : 1;
    while (true) {
      attempts++;
      try {
        final response = await action();
        return response;
      } on ProhibitedHeaderException {
        rethrow;
      } on AuthExpiredException catch (e) {
        throw WorshipApiException(
          e.message,
          statusCode: 401,
          endpoint: endpoint,
        );
      } on ForbiddenException catch (e) {
        throw WorshipApiException(
          e.message,
          statusCode: 403,
          endpoint: endpoint,
        );
      } on SocketException catch (e) {
        if (attempts >= maxAttempts) {
          throw WorshipApiException(
            'Network connection error. Please check your internet connection.',
            endpoint: e.address?.host ?? endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on http.ClientException catch (e) {
        if (attempts >= maxAttempts) {
          throw WorshipApiException(
            'Network request failed. Please check your connection and try again.',
            endpoint: e.uri?.path ?? endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on TimeoutException {
        if (attempts >= maxAttempts) {
          throw WorshipApiException(
            'Request timed out. Please try again.',
            endpoint: endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      }
    }
  }

  WorshipApiException _handleHttpError(http.Response response, String endpoint) {
    final statusCode = response.statusCode;
    String? serverError;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] != null) {
        serverError = decoded['error'].toString();
      } else if (decoded is Map<String, dynamic> && decoded['message'] != null) {
        serverError = decoded['message'].toString();
      }
    } catch (_) {
      serverError = null;
    }

    switch (statusCode) {
      case 400:
        return WorshipApiException(
          'Invalid request: ${serverError ?? 'Server returned status 400'}',
          statusCode: 400,
          endpoint: endpoint,
        );
      case 401:
        return WorshipApiException(
          'Authentication required. Please sign in.',
          statusCode: 401,
          endpoint: endpoint,
        );
      case 403:
        return WorshipApiException(
          'Access denied. You do not have permission for this worship action.',
          statusCode: 403,
          endpoint: endpoint,
        );
      case 404:
        return WorshipApiException(
          serverError ?? 'The requested worship resource was not found.',
          statusCode: 404,
          endpoint: endpoint,
        );
      case 500:
      default:
        return WorshipApiException(
          'A server error occurred. Please try again later.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
    }
  }

  @override
  Future<List<SongItem>> getSongs() async {
    const endpoint = '/api/v1/worship/songs';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
      endpoint: endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return decoded
          .whereType<Map>()
          .map((item) => SongItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SongItem> getSong(String id) async {
    final endpoint = '/api/v1/worship/songs/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
      endpoint: endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SongItem.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SongItem> createSong(SongInput input) async {
    const endpoint = '/api/v1/worship/songs';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.post(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SongItem.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SongItem> updateSong(String id, SongInput input) async {
    final endpoint = '/api/v1/worship/songs/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.put(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SongItem.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<void> deleteSong(String id) async {
    final endpoint = '/api/v1/worship/songs/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.delete(uri, headers: _buildHeaders()),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<List<SetlistItemData>> getSetlists() async {
    const endpoint = '/api/v1/worship/setlists';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
      endpoint: endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return decoded
          .whereType<Map>()
          .map((item) =>
              SetlistItemData.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SetlistItemData> getSetlist(String id) async {
    final endpoint = '/api/v1/worship/setlists/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
      endpoint: endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SetlistItemData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SetlistItemData> createSetlist(SetlistInput input) async {
    const endpoint = '/api/v1/worship/setlists';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.post(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SetlistItemData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<SetlistItemData> updateSetlist(String id, SetlistInput input) async {
    final endpoint = '/api/v1/worship/setlists/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.put(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw WorshipApiException(
          'Unexpected response format from server.',
          endpoint: endpoint,
        );
      }
      return SetlistItemData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<void> deleteSetlist(String id) async {
    final endpoint = '/api/v1/worship/setlists/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.delete(uri, headers: _buildHeaders()),
      endpoint: endpoint,
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw _handleHttpError(response, endpoint);
  }
}
