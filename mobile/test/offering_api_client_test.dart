import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/models/offering_models.dart';
import 'package:church_digital_platform_mobile/services/offering_api_client.dart';

void main() {
  group('HttpOfferingApiClient', () {
    test('getGivingConfig parses config response correctly', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final payload = {
          'upiId': 'churchgiving@upi',
          'payeeName': 'Church Digital Platform',
          'currency': 'INR',
          'availableFunds': [
            {'fundType': 0, 'name': 'Tithe', 'description': '10% tithe'},
            {'fundType': 1, 'name': 'General Offering', 'description': 'Regular'}
          ]
        };
        return http.Response(json.encode(payload), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final config = await client.getGivingConfig();

      expect(recordedRequest.method, 'GET');
      expect(recordedRequest.url.path, '/api/v1/offerings/config');
      expect(config.upiId, 'churchgiving@upi');
      expect(config.availableFunds, hasLength(2));
    });

    test('recordContribution posts input payload and returns created contribution', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final payload = {
          'id': 'contrib-123',
          'memberId': 'mem-456',
          'memberName': 'Grace Hopper',
          'fundType': 0,
          'fundName': 'Tithe',
          'amount': 1500.0,
          'currency': 'INR',
          'transactionReference': 'UTR123456',
          'upiPayeeId': 'churchgiving@upi',
          'upiIntentUri': 'upi://pay?pa=churchgiving@upi&am=1500.00',
          'paymentNote': 'Tithe',
          'status': 1,
          'receiptNumber': 'REC-20261103-XYZ',
          'createdAt': '2026-11-03T10:00:00Z',
        };
        return http.Response(json.encode(payload), 201, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final input = const RecordContributionInput(
        fundType: OfferingFundType.tithe,
        amount: 1500.0,
        currency: 'INR',
        paymentNote: 'Tithe',
        transactionReference: 'UTR123456',
      );

      final res = await client.recordContribution(input);

      expect(recordedRequest.method, 'POST');
      expect(recordedRequest.url.path, '/api/v1/offerings/contributions');
      expect(res.id, 'contrib-123');
      expect(res.status, ContributionStatus.submitted);
      expect(res.receiptNumber, 'REC-20261103-XYZ');
    });

    test('recordContribution throws OfferingApiException on bad request', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'error': 'Contribution amount must be greater than zero.'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      expect(
        () => client.recordContribution(
          const RecordContributionInput(
            fundType: OfferingFundType.generalOffering,
            amount: 0.0,
          ),
        ),
        throwsA(isA<OfferingApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('getMyContributions retrieves member history', () async {
      final mockClient = MockClient((request) async {
        final list = [
          {
            'id': 'c-1',
            'memberId': 'm-1',
            'memberName': 'Grace',
            'fundType': 1,
            'fundName': 'General Offering',
            'amount': 500.0,
            'currency': 'INR',
            'upiPayeeId': 'church@upi',
            'upiIntentUri': 'upi://pay',
            'status': 2,
            'receiptNumber': 'REC-01',
            'createdAt': '2026-11-03T10:00:00Z',
          }
        ];
        return http.Response(json.encode(list), 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final history = await client.getMyContributions();
      expect(history, hasLength(1));
      expect(history.first.receiptNumber, 'REC-01');
      expect(history.first.status, ContributionStatus.verified);
    });

    test('getLedger sends query parameters and returns records for pastors', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final list = [
          {
            'id': 'c-2',
            'memberId': 'm-2',
            'memberName': 'David',
            'fundType': 0,
            'fundName': 'Tithe',
            'amount': 2000.0,
            'currency': 'INR',
            'upiPayeeId': 'church@upi',
            'upiIntentUri': 'upi://pay',
            'status': 0,
            'receiptNumber': 'REC-02',
            'createdAt': '2026-11-03T10:00:00Z',
          }
        ];
        return http.Response(json.encode(list), 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final ledger = await client.getLedger(
        fundType: OfferingFundType.tithe,
        status: ContributionStatus.pending,
      );

      expect(recordedRequest.method, 'GET');
      expect(recordedRequest.url.path, '/api/v1/offerings/ledger');
      expect(recordedRequest.url.queryParameters['fundType'], 'tithe');
      expect(recordedRequest.url.queryParameters['status'], 'pending');
      expect(ledger, hasLength(1));
    });

    test('getLedger throws 403 Forbidden for unprivileged callers', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      expect(
        () => client.getLedger(),
        throwsA(isA<OfferingApiException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('verifyContribution calls verify endpoint with payload', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final payload = {
          'id': 'c-100',
          'memberId': 'm-100',
          'memberName': 'Ruth',
          'fundType': 2,
          'fundName': 'Missions & Outreach',
          'amount': 800.0,
          'currency': 'INR',
          'transactionReference': 'BANK-UTR-555',
          'upiPayeeId': 'church@upi',
          'upiIntentUri': 'upi://pay',
          'paymentNote': '[Verified]: Matched statement',
          'status': 2,
          'receiptNumber': 'REC-100',
          'verifiedBy': 'Pastor',
          'verifiedAt': '2026-11-03T11:00:00Z',
          'createdAt': '2026-11-03T10:00:00Z',
        };
        return http.Response(json.encode(payload), 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final verified = await client.verifyContribution(
        'c-100',
        transactionReference: 'BANK-UTR-555',
        verificationNote: 'Matched statement',
      );

      expect(recordedRequest.method, 'POST');
      expect(recordedRequest.url.path, '/api/v1/offerings/c-100/verify');
      expect(verified.status, ContributionStatus.verified);
      expect(verified.verifiedBy, 'Pastor');
    });

    test('getLedgerSummary parses aggregated totals', () async {
      final mockClient = MockClient((request) async {
        final payload = {
          'totalAmount': 10000.0,
          'totalCount': 10,
          'verifiedAmount': 8000.0,
          'pendingAmount': 2000.0,
          'byFundType': {'Tithe': 6000.0, 'GeneralOffering': 4000.0},
          'generatedAt': '2026-11-03T12:00:00Z',
        };
        return http.Response(json.encode(payload), 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpOfferingApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final summary = await client.getLedgerSummary();
      expect(summary.totalAmount, 10000.0);
      expect(summary.verifiedAmount, 8000.0);
      expect(summary.pendingAmount, 2000.0);
    });
  });
}
