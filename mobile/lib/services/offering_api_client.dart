import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/offering_models.dart';

/// Exception thrown when offerings API communication fails.
class OfferingApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  const OfferingApiException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'OfferingApiException ($statusCode): $message';
    }
    return 'OfferingApiException: $message';
  }
}

/// Abstract contract for the offerings and UPI contribution ledger API client.
abstract class OfferingApiClient {
  /// Fetches church giving config including UPI payee details and available funds.
  Future<ChurchGivingConfig> getGivingConfig();

  /// Records a member contribution intent or submitted payment reference.
  Future<Contribution> recordContribution(RecordContributionInput input);

  /// Fetches the authenticated member's personal contribution history.
  Future<List<Contribution>> getMyContributions();

  /// Fetches the church-wide contribution ledger (Pastor/Admin role required).
  Future<List<Contribution>> getLedger({
    OfferingFundType? fundType,
    ContributionStatus? status,
  });

  /// Verifies a contribution in the ledger (Pastor/Admin role required).
  Future<Contribution> verifyContribution(
    String id, {
    String? transactionReference,
    String? verificationNote,
  });

  /// Fetches aggregated ledger totals by fund category (Pastor/Admin role required).
  Future<LedgerSummary> getLedgerSummary();
}

/// HTTP implementation of [OfferingApiClient].
class HttpOfferingApiClient implements OfferingApiClient {
  final http.Client _client;
  final String baseUrl;
  final int maxRetries;

  HttpOfferingApiClient({
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
          throw OfferingApiException(
            'Network connection error: ${e.message}',
            endpoint: endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } on TimeoutException catch (e) {
        if (attempts > maxRetries) {
          throw OfferingApiException(
            'Request timed out: ${e.message}',
            endpoint: endpoint,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * attempts));
      } catch (e) {
        if (e is OfferingApiException) rethrow;
        throw OfferingApiException(
          'Unexpected request failure: $e',
          endpoint: endpoint,
        );
      }
    }
  }

  @override
  Future<ChurchGivingConfig> getGivingConfig() async {
    const endpoint = '/api/v1/offerings/config';
    final uri = _buildUri(endpoint);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChurchGivingConfig.fromJson(data);
    }

    throw OfferingApiException(
      'Failed to load church giving configuration.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<Contribution> recordContribution(RecordContributionInput input) async {
    const endpoint = '/api/v1/offerings/contributions';
    final uri = _buildUri(endpoint);
    final body = jsonEncode(input.toJson());

    final response = await _executeWithRetry(
      endpoint,
      () => _client.post(uri, headers: _buildHeaders(), body: body),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Contribution.fromJson(data);
    }

    String errorMsg = 'Failed to record contribution.';
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed.containsKey('error')) {
        errorMsg = parsed['error'].toString();
      }
    } catch (_) {}

    throw OfferingApiException(
      errorMsg,
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<List<Contribution>> getMyContributions() async {
    const endpoint = '/api/v1/offerings/my-contributions';
    final uri = _buildUri(endpoint);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((item) => Contribution.fromJson(item as Map<String, dynamic>)).toList();
    }

    throw OfferingApiException(
      'Failed to fetch member contributions.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<List<Contribution>> getLedger({
    OfferingFundType? fundType,
    ContributionStatus? status,
  }) async {
    const endpoint = '/api/v1/offerings/ledger';
    final queryParams = <String, String>{};
    if (fundType != null) {
      queryParams['fundType'] = fundType.toString().split('.').last;
    }
    if (status != null) {
      queryParams['status'] = status.toString().split('.').last;
    }

    final uri = _buildUri(endpoint, queryParams);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((item) => Contribution.fromJson(item as Map<String, dynamic>)).toList();
    }

    if (response.statusCode == 403) {
      throw OfferingApiException(
        'Access denied: Church ledger is restricted to pastoral leadership.',
        statusCode: 403,
        endpoint: endpoint,
      );
    }

    throw OfferingApiException(
      'Failed to load church contribution ledger.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<Contribution> verifyContribution(
    String id, {
    String? transactionReference,
    String? verificationNote,
  }) async {
    final endpoint = '/api/v1/offerings/$id/verify';
    final uri = _buildUri(endpoint);
    final payload = <String, dynamic>{};
    if (transactionReference != null && transactionReference.trim().isNotEmpty) {
      payload['transactionReference'] = transactionReference.trim();
    }
    if (verificationNote != null && verificationNote.trim().isNotEmpty) {
      payload['verificationNote'] = verificationNote.trim();
    }

    final response = await _executeWithRetry(
      endpoint,
      () => _client.post(uri, headers: _buildHeaders(), body: jsonEncode(payload)),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Contribution.fromJson(data);
    }

    if (response.statusCode == 403) {
      throw OfferingApiException(
        'Access denied: Only pastoral leadership can verify contributions.',
        statusCode: 403,
        endpoint: endpoint,
      );
    }

    throw OfferingApiException(
      'Failed to verify contribution.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  @override
  Future<LedgerSummary> getLedgerSummary() async {
    const endpoint = '/api/v1/offerings/ledger/summary';
    final uri = _buildUri(endpoint);
    final response = await _executeWithRetry(
      endpoint,
      () => _client.get(uri, headers: _buildHeaders()),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LedgerSummary.fromJson(data);
    }

    if (response.statusCode == 403) {
      throw OfferingApiException(
        'Access denied: Ledger summary is restricted to pastoral leadership.',
        statusCode: 403,
        endpoint: endpoint,
      );
    }

    throw OfferingApiException(
      'Failed to fetch ledger summary.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }
}
