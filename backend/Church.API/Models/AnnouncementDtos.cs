using System;
using Church.Core;

namespace Church.API.Models
{
    public record CreateAnnouncementRequest(
        string Title,
        string Content,
        AnnouncementPriority Priority = AnnouncementPriority.Routine,
        DateTime? PublishedAt = null,
        DateTime? ExpiresAt = null
    );

    public record AnnouncementResponse(
        Guid Id,
        Guid ChurchId,
        Guid AuthorId,
        string Title,
        string Content,
        AnnouncementPriority Priority,
        DateTime PublishedAt,
        DateTime? ExpiresAt
    );
}
