using System;

namespace Church.Core;

public class Contribution : IMultiTenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid TenantId { get; set; }
    public Guid ChurchId
    {
        get => TenantId;
        set => TenantId = value;
    }
    public Guid MemberId { get; set; }
    public string MemberName { get; set; } = string.Empty;
    public OfferingFundType FundType { get; set; } = OfferingFundType.GeneralOffering;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "INR";
    public string? TransactionReference { get; set; } // UTR / Payment confirmation reference
    public string UpiPayeeId { get; set; } = string.Empty; // e.g. "church@upi"
    public string? PaymentNote { get; set; }
    public ContributionStatus Status { get; set; } = ContributionStatus.Pending;
    public string? VerifiedBy { get; set; }
    public DateTime? VerifiedAt { get; set; }
    public string ReceiptNumber { get; set; } = string.Empty; // e.g. "REC-202611-ABC123"
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
