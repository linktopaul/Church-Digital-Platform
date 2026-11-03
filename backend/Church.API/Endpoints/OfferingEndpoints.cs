using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace Church.API.Endpoints;

public static class OfferingEndpoints
{
    private static readonly List<FundCategoryInfo> DefaultFunds = new()
    {
        new(OfferingFundType.Tithe, "Tithe", "10% biblical giving to support the church ministry and gospel mission"),
        new(OfferingFundType.GeneralOffering, "General Offering", "Regular offerings for daily church operations and Sunday worship services"),
        new(OfferingFundType.Missions, "Missions & Outreach", "Local community outreach, missionary support, and compassion aid"),
        new(OfferingFundType.BuildingFund, "Building & Maintenance", "Church building expansion, renovations, and property upkeep"),
        new(OfferingFundType.Special, "Special Thanksgiving", "Designated thanksgiving contributions and special ministry projects")
    };

    public static IEndpointRouteBuilder MapOfferingEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/offerings")
            .RequireAuthorization();

        // 1. Get Giving Config (UPI ID, payee info, available fund types)
        group.MapGet("/config", async (
            ClaimsPrincipal user,
            ITenantService tenantService,
            ApplicationDbContext db,
            Microsoft.Extensions.Configuration.IConfiguration config) =>
        {
            var churchId = ResolveTenantId(tenantService, user);
            Tenant? tenant = null;
            if (churchId != Guid.Empty)
            {
                tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == churchId);
            }

            var tenantKey = tenant?.Slug ?? churchId.ToString();
            var upiId = config[$"Giving:{tenantKey}:UpiId"]
                ?? config[$"Giving:{churchId}:UpiId"]
                ?? config["Giving:DefaultUpiId"]
                ?? "churchgiving@upi";
            var payeeName = tenant?.Name ?? config[$"Giving:{tenantKey}:PayeeName"] ?? "Church Digital Platform";
            var currency = "INR";

            return Results.Ok(new ChurchGivingConfigResponse(
                UpiId: upiId,
                PayeeName: payeeName,
                Currency: currency,
                AvailableFunds: DefaultFunds
            ));
        });

        // 2. Record Contribution Intent / Payment
        group.MapPost("/contributions", async (
            RecordContributionRequest request,
            ApplicationDbContext db,
            ITenantService tenantService,
            ClaimsPrincipal user,
            Microsoft.Extensions.Configuration.IConfiguration config) =>
        {
            if (request.Amount <= 0)
            {
                return Results.BadRequest(new { error = "Contribution amount must be greater than zero." });
            }

            var churchId = ResolveTenantId(tenantService, user);
            if (churchId == Guid.Empty)
            {
                return Results.BadRequest(new { error = "Tenant context is required." });
            }

            var tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == churchId);
            var tenantKey = tenant?.Slug ?? churchId.ToString();
            var upiPayeeId = config[$"Giving:{tenantKey}:UpiId"]
                ?? config[$"Giving:{churchId}:UpiId"]
                ?? config["Giving:DefaultUpiId"]
                ?? "churchgiving@upi";
            var payeeName = tenant?.Name ?? config[$"Giving:{tenantKey}:PayeeName"] ?? "Church Digital Platform";

            var (memberId, memberName) = await ResolveMemberIdentityAsync(db, user);
            var supportedCurrency = "INR";
            var requestedCurrency = string.IsNullOrWhiteSpace(request.Currency) ? supportedCurrency : request.Currency.Trim().ToUpperInvariant();
            if (!string.Equals(requestedCurrency, supportedCurrency, StringComparison.OrdinalIgnoreCase))
            {
                return Results.BadRequest(new { error = $"Currency '{request.Currency}' is not supported. Supported currency is '{supportedCurrency}'." });
            }
            var currency = supportedCurrency;

            string receiptNumber;
            do
            {
                receiptNumber = $"REC-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";
            } while (await db.Contributions.IgnoreQueryFilters().AnyAsync(c => c.ReceiptNumber == receiptNumber));

            var initialStatus = string.IsNullOrWhiteSpace(request.TransactionReference)
                ? ContributionStatus.Pending
                : ContributionStatus.Submitted;

            var contribution = new Contribution
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                MemberId = memberId,
                MemberName = memberName,
                FundType = request.FundType,
                Amount = Math.Round(request.Amount, 2),
                Currency = currency,
                TransactionReference = request.TransactionReference?.Trim(),
                UpiPayeeId = upiPayeeId,
                PaymentNote = request.PaymentNote?.Trim(),
                Status = initialStatus,
                ReceiptNumber = receiptNumber,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            db.Contributions.Add(contribution);
            await db.SaveChangesAsync();

            var response = MapToResponse(contribution, payeeName);
            return Results.Created($"/api/v1/offerings/contributions/{contribution.Id}", response);
        });

        // 3. Member Views Their Own Contribution History
        group.MapGet("/my-contributions", async (
            ApplicationDbContext db,
            ITenantService tenantService,
            ClaimsPrincipal user) =>
        {
            var (memberId, _) = await ResolveMemberIdentityAsync(db, user);

            var contributions = await db.Contributions
                .AsNoTracking()
                .Where(c => c.MemberId == memberId)
                .OrderByDescending(c => c.CreatedAt)
                .ToListAsync();

            var results = contributions.Select(c => MapToResponse(c, "Church Digital Platform")).ToList();
            return Results.Ok(results);
        });

        // 4. Church-Wide Ledger (Privileged: Pastor or Admin only)
        group.MapGet("/ledger", async (
            ApplicationDbContext db,
            ClaimsPrincipal user,
            OfferingFundType? fundType = null,
            ContributionStatus? status = null) =>
        {
            if (!IsPrivileged(user))
            {
                return Results.Forbid();
            }

            var query = db.Contributions.AsNoTracking();

            if (fundType.HasValue)
            {
                query = query.Where(c => c.FundType == fundType.Value);
            }

            if (status.HasValue)
            {
                query = query.Where(c => c.Status == status.Value);
            }

            var contributions = await query
                .OrderByDescending(c => c.CreatedAt)
                .ToListAsync();

            var results = contributions.Select(c => MapToResponse(c, "Church Digital Platform")).ToList();
            return Results.Ok(results);
        });

        // 5. Verify Contribution (Privileged: Pastor or Admin only)
        group.MapPost("/{id:guid}/verify", async (
            Guid id,
            VerifyContributionRequest? request,
            ApplicationDbContext db,
            ClaimsPrincipal user) =>
        {
            if (!IsPrivileged(user))
            {
                return Results.Forbid();
            }

            var contribution = await db.Contributions.FirstOrDefaultAsync(c => c.Id == id);
            if (contribution == null)
            {
                return Results.NotFound(new { error = "Contribution record not found." });
            }

            var verifierName = user.FindFirstValue(ClaimTypes.Name)
                ?? user.FindFirstValue("name")
                ?? (user.IsInRole("Pastor") ? "Pastor" : "Admin");

            contribution.Status = ContributionStatus.Verified;
            contribution.VerifiedBy = verifierName;
            contribution.VerifiedAt = DateTime.UtcNow;
            if (!string.IsNullOrWhiteSpace(request?.TransactionReference))
            {
                contribution.TransactionReference = request.TransactionReference.Trim();
            }
            if (!string.IsNullOrWhiteSpace(request?.VerificationNote))
            {
                contribution.PaymentNote = string.IsNullOrWhiteSpace(contribution.PaymentNote)
                    ? $"[Verified]: {request.VerificationNote.Trim()}"
                    : $"{contribution.PaymentNote} | [Verified]: {request.VerificationNote.Trim()}";
            }
            contribution.UpdatedAt = DateTime.UtcNow;

            await db.SaveChangesAsync();

            return Results.Ok(MapToResponse(contribution, "Church Digital Platform"));
        });

        // 6. Ledger Summary / Fund Totals (Privileged: Pastor or Admin only)
        group.MapGet("/ledger/summary", async (
            ApplicationDbContext db,
            ClaimsPrincipal user) =>
        {
            if (!IsPrivileged(user))
            {
                return Results.Forbid();
            }

            var contributions = await db.Contributions.AsNoTracking().ToListAsync();

            var totalAmount = contributions.Sum(c => c.Amount);
            var totalCount = contributions.Count;
            var verifiedAmount = contributions
                .Where(c => c.Status == ContributionStatus.Verified)
                .Sum(c => c.Amount);
            var pendingAmount = contributions
                .Where(c => c.Status == ContributionStatus.Pending || c.Status == ContributionStatus.Submitted)
                .Sum(c => c.Amount);

            var byFundType = contributions
                .GroupBy(c => c.FundType)
                .ToDictionary(
                    g => g.Key.ToString(),
                    g => g.Sum(c => c.Amount)
                );

            // Ensure all enum fund types are represented in dictionary
            foreach (var fund in Enum.GetValues<OfferingFundType>())
            {
                if (!byFundType.ContainsKey(fund.ToString()))
                {
                    byFundType[fund.ToString()] = 0m;
                }
            }

            return Results.Ok(new LedgerSummaryResponse(
                TotalAmount: totalAmount,
                TotalCount: totalCount,
                VerifiedAmount: verifiedAmount,
                PendingAmount: pendingAmount,
                ByFundType: byFundType,
                GeneratedAt: DateTime.UtcNow
            ));
        });

        return app;
    }

    private static bool IsPrivileged(ClaimsPrincipal user) =>
        user.IsInRole("Pastor") || user.IsInRole("Admin");

    private static Guid ResolveTenantId(ITenantService tenantService, ClaimsPrincipal user)
    {
        var tenantId = tenantService.GetCurrentTenantId();
        if (tenantId != Guid.Empty) return tenantId;

        var claim = user.FindFirst("church_id")?.Value ?? user.FindFirst("tenant_id")?.Value;
        return Guid.TryParse(claim, out var parsed) ? parsed : Guid.Empty;
    }

    private static async Task<(Guid MemberId, string MemberName)> ResolveMemberIdentityAsync(
        ApplicationDbContext db,
        ClaimsPrincipal user)
    {
        var sub = user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub");
        if (Guid.TryParse(sub, out var memberGuid))
        {
            var member = await db.Members.AsNoTracking().FirstOrDefaultAsync(m => m.Id == memberGuid);
            if (member != null)
            {
                var fullName = $"{member.FirstName} {member.LastName}".Trim();
                return (memberGuid, string.IsNullOrWhiteSpace(fullName) ? "Church Member" : fullName);
            }
            return (memberGuid, user.Identity?.Name ?? "Church Member");
        }

        var newGuid = Guid.NewGuid();
        return (newGuid, user.Identity?.Name ?? "Church Member");
    }

    private static ContributionResponse MapToResponse(Contribution c, string payeeName)
    {
        var fundName = c.FundType switch
        {
            OfferingFundType.Tithe => "Tithe",
            OfferingFundType.GeneralOffering => "General Offering",
            OfferingFundType.Missions => "Missions & Outreach",
            OfferingFundType.BuildingFund => "Building & Maintenance",
            OfferingFundType.Special => "Special Thanksgiving",
            _ => c.FundType.ToString()
        };

        var note = string.IsNullOrWhiteSpace(c.PaymentNote) ? c.ReceiptNumber : $"{c.ReceiptNumber} {c.PaymentNote}";
        var upiIntentUri = $"upi://pay?pa={Uri.EscapeDataString(c.UpiPayeeId)}&pn={Uri.EscapeDataString(payeeName)}&am={c.Amount:F2}&cu={c.Currency}&tn={Uri.EscapeDataString(note)}&tr={Uri.EscapeDataString(c.ReceiptNumber)}";

        return new ContributionResponse(
            Id: c.Id,
            MemberId: c.MemberId,
            MemberName: c.MemberName,
            FundType: c.FundType,
            FundName: fundName,
            Amount: c.Amount,
            Currency: c.Currency,
            TransactionReference: c.TransactionReference,
            UpiPayeeId: c.UpiPayeeId,
            UpiIntentUri: upiIntentUri,
            PaymentNote: c.PaymentNote,
            Status: c.Status,
            ReceiptNumber: c.ReceiptNumber,
            VerifiedBy: c.VerifiedBy,
            VerifiedAt: c.VerifiedAt,
            CreatedAt: c.CreatedAt
        );
    }
}
