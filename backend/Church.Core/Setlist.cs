using System;
using System.Collections.Generic;

namespace Church.Core
{
    public class Setlist : IMultiTenantEntity
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
        public DateTime ServiceDate { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public List<SetlistItem> Items { get; set; } = new();
    }
}
