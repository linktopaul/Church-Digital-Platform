using System;
using System.Collections.Generic;

namespace Church.API.Models
{
    public record CreateSongRequest(
        string Title,
        string? Artist,
        string? DefaultKey,
        int? TempoBpm,
        string Lyrics,
        string Chords
    );

    public record UpdateSongRequest(
        string Title,
        string? Artist,
        string? DefaultKey,
        int? TempoBpm,
        string Lyrics,
        string Chords
    );

    public record SongResponse(
        Guid Id,
        Guid ChurchId,
        string Title,
        string? Artist,
        string? DefaultKey,
        int? TempoBpm,
        string Lyrics,
        string Chords,
        DateTime CreatedAt
    );

    public record CreateSetlistItemRequest(
        Guid SongId,
        int Order,
        string? KeyOverride,
        string? Notes
    );

    public record CreateSetlistRequest(
        string Title,
        DateTime ServiceDate,
        string? Notes,
        List<CreateSetlistItemRequest>? Items
    );

    public record UpdateSetlistRequest(
        string Title,
        DateTime ServiceDate,
        string? Notes,
        List<CreateSetlistItemRequest>? Items
    );

    public record SetlistItemResponse(
        Guid Id,
        Guid SongId,
        string SongTitle,
        string? SongArtist,
        string? DefaultKey,
        string? KeyOverride,
        int? TempoBpm,
        string Lyrics,
        string Chords,
        int Order,
        string? Notes
    );

    public record SetlistResponse(
        Guid Id,
        Guid ChurchId,
        string Title,
        DateTime ServiceDate,
        string? Notes,
        int ItemCount,
        DateTime CreatedAt
    );

    public record SetlistDetailResponse(
        Guid Id,
        Guid ChurchId,
        string Title,
        DateTime ServiceDate,
        string? Notes,
        DateTime CreatedAt,
        List<SetlistItemResponse> Items
    );
}
