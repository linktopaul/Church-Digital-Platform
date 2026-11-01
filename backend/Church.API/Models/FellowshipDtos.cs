using System;
using System.Collections.Generic;
using Church.Core;

namespace Church.API.Models
{
    // Fellowship Group DTOs
    public record CreateFellowshipGroupRequest(
        string Name,
        string? Description,
        FellowshipGroupType GroupType,
        Guid? LeaderId,
        string? LeaderName,
        string? MeetingSchedule,
        string? Location,
        bool IsPrivate
    );

    public record UpdateFellowshipGroupRequest(
        string Name,
        string? Description,
        FellowshipGroupType GroupType,
        Guid? LeaderId,
        string? LeaderName,
        string? MeetingSchedule,
        string? Location,
        bool IsPrivate
    );

    public record FellowshipGroupResponse(
        Guid Id,
        Guid ChurchId,
        string Name,
        string? Description,
        FellowshipGroupType GroupType,
        Guid? LeaderId,
        string? LeaderName,
        string? MeetingSchedule,
        string? Location,
        bool IsPrivate,
        int MemberCount,
        DateTime CreatedAt
    );

    public record FellowshipGroupDetailResponse(
        Guid Id,
        Guid ChurchId,
        string Name,
        string? Description,
        FellowshipGroupType GroupType,
        Guid? LeaderId,
        string? LeaderName,
        string? MeetingSchedule,
        string? Location,
        bool IsPrivate,
        DateTime CreatedAt,
        List<FellowshipMemberResponse> Members,
        List<FellowshipPostResponse> RecentPosts
    );

    // Fellowship Member DTOs
    public record JoinFellowshipGroupRequest(
        string? MemberName
    );

    public record FellowshipMemberResponse(
        Guid Id,
        Guid FellowshipGroupId,
        Guid MemberId,
        string MemberName,
        string Role,
        DateTime JoinedAt
    );

    // Fellowship Post DTOs
    public record CreateFellowshipPostRequest(
        string Title,
        string Content,
        string? AuthorName
    );

    public record FellowshipPostResponse(
        Guid Id,
        Guid FellowshipGroupId,
        Guid AuthorId,
        string AuthorName,
        string Title,
        string Content,
        DateTime CreatedAt
    );
}
