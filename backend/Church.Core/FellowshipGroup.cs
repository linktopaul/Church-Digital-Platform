using System;
using System.Collections.Generic;

namespace Church.Core
{
    public class FellowshipGroup : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid ChurchId { get; set; }
        public Guid TenantId
        {
            get => ChurchId;
            set => ChurchId = value;
        }

        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public FellowshipGroupType GroupType { get; set; }
        public Guid? LeaderId { get; set; }
        public string? LeaderName { get; set; }
        public string? MeetingSchedule { get; set; }
        public string? Location { get; set; }
        public bool IsPrivate { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public ICollection<FellowshipMember> Members { get; set; } = new List<FellowshipMember>();
        public ICollection<FellowshipPost> Posts { get; set; } = new List<FellowshipPost>();
    }
}
