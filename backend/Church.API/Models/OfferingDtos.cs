using System;
using System.Collections.Generic;
using Church.Core;

namespace Church.API.Models;

public record FundCategoryInfo(
    OfferingFundType FundType,
    string Name,
    string Description
);

public record ChurchGivingConfigResponse(
    string UpiId,
    string PayeeName,
    string Currency,
    List<FundCategoryInfo> AvailableFunds
);

public record RecordContributionRequest(
    OfferingFundType FundType,
    decimal Amount,
    string? Currency,
    string? PaymentNote,
    string? TransactionReference
);

public record ContributionResponse(
    Guid Id,
    Guid MemberId,
    string MemberName,
    OfferingFundType FundType,
    string FundName,
    decimal Amount,
    string Currency,
    string? TransactionReference,
    string UpiPayeeId,
    string UpiIntentUri,
    string? PaymentNote,
    ContributionStatus Status,
    string ReceiptNumber,
    string? VerifiedBy,
    DateTime? VerifiedAt,
    DateTime CreatedAt
);

public record VerifyContributionRequest(
    string? TransactionReference,
    string? VerificationNote
);

public record LedgerSummaryResponse(
    decimal TotalAmount,
    int TotalCount,
    decimal VerifiedAmount,
    decimal PendingAmount,
    Dictionary<string, decimal> ByFundType,
    DateTime GeneratedAt
);
