using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace Church.API.Endpoints
{
    public static class MemberEndpoints
    {
        private static Guid GetCurrentUserId(ClaimsPrincipal user)
        {
            var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value
                            ?? user.FindFirst("sub")?.Value;
            _ = Guid.TryParse(userIdString, out var userId);
            return userId;
        }

        private static bool IsPrivileged(ClaimsPrincipal user)
        {
            return user.IsInRole("Admin") || user.IsInRole("Pastor");
        }

        private static DateTime? NormalizeToUtc(DateTime? dt)
        {
            if (!dt.HasValue) return null;
            return dt.Value.Kind switch
            {
                DateTimeKind.Utc => dt.Value,
                DateTimeKind.Local => dt.Value.ToUniversalTime(),
                _ => DateTime.SpecifyKind(dt.Value, DateTimeKind.Utc)
            };
        }

        private static DirectoryMemberResponse MapToDirectoryMember(Member m, bool isPrivileged, Guid callerId)
        {
            var isSelf = (m.Id == callerId);
            var canSeeEmail = isPrivileged || isSelf || m.ShowEmail;
            var canSeePhone = isPrivileged || isSelf || m.ShowPhoneNumber;
            var canSeeAddress = isPrivileged || isSelf || m.ShowAddress;
            var canSeeBirthday = isPrivileged || isSelf || m.ShowBirthDayAndMonth;

            var fullName = $"{m.FirstName} {m.LastName}".Trim();
            if (string.IsNullOrEmpty(fullName))
            {
                fullName = "Church Member";
            }

            return new DirectoryMemberResponse(
                Id: m.Id,
                FullName: fullName,
                AvatarUrl: m.AvatarUrl,
                Email: canSeeEmail ? m.Email : null,
                PhoneNumber: canSeePhone ? m.PhoneNumber : null,
                Address: canSeeAddress ? m.Address : null,
                BirthdayNotice: (canSeeBirthday && m.DateOfBirth.HasValue)
                    ? m.DateOfBirth.Value.ToString("MMMM d")
                    : null,
                FamilyId: m.FamilyId,
                FamilyName: m.Family?.FamilyName,
                FamilyRole: m.FamilyRole
            );
        }

        private static FullMemberProfileResponse MapToFullProfile(Member m)
        {
            return new FullMemberProfileResponse(
                Id: m.Id,
                TenantId: m.TenantId,
                FirstName: m.FirstName,
                LastName: m.LastName,
                Email: m.Email,
                PhoneNumber: m.PhoneNumber,
                AvatarUrl: m.AvatarUrl,
                DateOfBirth: m.DateOfBirth,
                AnniversaryDate: m.AnniversaryDate,
                Address: m.Address,
                FamilyId: m.FamilyId,
                FamilyName: m.Family?.FamilyName,
                FamilyRole: m.FamilyRole,
                DirectoryVisibility: m.DirectoryVisibility,
                ShowPhoneNumber: m.ShowPhoneNumber,
                ShowEmail: m.ShowEmail,
                ShowAddress: m.ShowAddress,
                ShowBirthDayAndMonth: m.ShowBirthDayAndMonth,
                UpdatedAt: m.UpdatedAt
            );
        }

        public static IEndpointRouteBuilder MapMemberEndpoints(this IEndpointRouteBuilder app)
        {
            var group = app.MapGroup("/api/v1/members")
                .RequireAuthorization();

            // 1. GET /api/v1/members/me
            group.MapGet("/me", async (
                ApplicationDbContext db,
                ITenantService tenantService,
                ClaimsPrincipal user) =>
            {
                var userId = GetCurrentUserId(user);
                if (userId == Guid.Empty)
                {
                    return Results.Unauthorized();
                }

                var churchId = tenantService.GetCurrentTenantId();

                var member = await db.Members
                    .Include(m => m.Family)
                    .FirstOrDefaultAsync(m => m.Id == userId);

                if (member == null)
                {
                    // Auto-provision initial member record from claims or AppUser with fail-closed private defaults
                    var email = user.FindFirst(ClaimTypes.Email)?.Value
                             ?? user.FindFirst("email")?.Value
                             ?? "member@church.local";

                    var name = user.FindFirst(ClaimTypes.Name)?.Value
                            ?? user.FindFirst("name")?.Value
                            ?? "Church Member";

                    var parts = name.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
                    var firstName = parts.Length > 0 ? parts[0] : "Church";
                    var lastName = parts.Length > 1 ? parts[1] : "Member";

                    member = new Member
                    {
                        Id = userId,
                        TenantId = churchId,
                        FirstName = firstName,
                        LastName = lastName,
                        Email = email,
                        DirectoryVisibility = DirectoryVisibility.Private, // Default private until member opts in
                        ShowPhoneNumber = false,
                        ShowEmail = false,
                        ShowAddress = false,
                        ShowBirthDayAndMonth = false,
                        CreatedAt = DateTime.UtcNow,
                        UpdatedAt = DateTime.UtcNow
                    };

                    db.Members.Add(member);
                    await db.SaveChangesAsync();
                }

                return Results.Ok(MapToFullProfile(member));
            });

            // 2. PUT /api/v1/members/me
            group.MapPut("/me", async (
                UpdateMemberProfileRequest request,
                ApplicationDbContext db,
                ITenantService tenantService,
                ClaimsPrincipal user) =>
            {
                var userId = GetCurrentUserId(user);
                if (userId == Guid.Empty)
                {
                    return Results.Unauthorized();
                }

                if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
                {
                    return Results.BadRequest(new { error = "First name and last name are required." });
                }

                var churchId = tenantService.GetCurrentTenantId();

                var member = await db.Members
                    .Include(m => m.Family)
                    .FirstOrDefaultAsync(m => m.Id == userId);

                if (member == null)
                {
                    var email = user.FindFirst(ClaimTypes.Email)?.Value
                             ?? user.FindFirst("email")?.Value
                             ?? "member@church.local";

                    member = new Member
                    {
                        Id = userId,
                        TenantId = churchId,
                        Email = email,
                        CreatedAt = DateTime.UtcNow
                    };
                    db.Members.Add(member);
                }

                member.FirstName = request.FirstName.Trim();
                member.LastName = request.LastName.Trim();
                member.PhoneNumber = request.PhoneNumber?.Trim();
                member.AvatarUrl = request.AvatarUrl?.Trim();
                member.DateOfBirth = NormalizeToUtc(request.DateOfBirth);
                member.AnniversaryDate = NormalizeToUtc(request.AnniversaryDate);
                member.Address = request.Address?.Trim();
                member.DirectoryVisibility = request.DirectoryVisibility;
                member.ShowPhoneNumber = request.ShowPhoneNumber;
                member.ShowEmail = request.ShowEmail;
                member.ShowAddress = request.ShowAddress;
                member.ShowBirthDayAndMonth = request.ShowBirthDayAndMonth;
                member.UpdatedAt = DateTime.UtcNow;

                await db.SaveChangesAsync();

                return Results.Ok(MapToFullProfile(member));
            });

            // 3. GET /api/v1/members (Directory listing with privacy redaction)
            group.MapGet("/", async (
                string? search,
                int? page,
                int? pageSize,
                ApplicationDbContext db,
                ClaimsPrincipal user) =>
            {
                var callerId = GetCurrentUserId(user);
                var privileged = IsPrivileged(user);

                var query = db.Members
                    .Include(m => m.Family)
                    .AsQueryable();

                // Non-privileged users only see PublicToMembers
                if (!privileged)
                {
                    query = query.Where(m => m.DirectoryVisibility == DirectoryVisibility.PublicToMembers || m.Id == callerId);
                }

                if (!string.IsNullOrWhiteSpace(search))
                {
                    var term = search.Trim().ToLower();
                    query = query.Where(m =>
                        m.FirstName.ToLower().Contains(term) ||
                        m.LastName.ToLower().Contains(term) ||
                        (m.Family != null && m.Family.FamilyName.ToLower().Contains(term)));
                }

                var p = page.GetValueOrDefault(1);
                var ps = pageSize.GetValueOrDefault(50);
                if (p < 1) p = 1;
                if (ps < 1 || ps > 100) ps = 50;

                var members = await query
                    .OrderBy(m => m.LastName)
                    .ThenBy(m => m.FirstName)
                    .Skip((p - 1) * ps)
                    .Take(ps)
                    .ToListAsync();

                var response = members
                    .Select(m => MapToDirectoryMember(m, privileged, callerId))
                    .ToList();

                return Results.Ok(response);
            });

            // 4. GET /api/v1/members/{id:guid}
            group.MapGet("/{id:guid}", async (
                Guid id,
                ApplicationDbContext db,
                ClaimsPrincipal user) =>
            {
                var callerId = GetCurrentUserId(user);
                var privileged = IsPrivileged(user);
                var isSelf = (id == callerId);

                var member = await db.Members
                    .Include(m => m.Family)
                    .FirstOrDefaultAsync(m => m.Id == id);

                if (member == null)
                {
                    return Results.NotFound(new { error = "Member not found." });
                }

                // If non-privileged and not self, check visibility
                if (!privileged && !isSelf && member.DirectoryVisibility != DirectoryVisibility.PublicToMembers)
                {
                    return Results.NotFound(new { error = "Member not found." });
                }

                return Results.Ok(MapToDirectoryMember(member, privileged, callerId));
            });

            // 5. GET /api/v1/members/families/{id:guid}
            group.MapGet("/families/{id:guid}", async (
                Guid id,
                ApplicationDbContext db,
                ClaimsPrincipal user) =>
            {
                var callerId = GetCurrentUserId(user);
                var privileged = IsPrivileged(user);

                var family = await db.Families
                    .Include(f => f.Members)
                    .FirstOrDefaultAsync(f => f.Id == id);

                if (family == null)
                {
                    return Results.NotFound(new { error = "Family not found." });
                }

                var isFamilyMember = family.Members.Any(m => m.Id == callerId);
                var visibleMembers = family.Members
                    .Where(m => privileged || m.Id == callerId || m.DirectoryVisibility == DirectoryVisibility.PublicToMembers)
                    .ToList();

                // If non-privileged caller is not in this family and cannot see any public members, return 404 to protect family privacy
                if (!privileged && !isFamilyMember && visibleMembers.Count == 0)
                {
                    return Results.NotFound(new { error = "Family not found." });
                }

                var memberResponses = visibleMembers
                    .OrderBy(m => m.FamilyRole == FamilyRole.HeadOfHousehold ? 0 :
                                  m.FamilyRole == FamilyRole.Spouse ? 1 : 2)
                    .ThenBy(m => m.FirstName)
                    .Select(m => MapToDirectoryMember(m, privileged, callerId))
                    .ToList();

                var response = new FamilyResponse(
                    Id: family.Id,
                    TenantId: family.TenantId,
                    FamilyName: family.FamilyName,
                    Members: memberResponses
                );

                return Results.Ok(response);
            });

            // 6. POST /api/v1/members/families (Admin or Pastor create family)
            group.MapPost("/families", [Authorize(Roles = "Admin,Pastor")] async (
                CreateFamilyRequest request,
                ApplicationDbContext db,
                ITenantService tenantService) =>
            {
                if (string.IsNullOrWhiteSpace(request.FamilyName))
                {
                    return Results.BadRequest(new { error = "Family name is required." });
                }

                var churchId = tenantService.GetCurrentTenantId();

                var family = new Family
                {
                    Id = Guid.NewGuid(),
                    TenantId = churchId,
                    FamilyName = request.FamilyName.Trim(),
                    CreatedAt = DateTime.UtcNow
                };

                db.Families.Add(family);
                await db.SaveChangesAsync();

                var response = new FamilyResponse(
                    Id: family.Id,
                    TenantId: family.TenantId,
                    FamilyName: family.FamilyName,
                    Members: new List<DirectoryMemberResponse>()
                );

                return Results.Created($"/api/v1/members/families/{family.Id}", response);
            });

            // 7. PUT /api/v1/members/{id:guid}/family (Assign member to family - Leaders only, or self-disassociate)
            group.MapPut("/{id:guid}/family", async (
                Guid id,
                AssignFamilyRequest request,
                ApplicationDbContext db,
                ClaimsPrincipal user) =>
            {
                var callerId = GetCurrentUserId(user);
                var privileged = IsPrivileged(user);

                // Regular members can only disassociate themselves (FamilyId == null).
                // Assigning someone to a family requires leader authorization (Admin or Pastor).
                if (!privileged)
                {
                    if (id != callerId || request.FamilyId.HasValue)
                    {
                        return Results.Forbid();
                    }
                }

                var member = await db.Members.FirstOrDefaultAsync(m => m.Id == id);
                if (member == null)
                {
                    return Results.NotFound(new { error = "Member not found." });
                }

                if (request.FamilyId.HasValue && request.FamilyId.Value != Guid.Empty)
                {
                    var familyExists = await db.Families.AnyAsync(f => f.Id == request.FamilyId.Value);
                    if (!familyExists)
                    {
                        return Results.BadRequest(new { error = "Specified family does not exist." });
                    }
                    member.FamilyId = request.FamilyId.Value;
                }
                else
                {
                    member.FamilyId = null;
                }

                member.FamilyRole = request.FamilyRole;
                member.UpdatedAt = DateTime.UtcNow;

                await db.SaveChangesAsync();

                return Results.Ok(new { message = "Family assigned successfully." });
            });

            return app;
        }
    }
}
