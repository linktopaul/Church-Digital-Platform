import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/celebration_models.dart';
import 'package:church_digital_platform_mobile/screens/celebrations_screen.dart';
import 'package:church_digital_platform_mobile/services/celebration_api_client.dart';

class FakeCelebrationApiClient implements CelebrationApiClient {
  List<CelebrationEvent> todayEvents;
  List<CelebrationEvent> upcomingEvents;
  List<BlessingTemplate> templates;
  bool shouldFail;
  String? failureMessage;

  FakeCelebrationApiClient({
    List<CelebrationEvent>? todayEvents,
    List<CelebrationEvent>? upcomingEvents,
    List<BlessingTemplate>? templates,
    this.shouldFail = false,
    this.failureMessage,
  })  : todayEvents = todayEvents ?? [],
        upcomingEvents = upcomingEvents ?? [],
        templates = templates ?? [];

  @override
  Future<List<CelebrationEvent>> getTodayCelebrations({DateTime? date}) async {
    if (shouldFail) {
      throw CelebrationApiException(failureMessage ?? 'Error fetching today celebrations');
    }
    return List.from(todayEvents);
  }

  @override
  Future<List<CelebrationEvent>> getUpcomingCelebrations({int days = 7, DateTime? startDate}) async {
    if (shouldFail) {
      throw CelebrationApiException(failureMessage ?? 'Error fetching upcoming celebrations');
    }
    return List.from(upcomingEvents);
  }

  @override
  Future<List<BlessingTemplate>> getBlessingTemplates() async {
    if (shouldFail) {
      throw CelebrationApiException(failureMessage ?? 'Error fetching templates');
    }
    return List.from(templates);
  }

  @override
  Future<Map<String, dynamic>> triggerDailyScan({DateTime? date}) async {
    return {'status': 'Completed', 'celebrationsFound': todayEvents.length};
  }
}

void main() {
  final sampleToday = [
    CelebrationEvent(
      memberId: 'm-1',
      memberName: 'Grace Hopper',
      type: CelebrationType.birthday,
      date: DateTime.utc(2026, 11, 3),
      years: 41,
      phoneNumber: '+15551234567',
      whatsAppUrl: 'https://wa.me/15551234567?text=blessing',
      canMessageDirectly: true,
    ),
    CelebrationEvent(
      memberId: 'm-2',
      memberName: 'Private Member',
      type: CelebrationType.anniversary,
      date: DateTime.utc(2026, 11, 3),
      years: 15,
      phoneNumber: null,
      whatsAppUrl: null,
      canMessageDirectly: false,
    ),
  ];

  final sampleUpcoming = [
    CelebrationEvent(
      memberId: 'm-3',
      memberName: 'David Livingstone',
      type: CelebrationType.birthday,
      date: DateTime.utc(2026, 11, 6),
      years: 25,
      canMessageDirectly: true,
    ),
  ];

  final sampleTemplates = [
    const BlessingTemplate(
      type: CelebrationType.birthday,
      title: 'Birthday Blessing',
      template: 'Dear {name}, may the Lord bless you and keep you!',
      defaultScripture: 'Numbers 6:24-25',
    ),
    const BlessingTemplate(
      type: CelebrationType.anniversary,
      title: 'Anniversary Blessing',
      template: 'Dear {name}, congratulations on your anniversary!',
      defaultScripture: '1 Corinthians 13:7',
    ),
    const BlessingTemplate(
      type: CelebrationType.birthday,
      title: 'Day of Joy Blessing',
      template: 'Dear {name}, rejoicing with you on your birthday!',
      defaultScripture: 'Psalm 118:24',
    ),
  ];

  Widget buildTestWidget({
    CelebrationApiClient? client,
    bool isPastor = false,
    Future<bool> Function(String)? onLaunchUrl,
  }) {
    return MaterialApp(
      home: CelebrationsScreen(
        apiClient: client,
        isPastor: isPastor,
        onLaunchUrl: onLaunchUrl,
      ),
    );
  }

  testWidgets('renders unauthenticated state when apiClient is null', (tester) async {
    await tester.pumpWidget(buildTestWidget(client: null));
    expect(find.text('Please sign in to view church celebrations.'), findsOneWidget);
  });

  testWidgets('renders empty state when there are no celebrations', (tester) async {
    final client = FakeCelebrationApiClient();
    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    expect(find.text('No celebrations today. Check back tomorrow!'), findsOneWidget);
  });

  testWidgets('renders today celebrations with milestone badges and contact controls', (tester) async {
    final client = FakeCelebrationApiClient(
      todayEvents: sampleToday,
      upcomingEvents: sampleUpcoming,
      templates: sampleTemplates,
    );

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('41st Birthday'), findsOneWidget);

    expect(find.text('Private Member'), findsOneWidget);
    expect(find.text('15th Anniversary'), findsOneWidget);
    expect(find.text('Private Contact'), findsOneWidget);
  });

  testWidgets('tapping WhatsApp button opens scrollable blessing preview and calls onLaunchUrl', (tester) async {
    String? launchedUrl;
    final client = FakeCelebrationApiClient(
      todayEvents: sampleToday,
      upcomingEvents: sampleUpcoming,
      templates: sampleTemplates,
    );

    await tester.pumpWidget(buildTestWidget(
      client: client,
      onLaunchUrl: (url) async {
        launchedUrl = url;
        return true;
      },
    ));
    await tester.pumpAndSettle();

    // Tap the send blessing button on Grace Hopper's card
    final sendButton = find.byTooltip('Send Blessing');
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // Modal sheet appears with scroll view and content
    expect(find.text('Bless Grace Hopper'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Birthday Blessing'), findsOneWidget);
    expect(find.text('Day of Joy Blessing'), findsOneWidget);
    expect(find.text('Dear Grace Hopper, may the Lord bless you and keep you!'), findsOneWidget);

    // Tap Open in WhatsApp
    final whatsappBtn = find.text('Open in WhatsApp');
    expect(whatsappBtn, findsOneWidget);
    await tester.tap(whatsappBtn);
    await tester.pumpAndSettle();

    expect(launchedUrl, 'https://wa.me/15551234567?text=blessing');
  });

  testWidgets('switches to upcoming tab and displays celebration date in subtitle', (tester) async {
    final client = FakeCelebrationApiClient(
      todayEvents: sampleToday,
      upcomingEvents: sampleUpcoming,
      templates: sampleTemplates,
    );

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    // Tap upcoming tab
    await tester.tap(find.text('Upcoming (7 Days)'));
    await tester.pumpAndSettle();

    expect(find.text('David Livingstone'), findsOneWidget);
    // Verified date is formatted alongside milestone
    expect(find.text('Nov 6 • 25th Birthday'), findsOneWidget);
  });

  testWidgets('blessing modal renders without overflow on a short viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final client = FakeCelebrationApiClient(
      todayEvents: sampleToday,
      upcomingEvents: sampleUpcoming,
      templates: sampleTemplates,
    );

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    final sendButton = find.byTooltip('Send Blessing');
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(find.text('Bless Grace Hopper'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('shows error view and retries on button tap', (tester) async {
    final client = FakeCelebrationApiClient(
      todayEvents: sampleToday,
      shouldFail: true,
      failureMessage: 'Server unreachable',
    );

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Server unreachable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    client.shouldFail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Grace Hopper'), findsOneWidget);
  });
}
