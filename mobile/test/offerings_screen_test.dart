import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/offering_models.dart';
import 'package:church_digital_platform_mobile/screens/offerings_screen.dart';
import 'package:church_digital_platform_mobile/services/offering_api_client.dart';

class FakeOfferingApiClient implements OfferingApiClient {
  final ChurchGivingConfig config;
  List<Contribution> myContributions;
  List<Contribution> ledgerContributions;
  final LedgerSummary ledgerSummary;
  RecordContributionInput? lastRecordedInput;
  bool verifyCalled = false;
  bool shouldFailMyGiving = false;
  bool shouldFailLedger = false;
  String? failureMessage;
  int? failureStatusCode;

  FakeOfferingApiClient({
    ChurchGivingConfig? config,
    List<Contribution>? myContributions,
    List<Contribution>? ledgerContributions,
    LedgerSummary? ledgerSummary,
    this.shouldFailMyGiving = false,
    this.shouldFailLedger = false,
    this.failureMessage,
    this.failureStatusCode,
  })  : config = config ??
            const ChurchGivingConfig(
              upiId: 'churchgiving@upi',
              payeeName: 'Grace Church',
              currency: 'INR',
              availableFunds: [
                FundCategoryInfo(
                  fundType: OfferingFundType.tithe,
                  name: 'Tithe',
                  description: '10% Biblical Tithe',
                ),
                FundCategoryInfo(
                  fundType: OfferingFundType.generalOffering,
                  name: 'General Offering',
                  description: 'Church operations',
                ),
              ],
            ),
        myContributions = myContributions ?? [],
        ledgerContributions = ledgerContributions ?? [],
        ledgerSummary = ledgerSummary ??
            LedgerSummary(
              totalAmount: 5000.0,
              totalCount: 3,
              verifiedAmount: 3000.0,
              pendingAmount: 2000.0,
              byFundType: const {'Tithe': 3000.0, 'GeneralOffering': 2000.0},
              generatedAt: DateTime.utc(2026, 11, 3),
            );

  @override
  Future<ChurchGivingConfig> getGivingConfig() async => config;

  @override
  Future<Contribution> recordContribution(RecordContributionInput input) async {
    lastRecordedInput = input;
    return Contribution(
      id: 'contrib-new-1',
      memberId: 'mem-1',
      memberName: 'Grace Hopper',
      fundType: input.fundType,
      fundName: input.fundType.displayName,
      amount: input.amount,
      currency: input.currency,
      transactionReference: input.transactionReference,
      upiPayeeId: config.upiId,
      upiIntentUri: 'upi://pay?pa=${config.upiId}&am=${input.amount.toStringAsFixed(2)}',
      paymentNote: input.paymentNote,
      status: input.transactionReference != null ? ContributionStatus.submitted : ContributionStatus.pending,
      receiptNumber: 'REC-20261103-TEST01',
      createdAt: DateTime.utc(2026, 11, 3, 10, 0),
    );
  }

  @override
  Future<List<Contribution>> getMyContributions() async {
    if (shouldFailMyGiving) {
      throw OfferingApiException(
        failureMessage ?? 'Error fetching my contributions',
        statusCode: failureStatusCode,
      );
    }
    return myContributions;
  }

  @override
  Future<List<Contribution>> getLedger({OfferingFundType? fundType, ContributionStatus? status}) async {
    if (shouldFailLedger) {
      throw OfferingApiException(
        failureMessage ?? 'Error fetching ledger',
        statusCode: failureStatusCode,
      );
    }
    if (fundType != null) {
      return ledgerContributions.where((c) => c.fundType == fundType).toList();
    }
    return ledgerContributions;
  }

  @override
  Future<Contribution> verifyContribution(String id, {String? transactionReference, String? verificationNote}) async {
    verifyCalled = true;
    final item = ledgerContributions.firstWhere((c) => c.id == id);
    return Contribution(
      id: item.id,
      memberId: item.memberId,
      memberName: item.memberName,
      fundType: item.fundType,
      fundName: item.fundName,
      amount: item.amount,
      currency: item.currency,
      transactionReference: transactionReference ?? item.transactionReference,
      upiPayeeId: item.upiPayeeId,
      upiIntentUri: item.upiIntentUri,
      paymentNote: verificationNote != null ? '[Verified]: $verificationNote' : item.paymentNote,
      status: ContributionStatus.verified,
      receiptNumber: item.receiptNumber,
      verifiedBy: 'Pastor',
      verifiedAt: DateTime.utc(2026, 11, 3, 11, 0),
      createdAt: item.createdAt,
    );
  }

  @override
  Future<LedgerSummary> getLedgerSummary() async {
    if (shouldFailLedger) {
      throw OfferingApiException(
        failureMessage ?? 'Error fetching ledger summary',
        statusCode: failureStatusCode,
      );
    }
    return ledgerSummary;
  }
}

void main() {
  Widget buildTestWidget({
    OfferingApiClient? apiClient,
    bool isPastor = false,
    bool canManageOfferings = false,
    Future<bool> Function(String)? onLaunchUrl,
  }) {
    return MaterialApp(
      home: OfferingsScreen(
        apiClient: apiClient,
        isPastor: isPastor,
        canManageOfferings: canManageOfferings,
        onLaunchUrl: onLaunchUrl,
      ),
    );
  }

  testWidgets('renders unauthenticated state when apiClient is null', (tester) async {
    await tester.pumpWidget(buildTestWidget(apiClient: null));
    await tester.pumpAndSettle();

    expect(find.text('Sign In Required'), findsOneWidget);
    expect(
      find.textContaining('Recording offerings, viewing receipts, and managing tithes require an active, authenticated member session.'),
      findsOneWidget,
    );
    expect(find.text('Give Now'), findsNothing);
  });

  testWidgets('Renders Give Now and My Giving tabs for regular members', (tester) async {
    final client = FakeOfferingApiClient();
    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: false));
    await tester.pumpAndSettle();

    expect(find.text('Digital Offerings & Giving'), findsOneWidget);
    expect(find.text('Give Now'), findsOneWidget);
    expect(find.text('My Giving'), findsOneWidget);
    expect(find.text('Ledger'), findsNothing); // Pastoral ledger hidden for members

    expect(find.text('Support the Church Ministry'), findsOneWidget);
    expect(find.text('Select Ministry Fund'), findsOneWidget);
    expect(find.text('Generate UPI Payment & Record'), findsOneWidget);
  });

  testWidgets('Validation prevents submission with empty or zero amount', (tester) async {
    final client = FakeOfferingApiClient();
    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: false));
    await tester.pumpAndSettle();

    // Tap submit without typing amount
    await tester.tap(find.text('Generate UPI Payment & Record'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter an amount.'), findsOneWidget);
    expect(client.lastRecordedInput, isNull);
  });

  testWidgets('Submitting valid contribution displays confirmation bottom sheet with receipt', (tester) async {
    final client = FakeOfferingApiClient();
    String? launchedUrl;

    await tester.pumpWidget(buildTestWidget(
      apiClient: client,
      isPastor: false,
      onLaunchUrl: (url) async {
        launchedUrl = url;
        return true;
      },
    ));
    await tester.pumpAndSettle();

    // Enter amount
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.pumpAndSettle();

    // Submit
    await tester.tap(find.text('Generate UPI Payment & Record'));
    await tester.pumpAndSettle();

    expect(find.text('Contribution Intent Recorded'), findsOneWidget);
    expect(find.text('Receipt: REC-20261103-TEST01'), findsOneWidget);
    expect(find.text('INR 1200.00'), findsOneWidget);
    expect(find.text('Open UPI App to Complete Payment'), findsOneWidget);

    // Tap launch UPI
    await tester.tap(find.text('Open UPI App to Complete Payment'));
    await tester.pumpAndSettle();

    expect(launchedUrl, isNotNull);
    expect(launchedUrl, startsWith('upi://pay'));

    // Close bottom sheet
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Contribution Intent Recorded'), findsNothing);
  });

  testWidgets('My Giving tab displays user receipts and supports pull-to-refresh', (tester) async {
    final client = FakeOfferingApiClient(
      myContributions: [
        Contribution(
          id: 'c-1',
          memberId: 'm-1',
          memberName: 'Grace Hopper',
          fundType: OfferingFundType.tithe,
          fundName: 'Tithe',
          amount: 500.0,
          currency: 'INR',
          upiPayeeId: 'church@upi',
          upiIntentUri: 'upi://pay',
          status: ContributionStatus.verified,
          receiptNumber: 'REC-TITHE-001',
          createdAt: DateTime.utc(2026, 11, 1),
        )
      ],
    );

    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: false));
    await tester.pumpAndSettle();

    // Switch to My Giving tab
    await tester.tap(find.text('My Giving'));
    await tester.pumpAndSettle();

    expect(find.text('INR 500.00 - Tithe'), findsOneWidget);
    expect(find.text('Receipt: REC-TITHE-001'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);

    // Pull to refresh
    client.myContributions = [
      ...client.myContributions,
      Contribution(
        id: 'c-2',
        memberId: 'm-1',
        memberName: 'Grace Hopper',
        fundType: OfferingFundType.generalOffering,
        fundName: 'General Offering',
        amount: 200.0,
        currency: 'INR',
        upiPayeeId: 'church@upi',
        upiIntentUri: 'upi://pay',
        status: ContributionStatus.submitted,
        receiptNumber: 'REC-GEN-002',
        createdAt: DateTime.utc(2026, 11, 2),
      ),
    ];

    await tester.drag(find.text('INR 500.00 - Tithe'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('INR 200.00 - General Offering'), findsOneWidget);
  });

  testWidgets('My Giving tab handles HTTP 401 error with retry', (tester) async {
    final client = FakeOfferingApiClient(
      shouldFailMyGiving: true,
      failureStatusCode: 401,
      failureMessage: '401 Unauthorized',
    );

    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Giving'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to Load Giving Records'), findsOneWidget);
    expect(find.text('Your session has expired. Please sign in again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    client.shouldFailMyGiving = false;
    client.myContributions = [
      Contribution(
        id: 'c-rec',
        memberId: 'm-1',
        memberName: 'Grace Hopper',
        fundType: OfferingFundType.tithe,
        fundName: 'Tithe',
        amount: 1000.0,
        currency: 'INR',
        upiPayeeId: 'church@upi',
        upiIntentUri: 'upi://pay',
        status: ContributionStatus.verified,
        receiptNumber: 'REC-1000',
        createdAt: DateTime.utc(2026, 11, 2),
      ),
    ];

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('INR 1000.00 - Tithe'), findsOneWidget);
  });

  testWidgets('Pastor mode shows Ledger tab with summary cards and verify action', (tester) async {
    final client = FakeOfferingApiClient(
      ledgerContributions: [
        Contribution(
          id: 'c-lead-1',
          memberId: 'm-2',
          memberName: 'Barnabas',
          fundType: OfferingFundType.missions,
          fundName: 'Missions & Outreach',
          amount: 2500.0,
          currency: 'INR',
          transactionReference: 'UTR998877',
          upiPayeeId: 'church@upi',
          upiIntentUri: 'upi://pay',
          status: ContributionStatus.submitted,
          receiptNumber: 'REC-MISS-99',
          createdAt: DateTime.utc(2026, 11, 2),
        ),
      ],
    );

    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: true));
    await tester.pumpAndSettle();

    expect(find.text('Ledger'), findsOneWidget);

    // Switch to Ledger tab
    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('Total Given'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Barnabas - INR 2500.00'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);

    // Tap verify button
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Verify Contribution'), findsOneWidget);
    expect(find.text('Confirm Verification'), findsOneWidget);

    await tester.tap(find.text('Confirm Verification'));
    await tester.pumpAndSettle();

    expect(client.verifyCalled, isTrue);
  });

  testWidgets('Ledger tab handles HTTP 403 error', (tester) async {
    final client = FakeOfferingApiClient(
      shouldFailLedger: true,
      failureStatusCode: 403,
      failureMessage: '403 Forbidden',
    );

    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to Load Ledger'), findsOneWidget);
    expect(find.text('Access denied: Restricted to pastoral leadership or authorized staff.'), findsOneWidget);
  });

  testWidgets('Renders without overflow on narrow 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final client = FakeOfferingApiClient();
    await tester.pumpWidget(buildTestWidget(apiClient: client, isPastor: true));
    await tester.pumpAndSettle();

    expect(find.text('Digital Offerings & Giving'), findsOneWidget);
    expect(find.text('Give Now'), findsOneWidget);
    expect(find.text('Select Ministry Fund'), findsOneWidget);
  });

  testWidgets('Admin role (canManageOfferings) shows Ledger tab for non-pastor admin', (tester) async {
    final client = FakeOfferingApiClient();
    await tester.pumpWidget(MaterialApp(
      home: OfferingsScreen(
        apiClient: client,
        isPastor: false,
        canManageOfferings: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ledger'), findsOneWidget);
    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();
    expect(find.text('Total Given'), findsOneWidget);
  });
}
