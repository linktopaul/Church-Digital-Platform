using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;

namespace Church.Core
{
    public class AppUser : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }

        [NotMapped]
        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        public string Email { get; set; } = string.Empty;
        public string NormalizedEmail { get; set; } = string.Empty;
        public string PasswordHash { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public ICollection<AppUserRole> UserRoles { get; set; } = new List<AppUserRole>();
    }

    public class OidcAuthorizationCode : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public Guid UserId { get; set; }
        public string CodeHash { get; set; } = string.Empty;
        public string ClientId { get; set; } = string.Empty;
        public string RedirectUri { get; set; } = string.Empty;
        public string CodeChallenge { get; set; } = string.Empty;
        public string CodeChallengeMethod { get; set; } = "S256";
        public string Scope { get; set; } = string.Empty;
        public string? Nonce { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime ExpiresAt { get; set; }
        public DateTime? ConsumedAt { get; set; }
    }

    public class OidcRefreshToken : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public Guid UserId { get; set; }
        public Guid? AuthorizationCodeId { get; set; }
        public string TokenHash { get; set; } = string.Empty;
        public string ClientId { get; set; } = string.Empty;
        public string Scope { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime ExpiresAt { get; set; }
        public DateTime? ConsumedAt { get; set; }
        public DateTime? RevokedAt { get; set; }
        public string? ReplacedByTokenHash { get; set; }
    }
}
