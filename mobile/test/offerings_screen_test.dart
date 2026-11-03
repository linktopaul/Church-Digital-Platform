import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/offering_models.dart';
import 'package:church_digital_platform_mobile/screens/offerings_screen.dart';
import 'package:church_digital_platform_mobile/services/offering_api_client.dart';

class FakeOfferingApiClient implements OfferingApiClient {
  final ChurchGivingConfig config;
  final List<Contribution> myContributions;
  final List<Contribution> ledgerContributions;
  final LedgerSummary ledgerSummary;
  RecordContributionInput? lastRecordedInput;
  bool verifyCalled = false;

  FakeOfferingApiClient({
    ChurchGivingConfig? config,
    List<Contribution>? myContributions,
    List<Contribution>? ledgerContributions,
    LedgerSummary? ledgerSummary,
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
  Future<List<Contribution>> getMyContributions() async => myContributions;

  @override
  Future<List<Contribution>> getLedger({OfferingFundType? fundType, ContributionStatus? status}) async {
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
  Future<LedgerSummary> getLedgerSummary() async => ledgerSummary;
}

void main() {
  Widget buildTestWidget({
    required OfferingApiClient apiClient,
    bool isPastor = false,
    Future<bool> Function(String)? onLaunchUrl,
  }) {
    return MaterialApp(
      home: OfferingsScreen(
        apiClient: apiClient,
        isPastor: isPastor,
        onLaunchUrl: onLaunchUrl,
      ),
    );
  }

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

  testWidgets('My Giving tab displays user receipts', (tester) async {
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

    // Switch to Ledger tab
    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('Total Given'), findsOneWidget);
  });
}
