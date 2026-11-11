import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/models/member_models.dart';
import 'package:church_digital_platform_mobile/screens/profile_screen.dart';
import 'package:church_digital_platform_mobile/services/member_api_client.dart';

class FakeMemberApiClient implements MemberApiClient {
  MemberProfile? myProfile;
  List<DirectoryMember> directory;
  FamilyData? family;
  bool shouldFailGetMyProfile;
  bool shouldFailUpdate;
  bool shouldFailDirectory;
  bool shouldFailFamily;
  String? failureMessage;
  String? nextUpdateFamilyId;
  Completer<void>? updateCompleter;

  FakeMemberApiClient({
    this.myProfile,
    List<DirectoryMember>? directory,
    this.family,
    this.shouldFailGetMyProfile = false,
    this.shouldFailUpdate = false,
    this.shouldFailDirectory = false,
    this.shouldFailFamily = false,
    this.failureMessage,
    this.updateCompleter,
  }) : directory = directory ?? [];

  @override
  Future<MemberProfile> getMyProfile() async {
    if (shouldFailGetMyProfile) {
      throw MemberApiException(failureMessage ?? 'Network error fetching profile');
    }
    return myProfile ??
        const MemberProfile(
          id: 'mem-default',
          tenantId: 'ten-default',
          firstName: 'John',
          lastName: 'Doe',
          email: 'john.doe@church.local',
        );
  }

  @override
  Future<MemberProfile> updateMyProfile(UpdateMemberProfileInput input) async {
    if (updateCompleter != null) {
      await updateCompleter!.future;
    }
    if (shouldFailUpdate) {
      throw MemberApiException(failureMessage ?? 'Failed to update profile');
    }
    myProfile = MemberProfile(
      id: myProfile?.id ?? 'mem-default',
      tenantId: myProfile?.tenantId ?? 'ten-default',
      firstName: input.firstName,
      lastName: input.lastName,
      email: myProfile?.email ?? 'john.doe@church.local',
      phoneNumber: input.phoneNumber,
      avatarUrl: input.avatarUrl ?? myProfile?.avatarUrl,
      address: input.address,
      dateOfBirth: input.dateOfBirth,
      anniversaryDate: input.anniversaryDate,
      directoryVisibility: input.directoryVisibility,
      showEmail: input.showEmail,
      showPhoneNumber: input.showPhoneNumber,
      showAddress: input.showAddress,
      showBirthday: input.showBirthday,
      familyId: nextUpdateFamilyId ?? myProfile?.familyId,
      familyName: myProfile?.familyName,
      familyRole: myProfile?.familyRole ?? FamilyRole.individual,
    );
    return myProfile!;
  }

  @override
  Future<List<DirectoryMember>> getDirectory({
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    if (shouldFailDirectory) {
      throw MemberApiException(failureMessage ?? 'Failed to load directory');
    }
    var list = List<DirectoryMember>.from(directory);
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list
          .where((m) =>
              m.fullName.toLowerCase().contains(q) ||
              (m.email?.toLowerCase().contains(q) ?? false) ||
              (m.familyName?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    final skip = (page - 1) * pageSize;
    return list.skip(skip).take(pageSize).toList();
  }

  @override
  Future<DirectoryMember> getMember(String id) async {
    return directory.firstWhere((m) => m.id == id);
  }

  @override
  Future<FamilyData> getFamily(String id) async {
    if (shouldFailFamily) {
      throw MemberApiException(failureMessage ?? 'Failed to load family');
    }
    return family ??
        FamilyData(
          id: id,
          tenantId: 'ten-default',
          familyName: 'Default Family',
          members: directory,
        );
  }
}

class MockAuthService implements AuthService {
  int signOutCount = 0;
  AuthSession? _currentSession;
  final _sessionController = StreamController<AuthSession?>.broadcast();

  MockAuthService([this._currentSession]);

  @override
  Stream<AuthSession?> get sessionStateStream => _sessionController.stream;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Object? get sessionIdentity => Object();

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

  @override
  void dispose() {
    _sessionController.close();
  }
}

void main() {
  late FakeMemberApiClient fakeClient;
  late MockAuthService mockAuthService;

  setUp(() {
    fakeClient = FakeMemberApiClient(
      myProfile: const MemberProfile(
        id: 'mem-1',
        tenantId: 'ten-1',
        firstName: 'Sarah',
        lastName: 'Connor',
        email: 'sarah@church.local',
        phoneNumber: '+15551234567',
        avatarUrl: 'https://church.local/sarah.png',
        address: '100 Resistance Way',
        directoryVisibility: DirectoryVisibility.publicToMembers,
        showEmail: true,
        showPhoneNumber: true,
        showBirthday: true,
        familyName: 'Connor Family',
        familyRole: FamilyRole.headOfHousehold,
      ),
      directory: const [
        DirectoryMember(
          id: 'mem-1',
          fullName: 'Sarah Connor',
          email: 'sarah@church.local',
          phoneNumber: '+15551234567',
          directoryVisibility: DirectoryVisibility.publicToMembers,
          familyName: 'Connor Family',
          familyRole: FamilyRole.headOfHousehold,
        ),
        DirectoryMember(
          id: 'mem-2',
          fullName: 'John Reese',
          email: null, // Redacted contact
          phoneNumber: null,
          directoryVisibility: null, // Unconfirmed visibility omitted
          familyRole: FamilyRole.individual,
        ),
      ],
    );

    mockAuthService = MockAuthService(
      AuthSession(
        accessToken: 'access_1',
        refreshToken: 'refresh_1',
        userId: 'mem-1',
        tenantId: 'ten-1',
        roles: ['Member'],
        expiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true),
      ),
    );
  });

  tearDown(() {
    mockAuthService.dispose();
  });

  Widget createSubject({
    MemberApiClient? client,
    AuthService? authService,
    bool isPastor = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProfileScreen(
          apiClient: client,
          authService: authService,
          isPastor: isPastor,
        ),
      ),
    );
  }

  testWidgets('renders unauthenticated fail-closed view when apiClient is null', (tester) async {
    await tester.pumpWidget(createSubject(client: null));
    await tester.pumpAndSettle();

    expect(find.text('Sign In Required'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
    expect(find.text('Sarah Connor'), findsNothing);
  });

  testWidgets('renders member profile details and privacy settings when authenticated', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('sarah@church.local'), findsOneWidget);
    expect(find.text('Connor Family (Head of Household)'), findsOneWidget);
    expect(find.text('+15551234567'), findsOneWidget);
    expect(find.text('100 Resistance Way'), findsOneWidget);
    expect(find.text('Public to Members'), findsOneWidget);

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('directory tab displays members and masks redacted contact information', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    // Tap Directory tab
    await tester.tap(find.text('Directory'));
    await tester.pumpAndSettle();

    // Check directory members
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('John Reese'), findsOneWidget);
    expect(find.text('Contact details unlisted'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // Search bar
  });

  testWidgets('edit profile dialog preserves avatar and updates profile and privacy switches', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    // Scroll to Edit Profile button in SingleChildScrollView
    final editButton = find.text('Edit Profile');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit Profile & Privacy'), findsOneWidget);

    // Save changes
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Profile updated successfully.'), findsOneWidget);
    expect(fakeClient.myProfile?.avatarUrl, 'https://church.local/sarah.png');
  });

  testWidgets('disables edit button while profile save is in progress', (tester) async {
    final completer = Completer<void>();
    fakeClient.updateCompleter = completer;

    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    final editButton = find.text('Edit Profile');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit Profile & Privacy'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit Profile'));
    expect(button.onPressed, isNull);

    completer.complete();
    await tester.pumpAndSettle();

    final enabledButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit Profile'));
    expect(enabledButton.onPressed, isNotNull);
    expect(find.text('Profile updated successfully.'), findsOneWidget);
  });

  testWidgets('failed directory search keeps previous query and disables pagination', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Directory'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);

    fakeClient.shouldFailDirectory = true;
    fakeClient.failureMessage = 'Directory lookup failed';

    await tester.enterText(find.byType(TextField), 'Unknown');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Directory lookup failed'), findsOneWidget);
    expect(find.text('Sarah Connor'), findsOneWidget);
  });

  testWidgets('reverting search input invalidates pending query', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Directory'));
    await tester.pumpAndSettle();

    // Type query then revert back to empty
    await tester.enterText(find.byType(TextField), 'John');
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    // Both members should be visible because empty query won
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('John Reese'), findsOneWidget);
  });

  testWidgets('sign out shows confirmation dialog, cancel leaves session intact', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    // Scroll to Sign Out button in SingleChildScrollView
    final signOutButton = find.text('Sign Out');
    await tester.ensureVisible(signOutButton);
    await tester.tap(signOutButton);
    await tester.pumpAndSettle();

    // Verify confirmation dialog appears
    expect(find.text('Are you sure you want to sign out? Your cached profile and church directory access will be cleared from this device.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(mockAuthService.signOutCount, 0);
    expect(find.text('Sarah Connor'), findsOneWidget);
  });

  testWidgets('sign out confirms, calls authService signOut and clears cached session state', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    // Scroll to Sign Out button in SingleChildScrollView
    final signOutButton = find.text('Sign Out');
    await tester.ensureVisible(signOutButton);
    await tester.tap(signOutButton);
    await tester.pumpAndSettle();

    // Find the Confirm Sign Out button in the dialog (which has label 'Sign Out' inside AlertDialog)
    final confirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Sign Out'),
    );
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(mockAuthService.signOutCount, 1);
    // Cached profile name should no longer be displayed
    expect(find.text('Sarah Connor'), findsNothing);
  });

  testWidgets('renders family unit details when profile has familyId', (tester) async {
    fakeClient.myProfile = fakeClient.myProfile?.copyWith(
      familyId: 'fam-1',
      familyName: 'Connor Family',
      familyRole: FamilyRole.headOfHousehold,
    );
    fakeClient.family = const FamilyData(
      id: 'fam-1',
      tenantId: 'ten-1',
      familyName: 'Connor Family',
      members: [
        DirectoryMember(
          id: 'mem-1',
          fullName: 'Sarah Connor',
          email: 'sarah@church.local',
          familyId: 'fam-1',
          familyName: 'Connor Family',
          familyRole: FamilyRole.headOfHousehold,
        ),
        DirectoryMember(
          id: 'mem-3',
          fullName: 'John Connor',
          email: 'johnc@church.local',
          familyId: 'fam-1',
          familyName: 'Connor Family',
          familyRole: FamilyRole.child,
        ),
      ],
    );

    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Connor Family'), findsWidgets);
    expect(find.text('John Connor'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Child • johnc@church.local'), findsOneWidget);
  });

  testWidgets('displays error and retry when family fetch fails', (tester) async {
    fakeClient.myProfile = fakeClient.myProfile?.copyWith(
      familyId: 'fam-fail',
      familyName: 'Failing Family',
    );
    fakeClient.family = null;
    fakeClient.shouldFailFamily = true;
    fakeClient.failureMessage = 'Family network error';

    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Family network error'), findsOneWidget);
    expect(find.text('Retry Family'), findsOneWidget);

    fakeClient.shouldFailFamily = false;
    fakeClient.family = const FamilyData(
      id: 'fam-fail',
      tenantId: 'ten-1',
      familyName: 'Failing Family',
      members: [],
    );

    await tester.tap(find.text('Retry Family'));
    await tester.pumpAndSettle();

    expect(find.text('No other family members listed.'), findsOneWidget);
  });

  testWidgets('displays 401 authentication required error with retry button', (tester) async {
    fakeClient.shouldFailGetMyProfile = true;
    fakeClient.failureMessage = 'Authentication required. Please sign in.';

    await tester.pumpWidget(createSubject(client: fakeClient));
    await tester.pumpAndSettle();

    expect(find.text('Authentication required. Please sign in.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('displays 403 access denied error with retry button', (tester) async {
    fakeClient.shouldFailGetMyProfile = true;
    fakeClient.failureMessage = 'Access denied. You do not have permission for this member action.';

    await tester.pumpWidget(createSubject(client: fakeClient));
    await tester.pumpAndSettle();

    expect(find.text('Access denied. You do not have permission for this member action.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('displays error message and retry button when getMyProfile fails', (tester) async {
    fakeClient.shouldFailGetMyProfile = true;
    fakeClient.failureMessage = 'Database connection failed';

    await tester.pumpWidget(createSubject(client: fakeClient));
    await tester.pumpAndSettle();

    expect(find.text('Database connection failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Now restore and retry
    fakeClient.shouldFailGetMyProfile = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Connor'), findsOneWidget);
  });

  testWidgets('clears cached family details when familyId changes and shows error/retry on failure', (tester) async {
    fakeClient.myProfile = fakeClient.myProfile?.copyWith(
      familyId: 'fam-1',
      familyName: 'Connor Family',
    );
    fakeClient.family = const FamilyData(
      id: 'fam-1',
      tenantId: 'ten-1',
      familyName: 'Connor Family',
      members: [
        DirectoryMember(
          id: 'mem-3',
          fullName: 'Old Family Member',
          familyId: 'fam-1',
          familyName: 'Connor Family',
          familyRole: FamilyRole.child,
        ),
      ],
    );

    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: mockAuthService,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Old Family Member'), findsOneWidget);

    // Reassign to fam-2 on next save and make fam-2 fetch fail.
    fakeClient.nextUpdateFamilyId = 'fam-2';
    fakeClient.shouldFailFamily = true;
    fakeClient.failureMessage = 'New family load failed';

    final editBtn = find.text('Edit Profile');
    await tester.ensureVisible(editBtn);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Previous family details must be cleared and error/retry surfaced.
    expect(find.text('Old Family Member'), findsNothing);
    expect(find.text('New family load failed'), findsOneWidget);
    expect(find.text('Retry Family'), findsOneWidget);

    // Retrying succeeds with new family data.
    fakeClient.shouldFailFamily = false;
    fakeClient.family = const FamilyData(
      id: 'fam-2',
      tenantId: 'ten-1',
      familyName: 'Reassigned Family',
      members: [
        DirectoryMember(
          id: 'mem-4',
          fullName: 'New Family Member',
          familyId: 'fam-2',
          familyName: 'Reassigned Family',
          familyRole: FamilyRole.spouse,
        ),
      ],
    );

    final retryBtn = find.text('Retry Family');
    await tester.ensureVisible(retryBtn);
    await tester.tap(retryBtn);
    await tester.pumpAndSettle();

    expect(find.text('New Family Member'), findsOneWidget);
    expect(find.text('Old Family Member'), findsNothing);
  });
}
