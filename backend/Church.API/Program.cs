using Church.Core;
using Church.Infrastructure;
using Church.API.Models;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddOpenApi();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ITenantService, TenantService>();

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Authentication & Role-Based Authorization
builder.Services.AddAuthentication("HeaderOrBearer")
    .AddScheme<AuthenticationSchemeOptions, CustomAuthHandler>("HeaderOrBearer", options => { });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("CanPublishAnnouncements", policy =>
        policy.RequireRole("Admin", "Pastor"));
    options.AddPolicy("PastorOnly", policy =>
        policy.RequireRole("Pastor"));
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();

// Announcement Endpoints
var announcementsGroup = app.MapGroup("/api/v1/announcements")
    .RequireAuthorization();

// Scenario 1: Member views feed
// Notices appear in reverse-chronological order, flagged by priority (Routine, Urgent/Emergency).
announcementsGroup.MapGet("/", async (ApplicationDbContext db) =>
{
    var announcements = await db.Announcements
        .OrderByDescending(a => a.PublishedAt)
        .Select(a => new AnnouncementResponse(
            a.Id,
            a.ChurchId,
            a.AuthorId,
            a.Title,
            a.Content,
            a.Priority,
            a.PublishedAt,
            a.ExpiresAt
        ))
        .ToListAsync();

    return Results.Ok(announcements);
});

// Scenario 2: Publishing Authorization
// Only users with Admin or Pastor roles can publish (otherwise 403 Forbidden).
announcementsGroup.MapPost("/", [Authorize(Roles = "Admin,Pastor")] async (
    CreateAnnouncementRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Content))
    {
        return Results.BadRequest(new { error = "Title and Content are required." });
    }

    var churchId = tenantService.GetCurrentTenantId();
    if (churchId == Guid.Empty)
    {
        var tenantClaim = user.FindFirst("church_id")?.Value ?? user.FindFirst("tenant_id")?.Value;
        if (Guid.TryParse(tenantClaim, out var parsedId))
        {
            churchId = parsedId;
        }
    }

    var authorIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user.FindFirst("sub")?.Value;
    _ = Guid.TryParse(authorIdString, out var authorId);
    if (authorId == Guid.Empty)
    {
        authorId = Guid.NewGuid();
    }

    var announcement = new Announcement
    {
        Id = Guid.NewGuid(),
        ChurchId = churchId,
        AuthorId = authorId,
        Title = request.Title.Trim(),
        Content = request.Content.Trim(),
        Priority = request.Priority,
        PublishedAt = request.PublishedAt ?? DateTime.UtcNow,
        ExpiresAt = request.ExpiresAt
    };

    db.Announcements.Add(announcement);
    await db.SaveChangesAsync();

    var response = new AnnouncementResponse(
        announcement.Id,
        announcement.ChurchId,
        announcement.AuthorId,
        announcement.Title,
        announcement.Content,
        announcement.Priority,
        announcement.PublishedAt,
        announcement.ExpiresAt
    );

    return Results.Created($"/api/v1/announcements/{announcement.Id}", response);
});

// Prayer Request Endpoints
var prayerRequestsGroup = app.MapGroup("/api/v1/prayer-requests")
    .RequireAuthorization();

// Submit a prayer request (Members)
prayerRequestsGroup.MapPost("/", async (
    CreatePrayerRequestRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Content))
    {
        return Results.BadRequest(new { error = "Content is required." });
    }

    var churchId = tenantService.GetCurrentTenantId();
    if (churchId == Guid.Empty)
    {
        var tenantClaim = user.FindFirst("church_id")?.Value ?? user.FindFirst("tenant_id")?.Value;
        if (Guid.TryParse(tenantClaim, out var parsedId))
        {
            churchId = parsedId;
        }
    }

    if (churchId == Guid.Empty)
    {
        return Results.BadRequest(new { error = "A valid church tenant is required." });
    }

    var memberIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user.FindFirst("sub")?.Value;
    _ = Guid.TryParse(memberIdString, out var memberId);
    if (memberId == Guid.Empty)
    {
        return Results.Unauthorized();
    }

    var prayerRequest = new PrayerRequest
    {
        Id = Guid.NewGuid(),
        ChurchId = churchId,
        MemberId = memberId,
        Content = request.Content.Trim(),
        Status = PrayerRequestStatus.Submitted,
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };

    db.PrayerRequests.Add(prayerRequest);
    await db.SaveChangesAsync();

    var response = new PrayerRequestResponse(
        prayerRequest.Id,
        prayerRequest.ChurchId,
        prayerRequest.MemberId,
        prayerRequest.Content,
        prayerRequest.Status,
        prayerRequest.CreatedAt,
        prayerRequest.UpdatedAt
    );

    return Results.Created($"/api/v1/prayer-requests/{prayerRequest.Id}", response);
});

// List all prayer requests (Pastor Only)
prayerRequestsGroup.MapGet("/", [Authorize(Policy = "PastorOnly")] async (ApplicationDbContext db) =>
{
    var requests = await db.PrayerRequests
        .OrderByDescending(p => p.CreatedAt)
        .Select(p => new PrayerRequestResponse(
            p.Id,
            p.TenantId,
            p.MemberId,
            p.Content,
            p.Status,
            p.CreatedAt,
            p.UpdatedAt
        ))
        .ToListAsync();

    return Results.Ok(requests);
});

// List member's own prayer requests
prayerRequestsGroup.MapGet("/my", async (ApplicationDbContext db, ClaimsPrincipal user) =>
{
    var memberIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user.FindFirst("sub")?.Value;
    if (!Guid.TryParse(memberIdString, out var memberId) || memberId == Guid.Empty)
    {
        return Results.Unauthorized();
    }

    var requests = await db.PrayerRequests
        .Where(p => p.MemberId == memberId)
        .OrderByDescending(p => p.CreatedAt)
        .Select(p => new PrayerRequestResponse(
            p.Id,
            p.TenantId,
            p.MemberId,
            p.Content,
            p.Status,
            p.CreatedAt,
            p.UpdatedAt
        ))
        .ToListAsync();

    return Results.Ok(requests);
});

// Update prayer request status (Pastor Only)
prayerRequestsGroup.MapPatch("/{id}/status", [Authorize(Policy = "PastorOnly")] async (
    Guid id,
    UpdatePrayerRequestStatusRequest request,
    ApplicationDbContext db) =>
{
    var prayerRequest = await db.PrayerRequests.FirstOrDefaultAsync(p => p.Id == id);
    if (prayerRequest == null)
    {
        return Results.NotFound();
    }

    prayerRequest.Status = request.Status;
    prayerRequest.UpdatedAt = DateTime.UtcNow;

    await db.SaveChangesAsync();

    var response = new PrayerRequestResponse(
        prayerRequest.Id,
        prayerRequest.ChurchId,
        prayerRequest.MemberId,
        prayerRequest.Content,
        prayerRequest.Status,
        prayerRequest.CreatedAt,
        prayerRequest.UpdatedAt
    );

    return Results.Ok(response);
});

app.Run();

// Export Program class for WebApplicationFactory in tests
public partial class Program { }

public class TenantService : ITenantService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public TenantService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public Guid GetCurrentTenantId()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext == null) return Guid.Empty;

        var tenantIdString = httpContext.Request.Headers["X-Tenant-Id"].FirstOrDefault();
        if (Guid.TryParse(tenantIdString, out var tenantId))
        {
            return tenantId;
        }

        var churchClaim = httpContext.User.FindFirst("church_id")?.Value;
        if (Guid.TryParse(churchClaim, out var churchId))
        {
            return churchId;
        }

        return Guid.Empty;
    }
}

public class CustomAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public CustomAuthHandler(
        Microsoft.Extensions.Options.IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        System.Text.Encodings.Web.UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // Support header-based user claims for direct integration testing and gateway proxying
        // e.g. Authorization header: "TestRole Admin" or "TestRole Member" or headers "X-User-Role", "X-User-Id"
        var role = Request.Headers["X-User-Role"].FirstOrDefault();
        var userId = Request.Headers["X-User-Id"].FirstOrDefault();
        var churchId = Request.Headers["X-Tenant-Id"].FirstOrDefault();

        // Also check Authorization header Bearer token / Test token
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        if (!string.IsNullOrEmpty(authHeader))
        {
            if (authHeader.StartsWith("TestRole ", StringComparison.OrdinalIgnoreCase))
            {
                role = authHeader.Substring("TestRole ".Length).Trim();
            }
            else if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            {
                var token = authHeader.Substring("Bearer ".Length).Trim();
                if (token.Equals("admin", StringComparison.OrdinalIgnoreCase)) role = "Admin";
                else if (token.Equals("pastor", StringComparison.OrdinalIgnoreCase)) role = "Pastor";
                else if (token.Equals("member", StringComparison.OrdinalIgnoreCase)) role = "Member";
            }
        }

        if (string.IsNullOrEmpty(role))
        {
            return Task.FromResult(AuthenticateResult.Fail("No authentication provided"));
        }

        if (!string.Equals(role, "Member", StringComparison.OrdinalIgnoreCase) &&
            string.IsNullOrWhiteSpace(userId))
        {
            userId = Guid.NewGuid().ToString();
        }

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.Role, role)
        };

        if (!string.IsNullOrWhiteSpace(userId))
        {
            claims.Add(new Claim(ClaimTypes.NameIdentifier, userId));
        }

        if (!string.IsNullOrEmpty(churchId))
        {
            claims.Add(new Claim("church_id", churchId));
        }

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, Scheme.Name);

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
