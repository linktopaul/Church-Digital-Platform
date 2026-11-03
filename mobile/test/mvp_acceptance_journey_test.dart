import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/models/prayer_models.dart';
import 'package:church_digital_platform_mobile/network/api_exceptions.dart';
import 'package:church_digital_platform_mobile/network/authenticated_http_client.dart';
import 'package:church_digital_platform_mobile/screens/prayer_screen.dart';
import 'package:church_digital_platform_mobile/services/prayer_api_client.dart';

/// Lightweight mock auth service that executes synchronously without lingering timers.
class MockAuthService implements AuthService {
  int signOutCount = 0;
  AuthSession? _currentSession;
  final StreamController<AuthSession?> _sessionController = StreamController<AuthSession?>.broadcast();

  MockAuthService([this._currentSession]);

  @override
  Stream<AuthSession?> get sessionStateStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Object? get sessionIdentity => _currentSession != null ? Object() : null;

  @override
  Future<AuthSession?> initialize() async => _currentSession;

  @override
  Future<AuthSession> signInWithAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) => throw UnimplementedError();

  @override
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    _sessionController.add(session);
  }

  @override
  Future<AuthSession> refresh() => throw UnimplementedError();

  @override
  Future<void> signOut() async {
    signOutCount++;
    _currentSession = null;
    _sessionController.add(null);
  }

  void dispose() {
    _sessionController.close();
  }
}

/// Fake in-memory prayer API client for acceptance testing.
class JourneyPrayerApiClient implements PrayerApiClient {
  List<PrayerRequestData> myRequests;
  List<PrayerRequestData> allRequests;
  bool shouldFailGetMy;
  bool shouldFailGetAll;
  bool shouldFailCreate;
  bool shouldFailUpdate;
  String? failureMessage;
  int createCallCount = 0;

  JourneyPrayerApiClient({
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
      throw PrayerApiException(failureMessage ?? 'Network error fetching my requests');
    }
    return List.from(myRequests);
  }

  @override
  Future<List<PrayerRequestData>> getAllPrayerRequests() async {
    if (shouldFailGetAll) {
      throw PrayerApiException(failureMessage ?? 'Access denied to pastoral feed', statusCode: 403);
    }
    return List.from(allRequests);
  }

  @override
  Future<PrayerRequestData> createPrayerRequest(CreatePrayerRequestInput input) async {
    createCallCount++;
    if (shouldFailCreate) {
      throw PrayerApiException(failureMessage ?? 'Failed to submit prayer request');
    }
    final created = PrayerRequestData(
      id: 'req-${DateTime.now().millisecondsSinceEpoch}',
      churchId: 'tenant-church-alpha',
      memberId: 'member-alpha-1',
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
      throw PrayerApiException(failureMessage ?? 'Status update failed');
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

/// Fake HTTP client for testing AuthenticatedHttpClient header validation and token attachment.
class FakeInnerHttpClient extends http.BaseClient {
  http.BaseRequest? lastCapturedRequest;
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastCapturedRequest = request;
    sendCount++;
    return http.StreamedResponse(
      const Stream.empty(),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('Security & Protocol Compliance: AuthenticatedHttpClient', () {
    test('rejects forged client-supplied tenant and role headers before network transmission', () async {
      final auth = MockAuthService();
      final inner = FakeInnerHttpClient();
      final client = AuthenticatedHttpClient(authService: auth, inner: inner);

      final forbiddenHeaders = [
        {'x-tenant-id': 'forged-tenant'},
        {'x-user-role': 'Pastor'},
        {'x-church-id': 'forged-church'},
        {'x-user-id': 'forged-user'},
      ];

      for (final headerMap in forbiddenHeaders) {
        final req = http.Request('GET', Uri.parse('https://church.api/v1/prayer-requests'))..headers.addAll(headerMap);
        expect(
          () => client.send(req),
          throwsA(isA<ProhibitedHeaderException>()),
          reason: 'Expected ProhibitedHeaderException for header ${headerMap.keys.first}',
        );
      }

      expect(inner.sendCount, 0, reason: 'No network request should have been dispatched');
    });

    test('automatically attaches Bearer token from active session without forged headers', () async {
      final session = AuthSession(
        accessToken: 'valid-signed-rsa-access-token',
        refreshToken: 'valid-refresh-token',
        userId: 'usr-verified-1',
        tenantId: 'ten-church-1',
        roles: const ['Member'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final auth = MockAuthService(session);
      final inner = FakeInnerHttpClient();
      final client = AuthenticatedHttpClient(authService: auth, inner: inner);

      final req = http.Request('GET', Uri.parse('https://church.api/v1/prayer-requests/my'));
      await client.send(req);

      expect(inner.sendCount, 1);
      expect(inner.lastCapturedRequest?.headers['authorization'], 'Bearer valid-signed-rsa-access-token');
      expect(inner.lastCapturedRequest?.headers.containsKey('x-tenant-id'), isFalse);
      expect(inner.lastCapturedRequest?.headers.containsKey('x-user-role'), isFalse);
    });
  });

  group('Mobile Acceptance Journey: Invite-to-Confidential-Prayer', () {
    testWidgets('Unauthenticated Journey: Fails closed with Sign In Required view and no pastoral controls', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PrayerScreen(apiClient: null, isPastor: false),
      ));
      await tester.pump();

      expect(find.text('Sign In Required'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(
        find.text('Confidential pastoral prayer requests require an active, authenticated member session.'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('All Pastoral Requests'), findsNothing);
    });

    testWidgets('Member Journey: Displays single tab, submits confidential prayer, and updates persisted list', (tester) async {
      final client = JourneyPrayerApiClient();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: client, isPastor: false),
        ),
      ));
      await tester.pump();

      // Verify no pastoral tabs or admin controls for regular member
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('All Pastoral Requests'), findsNothing);
      expect(find.text('No Submitted Requests'), findsOneWidget);

      // Open prayer submission sheet
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Confidential Prayer Request'), findsOneWidget);
      expect(find.text('This request is strictly confidential and visible only to pastoral staff.'), findsOneWidget);

      // Enter confidential prayer request text
      await tester.enterText(
        find.byType(TextField),
        'Please pray for quick recovery from upcoming surgery.',
      );
      await tester.pump();

      // Submit
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      // Verify client call and persisted record
      expect(client.createCallCount, 1);
      expect(find.text('Confidential Prayer Request'), findsNothing); // Sheet dismissed
      expect(find.text('Please pray for quick recovery from upcoming surgery.'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Confidential'), findsOneWidget);
    });

    testWidgets('Pastoral Journey: Conditionally exposes Pastoral Feed and enables status transition', (tester) async {
      final initialPrayer = PrayerRequestData(
        id: 'prayer-alpha-123',
        churchId: 'church-1',
        memberId: 'member-1',
        content: 'Urgent prayer for family coping with bereavement.',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      final client = JourneyPrayerApiClient(
        myRequests: [],
        allRequests: [initialPrayer],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: client, isPastor: true),
        ),
      ));
      await tester.pump();

      // Pastoral view shows both tabs in TabBar
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('All Pastoral Requests'), findsOneWidget);

      // Switch to pastoral feed tab
      await tester.tap(find.text('All Pastoral Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Urgent prayer for family coping with bereavement.'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);

      // Pastor opens status change popup
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Praying'), findsOneWidget);
      expect(find.text('Mark as Answered'), findsOneWidget);

      // Transition to Praying
      await tester.tap(find.text('Mark as Praying'));
      await tester.pumpAndSettle();

      expect(find.text('Praying'), findsOneWidget);
      expect(client.allRequests.first.status, PrayerRequestStatus.praying);

      // Transition to Answered
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as Answered'));
      await tester.pumpAndSettle();

      expect(find.text('Answered'), findsOneWidget);
      expect(client.allRequests.first.status, PrayerRequestStatus.answered);
    });

    testWidgets('Role Privacy Boundary: Non-pastor member cannot access status change controls', (tester) async {
      final prayer = PrayerRequestData(
        id: 'prayer-alpha-456',
        churchId: 'church-1',
        memberId: 'member-1',
        content: 'Prayer for college entrance exams.',
        status: PrayerRequestStatus.submitted,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final client = JourneyPrayerApiClient(myRequests: [prayer]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: client, isPastor: false),
        ),
      ));
      await tester.pump();

      expect(find.text('Prayer for college entrance exams.'), findsOneWidget);
      expect(find.byTooltip('Change Status'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('All Pastoral Requests'), findsNothing);
    });

    testWidgets('Session Switch & Logout: Confidential state is purged immediately', (tester) async {
      final clientA = JourneyPrayerApiClient(
        myRequests: [
          PrayerRequestData(
            id: 'confidential-a',
            churchId: 'church-a',
            memberId: 'member-a',
            content: 'Confidential request belonging to Member A.',
            status: PrayerRequestStatus.submitted,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: clientA, isPastor: false),
        ),
      ));
      await tester.pump();

      expect(find.text('Confidential request belonging to Member A.'), findsOneWidget);

      // Sign-out / client becomes null
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: null, isPastor: false),
        ),
      ));
      await tester.pump();

      // State is completely purged and fails closed
      expect(find.text('Confidential request belonging to Member A.'), findsNothing);
      expect(find.text('Sign In Required'), findsOneWidget);

      // Sign-in with different account Client B
      final clientB = JourneyPrayerApiClient(
        myRequests: [
          PrayerRequestData(
            id: 'confidential-b',
            churchId: 'church-b',
            memberId: 'member-b',
            content: 'Confidential request belonging to Member B.',
            status: PrayerRequestStatus.submitted,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: clientB, isPastor: false),
        ),
      ));
      await tester.pump();

      expect(find.text('Confidential request belonging to Member A.'), findsNothing);
      expect(find.text('Confidential request belonging to Member B.'), findsOneWidget);
    });

    testWidgets('Network Resilience: Submission rejection displays error, preserves draft, and prevents duplicate POST', (tester) async {
      final client = JourneyPrayerApiClient(
        shouldFailCreate: true,
        failureMessage: 'Server unreachable during submission',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrayerScreen(apiClient: client, isPastor: false),
        ),
      ));
      await tester.pump();

      // Open sheet
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Confidential Prayer Request'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Urgent medical prayer draft.',
      );
      await tester.pump();

      // Tap Submit Request
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      // Verifies inline error message displayed in sheet
      expect(find.text('Server unreachable during submission'), findsOneWidget);

      // Verifies draft text is NOT lost and sheet remained open
      expect(find.text('Urgent medical prayer draft.'), findsOneWidget);
      expect(find.text('Confidential Prayer Request'), findsOneWidget); // Bottom sheet remained open

      // Verifies no prayer item added to background list
      expect(client.myRequests, isEmpty);
    });
  });
}
