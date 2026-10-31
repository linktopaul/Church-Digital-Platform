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

// Worship & Choir Playlist Engine Endpoints
var worshipGroup = app.MapGroup("/api/v1/worship")
    .RequireAuthorization();

// Helper to resolve tenant ID
static Guid ResolveTenantId(ITenantService tenantService, ClaimsPrincipal user)
{
    var churchId = tenantService.GetCurrentTenantId();
    if (churchId == Guid.Empty)
    {
        var tenantClaim = user.FindFirst("church_id")?.Value ?? user.FindFirst("tenant_id")?.Value;
        if (Guid.TryParse(tenantClaim, out var parsedId))
        {
            churchId = parsedId;
        }
    }
    return churchId;
}

static DateTime NormalizeServiceDate(DateTime serviceDate) => serviceDate.Kind switch
{
    DateTimeKind.Utc => serviceDate,
    DateTimeKind.Local => serviceDate.ToUniversalTime(),
    _ => DateTime.SpecifyKind(serviceDate, DateTimeKind.Utc)
};

// ---------------- SONGS ----------------

// Get all songs in the library
worshipGroup.MapGet("/songs", async (ApplicationDbContext db) =>
{
    var songs = await db.Songs
        .OrderBy(s => s.Title)
        .Select(s => new SongResponse(
            s.Id,
            s.TenantId,
            s.Title,
            s.Artist,
            s.DefaultKey,
            s.TempoBpm,
            s.Lyrics,
            s.Chords,
            s.CreatedAt
        ))
        .ToListAsync();

    return Results.Ok(songs);
});

// Get a specific song
worshipGroup.MapGet("/songs/{id:guid}", async (Guid id, ApplicationDbContext db) =>
{
    var song = await db.Songs
        .Where(s => s.Id == id)
        .Select(s => new SongResponse(
            s.Id,
            s.TenantId,
            s.Title,
            s.Artist,
            s.DefaultKey,
            s.TempoBpm,
            s.Lyrics,
            s.Chords,
            s.CreatedAt
        ))
        .FirstOrDefaultAsync();

    if (song == null)
    {
        return Results.NotFound(new { error = "Song not found." });
    }

    return Results.Ok(song);
});

// Create a song (Admin, Pastor, WorshipLeader)
worshipGroup.MapPost("/songs", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    CreateSongRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
    {
        return Results.BadRequest(new { error = "Song title is required." });
    }

    var churchId = ResolveTenantId(tenantService, user);
    if (churchId == Guid.Empty)
    {
        return Results.BadRequest(new { error = "A valid church tenant is required." });
    }

    var song = new Song
    {
        Id = Guid.NewGuid(),
        TenantId = churchId,
        Title = request.Title.Trim(),
        Artist = request.Artist?.Trim(),
        DefaultKey = request.DefaultKey?.Trim(),
        TempoBpm = request.TempoBpm,
        Lyrics = request.Lyrics ?? string.Empty,
        Chords = request.Chords ?? string.Empty,
        CreatedAt = DateTime.UtcNow
    };

    db.Songs.Add(song);
    await db.SaveChangesAsync();

    var response = new SongResponse(
        song.Id,
        song.TenantId,
        song.Title,
        song.Artist,
        song.DefaultKey,
        song.TempoBpm,
        song.Lyrics,
        song.Chords,
        song.CreatedAt
    );

    return Results.Created($"/api/v1/worship/songs/{song.Id}", response);
});

// Update a song (Admin, Pastor, WorshipLeader)
worshipGroup.MapPut("/songs/{id:guid}", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    Guid id,
    UpdateSongRequest request,
    ApplicationDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
    {
        return Results.BadRequest(new { error = "Song title is required." });
    }

    var song = await db.Songs.FirstOrDefaultAsync(s => s.Id == id);
    if (song == null)
    {
        return Results.NotFound(new { error = "Song not found." });
    }

    song.Title = request.Title.Trim();
    song.Artist = request.Artist?.Trim();
    song.DefaultKey = request.DefaultKey?.Trim();
    song.TempoBpm = request.TempoBpm;
    song.Lyrics = request.Lyrics ?? string.Empty;
    song.Chords = request.Chords ?? string.Empty;

    await db.SaveChangesAsync();

    var response = new SongResponse(
        song.Id,
        song.TenantId,
        song.Title,
        song.Artist,
        song.DefaultKey,
        song.TempoBpm,
        song.Lyrics,
        song.Chords,
        song.CreatedAt
    );

    return Results.Ok(response);
});

// Delete a song (Admin, Pastor, WorshipLeader)
worshipGroup.MapDelete("/songs/{id:guid}", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    Guid id,
    ApplicationDbContext db) =>
{
    var song = await db.Songs.FirstOrDefaultAsync(s => s.Id == id);
    if (song == null)
    {
        return Results.NotFound(new { error = "Song not found." });
    }

    // Check if song is in any setlists
    var isInUse = await db.SetlistItems.AnyAsync(i => i.SongId == id);
    if (isInUse)
    {
        return Results.BadRequest(new { error = "Cannot delete song because it is referenced in one or more service setlists." });
    }

    db.Songs.Remove(song);
    await db.SaveChangesAsync();

    return Results.NoContent();
});

// ---------------- SETLISTS ----------------

// Get all setlists (summary)
worshipGroup.MapGet("/setlists", async (ApplicationDbContext db) =>
{
    var setlists = await db.Setlists
        .OrderByDescending(s => s.ServiceDate)
        .Select(s => new SetlistResponse(
            s.Id,
            s.TenantId,
            s.Title,
            s.ServiceDate,
            s.Notes,
            s.Items.Count,
            s.CreatedAt
        ))
        .ToListAsync();

    return Results.Ok(setlists);
});

// Get a setlist with songs
worshipGroup.MapGet("/setlists/{id:guid}", async (Guid id, ApplicationDbContext db) =>
{
    var setlist = await db.Setlists
        .Where(s => s.Id == id)
        .Include(s => s.Items.OrderBy(i => i.Order))
            .ThenInclude(i => i.Song)
        .FirstOrDefaultAsync();

    if (setlist == null)
    {
        return Results.NotFound(new { error = "Setlist not found." });
    }

    var itemResponses = setlist.Items
        .OrderBy(i => i.Order)
        .Select(i => new SetlistItemResponse(
            i.Id,
            i.SongId,
            i.Song?.Title ?? string.Empty,
            i.Song?.Artist,
            i.Song?.DefaultKey,
            i.KeyOverride,
            i.Song?.TempoBpm,
            i.Song?.Lyrics ?? string.Empty,
            i.Song?.Chords ?? string.Empty,
            i.Order,
            i.Notes
        ))
        .ToList();

    var response = new SetlistDetailResponse(
        setlist.Id,
        setlist.TenantId,
        setlist.Title,
        setlist.ServiceDate,
        setlist.Notes,
        setlist.CreatedAt,
        itemResponses
    );

    return Results.Ok(response);
});

// Create setlist (Admin, Pastor, WorshipLeader)
worshipGroup.MapPost("/setlists", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    CreateSetlistRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
    {
        return Results.BadRequest(new { error = "Setlist title is required." });
    }

    var churchId = ResolveTenantId(tenantService, user);
    if (churchId == Guid.Empty)
    {
        return Results.BadRequest(new { error = "A valid church tenant is required." });
    }

    var setlist = new Setlist
    {
        Id = Guid.NewGuid(),
        TenantId = churchId,
        Title = request.Title.Trim(),
        ServiceDate = NormalizeServiceDate(request.ServiceDate),
        Notes = request.Notes?.Trim(),
        CreatedAt = DateTime.UtcNow
    };

    if (request.Items != null && request.Items.Count > 0)
    {
        // Verify all songs belong to current tenant
        var songIds = request.Items.Select(i => i.SongId).Distinct().ToList();
        var existingCount = await db.Songs.CountAsync(s => songIds.Contains(s.Id));
        if (existingCount != songIds.Count)
        {
            return Results.BadRequest(new { error = "One or more songs do not exist or belong to another church tenant." });
        }

        foreach (var itemReq in request.Items)
        {
            setlist.Items.Add(new SetlistItem
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                SetlistId = setlist.Id,
                SongId = itemReq.SongId,
                Order = itemReq.Order,
                KeyOverride = itemReq.KeyOverride?.Trim(),
                Notes = itemReq.Notes?.Trim()
            });
        }
    }

    db.Setlists.Add(setlist);
    await db.SaveChangesAsync();

    // Reload with songs for response
    var savedSetlist = await db.Setlists
        .Where(s => s.Id == setlist.Id)
        .Include(s => s.Items.OrderBy(i => i.Order))
            .ThenInclude(i => i.Song)
        .FirstOrDefaultAsync();

    var itemResponses = savedSetlist!.Items
        .OrderBy(i => i.Order)
        .Select(i => new SetlistItemResponse(
            i.Id,
            i.SongId,
            i.Song?.Title ?? string.Empty,
            i.Song?.Artist,
            i.Song?.DefaultKey,
            i.KeyOverride,
            i.Song?.TempoBpm,
            i.Song?.Lyrics ?? string.Empty,
            i.Song?.Chords ?? string.Empty,
            i.Order,
            i.Notes
        ))
        .ToList();

    var detailResponse = new SetlistDetailResponse(
        savedSetlist.Id,
        savedSetlist.TenantId,
        savedSetlist.Title,
        savedSetlist.ServiceDate,
        savedSetlist.Notes,
        savedSetlist.CreatedAt,
        itemResponses
    );

    return Results.Created($"/api/v1/worship/setlists/{setlist.Id}", detailResponse);
});

// Update setlist (Admin, Pastor, WorshipLeader)
worshipGroup.MapPut("/setlists/{id:guid}", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    Guid id,
    UpdateSetlistRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
    {
        return Results.BadRequest(new { error = "Setlist title is required." });
    }

    var setlist = await db.Setlists
        .Include(s => s.Items)
        .FirstOrDefaultAsync(s => s.Id == id);

    if (setlist == null)
    {
        return Results.NotFound(new { error = "Setlist not found." });
    }

    var churchId = ResolveTenantId(tenantService, user);
    if (churchId == Guid.Empty)
    {
        return Results.BadRequest(new { error = "A valid church tenant is required." });
    }

    setlist.Title = request.Title.Trim();
    setlist.ServiceDate = NormalizeServiceDate(request.ServiceDate);
    setlist.Notes = request.Notes?.Trim();

    if (request.Items != null)
    {
        var songIds = request.Items.Select(i => i.SongId).Distinct().ToList();
        var existingCount = await db.Songs.CountAsync(s => songIds.Contains(s.Id));
        if (existingCount != songIds.Count)
        {
            return Results.BadRequest(new { error = "One or more songs do not exist or belong to another church tenant." });
        }

        // Remove old items and replace
        db.SetlistItems.RemoveRange(setlist.Items);
        setlist.Items.Clear();

        foreach (var itemReq in request.Items)
        {
            setlist.Items.Add(new SetlistItem
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                SetlistId = setlist.Id,
                SongId = itemReq.SongId,
                Order = itemReq.Order,
                KeyOverride = itemReq.KeyOverride?.Trim(),
                Notes = itemReq.Notes?.Trim()
            });
        }
    }

    await db.SaveChangesAsync();

    var savedSetlist = await db.Setlists
        .Where(s => s.Id == setlist.Id)
        .Include(s => s.Items.OrderBy(i => i.Order))
            .ThenInclude(i => i.Song)
        .FirstOrDefaultAsync();

    var itemResponses = savedSetlist!.Items
        .OrderBy(i => i.Order)
        .Select(i => new SetlistItemResponse(
            i.Id,
            i.SongId,
            i.Song?.Title ?? string.Empty,
            i.Song?.Artist,
            i.Song?.DefaultKey,
            i.KeyOverride,
            i.Song?.TempoBpm,
            i.Song?.Lyrics ?? string.Empty,
            i.Song?.Chords ?? string.Empty,
            i.Order,
            i.Notes
        ))
        .ToList();

    var detailResponse = new SetlistDetailResponse(
        savedSetlist.Id,
        savedSetlist.TenantId,
        savedSetlist.Title,
        savedSetlist.ServiceDate,
        savedSetlist.Notes,
        savedSetlist.CreatedAt,
        itemResponses
    );

    return Results.Ok(detailResponse);
});

// Delete setlist (Admin, Pastor, WorshipLeader)
worshipGroup.MapDelete("/setlists/{id:guid}", [Authorize(Roles = "Admin,Pastor,WorshipLeader")] async (
    Guid id,
    ApplicationDbContext db) =>
{
    var setlist = await db.Setlists.FirstOrDefaultAsync(s => s.Id == id);
    if (setlist == null)
    {
        return Results.NotFound(new { error = "Setlist not found." });
    }

    db.Setlists.Remove(setlist);
    await db.SaveChangesAsync();

    return Results.NoContent();
});

// ---------------- FELLOWSHIP MINISTRY SPACES ----------------
var fellowshipGroup = app.MapGroup("/api/v1/fellowships")
    .RequireAuthorization();

// Helper to get authenticated user ID
static Guid GetCurrentUserId(ClaimsPrincipal user)
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user.FindFirst("sub")?.Value;
    _ = Guid.TryParse(userIdString, out var userId);
    return userId;
}

// Helper to get authenticated user name
static string GetCurrentUserName(ClaimsPrincipal user)
{
    var name = user.FindFirst(ClaimTypes.Name)?.Value ??
               user.FindFirst("name")?.Value ??
               user.FindFirst(ClaimTypes.Role)?.Value ??
               "Church Member";
    return name;
}

// 1. List all fellowship groups (can filter by type)
fellowshipGroup.MapGet("/", async (
    FellowshipGroupType? groupType,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    var isPrivileged = user.IsInRole("Admin") || user.IsInRole("Pastor");

    var query = db.FellowshipGroups.AsQueryable();

    if (groupType.HasValue)
    {
        query = query.Where(g => g.GroupType == groupType.Value);
    }

    // Non-privileged users only see public groups or groups they are members of
    if (!isPrivileged)
    {
        query = query.Where(g => !g.IsPrivate || g.Members.Any(m => m.MemberId == userId));
    }

    var groups = await query
        .OrderBy(g => g.Name)
        .Select(g => new FellowshipGroupResponse(
            g.Id,
            g.TenantId,
            g.Name,
            g.Description,
            g.GroupType,
            g.LeaderId,
            g.LeaderName,
            g.MeetingSchedule,
            g.Location,
            g.IsPrivate,
            g.Members.Count,
            g.CreatedAt
        ))
        .ToListAsync();

    return Results.Ok(groups);
});

// 2. Get specific fellowship group detail
fellowshipGroup.MapGet("/{id:guid}", async (
    Guid id,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    var isPrivileged = user.IsInRole("Admin") || user.IsInRole("Pastor");

    var group = await db.FellowshipGroups
        .Where(g => g.Id == id)
        .Include(g => g.Members)
        .Include(g => g.Posts.OrderByDescending(p => p.CreatedAt).Take(20))
        .FirstOrDefaultAsync();

    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    if (group.IsPrivate && !isPrivileged && !group.Members.Any(m => m.MemberId == userId))
    {
        return Results.Forbid();
    }

    var memberResponses = group.Members
        .OrderBy(m => m.Role == "Leader" ? 0 : 1)
        .ThenBy(m => m.MemberName)
        .Select(m => new FellowshipMemberResponse(
            m.Id,
            m.FellowshipGroupId,
            m.MemberId,
            m.MemberName,
            m.Role,
            m.JoinedAt
        ))
        .ToList();

    var postResponses = group.Posts
        .OrderByDescending(p => p.CreatedAt)
        .Select(p => new FellowshipPostResponse(
            p.Id,
            p.FellowshipGroupId,
            p.AuthorId,
            p.AuthorName,
            p.Title,
            p.Content,
            p.CreatedAt
        ))
        .ToList();

    var response = new FellowshipGroupDetailResponse(
        group.Id,
        group.TenantId,
        group.Name,
        group.Description,
        group.GroupType,
        group.LeaderId,
        group.LeaderName,
        group.MeetingSchedule,
        group.Location,
        group.IsPrivate,
        group.CreatedAt,
        memberResponses,
        postResponses
    );

    return Results.Ok(response);
});

// 3. Create fellowship group (Admin, Pastor, FellowshipLeader)
fellowshipGroup.MapPost("/", [Authorize(Roles = "Admin,Pastor,FellowshipLeader")] async (
    CreateFellowshipGroupRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Name))
    {
        return Results.BadRequest(new { error = "Group name is required." });
    }

    var churchId = ResolveTenantId(tenantService, user);
    var currentUserId = GetCurrentUserId(user);

    var group = new FellowshipGroup
    {
        Id = Guid.NewGuid(),
        TenantId = churchId,
        Name = request.Name.Trim(),
        Description = request.Description?.Trim(),
        GroupType = request.GroupType,
        LeaderId = request.LeaderId ?? (currentUserId != Guid.Empty ? currentUserId : null),
        LeaderName = request.LeaderName?.Trim() ?? GetCurrentUserName(user),
        MeetingSchedule = request.MeetingSchedule?.Trim(),
        Location = request.Location?.Trim(),
        IsPrivate = request.IsPrivate,
        CreatedAt = DateTime.UtcNow
    };

    // If a leader is specified, automatically add them as a leader member
    if (group.LeaderId.HasValue && group.LeaderId != Guid.Empty)
    {
        group.Members.Add(new FellowshipMember
        {
            Id = Guid.NewGuid(),
            TenantId = churchId,
            FellowshipGroupId = group.Id,
            MemberId = group.LeaderId.Value,
            MemberName = group.LeaderName ?? "Leader",
            Role = "Leader",
            JoinedAt = DateTime.UtcNow
        });
    }

    db.FellowshipGroups.Add(group);
    await db.SaveChangesAsync();

    var response = new FellowshipGroupResponse(
        group.Id,
        group.TenantId,
        group.Name,
        group.Description,
        group.GroupType,
        group.LeaderId,
        group.LeaderName,
        group.MeetingSchedule,
        group.Location,
        group.IsPrivate,
        group.Members.Count,
        group.CreatedAt
    );

    return Results.Created($"/api/v1/fellowships/{group.Id}", response);
});

// 4. Update fellowship group (Admin, Pastor, FellowshipLeader)
fellowshipGroup.MapPut("/{id:guid}", [Authorize(Roles = "Admin,Pastor,FellowshipLeader")] async (
    Guid id,
    UpdateFellowshipGroupRequest request,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Name))
    {
        return Results.BadRequest(new { error = "Group name is required." });
    }

    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    var userId = GetCurrentUserId(user);
    if (user.IsInRole("FellowshipLeader") && !user.IsInRole("Admin") && !user.IsInRole("Pastor"))
    {
        if (group.LeaderId.HasValue && group.LeaderId.Value != userId)
        {
            return Results.Forbid();
        }
    }

    group.Name = request.Name.Trim();
    group.Description = request.Description?.Trim();
    group.GroupType = request.GroupType;
    group.LeaderId = request.LeaderId;
    group.LeaderName = request.LeaderName?.Trim();
    group.MeetingSchedule = request.MeetingSchedule?.Trim();
    group.Location = request.Location?.Trim();
    group.IsPrivate = request.IsPrivate;

    await db.SaveChangesAsync();

    var memberCount = await db.FellowshipMembers.CountAsync(m => m.FellowshipGroupId == group.Id);

    var response = new FellowshipGroupResponse(
        group.Id,
        group.TenantId,
        group.Name,
        group.Description,
        group.GroupType,
        group.LeaderId,
        group.LeaderName,
        group.MeetingSchedule,
        group.Location,
        group.IsPrivate,
        memberCount,
        group.CreatedAt
    );

    return Results.Ok(response);
});

// 5. Delete fellowship group (Admin, Pastor)
fellowshipGroup.MapDelete("/{id:guid}", [Authorize(Roles = "Admin,Pastor")] async (
    Guid id,
    ApplicationDbContext db) =>
{
    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    db.FellowshipGroups.Remove(group);
    await db.SaveChangesAsync();

    return Results.NoContent();
});

// 6. Join fellowship group (Authenticated Member)
fellowshipGroup.MapPost("/{id:guid}/join", async (
    Guid id,
    JoinFellowshipGroupRequest? request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    if (userId == Guid.Empty)
    {
        return Results.Unauthorized();
    }

    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    var churchId = ResolveTenantId(tenantService, user);

    var existingMember = await db.FellowshipMembers
        .FirstOrDefaultAsync(m => m.FellowshipGroupId == id && m.MemberId == userId);

    if (existingMember != null)
    {
        return Results.Ok(new FellowshipMemberResponse(
            existingMember.Id,
            existingMember.FellowshipGroupId,
            existingMember.MemberId,
            existingMember.MemberName,
            existingMember.Role,
            existingMember.JoinedAt
        ));
    }

    var memberName = !string.IsNullOrWhiteSpace(request?.MemberName)
        ? request.MemberName.Trim()
        : GetCurrentUserName(user);

    var member = new FellowshipMember
    {
        Id = Guid.NewGuid(),
        TenantId = churchId,
        FellowshipGroupId = id,
        MemberId = userId,
        MemberName = memberName,
        Role = "Member",
        JoinedAt = DateTime.UtcNow
    };

    db.FellowshipMembers.Add(member);
    await db.SaveChangesAsync();

    return Results.Created($"/api/v1/fellowships/{id}/members/{member.Id}", new FellowshipMemberResponse(
        member.Id,
        member.FellowshipGroupId,
        member.MemberId,
        member.MemberName,
        member.Role,
        member.JoinedAt
    ));
});

// 7. Leave fellowship group (Authenticated Member)
fellowshipGroup.MapPost("/{id:guid}/leave", async (
    Guid id,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    if (userId == Guid.Empty)
    {
        return Results.Unauthorized();
    }

    var member = await db.FellowshipMembers
        .FirstOrDefaultAsync(m => m.FellowshipGroupId == id && m.MemberId == userId);

    if (member == null)
    {
        return Results.NotFound(new { error = "Membership not found in this group." });
    }

    db.FellowshipMembers.Remove(member);
    await db.SaveChangesAsync();

    return Results.NoContent();
});

// 8. List members of fellowship group
fellowshipGroup.MapGet("/{id:guid}/members", async (
    Guid id,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    var isPrivileged = user.IsInRole("Admin") || user.IsInRole("Pastor");

    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    if (group.IsPrivate && !isPrivileged)
    {
        var isMember = await db.FellowshipMembers.AnyAsync(m => m.FellowshipGroupId == id && m.MemberId == userId);
        if (!isMember)
        {
            return Results.Forbid();
        }
    }

    var members = await db.FellowshipMembers
        .Where(m => m.FellowshipGroupId == id)
        .OrderBy(m => m.Role == "Leader" ? 0 : 1)
        .ThenBy(m => m.MemberName)
        .Select(m => new FellowshipMemberResponse(
            m.Id,
            m.FellowshipGroupId,
            m.MemberId,
            m.MemberName,
            m.Role,
            m.JoinedAt
        ))
        .ToListAsync();

    return Results.Ok(members);
});

// 9. List posts of fellowship group
fellowshipGroup.MapGet("/{id:guid}/posts", async (
    Guid id,
    ApplicationDbContext db,
    ClaimsPrincipal user) =>
{
    var userId = GetCurrentUserId(user);
    var isPrivileged = user.IsInRole("Admin") || user.IsInRole("Pastor");

    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    if (group.IsPrivate && !isPrivileged)
    {
        var isMember = await db.FellowshipMembers.AnyAsync(m => m.FellowshipGroupId == id && m.MemberId == userId);
        if (!isMember)
        {
            return Results.Forbid();
        }
    }

    var posts = await db.FellowshipPosts
        .Where(p => p.FellowshipGroupId == id)
        .OrderByDescending(p => p.CreatedAt)
        .Select(p => new FellowshipPostResponse(
            p.Id,
            p.FellowshipGroupId,
            p.AuthorId,
            p.AuthorName,
            p.Title,
            p.Content,
            p.CreatedAt
        ))
        .ToListAsync();

    return Results.Ok(posts);
});

// 10. Create post in fellowship group
fellowshipGroup.MapPost("/{id:guid}/posts", async (
    Guid id,
    CreateFellowshipPostRequest request,
    ApplicationDbContext db,
    ITenantService tenantService,
    ClaimsPrincipal user) =>
{
    if (string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Content))
    {
        return Results.BadRequest(new { error = "Title and Content are required." });
    }

    var userId = GetCurrentUserId(user);
    if (userId == Guid.Empty)
    {
        return Results.Unauthorized();
    }

    var group = await db.FellowshipGroups.FirstOrDefaultAsync(g => g.Id == id);
    if (group == null)
    {
        return Results.NotFound(new { error = "Fellowship group not found." });
    }

    var isPrivileged = user.IsInRole("Admin") || user.IsInRole("Pastor");
    var isMember = await db.FellowshipMembers.AnyAsync(m => m.FellowshipGroupId == id && m.MemberId == userId);

    if (!isPrivileged && !isMember)
    {
        return Results.Forbid();
    }

    var churchId = ResolveTenantId(tenantService, user);
    var authorName = !string.IsNullOrWhiteSpace(request.AuthorName)
        ? request.AuthorName.Trim()
        : GetCurrentUserName(user);

    var post = new FellowshipPost
    {
        Id = Guid.NewGuid(),
        TenantId = churchId,
        FellowshipGroupId = id,
        AuthorId = userId,
        AuthorName = authorName,
        Title = request.Title.Trim(),
        Content = request.Content.Trim(),
        CreatedAt = DateTime.UtcNow
    };

    db.FellowshipPosts.Add(post);
    await db.SaveChangesAsync();

    var response = new FellowshipPostResponse(
        post.Id,
        post.FellowshipGroupId,
        post.AuthorId,
        post.AuthorName,
        post.Title,
        post.Content,
        post.CreatedAt
    );

    return Results.Created($"/api/v1/fellowships/{id}/posts/{post.Id}", response);
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
