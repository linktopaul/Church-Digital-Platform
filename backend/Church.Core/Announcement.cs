using System;

namespace Church.Core
{
    public class Announcement : IMultiTenantEntity
    {
        public Guid Id { get; set; }

        // Maps to church_id and fulfills IMultiTenantEntity.TenantId
        public Guid TenantId { get; set; }

        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public Guid AuthorId { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public AnnouncementPriority Priority { get; set; } = AnnouncementPriority.Routine;
        public DateTime PublishedAt { get; set; } = DateTime.UtcNow;
        public DateTime? ExpiresAt { get; set; }
    }
}
