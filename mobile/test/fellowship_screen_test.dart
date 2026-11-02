import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

class ControllableFellowshipApiClient extends FakeFellowshipApiClient {
  Completer<List<FellowshipGroupData>>? completer;
  Completer<FellowshipGroupData>? createCompleter;

  ControllableFellowshipApiClient({super.initialGroups, this.completer, this.createCompleter});

  @override
  Future<List<FellowshipGroupData>> getFellowshipGroups({FellowshipCategory? category}) async {
    if (completer != null) {
      return completer!.future;
    }
    return super.getFellowshipGroups(category: category);
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
    if (createCompleter != null) {
      return createCompleter!.future;
    }
    return super.createFellowshipGroup(
      name: name,
      description: description,
      category: category,
      meetingSchedule: meetingSchedule,
      location: location,
      isPrivate: isPrivate,
    );
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

  testWidgets('MessagesScreen reloads groups when apiClient is updated via didUpdateWidget',
      (tester) async {
    final client1 = FakeFellowshipApiClient(initialGroups: []);
    final client2 = FakeFellowshipApiClient(initialGroups: createSampleGroups());

    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: client1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Men's Fellowship Brotherhood"), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: client2),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
  });

  testWidgets('Account switch discards pending load from previous session and prevents data leak',
      (tester) async {
    final completerA = Completer<List<FellowshipGroupData>>();
    final clientA = ControllableFellowshipApiClient(
      completer: completerA,
    );

    const privateGroupA = FellowshipGroupData(
      id: 'private_a',
      name: "Member A Private Fellowship",
      description: "Confidential fellowship",
      category: FellowshipCategory.housePrayer,
      isPrivate: true,
      members: ['Member A'],
    );

    const publicGroupB = FellowshipGroupData(
      id: 'public_b',
      name: "Member B Open Group",
      description: "Public group",
      category: FellowshipCategory.mensFellowship,
      isPrivate: false,
      members: ['Member B'],
    );

    final clientB = FakeFellowshipApiClient(initialGroups: [publicGroupB]);

    // Initial mount with client A: starts load that is slow/pending
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientA),
      ),
    );
    await tester.pump();

    // Switch account to client B: client B returns immediately
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientB),
      ),
    );
    await tester.pumpAndSettle();

    // Client B's group is shown
    expect(find.text("Member B Open Group"), findsOneWidget);
    expect(find.text("Member A Private Fellowship"), findsNothing);

    // Client A's slow pending response finally completes
    completerA.complete([privateGroupA]);
    await tester.pumpAndSettle();

    // Verify Member A's private data did NOT overwrite Member B's groups
    expect(find.text("Member B Open Group"), findsOneWidget);
    expect(find.text("Member A Private Fellowship"), findsNothing);
  });

  testWidgets('Account switch dismisses open private fellowship detail route and discards pending detail loads',
      (tester) async {
    const privateGroupA = FellowshipGroupData(
      id: 'private_a',
      name: "Member A Private Fellowship",
      description: "Secret members-only group",
      category: FellowshipCategory.housePrayer,
      isPrivate: true,
      members: ['Member A Confidential'],
    );

    final clientA = FakeFellowshipApiClient(
      initialGroups: [privateGroupA],
    );

    const publicGroupB = FellowshipGroupData(
      id: 'public_b',
      name: "Member B Open Group",
      description: "Public space",
      category: FellowshipCategory.mensFellowship,
      isPrivate: false,
      members: ['Member B'],
    );

    final clientB = FakeFellowshipApiClient(initialGroups: [publicGroupB]);

    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientA),
      ),
    );
    await tester.pumpAndSettle();

    // Open private group detail
    await tester.tap(find.text("Member A Private Fellowship"));
    await tester.pumpAndSettle();

    // Verify detail screen is mounted showing private group info
    expect(find.text("Secret members-only group"), findsOneWidget);

    // Switch account to Client B
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientB),
      ),
    );
    await tester.pumpAndSettle();

    // Detail route was dismissed; back at MessagesScreen showing Client B's group
    expect(find.text("Secret members-only group"), findsNothing);
    expect(find.text("Member B Open Group"), findsOneWidget);
  });

  testWidgets('Account switch discards pending group creation and does not add group to new account list',
      (tester) async {
    final createCompleterA = Completer<FellowshipGroupData>();

    final clientA = ControllableFellowshipApiClient(
      createCompleter: createCompleterA,
    );

    const publicGroupB = FellowshipGroupData(
      id: 'public_b',
      name: "Member B Open Group",
      description: "Public group for all members",
      category: FellowshipCategory.mensFellowship,
      members: ['Member B'],
    );
    final clientB = FakeFellowshipApiClient(initialGroups: [publicGroupB]);

    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientA),
      ),
    );
    await tester.pumpAndSettle();

    // Open create dialog
    await tester.tap(find.byKey(const Key('createFellowshipFab')));
    await tester.pumpAndSettle();

    // Fill out form
    await tester.enterText(find.byKey(const Key('createGroupNameField')), "Member A Secret Group");
    await tester.tap(find.byKey(const Key('saveGroupButton')));
    await tester.pump(); // creation is now pending on createCompleterA

    // Account switch happens to Client B while creation is pending
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(apiClient: clientB),
      ),
    );
    await tester.pumpAndSettle();

    // Verify dialog was popped and Client B's screen is visible
    expect(find.text("Member B Open Group"), findsOneWidget);
    expect(find.text("Member A Secret Group"), findsNothing);

    // Now Client A's pending creation finally completes
    createCompleterA.complete(const FellowshipGroupData(
      id: 'group_a_new',
      name: "Member A Secret Group",
      description: "Secret group description",
      category: FellowshipCategory.mensFellowship,
      members: ['Member A'],
    ));
    await tester.pumpAndSettle();

    // Verify Member A's group was NOT added to Client B's list
    expect(find.text("Member B Open Group"), findsOneWidget);
    expect(find.text("Member A Secret Group"), findsNothing);
  });
}
