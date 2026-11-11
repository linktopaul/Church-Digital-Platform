import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/announcement_models.dart';
import '../network/api_exceptions.dart';

abstract class AnnouncementApiClient {
  Future<List<Announcement>> getAnnouncements();
  Future<Announcement> publishAnnouncement(CreateAnnouncementInput input);
}

class DefaultAnnouncementApiClient implements AnnouncementApiClient {
  final String baseUrl;
  final http.Client client;

  DefaultAnnouncementApiClient({
    required this.baseUrl,
    required this.client,
  });

  @override
  Future<List<Announcement>> getAnnouncements() async {
    final response = await client.get(
      Uri.parse('$baseUrl/api/v1/announcements'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((json) => Announcement.fromJson(json)).toList();
    } else {
      throw ApiException(
        'Failed to fetch announcements: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<Announcement> publishAnnouncement(CreateAnnouncementInput input) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/announcements'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );

    if (response.statusCode == 201) {
      final Map<String, dynamic> body = jsonDecode(response.body);
      return Announcement.fromJson(body);
    } else if (response.statusCode == 403) {
      throw const ApiException('You do not have permission to publish announcements.', statusCode: 403);
    } else {
      throw ApiException(
        'Failed to publish announcement: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}
