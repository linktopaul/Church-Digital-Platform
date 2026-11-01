import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fellowship_models.dart';

abstract class FellowshipApiClient {
  Future<List<FellowshipGroupData>> getFellowshipGroups({FellowshipCategory? category});
  Future<FellowshipGroupData> getFellowshipGroupDetail(String id);
  Future<FellowshipGroupData> createFellowshipGroup({
    required String name,
    String? description,
    required FellowshipCategory category,
    String? meetingSchedule,
    String? location,
    bool isPrivate = false,
  });
  Future<bool> joinFellowshipGroup(String groupId, {String? memberName});
  Future<bool> leaveFellowshipGroup(String groupId);
  Future<FellowshipPostData> createPost(String groupId, {
    required String title,
    required String content,
    String? authorName,
  });
}

class HttpFellowshipApiClient implements FellowshipApiClient {
  final http.Client _client;
  final String baseUrl;
  final String Function()? getAuthToken;
  final String? currentUserId;
  final String? currentMemberName;

  HttpFellowshipApiClient({
    http.Client? client,
    String? baseUrl,
    this.getAuthToken,
    this.currentUserId,
    this.currentMemberName,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl();

  static String _defaultBaseUrl() {
    const rawUrl = String.fromEnvironment(
      'CHURCH_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5178',
    );
    final trimmed = rawUrl.replaceAll(RegExp(r'/+$'), '');
    return trimmed.endsWith('/api/v1') ? trimmed : '$trimmed/api/v1';
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (getAuthToken != null) {
      final token = getAuthToken!();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  int _mapCategoryToApiEnum(FellowshipCategory category) {
    switch (category) {
      case FellowshipCategory.mensFellowship:
        return 1;
      case FellowshipCategory.sundaySchool:
        return 2;
      case FellowshipCategory.housePrayer:
        return 3;
      case FellowshipCategory.all:
        return 4;
    }
  }

  String _mapCategoryToApiQuery(FellowshipCategory category) {
    switch (category) {
      case FellowshipCategory.mensFellowship:
        return 'MensFellowship';
      case FellowshipCategory.sundaySchool:
        return 'SundaySchool';
      case FellowshipCategory.housePrayer:
        return 'HousePrayer';
      case FellowshipCategory.all:
        return 'General';
    }
  }

  FellowshipCategory _mapApiToCategory(dynamic apiType) {
    final str = apiType.toString();
    if (str.contains('MensFellowship') || str == '1') return FellowshipCategory.mensFellowship;
    if (str.contains('SundaySchool') || str == '2') return FellowshipCategory.sundaySchool;
    if (str.contains('HousePrayer') || str == '3') return FellowshipCategory.housePrayer;
    return FellowshipCategory.all;
  }

  bool _isUserMemberFromRoster(List<dynamic> membersJson) {
    if (currentUserId == null && currentMemberName == null) return false;
    for (final m in membersJson) {
      if (m is Map) {
        final memberId = m['memberId']?.toString();
        final memberName = m['memberName']?.toString();
        if (currentUserId != null && memberId != null && memberId.toLowerCase() == currentUserId!.toLowerCase()) {
          return true;
        }
        if (currentMemberName != null && memberName != null && memberName.trim() == currentMemberName!.trim()) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Future<List<FellowshipGroupData>> getFellowshipGroups({FellowshipCategory? category}) async {
    var uri = Uri.parse('$baseUrl/fellowships');
    if (category != null && category != FellowshipCategory.all) {
      uri = uri.replace(queryParameters: {'groupType': _mapCategoryToApiQuery(category)});
    }

    final response = await _client.get(uri, headers: _buildHeaders());
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => FellowshipGroupData(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: _mapApiToCategory(json['groupType']),
        leaderName: json['leaderName']?.toString(),
        meetingSchedule: json['meetingSchedule']?.toString(),
        location: json['location']?.toString(),
        isPrivate: json['isPrivate'] == true,
        memberCount: json['memberCount'] is int ? json['memberCount'] : 0,
        isUserMember: json['isUserMember'] == true,
      )).toList();
    } else {
      throw Exception('Failed to load fellowship groups: ${response.statusCode}');
    }
  }

  @override
  Future<FellowshipGroupData> getFellowshipGroupDetail(String id) async {
    final uri = Uri.parse('$baseUrl/fellowships/$id');
    final response = await _client.get(uri, headers: _buildHeaders());
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body);
      final rawMembers = json['members'] as List<dynamic>? ?? [];
      final memberNames = rawMembers
          .map((m) => m['memberName']?.toString() ?? 'Member')
          .toList();

      final rawPosts = json['recentPosts'] as List<dynamic>? ?? [];
      final posts = rawPosts.map((p) => FellowshipPostData(
        id: p['id']?.toString() ?? '',
        authorName: p['authorName']?.toString() ?? 'Member',
        title: p['title']?.toString() ?? '',
        content: p['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(p['createdAt']?.toString() ?? '') ?? DateTime.now(),
      )).toList();

      final isUserMember = json['isUserMember'] == true || _isUserMemberFromRoster(rawMembers);

      return FellowshipGroupData(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: _mapApiToCategory(json['groupType']),
        leaderName: json['leaderName']?.toString(),
        meetingSchedule: json['meetingSchedule']?.toString(),
        location: json['location']?.toString(),
        isPrivate: json['isPrivate'] == true,
        memberCount: json['memberCount'] is int ? json['memberCount'] : memberNames.length,
        isUserMember: isUserMember,
        members: memberNames,
        posts: posts,
      );
    } else {
      throw Exception('Failed to load fellowship group detail: ${response.statusCode}');
    }
  }

  @override
  Future<FellowshipGroupData> createFellowshipGroup({
    required String name,
    String? description,
    required FellowshipCategory category,
    String? meetingSchedule,
    String? location,
    bool isPrivate = false,
  }) async {
    final uri = Uri.parse('$baseUrl/fellowships');
    final payload = {
      'name': name,
      'description': description,
      'groupType': _mapCategoryToApiEnum(category),
      'meetingSchedule': meetingSchedule,
      'location': location,
      'isPrivate': isPrivate,
    };

    final response = await _client.post(
      uri,
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body);
      return FellowshipGroupData(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: _mapApiToCategory(json['groupType']),
        leaderName: json['leaderName']?.toString(),
        meetingSchedule: json['meetingSchedule']?.toString(),
        location: json['location']?.toString(),
        isPrivate: json['isPrivate'] == true,
        memberCount: json['memberCount'] is int ? json['memberCount'] : 1,
        isUserMember: json['isUserMember'] == true || true,
      );
    } else {
      throw Exception('Failed to create fellowship space: ${response.statusCode}');
    }
  }

  @override
  Future<bool> joinFellowshipGroup(String groupId, {String? memberName}) async {
    final uri = Uri.parse('$baseUrl/fellowships/$groupId/join');
    final payload = {
      'memberName': memberName ?? currentMemberName,
    };
    final response = await _client.post(
      uri,
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> leaveFellowshipGroup(String groupId) async {
    final uri = Uri.parse('$baseUrl/fellowships/$groupId/leave');
    final response = await _client.post(uri, headers: _buildHeaders());
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    return false;
  }

  @override
  Future<FellowshipPostData> createPost(String groupId, {
    required String title,
    required String content,
    String? authorName,
  }) async {
    final uri = Uri.parse('$baseUrl/fellowships/$groupId/posts');
    final payload = {
      'title': title,
      'content': content,
      'authorName': authorName,
    };

    final response = await _client.post(
      uri,
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body);
      return FellowshipPostData(
        id: json['id']?.toString() ?? '',
        authorName: json['authorName']?.toString() ?? 'Author',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
    } else {
      throw Exception('Failed to post update: ${response.statusCode}');
    }
  }
}
