import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/main.dart';

void main() {
  testWidgets('main navigation exposes all five tabs', (tester) async {
    await tester.pumpWidget(const ChurchMobileApp());

    final navigationFinder = find.byType(NavigationBar);
    expect(navigationFinder, findsOneWidget);

    final navigation = tester.widget<NavigationBar>(navigationFinder);
    expect(navigation.destinations, hasLength(5));
    expect(navigation.selectedIndex, 0);

    await tester.tap(find.byIcon(Icons.music_note_outlined));
    await tester.pumpAndSettle();

    final updatedNavigation = tester.widget<NavigationBar>(navigationFinder);
    expect(updatedNavigation.selectedIndex, 3);
    expect(find.text('Worship'), findsWidgets);
  });
}
