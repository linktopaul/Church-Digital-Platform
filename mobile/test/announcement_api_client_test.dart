import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:church_digital_platform_mobile/models/announcement_models.dart';
import 'package:church_digital_platform_mobile/services/announcement_api_client.dart';
import 'package:church_digital_platform_mobile/network/api_exceptions.dart';

class MockClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;

  MockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
      headers: response.headers,
    );
  }
}

void main() {
  const baseUrl = 'http://test-api';

  group('DefaultAnnouncementApiClient', () {
    test('getAnnouncements parses successful response', () async {
      final mockData = [
        {
          'id': '1',
          'churchId': 'c1',
          'authorId': 'a1',
          'title': 'Test Title',
          'content': 'Test Content',
          'priority': 0,
          'publishedAt': '2026-01-01T10:00:00Z',
        }
      ];

      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/announcements');
        expect(request.method, 'GET');
        return http.Response(jsonEncode(mockData), 200);
      });

      final apiClient = DefaultAnnouncementApiClient(baseUrl: baseUrl, client: client);
      final result = await apiClient.getAnnouncements();

      expect(result.length, 1);
      expect(result.first.title, 'Test Title');
      expect(result.first.priority, AnnouncementPriority.routine);
    });

    test('getAnnouncements throws on error', () async {
      final client = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final apiClient = DefaultAnnouncementApiClient(baseUrl: baseUrl, client: client);

      expect(
        () => apiClient.getAnnouncements(),
        throwsA(isA<ApiException>()),
      );
    });

    test('publishAnnouncement parses successful response', () async {
      final input = const CreateAnnouncementInput(
        title: 'New Announcement',
        content: 'Content here',
        priority: AnnouncementPriority.urgent,
      );

      final responseData = {
        'id': '2',
        'churchId': 'c1',
        'authorId': 'a1',
        'title': 'New Announcement',
        'content': 'Content here',
        'priority': 1,
        'publishedAt': '2026-01-01T10:00:00Z',
      };

      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/announcements');
        expect(request.method, 'POST');
        return http.Response(jsonEncode(responseData), 201);
      });

      final apiClient = DefaultAnnouncementApiClient(baseUrl: baseUrl, client: client);
      final result = await apiClient.publishAnnouncement(input);

      expect(result.id, '2');
      expect(result.title, 'New Announcement');
      expect(result.priority, AnnouncementPriority.urgent);
    });

    test('publishAnnouncement throws 403 on permission error', () async {
      final input = const CreateAnnouncementInput(
        title: 'New Announcement',
        content: 'Content here',
      );

      final client = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      final apiClient = DefaultAnnouncementApiClient(baseUrl: baseUrl, client: client);

      expect(
        () => apiClient.publishAnnouncement(input),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('permission'),
          ),
        ),
      );
    });
  });
}
