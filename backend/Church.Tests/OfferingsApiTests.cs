using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests;

public class OfferingsApiTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public OfferingsApiTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    private void SeedContribution(Guid churchId, Contribution contribution)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        contribution.TenantId = churchId;
        db.Contributions.Add(contribution);
        db.SaveChanges();
    }

    [Fact]
    public async Task GetConfig_ReturnsGivingConfigAndDefaultFunds()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var response = await client.GetAsync("/api/v1/offerings/config");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var config = await response.Content.ReadFromJsonAsync<ChurchGivingConfigResponse>();
        Assert.NotNull(config);
        Assert.Equal("churchgiving@upi", config!.UpiId);
        Assert.Equal("INR", config.Currency);
        Assert.NotEmpty(config.AvailableFunds);
        Assert.Contains(config.AvailableFunds, f => f.FundType == OfferingFundType.Tithe);
        Assert.Contains(config.AvailableFunds, f => f.FundType == OfferingFundType.GeneralOffering);
        Assert.Contains(config.AvailableFunds, f => f.FundType == OfferingFundType.Missions);
    }

    [Fact]
    public async Task RecordContribution_RegularMember_ReturnsCreatedWithReceiptAndUpiIntent()
    {
        var churchId = Guid.NewGuid();
        var memberId = Guid.NewGuid();

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");
        client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());

        var request = new RecordContributionRequest(
            FundType: OfferingFundType.Tithe,
            Amount: 1500.00m,
            Currency: "INR",
            PaymentNote: "November Tithe",
            TransactionReference: null
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var contribution = await response.Content.ReadFromJsonAsync<ContributionResponse>();
        Assert.NotNull(contribution);
        Assert.NotEqual(Guid.Empty, contribution!.Id);
        Assert.Equal(memberId, contribution.MemberId);
        Assert.Equal(1500.00m, contribution.Amount);
        Assert.Equal(OfferingFundType.Tithe, contribution.FundType);
        Assert.Equal("Tithe", contribution.FundName);
        Assert.Equal(ContributionStatus.Pending, contribution.Status);
        Assert.StartsWith("REC-", contribution.ReceiptNumber);
        Assert.StartsWith("upi://pay", contribution.UpiIntentUri);
        Assert.Contains("churchgiving%40upi", contribution.UpiIntentUri, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("1500.00", contribution.UpiIntentUri);
    }

    [Fact]
    public async Task RecordContribution_InvalidAmount_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var zeroReq = new RecordContributionRequest(
            FundType: OfferingFundType.GeneralOffering,
            Amount: 0m,
            Currency: "INR",
            PaymentNote: null,
            TransactionReference: null
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", zeroReq);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task MyContributions_MemberOnlyReceivesOwnRecords()
    {
        var churchId = Guid.NewGuid();
        var memberA = Guid.NewGuid();
        var memberB = Guid.NewGuid();

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = memberA,
            MemberName = "Member A",
            FundType = OfferingFundType.GeneralOffering,
            Amount = 250m,
            Currency = "INR",
            ReceiptNumber = "REC-MEMBER-A",
            Status = ContributionStatus.Pending,
            CreatedAt = DateTime.UtcNow
        });

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = memberB,
            MemberName = "Member B",
            FundType = OfferingFundType.Missions,
            Amount = 500m,
            Currency = "INR",
            ReceiptNumber = "REC-MEMBER-B",
            Status = ContributionStatus.Verified,
            CreatedAt = DateTime.UtcNow
        });

        var clientA = _factory.CreateClient();
        clientA.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        clientA.DefaultRequestHeaders.Add("X-User-Role", "Member");
        clientA.DefaultRequestHeaders.Add("X-User-Id", memberA.ToString());

        var response = await clientA.GetAsync("/api/v1/offerings/my-contributions");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var list = await response.Content.ReadFromJsonAsync<List<ContributionResponse>>();
        Assert.NotNull(list);
        Assert.Contains(list!, c => c.ReceiptNumber == "REC-MEMBER-A");
        Assert.DoesNotContain(list!, c => c.ReceiptNumber == "REC-MEMBER-B");
    }

    [Fact]
    public async Task Ledger_RegularMember_ReturnsForbidden()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var response = await client.GetAsync("/api/v1/offerings/ledger");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Ledger_PastorCanViewAndFilterAllContributions()
    {
        var churchId = Guid.NewGuid();
        var memberId = Guid.NewGuid();

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = memberId,
            MemberName = "John Doe",
            FundType = OfferingFundType.Tithe,
            Amount = 1000m,
            Currency = "INR",
            ReceiptNumber = "REC-TITHE-01",
            Status = ContributionStatus.Submitted,
            CreatedAt = DateTime.UtcNow
        });

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = memberId,
            MemberName = "John Doe",
            FundType = OfferingFundType.BuildingFund,
            Amount = 2000m,
            Currency = "INR",
            ReceiptNumber = "REC-BUILDING-01",
            Status = ContributionStatus.Verified,
            CreatedAt = DateTime.UtcNow
        });

        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        // 1. Fetch all
        var allResp = await pastorClient.GetAsync("/api/v1/offerings/ledger");
        Assert.Equal(HttpStatusCode.OK, allResp.StatusCode);
        var allList = await allResp.Content.ReadFromJsonAsync<List<ContributionResponse>>();
        Assert.NotNull(allList);
        Assert.Contains(allList!, c => c.ReceiptNumber == "REC-TITHE-01");
        Assert.Contains(allList!, c => c.ReceiptNumber == "REC-BUILDING-01");

        // 2. Filter by Tithe
        var filterResp = await pastorClient.GetAsync("/api/v1/offerings/ledger?fundType=Tithe");
        Assert.Equal(HttpStatusCode.OK, filterResp.StatusCode);
        var filterList = await filterResp.Content.ReadFromJsonAsync<List<ContributionResponse>>();
        Assert.NotNull(filterList);
        Assert.Contains(filterList!, c => c.ReceiptNumber == "REC-TITHE-01");
        Assert.DoesNotContain(filterList!, c => c.ReceiptNumber == "REC-BUILDING-01");
    }

    [Fact]
    public async Task VerifyContribution_Pastor_UpdatesStatusToVerified()
    {
        var churchId = Guid.NewGuid();
        var contribId = Guid.NewGuid();

        SeedContribution(churchId, new Contribution
        {
            Id = contribId,
            TenantId = churchId,
            MemberId = Guid.NewGuid(),
            MemberName = "Hannah Smith",
            FundType = OfferingFundType.Missions,
            Amount = 750m,
            Currency = "INR",
            ReceiptNumber = "REC-VERIFY-TEST",
            Status = ContributionStatus.Submitted,
            CreatedAt = DateTime.UtcNow
        });

        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var verifyReq = new VerifyContributionRequest(
            TransactionReference: "UPI-UTR-99887766",
            VerificationNote: "Confirmed on bank statement"
        );

        var verifyResp = await pastorClient.PostAsJsonAsync($"/api/v1/offerings/{contribId}/verify", verifyReq);
        Assert.Equal(HttpStatusCode.OK, verifyResp.StatusCode);

        var verified = await verifyResp.Content.ReadFromJsonAsync<ContributionResponse>();
        Assert.NotNull(verified);
        Assert.Equal(ContributionStatus.Verified, verified!.Status);
        Assert.Equal("UPI-UTR-99887766", verified.TransactionReference);
        Assert.NotNull(verified.VerifiedBy);
        Assert.NotNull(verified.VerifiedAt);
        Assert.Equal("Confirmed on bank statement", verified.VerificationNote);
    }

    [Fact]
    public async Task VerifyContribution_RegularMember_ReturnsForbidden()
    {
        var churchId = Guid.NewGuid();
        var contribId = Guid.NewGuid();

        SeedContribution(churchId, new Contribution
        {
            Id = contribId,
            TenantId = churchId,
            MemberId = Guid.NewGuid(),
            MemberName = "Hannah Smith",
            FundType = OfferingFundType.Missions,
            Amount = 750m,
            Currency = "INR",
            ReceiptNumber = "REC-VERIFY-FORBIDDEN",
            Status = ContributionStatus.Submitted,
            CreatedAt = DateTime.UtcNow
        });

        var memberClient = _factory.CreateClient();
        memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var verifyReq = new VerifyContributionRequest("UTR-123", "Attempt");
        var response = await memberClient.PostAsJsonAsync($"/api/v1/offerings/{contribId}/verify", verifyReq);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task LedgerSummary_Pastor_ReturnsAccurateTotalsAndFundAggregation()
    {
        var churchId = Guid.NewGuid();

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = Guid.NewGuid(),
            MemberName = "Alice",
            FundType = OfferingFundType.Tithe,
            Amount = 1000m,
            Currency = "INR",
            ReceiptNumber = "REC-SUM-01",
            Status = ContributionStatus.Verified,
            CreatedAt = DateTime.UtcNow
        });

        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = Guid.NewGuid(),
            MemberName = "Bob",
            FundType = OfferingFundType.Special,
            Amount = 500m,
            Currency = "INR",
            ReceiptNumber = "REC-SUM-02",
            Status = ContributionStatus.Pending,
            CreatedAt = DateTime.UtcNow
        });

        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var response = await pastorClient.GetAsync("/api/v1/offerings/ledger/summary");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var summary = await response.Content.ReadFromJsonAsync<LedgerSummaryResponse>();
        Assert.NotNull(summary);
        Assert.True(summary!.TotalAmount >= 1500m);
        Assert.True(summary.VerifiedAmount >= 1000m);
        Assert.True(summary.PendingAmount >= 500m);
        Assert.NotNull(summary.ByFundType);
        Assert.True(summary.ByFundType.ContainsKey("Tithe"));
        Assert.True(summary.ByFundType.ContainsKey("Special"));
    }

    [Fact]
    public async Task TenantIsolation_CrossTenantQuery_NeverExposesOtherTenantContributions()
    {
        var tenant1 = Guid.NewGuid();
        var tenant2 = Guid.NewGuid();

        SeedContribution(tenant1, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = tenant1,
            MemberId = Guid.NewGuid(),
            MemberName = "Tenant1 Member",
            FundType = OfferingFundType.Tithe,
            Amount = 5000m,
            Currency = "INR",
            ReceiptNumber = "REC-TENANT1-CONFIDENTIAL",
            Status = ContributionStatus.Verified,
            CreatedAt = DateTime.UtcNow
        });

        var pastorTenant2 = _factory.CreateClient();
        pastorTenant2.DefaultRequestHeaders.Add("X-Tenant-Id", tenant2.ToString());
        pastorTenant2.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var response = await pastorTenant2.GetAsync("/api/v1/offerings/ledger");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var list = await response.Content.ReadFromJsonAsync<List<ContributionResponse>>();
        Assert.NotNull(list);
        Assert.DoesNotContain(list!, c => c.ReceiptNumber == "REC-TENANT1-CONFIDENTIAL");
    }


    [Fact]
    public async Task RecordContribution_UnsupportedCurrency_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var payload = new RecordContributionRequest(
            FundType: OfferingFundType.Tithe,
            Amount: 100m,
            Currency: "USD",
            TransactionReference: null,
            PaymentNote: null
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task RecordContribution_PaymentNoteExceedsMaxLength_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var payload = new RecordContributionRequest(
            FundType: OfferingFundType.Tithe,
            Amount: 100m,
            Currency: "INR",
            TransactionReference: null,
            PaymentNote: new string('A', 501)
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task RecordContribution_TransactionReferenceExceedsMaxLength_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var payload = new RecordContributionRequest(
            FundType: OfferingFundType.Tithe,
            Amount: 100m,
            Currency: "INR",
            TransactionReference: new string('B', 101),
            PaymentNote: null
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task VerifyContribution_TransactionReferenceExceedsMaxLength_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var contributionId = Guid.NewGuid();
        SeedContribution(churchId, new Contribution
        {
            Id = contributionId,
            TenantId = churchId,
            MemberId = Guid.NewGuid(),
            MemberName = "Test Member",
            FundType = OfferingFundType.Tithe,
            Amount = 100m,
            Currency = "INR",
            ReceiptNumber = "REC-MAXLEN-TEST",
            Status = ContributionStatus.Submitted,
            CreatedAt = DateTime.UtcNow
        });

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var verifyPayload = new VerifyContributionRequest(
            TransactionReference: new string('C', 101),
            VerificationNote: "Valid note"
        );

        var response = await client.PostAsJsonAsync($"/api/v1/offerings/{contributionId}/verify", verifyPayload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task MyContributions_DoesNotExposeAuditNotes()
    {
        var churchId = Guid.NewGuid();
        var memberId = Guid.NewGuid();
        SeedContribution(churchId, new Contribution
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            MemberId = memberId,
            MemberName = "Member With Notes",
            FundType = OfferingFundType.Tithe,
            Amount = 500m,
            Currency = "INR",
            ReceiptNumber = "REC-AUDIT-TEST",
            Status = ContributionStatus.Verified,
            VerificationNote = "Confidential pastoral check",
            CreatedAt = DateTime.UtcNow
        });

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");
        client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());

        var response = await client.GetAsync("/api/v1/offerings/my-contributions");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var list = await response.Content.ReadFromJsonAsync<List<ContributionResponse>>();
        Assert.NotNull(list);
        var item = Assert.Single(list!);
        Assert.Null(item.VerificationNote);
    }

    [Fact]
    public async Task RecordContribution_SubCentAmountRoundsToZero_ReturnsBadRequest()
    {
        var churchId = Guid.NewGuid();
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var payload = new RecordContributionRequest(
            FundType: OfferingFundType.Tithe,
            Amount: 0.001m,
            Currency: "INR",
            TransactionReference: null,
            PaymentNote: null
        );

        var response = await client.PostAsJsonAsync("/api/v1/offerings/contributions", payload);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}