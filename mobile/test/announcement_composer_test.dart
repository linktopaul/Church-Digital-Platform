import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/announcement_models.dart';
import 'package:church_digital_platform_mobile/screens/announcement_composer_screen.dart';

Widget buildTestWidget({
  required AnnouncementSubmitCallback onSubmit,
  VoidCallback? onCancel,
  AnnouncementPriority initialPriority = AnnouncementPriority.routine,
  String? initialTitle,
  String? initialContent,
}) {
  return MaterialApp(
    home: AnnouncementComposerScreen(
      onSubmit: onSubmit,
      onCancel: onCancel,
      initialPriority: initialPriority,
      initialTitle: initialTitle,
      initialContent: initialContent,
    ),
  );
}

void main() {
  group('Announcement Models', () {
    test('AnnouncementPriority serialization and deserialization', () {
      expect(AnnouncementPriority.fromJson(0), AnnouncementPriority.routine);
      expect(AnnouncementPriority.fromJson(1), AnnouncementPriority.urgent);
      expect(AnnouncementPriority.fromJson(2), AnnouncementPriority.emergency);
      expect(AnnouncementPriority.fromJson('routine'), AnnouncementPriority.routine);
      expect(AnnouncementPriority.fromJson('urgent'), AnnouncementPriority.urgent);
      expect(AnnouncementPriority.fromJson('EMERGENCY'), AnnouncementPriority.emergency);
      expect(AnnouncementPriority.fromJson('unknown'), AnnouncementPriority.routine);

      expect(AnnouncementPriority.routine.displayName, 'Routine');
      expect(AnnouncementPriority.urgent.displayName, 'Urgent');
      expect(AnnouncementPriority.emergency.displayName, 'Emergency');
      expect(AnnouncementPriority.urgent.toJson(), 1);
    });

    test('CreateAnnouncementInput toJson matching backend contract', () {
      final input = CreateAnnouncementInput(
        title: 'Weekly Service',
        content: 'Service starts at 10:00 AM.',
        priority: AnnouncementPriority.urgent,
        publishedAt: DateTime.utc(2026, 11, 10, 9, 0),
      );

      final json = input.toJson();
      expect(json['title'], 'Weekly Service');
      expect(json['content'], 'Service starts at 10:00 AM.');
      expect(json['priority'], 1);
      expect(json['publishedAt'], '2026-11-10T09:00:00.000Z');
      expect(json.containsKey('expiresAt'), isFalse);
    });

    test('Announcement fromJson deserialization', () {
      final json = {
        'id': 'a1-b2',
        'churchId': 'c1-d2',
        'authorId': 'u1-v2',
        'title': 'Youth Retreat',
        'content': 'Registration open now.',
        'priority': 2,
        'publishedAt': '2026-11-09T12:00:00.000Z',
      };

      final announcement = Announcement.fromJson(json);
      expect(announcement.id, 'a1-b2');
      expect(announcement.churchId, 'c1-d2');
      expect(announcement.authorId, 'u1-v2');
      expect(announcement.title, 'Youth Retreat');
      expect(announcement.content, 'Registration open now.');
      expect(announcement.priority, AnnouncementPriority.emergency);
      expect(announcement.publishedAt, DateTime.utc(2026, 11, 9, 12, 0));
      expect(announcement.expiresAt, isNull);
    });
  });

  group('AnnouncementComposerScreen', () {
    testWidgets('Renders all input fields and initial routine priority', (tester) async {
      await tester.pumpWidget(buildTestWidget(onSubmit: (_) async {}));

      expect(find.text('New Announcement'), findsOneWidget);
      expect(find.byKey(const Key('announcement_title_field')), findsOneWidget);
      expect(find.byKey(const Key('announcement_content_field')), findsOneWidget);
      expect(find.byKey(const Key('announcement_priority_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('announcement_publish_button')), findsOneWidget);
      expect(find.text('Routine'), findsOneWidget);
    });

    testWidgets('Populates initial values when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        onSubmit: (_) async {},
        initialTitle: 'Draft Title',
        initialContent: 'Draft Content',
        initialPriority: AnnouncementPriority.urgent,
      ));

      expect(find.text('Draft Title'), findsOneWidget);
      expect(find.text('Draft Content'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
    });

    testWidgets('Validation: Empty and whitespace fields show validation errors and block submission', (tester) async {
      var submitCalled = false;
      await tester.pumpWidget(buildTestWidget(
        onSubmit: (_) async {
          submitCalled = true;
        },
      ));

      // Attempt submit without filling anything
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter an announcement title.'), findsOneWidget);
      expect(find.text('Please enter announcement content.'), findsOneWidget);
      expect(submitCalled, isFalse);

      // Fill with only whitespace
      await tester.enterText(find.byKey(const Key('announcement_title_field')), '   ');
      await tester.enterText(find.byKey(const Key('announcement_content_field')), ' \n  ');
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter an announcement title.'), findsOneWidget);
      expect(find.text('Please enter announcement content.'), findsOneWidget);
      expect(submitCalled, isFalse);
    });

    testWidgets('Submission progress: Disables inputs and prevents duplicate submission', (tester) async {
      final completer = Completer<void>();
      var submitCallCount = 0;

      await tester.pumpWidget(buildTestWidget(
        onSubmit: (_) {
          submitCallCount++;
          return completer.future;
        },
      ));

      await tester.enterText(find.byKey(const Key('announcement_title_field')), 'Choir Practice');
      await tester.enterText(find.byKey(const Key('announcement_content_field')), 'Saturday at 4pm in Main Hall.');

      // Tap publish once
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pump();

      expect(submitCallCount, 1);
      expect(find.text('Publishing...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify fields are disabled during submission
      final titleField = tester.widget<TextFormField>(find.byKey(const Key('announcement_title_field')));
      expect(titleField.enabled, isFalse);

      final contentField = tester.widget<TextFormField>(find.byKey(const Key('announcement_content_field')));
      expect(contentField.enabled, isFalse);

      // Attempt second tap while in-flight
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pump();

      // Submit call count must remain 1 (no duplicate submission)
      expect(submitCallCount, 1);

      // Complete the async operation
      completer.complete();
      await tester.pumpAndSettle();

      expect(find.text('Announcement published successfully.'), findsOneWidget);
    });

    testWidgets('Success: Collects title, content, priority and pops route', (tester) async {
      CreateAnnouncementInput? submittedInput;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AnnouncementComposerScreen.show(
              context,
              onSubmit: (input) async {
                submittedInput = input;
              },
            ),
            child: const Text('Open Composer'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Composer'));
      await tester.pumpAndSettle();

      expect(find.text('New Announcement'), findsOneWidget);

      // Enter details
      await tester.enterText(find.byKey(const Key('announcement_title_field')), 'Building Renovation');
      await tester.enterText(find.byKey(const Key('announcement_content_field')), 'Main sanctuary painting begins Monday.');

      // Change priority to Urgent
      await tester.tap(find.byKey(const Key('announcement_priority_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgent').last);
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(submittedInput, isNotNull);
      expect(submittedInput!.title, 'Building Renovation');
      expect(submittedInput!.content, 'Main sanctuary painting begins Monday.');
      expect(submittedInput!.priority, AnnouncementPriority.urgent);

      // Screen popped back to caller
      expect(find.text('Open Composer'), findsOneWidget);
      expect(find.text('New Announcement'), findsNothing);
    });

    testWidgets('Recoverable failure: Displays error, re-enables publish, and retains draft intact for retry', (tester) async {
      var attempt = 0;
      CreateAnnouncementInput? secondAttemptInput;

      await tester.pumpWidget(buildTestWidget(
        onSubmit: (input) async {
          attempt++;
          if (attempt == 1) {
            throw Exception('Connection failed: HTTP 503 Service Unavailable');
          }
          secondAttemptInput = input;
        },
      ));

      await tester.enterText(find.byKey(const Key('announcement_title_field')), 'Annual Picnic');
      await tester.enterText(find.byKey(const Key('announcement_content_field')), 'Please bring your own lunch boxes.');

      // Select Emergency priority
      await tester.tap(find.byKey(const Key('announcement_priority_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emergency').last);
      await tester.pumpAndSettle();

      // First submit attempt fails
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(attempt, 1);

      // Verify error banner and message
      expect(find.byKey(const Key('announcement_error_banner')), findsOneWidget);
      expect(find.text('Connection failed: HTTP 503 Service Unavailable'), findsWidgets);

      // Verify draft is completely preserved
      expect(find.text('Annual Picnic'), findsOneWidget);
      expect(find.text('Please bring your own lunch boxes.'), findsOneWidget);
      expect(find.text('Emergency'), findsOneWidget);

      // Verify button is re-enabled for retry
      expect(find.text('Publish Announcement'), findsOneWidget);

      // Retry submission with the preserved draft
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(secondAttemptInput, isNotNull);
      expect(secondAttemptInput!.title, 'Annual Picnic');
      expect(secondAttemptInput!.content, 'Please bring your own lunch boxes.');
      expect(secondAttemptInput!.priority, AnnouncementPriority.emergency);
      expect(find.text('Announcement published successfully.'), findsOneWidget);
    });

    testWidgets('Cancel button invokes callback or pops route', (tester) async {
      var cancelInvoked = false;
      await tester.pumpWidget(buildTestWidget(
        onSubmit: (_) async {},
        onCancel: () {
          cancelInvoked = true;
        },
      ));

      await tester.tap(find.byKey(const Key('announcement_cancel_button')));
      await tester.pumpAndSettle();

      expect(cancelInvoked, isTrue);
    });

    testWidgets('Validation: Title exceeding 255 characters is rejected', (tester) async {
      var submitCalled = false;
      await tester.pumpWidget(buildTestWidget(
        onSubmit: (_) async {
          submitCalled = true;
        },
        initialTitle: 'A' * 256,
        initialContent: 'Valid announcement content.',
      ));

      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pumpAndSettle();

      expect(find.text('Title cannot exceed 255 characters.'), findsOneWidget);
      expect(submitCalled, isFalse);
    });

    testWidgets('System back navigation: PopScope blocks popping while submitting', (tester) async {
      final completer = Completer<void>();
      var submitCallCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AnnouncementComposerScreen.show(
              context,
              onSubmit: (_) {
                submitCallCount++;
                return completer.future;
              },
            ),
            child: const Text('Launch Composer'),
          ),
        ),
      ));

      await tester.tap(find.text('Launch Composer'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('announcement_title_field')), 'Service Update');
      await tester.enterText(find.byKey(const Key('announcement_content_field')), 'Details regarding service.');

      // Tap publish to start in-flight submission
      await tester.tap(find.byKey(const Key('announcement_publish_button')));
      await tester.pump();

      expect(submitCallCount, 1);
      expect(find.text('Publishing...'), findsOneWidget);

      // Verify PopScope has canPop == false
      final popScopeFinder = find.byType(PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Attempt to pop route (simulating system back)
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();

      // Composer must NOT have popped
      expect(find.text('New Announcement'), findsOneWidget);

      // Complete async submission
      completer.complete();
      await tester.pumpAndSettle();

      // Once completed, route pops cleanly
      expect(find.text('Launch Composer'), findsOneWidget);
      expect(find.text('New Announcement'), findsNothing);
    });

    testWidgets('Renders without overflow on narrow 320px viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildTestWidget(onSubmit: (_) async {}));
      await tester.pumpAndSettle();

      expect(find.text('New Announcement'), findsOneWidget);
      expect(find.byKey(const Key('announcement_title_field')), findsOneWidget);
      expect(find.byKey(const Key('announcement_priority_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('announcement_publish_button')), findsOneWidget);
    });
  });
}
