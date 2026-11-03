using System;
using Church.Core;

namespace Church.API.Models;

public record CelebrationEventResponse(
    Guid MemberId,
    string MemberName,
    string? AvatarUrl,
    CelebrationType Type,
    DateTime Date,
    int? Years,
    string? PhoneNumber,
    string? WhatsAppUrl,
    bool CanMessageDirectly
);

public record BlessingTemplateResponse(
    CelebrationType Type,
    string Title,
    string Template,
    string DefaultScripture
);

public record DailyScanResultResponse(
    DateTime Date,
    int CelebrationsFound,
    string Status,
    string Message
);
