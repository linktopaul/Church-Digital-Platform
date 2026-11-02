using System;

namespace Church.Core
{
    public class Member : IMultiTenantEntity
    {
        public Guid Id { get; set; } // Matches authenticated sub / NameIdentifier
        public Guid TenantId { get; set; }
        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }
        public string FirstName { get; set; } = string.Empty;
        public string LastName { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public string? AvatarUrl { get; set; }
        public DateTime? DateOfBirth { get; set; }
        public DateTime? AnniversaryDate { get; set; }
        public string? Address { get; set; }

        // Family Unit Association
        public Guid? FamilyId { get; set; }
        public Family? Family { get; set; }
        public FamilyRole FamilyRole { get; set; } = FamilyRole.Individual;

        // Privacy Visibility Controls (fail-closed private by default)
        public DirectoryVisibility DirectoryVisibility { get; set; } = DirectoryVisibility.Private;
        public bool ShowPhoneNumber { get; set; } = false;
        public bool ShowEmail { get; set; } = false;
        public bool ShowAddress { get; set; } = false;
        public bool ShowBirthDayAndMonth { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
