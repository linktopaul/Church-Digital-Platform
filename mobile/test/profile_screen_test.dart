import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/models/member_models.dart';
import 'package:church_digital_platform_mobile/screens/profile_screen.dart';
import 'package:church_digital_platform_mobile/services/member_api_client.dart';
import 'support/in_memory_secure_token_storage.dart';
import 'support/mock_auth_provider.dart';

class FakeMemberApiClient implements MemberApiClient {
  MemberProfile? myProfile;
  List<DirectoryMember> directory;
  FamilyData? family;
  bool shouldFailGetMyProfile;
  bool shouldFailUpdate;
  bool shouldFailDirectory;
  String? failureMessage;

  FakeMemberApiClient({
    this.myProfile,
    List<DirectoryMember>? directory,
    this.family,
    this.shouldFailGetMyProfile = false,
    this.shouldFailUpdate = false,
    this.shouldFailDirectory = false,
    this.failureMessage,
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
      familyId: myProfile?.familyId,
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
    return family ??
        FamilyData(
          id: id,
          tenantId: 'ten-default',
          familyName: 'Default Family',
          members: directory,
        );
  }
}

void main() {
  late FakeMemberApiClient fakeClient;
  late MockAuthProvider mockAuthProvider;
  late InMemorySecureTokenStorage inMemoryStorage;
  late AuthSessionManager authSessionManager;

  setUp(() async {
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

    mockAuthProvider = MockAuthProvider();
    inMemoryStorage = InMemorySecureTokenStorage(
      AuthSession(
        accessToken: 'access_1',
        userId: 'mem-1',
        tenantId: 'ten-1',
        roles: const ['Member'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    authSessionManager = AuthSessionManager(
      provider: mockAuthProvider,
      storage: inMemoryStorage,
    );
    await authSessionManager.initialize();
  });

  tearDown(() {
    authSessionManager.dispose();
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
      authService: authSessionManager,
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
      authService: authSessionManager,
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
      authService: authSessionManager,
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

  testWidgets('sign out button triggers authService signOut', (tester) async {
    await tester.pumpWidget(createSubject(
      client: fakeClient,
      authService: authSessionManager,
    ));
    await tester.pumpAndSettle();

    // Scroll to Sign Out button in SingleChildScrollView
    final signOutButton = find.text('Sign Out');
    await tester.ensureVisible(signOutButton);
    await tester.tap(signOutButton);
    await tester.pumpAndSettle();

    expect(mockAuthProvider.revokeCount, 1);
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
}
