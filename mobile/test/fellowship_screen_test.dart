import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/fellowship_models.dart';
import 'package:church_digital_platform_mobile/screens/messages_screen.dart';

void main() {
  final sampleGroups = [
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
    FellowshipGroupData(
      id: '2',
      name: 'Sunday School - Primary Department',
      description: 'Bible lessons for children ages 6 to 10.',
      category: FellowshipCategory.sundaySchool,
      leaderName: 'Sister Mary Grace',
      meetingSchedule: 'Sundays at 9:00 AM',
      location: 'Room 102',
      memberCount: 18,
      isUserMember: false,
      members: const ['Sister Mary Grace'],
      posts: const [],
    ),
    FellowshipGroupData(
      id: '3',
      name: 'North District House Prayer',
      description: 'Weekly home fellowship and intercessory prayer meeting.',
      category: FellowshipCategory.housePrayer,
      leaderName: 'Brother David',
      meetingSchedule: 'Wednesdays at 7:30 PM',
      location: "David's Residence",
      memberCount: 12,
      isUserMember: false,
      members: const ['Brother David'],
      posts: const [],
    ),
  ];

  testWidgets('MessagesScreen displays fellowship groups and filter chips',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsOneWidget);
    expect(find.text('North District House Prayer'), findsOneWidget);

    // Verify filter chips exist
    expect(find.byKey(const Key('filterChipAll')), findsOneWidget);
    expect(find.byKey(const Key('filterChipMens')), findsOneWidget);
    expect(find.byKey(const Key('filterChipSundaySchool')), findsOneWidget);
    expect(find.byKey(const Key('filterChipHousePrayer')), findsOneWidget);
  });

  testWidgets('Filter chip narrows down displayed fellowship groups',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

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
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('searchFellowshipField')), 'accountability');
    await tester.pumpAndSettle();

    expect(find.text("Men's Fellowship Brotherhood"), findsOneWidget);
    expect(find.text('Sunday School - Primary Department'), findsNothing);
  });

  testWidgets('Tapping fellowship space opens detail screen with posts and members',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

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

  testWidgets('User can post new message to fellowship group', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

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

  testWidgets('Toggle membership joins and leaves fellowship space',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessagesScreen(initialGroups: sampleGroups),
      ),
    );

    // Open group 2 (initially not member)
    await tester.tap(find.byKey(const Key('groupItem_2')));
    await tester.pumpAndSettle();

    expect(find.text('Join'), findsOneWidget);

    // Tap join
    await tester.tap(find.byKey(const Key('toggleMembershipButton')));
    await tester.pumpAndSettle();

    expect(find.text('Joined'), findsOneWidget);
  });
}
