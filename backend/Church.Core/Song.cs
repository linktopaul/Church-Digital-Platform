using System;

namespace Church.Core
{
    public class Song : IMultiTenantEntity
    {
        public Guid Id { get; set; }

        // Maps to church_id and fulfills IMultiTenantEntity.TenantId
        public Guid TenantId { get; set; }

        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public string Title { get; set; } = string.Empty;
        public string? Artist { get; set; }
        public string? DefaultKey { get; set; }
        public int? TempoBpm { get; set; }
        public string Lyrics { get; set; } = string.Empty;
        public string Chords { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
