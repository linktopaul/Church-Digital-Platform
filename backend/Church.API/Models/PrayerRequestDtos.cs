using System;
using Church.Core;

namespace Church.API.Models
{
    public record CreatePrayerRequestRequest(
        string Content
    );

    public record UpdatePrayerRequestStatusRequest(
        PrayerRequestStatus Status
    );

    public record PrayerRequestResponse(
        Guid Id,
        Guid ChurchId,
        Guid MemberId,
        string Content,
        PrayerRequestStatus Status,
        DateTime CreatedAt,
        DateTime UpdatedAt
    );
}
