using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Text.RegularExpressions;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace Church.API.Endpoints;

public static class CelebrationEndpoints
{
    private static readonly Regex PhoneSanitizerRegex = new(@"[^\d]", RegexOptions.Compiled);

    public static IEndpointRouteBuilder MapCelebrationEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/celebrations")
            .RequireAuthorization();

        // 1. Get today's celebrations (Birthdays & Anniversaries)
        group.MapGet("/today", async (
            ApplicationDbContext db,
            ClaimsPrincipal user,
            DateTime? date = null) =>
        {
            var targetDate = (date ?? DateTime.UtcNow).Date;
            var month = targetDate.Month;
            var day = targetDate.Day;
            var isPrivileged = user.IsInRole("Pastor") || user.IsInRole("Admin");

            // Query members within tenant boundary (enforced via EF global query filter)
            var membersQuery = db.Members.AsNoTracking();

            // Privacy filter: non-privileged callers only see members who opted into public directory visibility
            // AND consented to birthday/anniversary display
            if (!isPrivileged)
            {
                membersQuery = membersQuery.Where(m =>
                    m.ShowBirthDayAndMonth &&
                    m.DirectoryVisibility == DirectoryVisibility.PublicToMembers);
            }

            var members = await membersQuery.ToListAsync();
            var results = new List<CelebrationEventResponse>();

            foreach (var m in members)
            {
                var fullName = $"{m.FirstName} {m.LastName}".Trim();

                // Birthday check
                if (m.DateOfBirth.HasValue &&
                    m.DateOfBirth.Value.Month == month &&
                    m.DateOfBirth.Value.Day == day)
                {
                    var years = targetDate.Year - m.DateOfBirth.Value.Year;
                    // Birth year / exact age is only disclosed to privileged callers (Pastor/Admin)
                    // Regular callers receive null years to protect full date of birth privacy
                    var exposedYears = isPrivileged && years > 0 ? (int?)years : null;

                    var (phone, waUrl, canMessage) = ResolveContactDetails(m, isPrivileged, CelebrationType.Birthday, fullName, years);
                    results.Add(new CelebrationEventResponse(
                        m.Id,
                        fullName,
                        m.AvatarUrl,
                        CelebrationType.Birthday,
                        targetDate,
                        exposedYears,
                        phone,
                        waUrl,
                        canMessage
                    ));
                }

                // Anniversary check
                if (m.AnniversaryDate.HasValue &&
                    m.AnniversaryDate.Value.Month == month &&
                    m.AnniversaryDate.Value.Day == day)
                {
                    var years = targetDate.Year - m.AnniversaryDate.Value.Year;
                    var (phone, waUrl, canMessage) = ResolveContactDetails(m, isPrivileged, CelebrationType.Anniversary, fullName, years);
                    results.Add(new CelebrationEventResponse(
                        m.Id,
                        fullName,
                        m.AvatarUrl,
                        CelebrationType.Anniversary,
                        targetDate,
                        years > 0 ? years : null,
                        phone,
                        waUrl,
                        canMessage
                    ));
                }
            }

            return Results.Ok(results.OrderBy(r => r.MemberName));
        });

        // 2. Get upcoming celebrations for the next N days (default 7, max 30)
        group.MapGet("/upcoming", async (
            ApplicationDbContext db,
            ClaimsPrincipal user,
            int days = 7,
            DateTime? startDate = null) =>
        {
            var clampedDays = Math.Clamp(days, 1, 30);
            var start = (startDate ?? DateTime.UtcNow).Date;
            var isPrivileged = user.IsInRole("Pastor") || user.IsInRole("Admin");

            var membersQuery = db.Members.AsNoTracking();
            if (!isPrivileged)
            {
                membersQuery = membersQuery.Where(m =>
                    m.ShowBirthDayAndMonth &&
                    m.DirectoryVisibility == DirectoryVisibility.PublicToMembers);
            }

            var members = await membersQuery.ToListAsync();
            var results = new List<CelebrationEventResponse>();

            // Generate lookup of (month, day) -> target date offset
            var dayOffsets = new Dictionary<(int Month, int Day), (DateTime Date, int Offset)>();
            for (var offset = 0; offset <= clampedDays; offset++)
            {
                var cur = start.AddDays(offset);
                dayOffsets[(cur.Month, cur.Day)] = (cur, offset);
            }

            foreach (var m in members)
            {
                var fullName = $"{m.FirstName} {m.LastName}".Trim();

                if (m.DateOfBirth.HasValue &&
                    dayOffsets.TryGetValue((m.DateOfBirth.Value.Month, m.DateOfBirth.Value.Day), out var bdayInfo))
                {
                    var years = bdayInfo.Date.Year - m.DateOfBirth.Value.Year;
                    // Birth year / exact age is suppressed for regular callers
                    var exposedYears = isPrivileged && years > 0 ? (int?)years : null;

                    var (phone, waUrl, canMessage) = ResolveContactDetails(m, isPrivileged, CelebrationType.Birthday, fullName, years);
                    results.Add(new CelebrationEventResponse(
                        m.Id,
                        fullName,
                        m.AvatarUrl,
                        CelebrationType.Birthday,
                        bdayInfo.Date,
                        exposedYears,
                        phone,
                        waUrl,
                        canMessage
                    ));
                }

                if (m.AnniversaryDate.HasValue &&
                    dayOffsets.TryGetValue((m.AnniversaryDate.Value.Month, m.AnniversaryDate.Value.Day), out var annInfo))
                {
                    var years = annInfo.Date.Year - m.AnniversaryDate.Value.Year;
                    var (phone, waUrl, canMessage) = ResolveContactDetails(m, isPrivileged, CelebrationType.Anniversary, fullName, years);
                    results.Add(new CelebrationEventResponse(
                        m.Id,
                        fullName,
                        m.AvatarUrl,
                        CelebrationType.Anniversary,
                        annInfo.Date,
                        years > 0 ? years : null,
                        phone,
                        waUrl,
                        canMessage
                    ));
                }
            }

            return Results.Ok(results.OrderBy(r => r.Date).ThenBy(r => r.MemberName));
        });

        // 3. Get pre-approved scripture blessing templates
        group.MapGet("/templates", () =>
        {
            var templates = new List<BlessingTemplateResponse>
            {
                new(
                    CelebrationType.Birthday,
                    "Birthday Blessing",
                    "Dear {name}, your church family celebrates with you on your Birthday! May God's grace and joy surround you today and always.",
                    "Numbers 6:24-25 — 'The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you.'"
                ),
                new(
                    CelebrationType.Anniversary,
                    "Anniversary Blessing",
                    "Dear {name}, warm congratulations on your wedding anniversary! May God continue to bless your marriage with enduring love, peace, and unity.",
                    "1 Corinthians 13:7 — 'Love always protects, always trusts, always hopes, always perseveres.'"
                ),
                new(
                    CelebrationType.Birthday,
                    "Day of Joy Blessing",
                    "Dear {name}, rejoicing with you today on your birthday as we thank God for the blessing of your life!",
                    "Psalm 118:24 — 'This is the day the Lord has made; let us rejoice and be glad in it.'"
                )
            };
            return Results.Ok(templates);
        });

        // 4. Daily scan endpoint (Admin/Pastor operational trigger for cron/background automation)
        group.MapPost("/scan-daily", async (
            ApplicationDbContext db,
            ClaimsPrincipal user,
            DateTime? date = null) =>
        {
            if (!user.IsInRole("Pastor") && !user.IsInRole("Admin"))
            {
                return Results.Forbid();
            }

            var targetDate = (date ?? DateTime.UtcNow).Date;
            var month = targetDate.Month;
            var day = targetDate.Day;

            var members = await db.Members.AsNoTracking()
                .Where(m => (m.DateOfBirth.HasValue && m.DateOfBirth.Value.Month == month && m.DateOfBirth.Value.Day == day) ||
                            (m.AnniversaryDate.HasValue && m.AnniversaryDate.Value.Month == month && m.AnniversaryDate.Value.Day == day))
                .ToListAsync();

            var scanCount = members.Count;
            return Results.Ok(new DailyScanResultResponse(
                targetDate,
                scanCount,
                "Completed",
                $"Daily scan completed for {targetDate:yyyy-MM-dd}. Found {scanCount} celebration(s)."
            ));
        });

        return app;
    }

    private static (string? Phone, string? WhatsAppUrl, bool CanMessage) ResolveContactDetails(
        Member m,
        bool isPrivileged,
        CelebrationType type,
        string fullName,
        int years)
    {
        // Contact phone privacy: unlisted phone numbers are suppressed for regular members
        var canSharePhone = isPrivileged || m.ShowPhoneNumber;
        if (!canSharePhone || string.IsNullOrWhiteSpace(m.PhoneNumber))
        {
            return (null, null, false);
        }

        var cleanPhone = PhoneSanitizerRegex.Replace(m.PhoneNumber.Trim(), "");
        if (string.IsNullOrWhiteSpace(cleanPhone))
        {
            return (null, null, false);
        }

        var greeting = type == CelebrationType.Birthday
            ? $"Dear {fullName}, your church family celebrates your Birthday! May the Lord bless you and keep you today and throughout the year. (Numbers 6:24)"
            : $"Dear {fullName}, congratulations on your wedding anniversary! May God continue to enrich your marriage with love and peace.";

        var waUrl = $"https://wa.me/{cleanPhone}?text={Uri.EscapeDataString(greeting)}";
        return (m.PhoneNumber.Trim(), waUrl, true);
    }
}
