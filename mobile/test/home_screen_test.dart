import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/celebration_models.dart';
import 'package:church_digital_platform_mobile/screens/celebrations_screen.dart';
import 'package:church_digital_platform_mobile/screens/home_screen.dart';
import 'package:church_digital_platform_mobile/services/celebration_api_client.dart';

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

void main() {
  testWidgets('renders placeholder when celebrationClient is null', (tester) async {
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

  testWidgets('renders welcome card on a narrow portrait phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final client = StubCelebrationApiClient();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(celebrationClient: client),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Church Digital Platform'), findsOneWidget);
    expect(find.text('Celebrations & Blessings'), findsOneWidget);
  });
}
