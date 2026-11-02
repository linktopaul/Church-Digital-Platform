import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/models/prayer_models.dart';
import 'package:church_digital_platform_mobile/services/prayer_api_client.dart';

void main() {
  group('PrayerRequestStatus & Model Serialization', () {
    test('PrayerRequestStatus maps from int and string correctly', () {
      expect(PrayerRequestStatus.fromJson(0), PrayerRequestStatus.submitted);
      expect(PrayerRequestStatus.fromJson(1), PrayerRequestStatus.praying);
      expect(PrayerRequestStatus.fromJson(2), PrayerRequestStatus.answered);

      expect(PrayerRequestStatus.fromJson('Submitted'), PrayerRequestStatus.submitted);
      expect(PrayerRequestStatus.fromJson('Praying'), PrayerRequestStatus.praying);
      expect(PrayerRequestStatus.fromJson('Answered'), PrayerRequestStatus.answered);

      expect(PrayerRequestStatus.fromJson('unknown'), PrayerRequestStatus.submitted);
      expect(PrayerRequestStatus.fromJson(null), PrayerRequestStatus.submitted);
    });

    test('PrayerRequestData serialization handles int status and ISO timestamps', () {
      final json = {
        'id': 'p1',
        'churchId': 'c1',
        'memberId': 'm1',
        'content': 'Please pray for my mother.',
        'status': 1,
        'createdAt': '2026-11-01T10:00:00.000Z',
        'updatedAt': '2026-11-01T12:00:00.000Z',
      };

      final data = PrayerRequestData.fromJson(json);
      expect(data.id, 'p1');
      expect(data.churchId, 'c1');
      expect(data.memberId, 'm1');
      expect(data.content, 'Please pray for my mother.');
      expect(data.status, PrayerRequestStatus.praying);
      expect(data.status.displayName, 'Praying');

      final serialized = data.toJson();
      expect(serialized['id'], 'p1');
      expect(serialized['status'], 1);
    });

    test('PrayerRequestData redacts sensitive content in toString() for privacy', () {
      final data = PrayerRequestData(
        id: 'p1',
        churchId: 'c1',
        memberId: 'm1',
        content: 'Confidential medical issue details',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );

      final str = data.toString();
      expect(str.contains('Confidential medical issue details'), isFalse);
      expect(str.contains('[CONFIDENTIAL]'), isTrue);
    });
  });

  group('HttpPrayerApiClient', () {
    test('normalizes baseUrl with trailing slashes', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://api.example.com/api/v1/prayer-requests/my');
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpPrayerApiClient(
        client: mockClient,
        baseUrl: 'https://api.example.com///',
      );

      final res = await client.getMyPrayerRequests();
      expect(res, isEmpty);
    });

    test('getMyPrayerRequests parses list of prayer requests', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/prayer-requests/my');
        return http.Response(
          jsonEncode([
            {
              'id': 'req-1',
              'churchId': 'church-1',
              'memberId': 'user-1',
              'content': 'Need strength for exam',
              'status': 0,
              'createdAt': '2026-11-01T08:00:00.000Z',
              'updatedAt': '2026-11-01T08:00:00.000Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      final list = await client.getMyPrayerRequests();

      expect(list.length, 1);
      expect(list.first.id, 'req-1');
      expect(list.first.content, 'Need strength for exam');
      expect(list.first.status, PrayerRequestStatus.submitted);
    });

    test('getAllPrayerRequests calls pastor endpoint', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/prayer-requests');
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      final list = await client.getAllPrayerRequests();
      expect(list, isEmpty);
    });

    test('createPrayerRequest sends JSON body and parses created response', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/prayer-requests');
        final decodedBody = jsonDecode(request.body) as Map<String, dynamic>;
        expect(decodedBody['content'], 'Healing prayer');

        return http.Response(
          jsonEncode({
            'id': 'created-id',
            'churchId': 'church-1',
            'memberId': 'user-1',
            'content': 'Healing prayer',
            'status': 0,
            'createdAt': '2026-11-01T08:00:00.000Z',
            'updatedAt': '2026-11-01T08:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      final created = await client.createPrayerRequest(
        const CreatePrayerRequestInput(content: 'Healing prayer'),
      );

      expect(created.id, 'created-id');
      expect(created.content, 'Healing prayer');
    });

    test('updatePrayerRequestStatus sends PATCH with status enum', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/prayer-requests/req-9/status');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 1);

        return http.Response(
          jsonEncode({
            'id': 'req-9',
            'churchId': 'church-1',
            'memberId': 'user-1',
            'content': 'Existing prayer',
            'status': 1,
            'createdAt': '2026-11-01T08:00:00.000Z',
            'updatedAt': '2026-11-01T08:30:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      final updated = await client.updatePrayerRequestStatus(
        'req-9',
        const UpdatePrayerRequestStatusInput(status: PrayerRequestStatus.praying),
      );

      expect(updated.id, 'req-9');
      expect(updated.status, PrayerRequestStatus.praying);
    });

    test('throws typed PrayerApiException on 400 Bad Request', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Content is required.'}),
          400,
        );
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      expect(
        () => client.createPrayerRequest(const CreatePrayerRequestInput(content: '')),
        throwsA(
          isA<PrayerApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('Content is required')),
        ),
      );
    });

    test('throws typed PrayerApiException on 401 Unauthorized', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      expect(
        () => client.getMyPrayerRequests(),
        throwsA(
          isA<PrayerApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('Authentication required')),
        ),
      );
    });

    test('throws typed PrayerApiException on 403 Forbidden', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      expect(
        () => client.getAllPrayerRequests(),
        throwsA(
          isA<PrayerApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('Access denied')),
        ),
      );
    });

    test('throws typed PrayerApiException on 500 Internal Server Error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = HttpPrayerApiClient(client: mockClient, baseUrl: 'https://api.example.com');
      expect(
        () => client.getMyPrayerRequests(),
        throwsA(
          isA<PrayerApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('server error occurred')),
        ),
      );
    });

    test('retries on transient ClientException and succeeds', () async {
      int attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw http.ClientException('Connection reset by peer');
        }
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpPrayerApiClient(
        client: mockClient,
        baseUrl: 'https://api.example.com',
        maxRetries: 2,
      );

      final result = await client.getMyPrayerRequests();
      expect(result, isEmpty);
      expect(attempts, 2);
    });
  });
}
