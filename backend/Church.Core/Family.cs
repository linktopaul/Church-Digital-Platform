using System;
using System.Collections.Generic;

namespace Church.Core
{
    public class Family : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }
        public string FamilyName { get; set; } = string.Empty;
        public ICollection<Member> Members { get; set; } = new List<Member>();
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
