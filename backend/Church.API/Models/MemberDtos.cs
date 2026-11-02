using System;
using System.Collections.Generic;
using Church.Core;

namespace Church.API.Models
{
    public record FullMemberProfileResponse(
        Guid Id,
        Guid TenantId,
        string FirstName,
        string LastName,
        string Email,
        string? PhoneNumber,
        string? AvatarUrl,
        DateTime? DateOfBirth,
        DateTime? AnniversaryDate,
        string? Address,
        Guid? FamilyId,
        string? FamilyName,
        FamilyRole FamilyRole,
        DirectoryVisibility DirectoryVisibility,
        bool ShowPhoneNumber,
        bool ShowEmail,
        bool ShowAddress,
        bool ShowBirthDayAndMonth,
        DateTime UpdatedAt
    );

    public record DirectoryMemberResponse(
        Guid Id,
        string FullName,
        string? AvatarUrl,
        string? Email,       // Redacted if !ShowEmail && !IsPrivileged
        string? PhoneNumber, // Redacted if !ShowPhoneNumber && !IsPrivileged
        string? Address,     // Redacted if !ShowAddress && !IsPrivileged
        string? BirthdayNotice, // e.g. "April 15" if ShowBirthDayAndMonth
        Guid? FamilyId,
        string? FamilyName,
        FamilyRole FamilyRole
    );

    public record UpdateMemberProfileRequest(
        string FirstName,
        string LastName,
        string? PhoneNumber,
        string? AvatarUrl,
        DateTime? DateOfBirth,
        DateTime? AnniversaryDate,
        string? Address,
        DirectoryVisibility DirectoryVisibility,
        bool ShowPhoneNumber,
        bool ShowEmail,
        bool ShowAddress,
        bool ShowBirthDayAndMonth
    );

    public record FamilyResponse(
        Guid Id,
        Guid TenantId,
        string FamilyName,
        List<DirectoryMemberResponse> Members
    );

    public record CreateFamilyRequest(
        string FamilyName
    );

    public record AssignFamilyRequest(
        Guid? FamilyId,
        FamilyRole FamilyRole
    );
}
