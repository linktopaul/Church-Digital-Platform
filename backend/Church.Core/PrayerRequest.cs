using System;

namespace Church.Core
{
    public class PrayerRequest : IMultiTenantEntity
    {
        public Guid Id { get; set; }

        public Guid TenantId { get; set; }

        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public Guid MemberId { get; set; }
        public string Content { get; set; } = string.Empty;
        public PrayerRequestStatus Status { get; set; } = PrayerRequestStatus.Submitted;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
