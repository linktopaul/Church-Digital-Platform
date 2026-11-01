using System;

namespace Church.Core
{
    public class FellowshipPost : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid ChurchId { get; set; }
        public Guid TenantId
        {
            get => ChurchId;
            set => ChurchId = value;
        }

        public Guid FellowshipGroupId { get; set; }
        public FellowshipGroup? FellowshipGroup { get; set; }

        public Guid AuthorId { get; set; }
        public string AuthorName { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
