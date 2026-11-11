import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/announcement_models.dart';
import 'package:church_digital_platform_mobile/models/celebration_models.dart';
import 'package:church_digital_platform_mobile/models/offering_models.dart';
import 'package:church_digital_platform_mobile/screens/celebrations_screen.dart';
import 'package:church_digital_platform_mobile/screens/home_screen.dart';
import 'package:church_digital_platform_mobile/screens/offerings_screen.dart';
import 'package:church_digital_platform_mobile/services/announcement_api_client.dart';
import 'package:church_digital_platform_mobile/services/celebration_api_client.dart';
import 'package:church_digital_platform_mobile/services/offering_api_client.dart';

class StubAnnouncementApiClient implements AnnouncementApiClient {
  List<Announcement> announcementsToReturn = [];
  bool shouldThrow = false;

  @override
  Future<List<Announcement>> getAnnouncements() async {
    if (shouldThrow) throw Exception('Network error');
    return announcementsToReturn;
  }

  @override
  Future<Announcement> publishAnnouncement(CreateAnnouncementInput input) async {
    final newAnnouncement = Announcement(
      id: 'new-id',
      churchId: 'c1',
      authorId: 'a1',
      title: input.title,
      content: input.content,
      priority: input.priority,
      publishedAt: DateTime.now(),
    );
    announcementsToReturn.insert(0, newAnnouncement);
    return newAnnouncement;
  }
}

class StubCelebrationApiClient implements CelebrationApiClient {
  @override
  Future<List<CelebrationEvent>> getTodayCelebrations({DateTime? date}) async => [];

  @override
  Future<List<CelebrationEvent>> getUpcomingCelebrations({int days = 7, DateTime? startDate}) async => [];

  @override
  Future<List<BlessingTemplate>> getBlessingTemplates() async => [];

  @override
  Future<Map<String, dynamic>> triggerDailyScan({DateTime? date}) async => {'status': 'Completed'};
}

class StubOfferingApiClient implements OfferingApiClient {
  @override
  Future<ChurchGivingConfig> getGivingConfig() async => const ChurchGivingConfig(
        upiId: 'test@upi',
        payeeName: 'Test Church',
        currency: 'INR',
        availableFunds: [],
      );

  @override
  Future<Contribution> recordContribution(RecordContributionInput input) async => Contribution(
        id: 'c-test',
        memberId: 'm-test',
        memberName: 'Member',
        fundType: input.fundType,
        fundName: 'Tithe',
        amount: input.amount,
        currency: 'INR',
        upiPayeeId: 'test@upi',
        upiIntentUri: 'upi://pay',
        status: ContributionStatus.pending,
        receiptNumber: 'REC-001',
        createdAt: DateTime.now(),
      );

  @override
  Future<List<Contribution>> getMyContributions() async => [];

  @override
  Future<List<Contribution>> getLedger({OfferingFundType? fundType, ContributionStatus? status}) async => [];

  @override
  Future<Contribution> verifyContribution(String id, {String? transactionReference, String? verificationNote}) async =>
      Contribution(
        id: id,
        memberId: 'm-test',
        memberName: 'Member',
        fundType: OfferingFundType.tithe,
        fundName: 'Tithe',
        amount: 100,
        currency: 'INR',
        upiPayeeId: 'test@upi',
        upiIntentUri: 'upi://pay',
        status: ContributionStatus.verified,
        receiptNumber: 'REC-001',
        createdAt: DateTime.now(),
      );

  @override
  Future<LedgerSummary> getLedgerSummary() async => LedgerSummary(
        totalAmount: 0,
        totalCount: 0,
        verifiedAmount: 0,
        pendingAmount: 0,
        byFundType: {},
        generatedAt: DateTime.now(),
      );
}

void main() {
  testWidgets('renders placeholder when all clients are null', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Church announcements and updates will appear here.'), findsOneWidget);
  });

  testWidgets('renders celebrations card and navigates to CelebrationsScreen', (tester) async {
    final client = StubCelebrationApiClient();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(celebrationClient: client),
    ));

    expect(find.text('Celebrations & Blessings'), findsOneWidget);

    await tester.tap(find.text('Celebrations & Blessings'));
    await tester.pumpAndSettle();

    expect(find.byType(CelebrationsScreen), findsOneWidget);
  });

  testWidgets('renders offerings card and navigates to OfferingsScreen', (tester) async {
    final client = StubOfferingApiClient();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(offeringClient: client),
    ));

    expect(find.text('Digital Offerings & Giving'), findsOneWidget);

    await tester.tap(find.text('Digital Offerings & Giving'));
    await tester.pumpAndSettle();

    expect(find.byType(OfferingsScreen), findsOneWidget);
  });

  testWidgets('renders announcements empty state', (tester) async {
    final announcementClient = StubAnnouncementApiClient();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('No announcements yet.'), findsOneWidget);
  });

  testWidgets('renders announcements list', (tester) async {
    final announcementClient = StubAnnouncementApiClient()
      ..announcementsToReturn = [
        Announcement(
          id: '1',
          churchId: 'c1',
          authorId: 'a1',
          title: 'Test Announcement',
          content: 'Important info',
          priority: AnnouncementPriority.routine,
          publishedAt: DateTime.now(),
        ),
      ];

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Test Announcement'), findsOneWidget);
    expect(find.text('Important info'), findsOneWidget);
  });

  testWidgets('renders error state and retry button', (tester) async {
    final announcementClient = StubAnnouncementApiClient()..shouldThrow = true;
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Test retry
    announcementClient.shouldThrow = false;
    announcementClient.announcementsToReturn = [
      Announcement(
        id: '1',
        churchId: 'c1',
        authorId: 'a1',
        title: 'Recovered Announcement',
        content: 'We are back',
        priority: AnnouncementPriority.routine,
        publishedAt: DateTime.now(),
      ),
    ];

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered Announcement'), findsOneWidget);
  });

  testWidgets('FAB is visible only for pastor/admin and opens composer', (tester) async {
    final announcementClient = StubAnnouncementApiClient();

    // Test normal user (no FAB)
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient, isPastor: false, isAdmin: false),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);

    // Test pastor (has FAB)
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient, isPastor: true, isAdmin: false),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Test admin (has FAB)
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(announcementClient: announcementClient, isPastor: false, isAdmin: true),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Open composer
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New Announcement'), findsOneWidget);
  });
}
