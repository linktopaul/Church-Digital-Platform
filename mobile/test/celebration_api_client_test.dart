import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/models/celebration_models.dart';
import 'package:church_digital_platform_mobile/services/celebration_api_client.dart';

void main() {
  group('HttpCelebrationApiClient', () {
    test('getTodayCelebrations requests correct endpoint and parses items', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final responsePayload = [
          {
            'memberId': 'm-1',
            'memberName': 'Grace Hopper',
            'avatarUrl': null,
            'type': 0,
            'date': '2026-11-03T00:00:00Z',
            'years': 41,
            'phoneNumber': '+15551234567',
            'whatsAppUrl': 'https://wa.me/15551234567?text=blessing',
            'canMessageDirectly': true,
          }
        ];
        return http.Response(json.encode(responsePayload), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HttpCelebrationApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final date = DateTime.utc(2026, 11, 3);
      final results = await client.getTodayCelebrations(date: date);

      expect(recordedRequest.method, 'GET');
      expect(recordedRequest.url.path, '/api/v1/celebrations/today');
      expect(recordedRequest.url.queryParameters['date'], '2026-11-03');
      expect(results, hasLength(1));
      expect(results.first.memberName, 'Grace Hopper');
      expect(results.first.type, CelebrationType.birthday);
      expect(results.first.canMessageDirectly, isTrue);
    });

    test('getUpcomingCelebrations requests with days query param and parses list', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        final responsePayload = [
          {
            'memberId': 'm-2',
            'memberName': 'David Livingstone',
            'type': 1,
            'date': '2026-11-06T00:00:00Z',
            'years': 15,
            'phoneNumber': null,
            'whatsAppUrl': null,
            'canMessageDirectly': false,
          }
        ];
        return http.Response(json.encode(responsePayload), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HttpCelebrationApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final results = await client.getUpcomingCelebrations(days: 14);

      expect(recordedRequest.method, 'GET');
      expect(recordedRequest.url.path, '/api/v1/celebrations/upcoming');
      expect(recordedRequest.url.queryParameters['days'], '14');
      expect(results, hasLength(1));
      expect(results.first.memberName, 'David Livingstone');
      expect(results.first.type, CelebrationType.anniversary);
      expect(results.first.canMessageDirectly, isFalse);
    });

    test('getBlessingTemplates returns pre-approved scripture templates', () async {
      final mockClient = MockClient((request) async {
        final payload = [
          {
            'type': 0,
            'title': 'Birthday Blessing',
            'template': 'Dear {name}, happy birthday!',
            'defaultScripture': 'Numbers 6:24-25',
          },
          {
            'type': 1,
            'title': 'Anniversary Blessing',
            'template': 'Dear {name}, happy anniversary!',
            'defaultScripture': '1 Corinthians 13:7',
          }
        ];
        return http.Response(json.encode(payload), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HttpCelebrationApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final templates = await client.getBlessingTemplates();
      expect(templates, hasLength(2));
      expect(templates.first.title, 'Birthday Blessing');
      expect(templates.last.title, 'Anniversary Blessing');
    });

    test('triggerDailyScan sends POST to scan-daily and parses result', () async {
      late http.BaseRequest recordedRequest;

      final mockClient = MockClient((request) async {
        recordedRequest = request;
        return http.Response(
          json.encode({
            'date': '2026-11-03T00:00:00Z',
            'celebrationsFound': 2,
            'status': 'Completed',
            'message': 'Daily scan completed.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpCelebrationApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      final res = await client.triggerDailyScan();
      expect(recordedRequest.method, 'POST');
      expect(recordedRequest.url.path, '/api/v1/celebrations/scan-daily');
      expect(res['status'], 'Completed');
      expect(res['celebrationsFound'], 2);
    });

    test('HTTP error throws CelebrationApiException with status code', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final client = HttpCelebrationApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.example',
      );

      expect(
        () => client.getTodayCelebrations(),
        throwsA(isA<CelebrationApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}
