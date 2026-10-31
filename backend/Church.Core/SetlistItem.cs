using System;

namespace Church.Core
{
    public class SetlistItem : IMultiTenantEntity
    {
        public Guid Id { get; set; }

        // Maps to church_id and fulfills IMultiTenantEntity.TenantId
        public Guid TenantId { get; set; }

        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public Guid SetlistId { get; set; }
        public Setlist? Setlist { get; set; }

        public Guid SongId { get; set; }
        public Song? Song { get; set; }

        public int Order { get; set; }
        public string? KeyOverride { get; set; }
        public string? Notes { get; set; }
    }
}
