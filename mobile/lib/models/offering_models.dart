/// Types of offering funds supported by the church platform.
enum OfferingFundType {
  tithe,
  generalOffering,
  missions,
  buildingFund,
  special,
}

extension OfferingFundTypeX on OfferingFundType {
  String get displayName {
    switch (this) {
      case OfferingFundType.tithe:
        return 'Tithe';
      case OfferingFundType.generalOffering:
        return 'General Offering';
      case OfferingFundType.missions:
        return 'Missions & Outreach';
      case OfferingFundType.buildingFund:
        return 'Building & Maintenance';
      case OfferingFundType.special:
        return 'Special Thanksgiving';
    }
  }

  static OfferingFundType fromJson(dynamic value) {
    if (value is int) {
      switch (value) {
        case 0:
          return OfferingFundType.tithe;
        case 1:
          return OfferingFundType.generalOffering;
        case 2:
          return OfferingFundType.missions;
        case 3:
          return OfferingFundType.buildingFund;
        case 4:
          return OfferingFundType.special;
        default:
          return OfferingFundType.generalOffering;
      }
    }

    if (value is String) {
      final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (normalized.contains('tithe')) return OfferingFundType.tithe;
      if (normalized.contains('mission')) return OfferingFundType.missions;
      if (normalized.contains('building')) return OfferingFundType.buildingFund;
      if (normalized.contains('special') || normalized.contains('thanksgiving')) {
        return OfferingFundType.special;
      }
      return OfferingFundType.generalOffering;
    }

    return OfferingFundType.generalOffering;
  }

  dynamic toJson() {
    switch (this) {
      case OfferingFundType.tithe:
        return 0;
      case OfferingFundType.generalOffering:
        return 1;
      case OfferingFundType.missions:
        return 2;
      case OfferingFundType.buildingFund:
        return 3;
      case OfferingFundType.special:
        return 4;
    }
  }
}

/// Verification / processing status of a contribution.
enum ContributionStatus {
  pending,
  submitted,
  verified,
  rejected,
}

extension ContributionStatusX on ContributionStatus {
  String get displayName {
    switch (this) {
      case ContributionStatus.pending:
        return 'Pending';
      case ContributionStatus.submitted:
        return 'Submitted';
      case ContributionStatus.verified:
        return 'Verified';
      case ContributionStatus.rejected:
        return 'Rejected';
    }
  }

  static ContributionStatus fromJson(dynamic value) {
    if (value is int) {
      switch (value) {
        case 0:
          return ContributionStatus.pending;
        case 1:
          return ContributionStatus.submitted;
        case 2:
          return ContributionStatus.verified;
        case 3:
          return ContributionStatus.rejected;
        default:
          return ContributionStatus.pending;
      }
    }

    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'verified') return ContributionStatus.verified;
      if (normalized == 'submitted') return ContributionStatus.submitted;
      if (normalized == 'rejected') return ContributionStatus.rejected;
      return ContributionStatus.pending;
    }

    return ContributionStatus.pending;
  }

  dynamic toJson() {
    switch (this) {
      case ContributionStatus.pending:
        return 0;
      case ContributionStatus.submitted:
        return 1;
      case ContributionStatus.verified:
        return 2;
      case ContributionStatus.rejected:
        return 3;
    }
  }
}

/// Description of an available fund category.
class FundCategoryInfo {
  final OfferingFundType fundType;
  final String name;
  final String description;

  const FundCategoryInfo({
    required this.fundType,
    required this.name,
    required this.description,
  });

  factory FundCategoryInfo.fromJson(Map<String, dynamic> json) {
    return FundCategoryInfo(
      fundType: OfferingFundTypeX.fromJson(json['fundType']),
      name: json['name'] as String? ?? 'General Fund',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'fundType': fundType.toJson(),
        'name': name,
        'description': description,
      };
}

/// Church giving configuration including UPI details and active funds.
class ChurchGivingConfig {
  final String upiId;
  final String payeeName;
  final String currency;
  final List<FundCategoryInfo> availableFunds;

  const ChurchGivingConfig({
    required this.upiId,
    required this.payeeName,
    required this.currency,
    required this.availableFunds,
  });

  factory ChurchGivingConfig.fromJson(Map<String, dynamic> json) {
    final fundsList = (json['availableFunds'] as List<dynamic>?)
            ?.map((f) => FundCategoryInfo.fromJson(f as Map<String, dynamic>))
            .toList() ??
        const [];

    return ChurchGivingConfig(
      upiId: json['upiId'] as String? ?? 'churchgiving@upi',
      payeeName: json['payeeName'] as String? ?? 'Church Digital Platform',
      currency: json['currency'] as String? ?? 'INR',
      availableFunds: fundsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'upiId': upiId,
        'payeeName': payeeName,
        'currency': currency,
        'availableFunds': availableFunds.map((f) => f.toJson()).toList(),
      };
}

/// Contribution record model.
class Contribution {
  final String id;
  final String memberId;
  final String memberName;
  final OfferingFundType fundType;
  final String fundName;
  final double amount;
  final String currency;
  final String? transactionReference;
  final String upiPayeeId;
  final String upiIntentUri;
  final String? paymentNote;
  final ContributionStatus status;
  final String receiptNumber;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final String? verificationNote;

  const Contribution({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.fundType,
    required this.fundName,
    required this.amount,
    required this.currency,
    this.transactionReference,
    required this.upiPayeeId,
    required this.upiIntentUri,
    this.paymentNote,
    required this.status,
    required this.receiptNumber,
    this.verifiedBy,
    this.verifiedAt,
    required this.createdAt,
    this.verificationNote,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final double amount = (rawAmount is num) ? rawAmount.toDouble() : 0.0;

    return Contribution(
      id: json['id'] as String? ?? '',
      memberId: json['memberId'] as String? ?? '',
      memberName: json['memberName'] as String? ?? 'Church Member',
      fundType: OfferingFundTypeX.fromJson(json['fundType']),
      fundName: json['fundName'] as String? ?? 'General Offering',
      amount: amount,
      currency: json['currency'] as String? ?? 'INR',
      transactionReference: json['transactionReference'] as String?,
      upiPayeeId: json['upiPayeeId'] as String? ?? '',
      upiIntentUri: json['upiIntentUri'] as String? ?? '',
      paymentNote: json['paymentNote'] as String?,
      status: ContributionStatusX.fromJson(json['status']),
      receiptNumber: json['receiptNumber'] as String? ?? '',
      verifiedBy: json['verifiedBy'] as String?,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      verificationNote: json['verificationNote'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'memberName': memberName,
        'fundType': fundType.toJson(),
        'fundName': fundName,
        'amount': amount,
        'currency': currency,
        'transactionReference': transactionReference,
        'upiPayeeId': upiPayeeId,
        'upiIntentUri': upiIntentUri,
        'paymentNote': paymentNote,
        'status': status.toJson(),
        'receiptNumber': receiptNumber,
        'verifiedBy': verifiedBy,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        if (verificationNote != null) 'verificationNote': verificationNote,
      };
}

/// Input model for recording a contribution.
class RecordContributionInput {
  final OfferingFundType fundType;
  final double amount;
  final String currency;
  final String? paymentNote;
  final String? transactionReference;

  const RecordContributionInput({
    required this.fundType,
    required this.amount,
    this.currency = 'INR',
    this.paymentNote,
    this.transactionReference,
  });

  Map<String, dynamic> toJson() => {
        'fundType': fundType.toJson(),
        'amount': amount,
        'currency': currency,
        if (paymentNote != null && paymentNote!.trim().isNotEmpty)
          'paymentNote': paymentNote!.trim(),
        if (transactionReference != null && transactionReference!.trim().isNotEmpty)
          'transactionReference': transactionReference!.trim(),
      };
}

/// Privileged summary aggregation of church giving.
class LedgerSummary {
  final double totalAmount;
  final int totalCount;
  final double verifiedAmount;
  final double pendingAmount;
  final Map<String, double> byFundType;
  final DateTime generatedAt;

  const LedgerSummary({
    required this.totalAmount,
    required this.totalCount,
    required this.verifiedAmount,
    required this.pendingAmount,
    required this.byFundType,
    required this.generatedAt,
  });

  factory LedgerSummary.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['totalAmount'];
    final rawVerified = json['verifiedAmount'];
    final rawPending = json['pendingAmount'];

    final Map<String, double> fundMap = {};
    if (json['byFundType'] is Map<String, dynamic>) {
      (json['byFundType'] as Map<String, dynamic>).forEach((k, v) {
        if (v is num) fundMap[k] = v.toDouble();
      });
    }

    return LedgerSummary(
      totalAmount: (rawTotal is num) ? rawTotal.toDouble() : 0.0,
      totalCount: json['totalCount'] as int? ?? 0,
      verifiedAmount: (rawVerified is num) ? rawVerified.toDouble() : 0.0,
      pendingAmount: (rawPending is num) ? rawPending.toDouble() : 0.0,
      byFundType: fundMap,
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalAmount': totalAmount,
        'totalCount': totalCount,
        'verifiedAmount': verifiedAmount,
        'pendingAmount': pendingAmount,
        'byFundType': byFundType,
        'generatedAt': generatedAt.toIso8601String(),
      };
}
