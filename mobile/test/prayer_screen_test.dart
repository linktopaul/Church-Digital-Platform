import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/main.dart';
import 'package:church_digital_platform_mobile/models/prayer_models.dart';
import 'package:church_digital_platform_mobile/screens/prayer_screen.dart';
import 'package:church_digital_platform_mobile/services/prayer_api_client.dart';
import 'support/in_memory_secure_token_storage.dart';
import 'support/mock_auth_provider.dart';

class FakePrayerApiClient implements PrayerApiClient {
  List<PrayerRequestData> myRequests;
  List<PrayerRequestData> allRequests;
  bool shouldFailGetMy;
  bool shouldFailGetAll;
  bool shouldFailCreate;
  bool shouldFailUpdate;
  String? failureMessage;

  FakePrayerApiClient({
    List<PrayerRequestData>? myRequests,
    List<PrayerRequestData>? allRequests,
    this.shouldFailGetMy = false,
    this.shouldFailGetAll = false,
    this.shouldFailCreate = false,
    this.shouldFailUpdate = false,
    this.failureMessage,
  })  : myRequests = myRequests ?? [],
        allRequests = allRequests ?? [];

  @override
  Future<List<PrayerRequestData>> getMyPrayerRequests() async {
    if (shouldFailGetMy) {
      throw PrayerApiException(failureMessage ?? 'Network error fetching requests');
    }
    return List.from(myRequests);
  }

  @override
  Future<List<PrayerRequestData>> getAllPrayerRequests() async {
    if (shouldFailGetAll) {
      throw PrayerApiException(failureMessage ?? 'Access denied');
    }
    return List.from(allRequests);
  }

  @override
  Future<PrayerRequestData> createPrayerRequest(CreatePrayerRequestInput input) async {
    if (shouldFailCreate) {
      throw PrayerApiException(failureMessage ?? 'Failed to submit prayer request');
    }
    final created = PrayerRequestData(
      id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
      churchId: 'church-1',
      memberId: 'member-1',
      content: input.content,
      status: PrayerRequestStatus.submitted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    myRequests.insert(0, created);
    allRequests.insert(0, created);
    return created;
  }

  @override
  Future<PrayerRequestData> updatePrayerRequestStatus(
    String id,
    UpdatePrayerRequestStatusInput input,
  ) async {
    if (shouldFailUpdate) {
      throw PrayerApiException(failureMessage ?? 'Status update rejected');
    }
    final idx = allRequests.indexWhere((r) => r.id == id);
    if (idx == -1) {
      throw const PrayerApiException('Not found', statusCode: 404);
    }
    final updated = allRequests[idx].copyWith(
      status: input.status,
      updatedAt: DateTime.now(),
    );
    allRequests[idx] = updated;
    final myIdx = myRequests.indexWhere((r) => r.id == id);
    if (myIdx != -1) {
      myRequests[myIdx] = updated;
    }
    return updated;
  }
}

class DeferredPrayerApiClient extends FakePrayerApiClient {
  final Completer<List<PrayerRequestData>> myRequestsCompleter = Completer<List<PrayerRequestData>>();
  final Completer<PrayerRequestData> createCompleter = Completer<PrayerRequestData>();

  @override
  Future<List<PrayerRequestData>> getMyPrayerRequests() => myRequestsCompleter.future;

  @override
  Future<PrayerRequestData> createPrayerRequest(CreatePrayerRequestInput input) =>
      createCompleter.future;
}

void main() {
  Widget createWidgetUnderTest({
    PrayerApiClient? apiClient,
    bool isPastor = false,
  }) {
    return MaterialApp(
      home: PrayerScreen(
        apiClient: apiClient,
        isPastor: isPastor,
      ),
    );
  }

  testWidgets('fails closed with explicit sign-in UI when apiClient is null', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(apiClient: null));
    await tester.pump();

    expect(find.text('Sign In Required'), findsOneWidget);
    expect(find.textContaining('Confidential pastoral prayer requests require an active, authenticated member session.'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('displays loading and then empty state for member', (tester) async {
    final fakeClient = FakePrayerApiClient(myRequests: []);

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('No Submitted Requests'), findsOneWidget);
    expect(find.textContaining('Share your requests with our pastoral team confidentially.'), findsOneWidget);
    expect(find.text('Request Prayer'), findsOneWidget);
  });

  testWidgets('empty state supports pull-to-refresh to load newly submitted requests', (tester) async {
    final fakeClient = FakePrayerApiClient(myRequests: [], allRequests: []);

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Pastoral Requests'));
    await tester.pumpAndSettle();
    expect(find.text('No Prayer Requests'), findsOneWidget);

    fakeClient.allRequests = [
      PrayerRequestData(
        id: 'new-pastor-req',
        churchId: 'c1',
        memberId: 'm2',
        content: 'Newly arrived confidential prayer request',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime(2026, 11, 2),
        updatedAt: DateTime(2026, 11, 2),
      ),
    ];

    await tester.drag(find.text('No Prayer Requests'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('Newly arrived confidential prayer request'), findsOneWidget);
  });

  testWidgets('displays list of requests for member without pastor controls', (tester) async {
    final fakeClient = FakePrayerApiClient(
      myRequests: [
        PrayerRequestData(
          id: 'req-1',
          churchId: 'church-1',
          memberId: 'member-1',
          content: 'Please pray for wisdom with family decisions.',
          status: PrayerRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: false));
    await tester.pumpAndSettle();

    expect(find.text('Please pray for wisdom with family decisions.'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Confidential'), findsOneWidget);
    // Member cannot mutate status
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('shows error state with functional retry button', (tester) async {
    final fakeClient = FakePrayerApiClient(
      shouldFailGetMy: true,
      failureMessage: 'Connection failed',
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient));
    await tester.pumpAndSettle();

    expect(find.text('Unable to Load Requests'), findsOneWidget);
    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Fix error and tap Retry
    fakeClient.shouldFailGetMy = false;
    fakeClient.myRequests = [
      PrayerRequestData(
        id: 'r2',
        churchId: 'c1',
        memberId: 'm1',
        content: 'Recovered after retry',
        status: PrayerRequestStatus.praying,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      ),
    ];

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered after retry'), findsOneWidget);
  });

  testWidgets('submits new prayer request and updates UI on success', (tester) async {
    final fakeClient = FakePrayerApiClient();

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient));
    await tester.pumpAndSettle();

    // Open bottom sheet
    await tester.tap(find.text('Request Prayer'));
    await tester.pumpAndSettle();

    expect(find.text('Confidential Prayer Request'), findsOneWidget);
    expect(find.textContaining('visible only to pastoral staff'), findsOneWidget);

    // Enter request
    await tester.enterText(
      find.byType(TextFormField),
      'Praying for church unity and upcoming mission trip.',
    );

    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(find.text('Praying for church unity and upcoming mission trip.'), findsOneWidget);
    expect(find.text('Your prayer request was submitted confidentially.'), findsOneWidget);
  });

  testWidgets('preserves submission confirmation and list update if sheet is dismissed while POST is pending', (tester) async {
    final deferredClient = DeferredPrayerApiClient();
    deferredClient.myRequestsCompleter.complete([]);

    await tester.pumpWidget(createWidgetUnderTest(apiClient: deferredClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request Prayer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Slow network prayer request');
    await tester.tap(find.text('Submit Request'));
    await tester.pump();

    // User dismisses the bottom sheet while POST is still in flight.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    // Server confirms creation after sheet was dismissed.
    deferredClient.createCompleter.complete(
      PrayerRequestData(
        id: 'created-slow',
        churchId: 'c1',
        memberId: 'm1',
        content: 'Slow network prayer request',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime(2026, 11, 2),
        updatedAt: DateTime(2026, 11, 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Slow network prayer request'), findsOneWidget);
    expect(find.text('Your prayer request was submitted confidentially.'), findsOneWidget);
  });

  testWidgets('handles submission rejection with error and preserves input without optimistic addition', (tester) async {
    final fakeClient = FakePrayerApiClient(
      shouldFailCreate: true,
      failureMessage: 'Service rejected invalid tenant',
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request Prayer'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField),
      'Should not be optimistically added',
    );

    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    // Bottom sheet remains open with error displayed
    expect(find.text('Service rejected invalid tenant'), findsOneWidget);
    expect(find.text('Should not be optimistically added'), findsOneWidget);

    // Dismiss sheet by tapping close
    final closeFinder = find.byIcon(Icons.close);
    await tester.ensureVisible(closeFinder);
    await tester.tap(closeFinder);
    await tester.pumpAndSettle();

    // The bottom sheet is dismissed and the item was never added to the list
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Should not be optimistically added'), findsNothing);
    expect(find.text('No Submitted Requests'), findsOneWidget);
  });

  testWidgets('pastor view displays tabs and allows status change on server confirmation', (tester) async {
    final fakeClient = FakePrayerApiClient(
      myRequests: [],
      allRequests: [
        PrayerRequestData(
          id: 'req-pastor-1',
          churchId: 'c1',
          memberId: 'other-user',
          content: 'Parishioner surgery needs',
          status: PrayerRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: true));
    await tester.pumpAndSettle();

    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('All Pastoral Requests'), findsOneWidget);

    // Switch to Pastoral Requests tab
    await tester.tap(find.text('All Pastoral Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Parishioner surgery needs'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);

    // Open popup menu to change status
    final popupFinder = find.byIcon(Icons.more_vert);
    expect(popupFinder, findsOneWidget);
    await tester.tap(popupFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as Praying'));
    await tester.pumpAndSettle();

    expect(find.text('Praying'), findsOneWidget);
    expect(fakeClient.allRequests.first.status, PrayerRequestStatus.praying);
  });

  testWidgets('pastor status rejection displays error snackbar and leaves status unchanged', (tester) async {
    final fakeClient = FakePrayerApiClient(
      shouldFailUpdate: true,
      failureMessage: 'Forbidden status change',
      allRequests: [
        PrayerRequestData(
          id: 'req-pastor-2',
          churchId: 'c1',
          memberId: 'other-user',
          content: 'Needs pastor prayer',
          status: PrayerRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Pastoral Requests'));
    await tester.pumpAndSettle();

    final popupFinder = find.byIcon(Icons.more_vert);
    await tester.tap(popupFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as Answered'));
    await tester.pumpAndSettle();

    // Shows error SnackBar
    expect(find.text('Forbidden status change'), findsOneWidget);
    // Status in list remains Submitted
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Answered'), findsNothing);
  });

  testWidgets('discards late A response after switching from client A to client B', (tester) async {
    final clientA = DeferredPrayerApiClient();
    final clientB = FakePrayerApiClient(
      myRequests: [
        PrayerRequestData(
          id: 'req-b',
          churchId: 'c1',
          memberId: 'member-b',
          content: 'Member B confidential request',
          status: PrayerRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 2),
          updatedAt: DateTime(2026, 11, 2),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: clientA));
    await tester.pump();

    // Switch to Member B before Member A's response arrives.
    await tester.pumpWidget(createWidgetUnderTest(apiClient: clientB));
    await tester.pumpAndSettle();

    expect(find.text('Member B confidential request'), findsOneWidget);

    // Late completion of Member A's load must be ignored.
    clientA.myRequestsCompleter.complete([
      PrayerRequestData(
        id: 'req-a',
        churchId: 'c1',
        memberId: 'member-a',
        content: 'Member A secret prayer',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Member B confidential request'), findsOneWidget);
    expect(find.text('Member A secret prayer'), findsNothing);
  });

  testWidgets('invalidates open submission sheet on account switch or logout', (tester) async {
    final clientA = DeferredPrayerApiClient();
    clientA.myRequestsCompleter.complete([]);
    final clientB = FakePrayerApiClient(myRequests: []);

    await tester.pumpWidget(createWidgetUnderTest(apiClient: clientA));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request Prayer'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Member A pending submission');
    await tester.tap(find.text('Submit Request'));
    await tester.pump();

    // Switch account to clientB while sheet is open and POST is pending.
    await tester.pumpWidget(createWidgetUnderTest(apiClient: clientB));
    await tester.pumpAndSettle();

    // Sheet is automatically dismissed and late completion from A is ignored.
    expect(find.byType(BottomSheet), findsNothing);
    clientA.createCompleter.complete(
      PrayerRequestData(
        id: 'a-created',
        churchId: 'c1',
        memberId: 'member-a',
        content: 'Member A pending submission',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime(2026, 11, 2),
        updatedAt: DateTime(2026, 11, 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Member A pending submission'), findsNothing);
  });

  testWidgets('supports updating isPastor from false to true without ticker assertion', (tester) async {
    final fakeClient = FakePrayerApiClient(
      myRequests: [],
      allRequests: [
        PrayerRequestData(
          id: 'pastor-feed-item',
          churchId: 'c1',
          memberId: 'm2',
          content: 'Pastoral care needed',
          status: PrayerRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 2),
          updatedAt: DateTime(2026, 11, 2),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: false));
    await tester.pumpAndSettle();
    expect(find.text('All Pastoral Requests'), findsNothing);

    await tester.pumpWidget(createWidgetUnderTest(apiClient: fakeClient, isPastor: true));
    await tester.pumpAndSettle();

    expect(find.text('All Pastoral Requests'), findsOneWidget);
    await tester.tap(find.text('All Pastoral Requests'));
    await tester.pumpAndSettle();
    expect(find.text('Pastoral care needed'), findsOneWidget);
  });

  group('MainNavigationScreen prayer wiring', () {
    testWidgets('shows unauthenticated state when no session is present', (tester) async {
      await tester.pumpWidget(const ChurchMobileApp());
      // Switch to Prayer tab (index 2)
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.text('Sign In Required'), findsOneWidget);
    });

    testWidgets('wires HttpPrayerApiClient and pastoral feed when pastor session is present', (tester) async {
      final mockAuth = MockAuthProvider(
        mockSessionToReturn: AuthSession(
          accessToken: 'pastor-token',
          refreshToken: 'pastor-refresh',
          userId: 'pastor-user-id',
          tenantId: 'tenant-1',
          roles: const ['Pastor'],
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final manager = AuthSessionManager(
        provider: mockAuth,
        storage: InMemorySecureTokenStorage(),
      );
      await manager.setSession(mockAuth.mockSessionToReturn!);

      await tester.pumpWidget(ChurchMobileApp(
        authService: manager,
        apiBaseUrl: 'https://church.example.com',
      ));
      // Switch to Prayer tab (index 2)
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      // Expect pastoral tabs ("My Requests" and "All Pastoral Requests") rather than "Sign In Required"
      expect(find.text('Sign In Required'), findsNothing);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('All Pastoral Requests'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('preserves prayer client and does not reset state across same-session token refresh', (tester) async {
      final initialSession = AuthSession(
        accessToken: 'pastor-token-1',
        refreshToken: 'pastor-refresh-1',
        userId: 'pastor-user-id',
        tenantId: 'tenant-1',
        roles: const ['Pastor'],
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      final mockAuth = MockAuthProvider(mockSessionToReturn: initialSession);
      final manager = AuthSessionManager(
        provider: mockAuth,
        storage: InMemorySecureTokenStorage(),
      );
      await manager.setSession(initialSession);

      await tester.pumpWidget(ChurchMobileApp(
        authService: manager,
        apiBaseUrl: 'https://church.example.com',
      ));
      // Switch to Prayer tab (index 2)
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(find.text('Sign In Required'), findsNothing);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('All Pastoral Requests'), findsOneWidget);

      // Trigger token refresh with same userId and tenantId
      final refreshedSession = initialSession.copyWith(
        accessToken: 'pastor-token-refreshed',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await manager.setSession(refreshedSession);
      await tester.pump();

      // State is preserved and pastoral feed remains displayed
      expect(find.text('Sign In Required'), findsNothing);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('All Pastoral Requests'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('retains authenticated prayer client for refreshable session when access token is expired', (tester) async {
      final expiredRefreshableSession = AuthSession(
        accessToken: 'expired-pastor-token',
        refreshToken: 'valid-pastor-refresh',
        userId: 'pastor-user-id',
        tenantId: 'tenant-1',
        roles: const ['Pastor'],
        expiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final mockAuth = MockAuthProvider(mockSessionToReturn: expiredRefreshableSession);
      final manager = AuthSessionManager(
        provider: mockAuth,
        storage: InMemorySecureTokenStorage(),
      );
      await manager.setSession(expiredRefreshableSession);

      await tester.pumpWidget(ChurchMobileApp(
        authService: manager,
        apiBaseUrl: 'https://church.example.com',
      ));
      // Switch to Prayer tab (index 2)
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      // Because session has a valid refresh token, it retains the authenticated client
      expect(find.text('Sign In Required'), findsNothing);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('All Pastoral Requests'), findsOneWidget);

      manager.dispose();
    });
  });
}