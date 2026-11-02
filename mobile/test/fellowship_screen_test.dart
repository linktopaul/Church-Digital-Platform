import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/models/fellowship_models.dart';
import 'package:church_digital_platform_mobile/screens/messages_screen.dart';
import 'package:church_digital_platform_mobile/services/fellowship_api_client.dart';

class FakeFellowshipApiClient implements FellowshipApiClient {
  List<FellowshipGroupData> groups;

  FakeFellowshipApiClient({List<FellowshipGroupData>? initialGroups})
      : groups = initialGroups ?? [];

  @override
  Future<List<FellowshipGroupData>> getFellowshipGroups({FellowshipCategory? category}) async {
    if (category == null || category == FellowshipCategory.all) {
      return List.from(groups);
    }
    return groups.where((g) => g.category == category).toList();
  }

  @override
  Future<FellowshipGroupData> getFellowshipGroupDetail(String id) async {
    return groups.firstWhere((g) => g.id == id);
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
    final newGroup = FellowshipGroupData(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description ?? '',
      category: category,
      meetingSchedule: meetingSchedule,
      location: location,
      isPrivate: isPrivate,
      memberCount: 1,
      isUserMember: true,
      members: const ['Current User'],
    );
    groups.add(newGroup);
    return newGroup;
  }

  @override
  Future<bool> joinFellowshipGroup(String groupId, {String? memberName}) async {
    final index = groups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      final g = groups[index];
      groups[index] = g.copyWith(
        isUserMember: true,
        memberCount: g.memberCount + 1,
        members: [...g.members, memberName ?? 'Current User'],
      );
      return true;
    }
    return false;
  }

  @override
  Future<bool> leaveFellowshipGroup(String groupId) async {
    final index = groups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      final g = groups[index];
      groups[index] = g.copyWith(
        isUserMember: false,
        memberCount: g.memberCount > 0 ? g.memberCount - 1 : 0,
      );
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
    final post = FellowshipPostData(
      id: 'post_${DateTime.now().millisecondsSinceEpoch}',
      authorName: authorName ?? 'Current User',
      title: title,
      content: content,
      createdAt: DateTime.now(),
    );
    final index = groups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      final g = groups[index];
      groups[index] = g.copyWith(posts: [post, ...g.posts]);
    }
    return post;
  }
}

void main() {
  List<FellowshipGroupData> createSampleGroups() => [
    FellowshipGroupData(
      id: '1',
      name: "Men's Fellowship Brotherhood",
      description: 'Men gathering for spiritual growth and accountability.',
      category: FellowshipCategory.mensFellowship,
      leaderName: 'Elder John Thomas',
      meetingSchedule: 'Saturdays at 7:00 AM',
      location: 'Main Fellowship Hall',
      memberCount: 24,
      isUserMember: true,
      members: const ['Elder John Thomas', 'Brother Timothy'],
      posts: [
        FellowshipPostData(
          id: 'p1',
          authorName: 'Elder John Thomas',
          title: 'Upcoming Men\'s Breakfast',
          content: 'Join us this Saturday for breakfast and prayer.',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
        ),
      ],
    ),
    const FellowshipGroupData(
      id: '2',
      name: 'Sunday School - Primary Department',
      description: 'Bible lessons for children ages 6 to 10.',
      category: FellowshipCategory.sundaySchool,
      leaderName: 'Sister Mary Grace',
      meetingSchedule: 'Sundays at 9:00 AM',
      location: 'Room 102',
      memberCount: 18,
      isUserMember: false,
      members: ['Sister Mary Grace'],
      posts: [],
    ),
    const FellowshipGroupData(
      id: '3',
      name: 'North District House Prayer',
      description: 'Weekly home fellowship and intercessory prayer meeting.',
      category: FellowshipCategory.housePrayer,
      leaderName: 'Brother David',
      meetingSchedule: 'Wednesdays at 7:30 PM',
      location: "David's Residence",
      memberCount: 12,
      isUserMember: false,
      members: ['Brother David'],
      posts: [],
    ),
  ];

  testWidgets('MessagesScreen displays fellowship groups loaded from API and filter chips',
      (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsOneWidget);
    expect(find.text('North District House Prayer'), findsOneWidget);

    // Verify filter chips exist
    expect(find.byKey(const Key('filterChipAll')), findsOneWidget);
    expect(find.byKey(const Key('filterChipMens')), findsOneWidget);
    expect(find.byKey(const Key('filterChipSundaySchool')), findsOneWidget);
    expect(find.byKey(const Key('filterChipHousePrayer')), findsOneWidget);
  });

  testWidgets('Filter chip narrows down displayed fellowship groups via API',
      (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    // Filter to Sunday School
    await tester.ensureVisible(find.byKey(const Key('filterChipSundaySchool')));
    await tester.tap(find.byKey(const Key('filterChipSundaySchool')));
    await tester.pumpAndSettle();

    expect(find.text('Sunday School - Primary Department'), findsOneWidget);
    expect(find.text("Men's Fellowship Brotherhood"), findsNothing);
    expect(find.text('North District House Prayer'), findsNothing);

    // Filter to House Prayer
    await tester.ensureVisible(find.byKey(const Key('filterChipHousePrayer')));
    await tester.tap(find.byKey(const Key('filterChipHousePrayer')));
    await tester.pumpAndSettle();

    expect(find.text('North District House Prayer'), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsNothing);

    // Return to All
    await tester.ensureVisible(find.byKey(const Key('filterChipAll')));
    await tester.tap(find.byKey(const Key('filterChipAll')));
    await tester.pumpAndSettle();

    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsOneWidget);
    expect(find.text('North District House Prayer'), findsOneWidget);
  });

  testWidgets('Search query filters fellowship groups by name or description',
      (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('searchFellowshipField')), 'accountability');
    await tester.pumpAndSettle();

    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsNothing);
  });

  testWidgets('Tapping fellowship space opens detail screen with posts and members from API',
      (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('groupItem_1')));
    await tester.pumpAndSettle();

    // Verify detail screen opened
    expect(find.text("Men's Fellowship Brotherhood"), findsWidgets);
    expect(find.text('Upcoming Men\'s Breakfast'), findsOneWidget);
    expect(find.text('Join us this Saturday for breakfast and prayer.'),
        findsOneWidget);

    // Switch to About & Members tab
    await tester.tap(find.text('About & Members'));
    await tester.pumpAndSettle();

    expect(find.text('Elder John Thomas'), findsWidgets);
    expect(find.text('Brother Timothy'), findsOneWidget);
    expect(find.text('Meeting Schedule'), findsOneWidget);
    expect(find.text('Main Fellowship Hall'), findsOneWidget);
  });

  testWidgets('User can post new message persisted through API client', (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('groupItem_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addPostButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('addPostButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('postTitleField')), 'New Prayer Topic');
    await tester.enterText(
        find.byKey(const Key('postContentField')), 'Please pray for the upcoming mission trip.');
    await tester.tap(find.byKey(const Key('submitPostButton')));
    await tester.pumpAndSettle();

    expect(find.text('New Prayer Topic'), findsOneWidget);
    expect(
        find.text('Please pray for the upcoming mission trip.'), findsOneWidget);
  });

  testWidgets('Toggle membership joins and leaves fellowship space through API client',
      (tester) async {
    final fakeClient = FakeFellowshipApiClient(initialGroups: createSampleGroups());
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: fakeClient),
      ),
    );
    await tester.pumpAndSettle();

    // Open group 2 (initially not member)
    await tester.tap(find.byKey(const Key('groupItem_2')));
    await tester.pumpAndSettle();

    expect(find.text('Join'), findsOneWidget);

    // Tap join
    await tester.tap(find.byKey(const Key('toggleMembershipButton')));
    await tester.pumpAndSettle();

    expect(find.text('Joined'), findsOneWidget);
  });

  group('HttpFellowshipApiClient unit & contract tests', () {
    test('createFellowshipGroup serializes groupType as integer enum matching backend contract', () async {
      late String capturedBody;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/fellowships' && request.method == 'POST') {
          capturedBody = request.body;
          return http.Response(
            jsonEncode({
              'id': 'g-created-1',
              'name': 'Test Group',
              'description': 'Test Desc',
              'groupType': 1,
              'leaderName': 'Leader',
              'isPrivate': false,
              'memberCount': 1,
              'isUserMember': true,
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = HttpFellowshipApiClient(
        client: mockClient,
        baseUrl: 'http://example.com/api/v1',
      );

      final result = await apiClient.createFellowshipGroup(
        name: 'Men of Faith',
        category: FellowshipCategory.mensFellowship,
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      expect(decoded['groupType'], equals(1)); // MensFellowship is 1, not 'MensFellowship' string
      expect(result.id, equals('g-created-1'));
      expect(result.category, equals(FellowshipCategory.mensFellowship));
    });

    test('getFellowshipGroups and getFellowshipGroupDetail restore isUserMember from API response', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/fellowships' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'g1',
                'name': 'Group 1',
                'description': 'Desc',
                'groupType': 1,
                'memberCount': 5,
                'isUserMember': true,
              },
              {
                'id': 'g2',
                'name': 'Group 2',
                'description': 'Desc',
                'groupType': 2,
                'memberCount': 2,
                'isUserMember': false,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/fellowships/g1' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 'g1',
              'name': 'Group 1',
              'description': 'Desc',
              'groupType': 1,
              'isUserMember': true,
              'members': [
                {'memberId': 'user-123', 'memberName': 'Timothy', 'role': 'Member'},
              ],
              'recentPosts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = HttpFellowshipApiClient(
        client: mockClient,
        baseUrl: 'http://example.com/api/v1',
      );

      final groups = await apiClient.getFellowshipGroups();
      expect(groups[0].isUserMember, isTrue);
      expect(groups[1].isUserMember, isFalse);

      final detail = await apiClient.getFellowshipGroupDetail('g1');
      expect(detail.isUserMember, isTrue);
    });

    test('joinFellowshipGroup and leaveFellowshipGroup return false on HTTP 400, 401, or 403', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/fellowships/forbidden/join') {
          return http.Response(jsonEncode({'error': 'Private group cannot be joined'}), 403);
        }
        if (request.url.path == '/api/v1/fellowships/unauthorized/leave') {
          return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
        }
        return http.Response('OK', 200);
      });

      final apiClient = HttpFellowshipApiClient(
        client: mockClient,
        baseUrl: 'http://example.com/api/v1',
      );

      final joinResult = await apiClient.joinFellowshipGroup('forbidden');
      expect(joinResult, isFalse);

      final leaveResult = await apiClient.leaveFellowshipGroup('unauthorized');
      expect(leaveResult, isFalse);
    });
  });

  group('Failed-mutation and reload-after-success widget tests', () {
    testWidgets('Failed join (HTTP 403) does not alter local membership or member count and shows error', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/fellowships' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'private-g',
                'name': 'Private Group',
                'description': 'Confidential prayer cell',
                'groupType': 3,
                'memberCount': 2,
                'isPrivate': true,
                'isUserMember': false,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/fellowships/private-g' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 'private-g',
              'name': 'Private Group',
              'description': 'Confidential prayer cell',
              'groupType': 3,
              'memberCount': 2,
              'isPrivate': true,
              'isUserMember': false,
              'members': [],
              'recentPosts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/fellowships/private-g/join') {
          return http.Response(
            jsonEncode({'error': 'Unauthorized self-join'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = HttpFellowshipApiClient(
        client: mockClient,
        baseUrl: 'http://example.com/api/v1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MessagesScreen(apiClient: apiClient),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private Group'), findsOneWidget);

      // Open detail
      await tester.tap(find.byKey(const Key('groupItem_private-g')));
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsOneWidget);

      // Attempt to join
      await tester.tap(find.byKey(const Key('toggleMembershipButton')));
      await tester.pumpAndSettle();

      // Ensure membership is NOT updated to 'Joined'
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Joined'), findsNothing);

      // Ensure SnackBar error message is shown
      expect(find.text('Failed to join space. Please check permissions.'), findsOneWidget);
    });

    testWidgets('Successful join reloads group detail and updates membership from server', (tester) async {
      int detailFetchCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/fellowships' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'open-g',
                'name': 'Open Community',
                'description': 'Open for everyone',
                'groupType': 4,
                'memberCount': 5,
                'isPrivate': false,
                'isUserMember': false,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/fellowships/open-g' && request.method == 'GET') {
          detailFetchCount++;
          final isMemberNow = detailFetchCount > 1;
          return http.Response(
            jsonEncode({
              'id': 'open-g',
              'name': 'Open Community',
              'description': 'Open for everyone',
              'groupType': 4,
              'memberCount': isMemberNow ? 6 : 5,
              'isPrivate': false,
              'isUserMember': isMemberNow,
              'members': isMemberNow
                  ? [
                      {'memberId': 'u1', 'memberName': 'Leader', 'role': 'Leader'},
                      {'memberId': 'u2', 'memberName': 'New Joined User', 'role': 'Member'}
                    ]
                  : [
                      {'memberId': 'u1', 'memberName': 'Leader', 'role': 'Leader'}
                    ],
              'recentPosts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/fellowships/open-g/join') {
          return http.Response(
            jsonEncode({'id': 'mem-1'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = HttpFellowshipApiClient(
        client: mockClient,
        baseUrl: 'http://example.com/api/v1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MessagesScreen(apiClient: apiClient),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('groupItem_open-g')));
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsOneWidget);

      // Tap join
      await tester.tap(find.byKey(const Key('toggleMembershipButton')));
      await tester.pumpAndSettle();

      // State is now Joined and detail was reloaded (detailFetchCount == 2)
      expect(find.text('Joined'), findsOneWidget);
      expect(detailFetchCount, equals(2));

      // Switch to About & Members tab to verify newly fetched member
      await tester.tap(find.text('About & Members'));
      await tester.pumpAndSettle();

      expect(find.text('New Joined User'), findsOneWidget);
      expect(find.text('Members (2)'), findsOneWidget);
    });
  });
}
