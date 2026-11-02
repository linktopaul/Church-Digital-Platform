import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/member_models.dart';

/// Exception thrown when member profile or directory API communication fails.
class MemberApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const MemberApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'MemberApiException ($statusCode): $message';
    }
    return 'MemberApiException: $message';
  }
}

/// Abstract contract for the member profile and family directory API client.
abstract class MemberApiClient {
  /// Fetches the profile of the currently authenticated member.
  Future<MemberProfile> getMyProfile();

  /// Updates the profile and privacy settings of the currently authenticated member.
  Future<MemberProfile> updateMyProfile(UpdateMemberProfileInput input);

  /// Fetches the church member directory (respecting privacy visibility rules).
  Future<List<DirectoryMember>> getDirectory({String? search});

  /// Fetches an individual member by ID from the directory.
  Future<DirectoryMember> getMember(String id);

  /// Fetches family unit details and visible family members by family ID.
  Future<FamilyData> getFamily(String id);
}

/// HTTP implementation of [MemberApiClient].
class HttpMemberApiClient implements MemberApiClient {
  final http.Client _client;
  final String baseUrl;
  final int maxRetries;

  HttpMemberApiClient({
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

  Future<http.Response> _executeRequest(
    Future<http.Response> Function() action, {
    bool retryable = true,
  }) async {
    int attempts = 0;
    final maxAttempts = retryable ? maxRetries + 1 : 1;
    while (true) {
      attempts++;
      try {
        final response = await action();
        return response;
      } on SocketException catch (e) {
        if (attempts >= maxAttempts) {
          throw MemberApiException(
            'Network connection error. Please check your internet connection.',
            endpoint: e.address?.host,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on http.ClientException catch (e) {
        if (attempts >= maxAttempts) {
          throw MemberApiException(
            'Network request failed. Please check your connection and try again.',
            endpoint: e.uri?.path,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on TimeoutException {
        if (attempts >= maxAttempts) {
          throw const MemberApiException('Request timed out. Please try again.');
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      }
    }
  }

  MemberApiException _handleHttpError(http.Response response, String endpoint) {
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
        return MemberApiException('Invalid request: $errorMessage', statusCode: 400, endpoint: endpoint);
      case 401:
        return MemberApiException('Authentication required. Please sign in.', statusCode: 401, endpoint: endpoint);
      case 403:
        return MemberApiException('Access denied. You do not have permission for this member action.', statusCode: 403, endpoint: endpoint);
      case 404:
        return MemberApiException('The requested member or family was not found.', statusCode: 404, endpoint: endpoint);
      case 500:
      default:
        return MemberApiException('A server error occurred. Please try again later.', statusCode: statusCode, endpoint: endpoint);
    }
  }

  @override
  Future<MemberProfile> getMyProfile() async {
    const endpoint = '/api/v1/members/me';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MemberApiException('Unexpected response format from server.');
      }
      return MemberProfile.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<MemberProfile> updateMyProfile(UpdateMemberProfileInput input) async {
    const endpoint = '/api/v1/members/me';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.put(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(input.toJson()),
      ),
      retryable: false,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MemberApiException('Unexpected response format from server.');
      }
      return MemberProfile.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<List<DirectoryMember>> getDirectory({String? search}) async {
    const endpoint = '/api/v1/members';
    final queryParams = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      queryParams['search'] = search.trim();
    }
    final uri = _buildUri(endpoint, queryParams.isEmpty ? null : queryParams);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const MemberApiException('Unexpected response format from server.');
      }
      return decoded
          .map((item) => DirectoryMember.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<DirectoryMember> getMember(String id) async {
    final endpoint = '/api/v1/members/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MemberApiException('Unexpected response format from server.');
      }
      return DirectoryMember.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }

  @override
  Future<FamilyData> getFamily(String id) async {
    final endpoint = '/api/v1/members/families/$id';
    final uri = _buildUri(endpoint);

    final response = await _executeRequest(
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MemberApiException('Unexpected response format from server.');
      }
      return FamilyData.fromJson(decoded);
    }

    throw _handleHttpError(response, endpoint);
  }
}
