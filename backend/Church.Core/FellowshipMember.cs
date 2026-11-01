using System;

namespace Church.Core
{
    public class FellowshipMember : IMultiTenantEntity
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

        public Guid MemberId { get; set; }
        public string MemberName { get; set; } = string.Empty;
        public string Role { get; set; } = "Member"; // e.g. Leader, Member
        public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    }
}
