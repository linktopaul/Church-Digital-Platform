import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/offering_models.dart';

void main() {
  group('OfferingFundType', () {
    test('displayName returns expected labels', () {
      expect(OfferingFundType.tithe.displayName, equals('Tithe'));
      expect(OfferingFundType.generalOffering.displayName, equals('General Offering'));
      expect(OfferingFundType.missions.displayName, equals('Missions & Outreach'));
      expect(OfferingFundType.buildingFund.displayName, equals('Building & Maintenance'));
      expect(OfferingFundType.special.displayName, equals('Special Thanksgiving'));
    });

    test('fromJson parses integers and strings correctly', () {
      expect(OfferingFundTypeX.fromJson(0), equals(OfferingFundType.tithe));
      expect(OfferingFundTypeX.fromJson(1), equals(OfferingFundType.generalOffering));
      expect(OfferingFundTypeX.fromJson(2), equals(OfferingFundType.missions));
      expect(OfferingFundTypeX.fromJson(3), equals(OfferingFundType.buildingFund));
      expect(OfferingFundTypeX.fromJson(4), equals(OfferingFundType.special));

      expect(OfferingFundTypeX.fromJson('Tithe'), equals(OfferingFundType.tithe));
      expect(OfferingFundTypeX.fromJson('Missions'), equals(OfferingFundType.missions));
      expect(OfferingFundTypeX.fromJson('BuildingFund'), equals(OfferingFundType.buildingFund));
      expect(OfferingFundTypeX.fromJson('Special'), equals(OfferingFundType.special));
      expect(OfferingFundTypeX.fromJson('unknown'), equals(OfferingFundType.generalOffering));
    });

    test('toJson produces integer codes', () {
      expect(OfferingFundType.tithe.toJson(), equals(0));
      expect(OfferingFundType.generalOffering.toJson(), equals(1));
      expect(OfferingFundType.missions.toJson(), equals(2));
      expect(OfferingFundType.buildingFund.toJson(), equals(3));
      expect(OfferingFundType.special.toJson(), equals(4));
    });
  });

  group('ContributionStatus', () {
    test('displayName returns expected labels', () {
      expect(ContributionStatus.pending.displayName, equals('Pending'));
      expect(ContributionStatus.submitted.displayName, equals('Submitted'));
      expect(ContributionStatus.verified.displayName, equals('Verified'));
      expect(ContributionStatus.rejected.displayName, equals('Rejected'));
    });

    test('fromJson parses integers and strings correctly', () {
      expect(ContributionStatusX.fromJson(0), equals(ContributionStatus.pending));
      expect(ContributionStatusX.fromJson(1), equals(ContributionStatus.submitted));
      expect(ContributionStatusX.fromJson(2), equals(ContributionStatus.verified));
      expect(ContributionStatusX.fromJson(3), equals(ContributionStatus.rejected));

      expect(ContributionStatusX.fromJson('Verified'), equals(ContributionStatus.verified));
      expect(ContributionStatusX.fromJson('Submitted'), equals(ContributionStatus.submitted));
      expect(ContributionStatusX.fromJson('Pending'), equals(ContributionStatus.pending));
    });

    test('toJson produces integer codes', () {
      expect(ContributionStatus.pending.toJson(), equals(0));
      expect(ContributionStatus.submitted.toJson(), equals(1));
      expect(ContributionStatus.verified.toJson(), equals(2));
      expect(ContributionStatus.rejected.toJson(), equals(3));
    });
  });

  group('ChurchGivingConfig', () {
    test('fromJson and toJson roundtrip', () {
      final json = {
        'upiId': 'gracechurch@upi',
        'payeeName': 'Grace Community Church',
        'currency': 'INR',
        'availableFunds': [
          {
            'fundType': 0,
            'name': 'Tithe',
            'description': 'Biblical 10% tithe',
          },
          {
            'fundType': 2,
            'name': 'Missions',
            'description': 'Outreach fund',
          }
        ]
      };

      final config = ChurchGivingConfig.fromJson(json);
      expect(config.upiId, equals('gracechurch@upi'));
      expect(config.payeeName, equals('Grace Community Church'));
      expect(config.currency, equals('INR'));
      expect(config.availableFunds.length, equals(2));
      expect(config.availableFunds.first.fundType, equals(OfferingFundType.tithe));
      expect(config.availableFunds.last.fundType, equals(OfferingFundType.missions));

      final serialized = config.toJson();
      expect(serialized['upiId'], equals('gracechurch@upi'));
      expect((serialized['availableFunds'] as List).length, equals(2));
    });
  });

  group('Contribution', () {
    test('fromJson correctly deserializes response payload', () {
      final now = DateTime.utc(2026, 11, 3, 10, 30);
      final json = {
        'id': 'd290f1ee-6c54-4b01-90e6-d701748f0851',
        'memberId': 'b391f2ee-7c65-4c02-91e7-e802859f1962',
        'memberName': 'Esther Queen',
        'fundType': 0,
        'fundName': 'Tithe',
        'amount': 2500.50,
        'currency': 'INR',
        'transactionReference': 'UTR123456789',
        'upiPayeeId': 'churchgiving@upi',
        'upiIntentUri': 'upi://pay?pa=churchgiving@upi&am=2500.50',
        'paymentNote': 'November offering',
        'status': 2,
        'receiptNumber': 'REC-20261103-ABC123',
        'verifiedBy': 'Pastor',
        'verifiedAt': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
      };

      final c = Contribution.fromJson(json);
      expect(c.id, equals('d290f1ee-6c54-4b01-90e6-d701748f0851'));
      expect(c.memberName, equals('Esther Queen'));
      expect(c.fundType, equals(OfferingFundType.tithe));
      expect(c.amount, equals(2500.50));
      expect(c.status, equals(ContributionStatus.verified));
      expect(c.receiptNumber, equals('REC-20261103-ABC123'));
      expect(c.verifiedBy, equals('Pastor'));
    });
  });

  group('LedgerSummary', () {
    test('fromJson deserializes totals and fund map', () {
      final json = {
        'totalAmount': 50000.0,
        'totalCount': 25,
        'verifiedAmount': 42000.0,
        'pendingAmount': 8000.0,
        'byFundType': {
          'Tithe': 30000.0,
          'GeneralOffering': 15000.0,
          'Missions': 5000.0,
        },
        'generatedAt': '2026-11-03T12:00:00Z',
      };

      final summary = LedgerSummary.fromJson(json);
      expect(summary.totalAmount, equals(50000.0));
      expect(summary.totalCount, equals(25));
      expect(summary.verifiedAmount, equals(42000.0));
      expect(summary.pendingAmount, equals(8000.0));
      expect(summary.byFundType['Tithe'], equals(30000.0));
      expect(summary.byFundType['Missions'], equals(5000.0));
    });
  });
}
