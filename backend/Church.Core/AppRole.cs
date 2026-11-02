using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;

namespace Church.Core
{
    public static class ChurchRoleNames
    {
        public const string Admin = "Admin";
        public const string Pastor = "Pastor";
        public const string WorshipLeader = "WorshipLeader";
        public const string FellowshipLeader = "FellowshipLeader";
        public const string Member = "Member";

        public static readonly IReadOnlyList<string> All = new[]
        {
            Admin,
            Pastor,
            WorshipLeader,
            FellowshipLeader,
            Member
        };
    }

    public class AppRole : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }

        [NotMapped]
        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public string Name { get; set; } = string.Empty;
        public string NormalizedName { get; set; } = string.Empty;

        public ICollection<AppUserRole> UserRoles { get; set; } = new List<AppUserRole>();
    }

    public class AppUserRole : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public Guid UserId { get; set; }
        public Guid RoleId { get; set; }

        public AppUser? User { get; set; }
        public AppRole? Role { get; set; }
    }
}
