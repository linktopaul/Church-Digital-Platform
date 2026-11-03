using Church.Core;

using Microsoft.EntityFrameworkCore;

using System;



namespace Church.Infrastructure

{

    public class ApplicationDbContext : DbContext

    {

        private readonly ITenantService _tenantService;

        private Guid CurrentTenantId => _tenantService.GetCurrentTenantId();



        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options, ITenantService tenantService) : base(options)

        {

            _tenantService = tenantService;

        }



        public DbSet<Tenant> Tenants { get; set; }

        public DbSet<AppUser> AppUsers { get; set; }

        public DbSet<AppRole> AppRoles { get; set; }

        public DbSet<AppUserRole> AppUserRoles { get; set; }

        public DbSet<OidcAuthorizationCode> OidcAuthorizationCodes { get; set; }

        public DbSet<OidcRefreshToken> OidcRefreshTokens { get; set; }

        public DbSet<Announcement> Announcements { get; set; }

        public DbSet<PrayerRequest> PrayerRequests { get; set; }

        public DbSet<Song> Songs { get; set; }

        public DbSet<Setlist> Setlists { get; set; }

        public DbSet<SetlistItem> SetlistItems { get; set; }

        public DbSet<FellowshipGroup> FellowshipGroups { get; set; }

        public DbSet<FellowshipMember> FellowshipMembers { get; set; }

        public DbSet<FellowshipPost> FellowshipPosts { get; set; }

        public DbSet<Family> Families { get; set; }

        public DbSet<Member> Members { get; set; }

        public DbSet<Contribution> Contributions { get; set; }



        protected override void OnModelCreating(ModelBuilder modelBuilder)

        {

            base.OnModelCreating(modelBuilder);



            // Configure Tenant entity

            modelBuilder.Entity<Tenant>(entity =>

            {

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Name).IsRequired().HasMaxLength(255);

                entity.Property(e => e.Slug).IsRequired().HasMaxLength(100);

                entity.HasIndex(e => e.Slug).IsUnique();

                entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");

            });



            // Configure AppUser entity

            modelBuilder.Entity<AppUser>(entity =>

            {

                entity.ToTable("AppUsers");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.Email).HasColumnName("email").IsRequired().HasMaxLength(255);

                entity.Property(e => e.NormalizedEmail).HasColumnName("normalized_email").IsRequired().HasMaxLength(255);

                entity.Property(e => e.PasswordHash).HasColumnName("password_hash").IsRequired();

                entity.Property(e => e.DisplayName).HasColumnName("display_name").IsRequired().HasMaxLength(255);

                entity.Property(e => e.IsActive).HasColumnName("is_active").IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => new { e.TenantId, e.NormalizedEmail }).IsUnique();

            });



            // Configure AppRole entity

            modelBuilder.Entity<AppRole>(entity =>

            {

                entity.ToTable("AppRoles");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.Name).HasColumnName("name").IsRequired().HasMaxLength(100);

                entity.Property(e => e.NormalizedName).HasColumnName("normalized_name").IsRequired().HasMaxLength(100);



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => new { e.TenantId, e.NormalizedName }).IsUnique();

            });



            // Configure AppUserRole entity

            modelBuilder.Entity<AppUserRole>(entity =>

            {

                entity.ToTable("AppUserRoles");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Property(e => e.UserId).HasColumnName("user_id").IsRequired();

                entity.Property(e => e.RoleId).HasColumnName("role_id").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => new { e.UserId, e.RoleId }).IsUnique();



                entity.HasOne(e => e.User)

                    .WithMany(u => u.UserRoles)

                    .HasForeignKey(e => e.UserId)

                    .OnDelete(DeleteBehavior.Cascade);



                entity.HasOne(e => e.Role)

                    .WithMany(r => r.UserRoles)

                    .HasForeignKey(e => e.RoleId)

                    .OnDelete(DeleteBehavior.Cascade);

            });



            // Configure OidcAuthorizationCode entity

            modelBuilder.Entity<OidcAuthorizationCode>(entity =>

            {

                entity.ToTable("OidcAuthorizationCodes");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Property(e => e.UserId).HasColumnName("user_id").IsRequired();

                entity.Property(e => e.CodeHash).HasColumnName("code_hash").IsRequired().HasMaxLength(128);

                entity.Property(e => e.ClientId).HasColumnName("client_id").IsRequired().HasMaxLength(100);

                entity.Property(e => e.RedirectUri).HasColumnName("redirect_uri").IsRequired().HasMaxLength(500);

                entity.Property(e => e.CodeChallenge).HasColumnName("code_challenge").IsRequired().HasMaxLength(255);

                entity.Property(e => e.CodeChallengeMethod).HasColumnName("code_challenge_method").IsRequired().HasMaxLength(20);

                entity.Property(e => e.Scope).HasColumnName("scope").IsRequired().HasMaxLength(500);

                entity.Property(e => e.Nonce).HasColumnName("nonce").HasMaxLength(255);

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();

                entity.Property(e => e.ExpiresAt).HasColumnName("expires_at").IsRequired();

                entity.Property(e => e.ConsumedAt).HasColumnName("consumed_at");



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.CodeHash).IsUnique();

            });



            // Configure OidcRefreshToken entity

            modelBuilder.Entity<OidcRefreshToken>(entity =>

            {

                entity.ToTable("OidcRefreshTokens");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Property(e => e.UserId).HasColumnName("user_id").IsRequired();

                entity.Property(e => e.AuthorizationCodeId).HasColumnName("authorization_code_id");

                entity.Property(e => e.TokenHash).HasColumnName("token_hash").IsRequired().HasMaxLength(128);

                entity.Property(e => e.ClientId).HasColumnName("client_id").IsRequired().HasMaxLength(100);

                entity.Property(e => e.Scope).HasColumnName("scope").IsRequired().HasMaxLength(500);

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();

                entity.Property(e => e.ExpiresAt).HasColumnName("expires_at").IsRequired();

                entity.Property(e => e.ConsumedAt).HasColumnName("consumed_at");

                entity.Property(e => e.RevokedAt).HasColumnName("revoked_at");

                entity.Property(e => e.ReplacedByTokenHash).HasColumnName("replaced_by_token_hash").HasMaxLength(128);



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.TokenHash).IsUnique();

            });



            // Configure Announcement entity

            modelBuilder.Entity<Announcement>(entity =>

            {

                entity.ToTable("Announcements");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.AuthorId).HasColumnName("author_id").IsRequired();

                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Content).HasColumnName("content").IsRequired();

                entity.Property(e => e.Priority).HasColumnName("priority").HasConversion<string>().IsRequired();

                entity.Property(e => e.PublishedAt).HasColumnName("published_at").IsRequired();

                entity.Property(e => e.ExpiresAt).HasColumnName("expires_at");



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.PublishedAt);

            });



            // Configure PrayerRequest entity

            modelBuilder.Entity<PrayerRequest>(entity =>

            {

                entity.ToTable("PrayerRequests");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.MemberId).HasColumnName("member_id").IsRequired();

                entity.Property(e => e.Content).HasColumnName("content").IsRequired();

                entity.Property(e => e.Status).HasColumnName("status").HasConversion<string>().IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("CURRENT_TIMESTAMP");

                entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").HasDefaultValueSql("CURRENT_TIMESTAMP");



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.MemberId);

            });



            // Configure Song entity

            modelBuilder.Entity<Song>(entity =>

            {

                entity.ToTable("Songs");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Artist).HasColumnName("artist").HasMaxLength(255);

                entity.Property(e => e.DefaultKey).HasColumnName("default_key").HasMaxLength(10);

                entity.Property(e => e.TempoBpm).HasColumnName("tempo_bpm");

                entity.Property(e => e.Lyrics).HasColumnName("lyrics").IsRequired();

                entity.Property(e => e.Chords).HasColumnName("chords").IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.Title);

            });



            // Configure Setlist entity

            modelBuilder.Entity<Setlist>(entity =>

            {

                entity.ToTable("Setlists");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);

                entity.Property(e => e.ServiceDate).HasColumnName("service_date").IsRequired();

                entity.Property(e => e.Notes).HasColumnName("notes");

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.ServiceDate);



                entity.HasMany(e => e.Items)

                    .WithOne(i => i.Setlist!)

                    .HasForeignKey(i => i.SetlistId)

                    .OnDelete(DeleteBehavior.Cascade);

            });



            // Configure SetlistItem entity

            modelBuilder.Entity<SetlistItem>(entity =>

            {

                entity.ToTable("SetlistItems");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.SetlistId).HasColumnName("setlist_id").IsRequired();

                entity.Property(e => e.SongId).HasColumnName("song_id").IsRequired();

                entity.Property(e => e.Order).HasColumnName("order").IsRequired();

                entity.Property(e => e.KeyOverride).HasColumnName("key_override").HasMaxLength(10);

                entity.Property(e => e.Notes).HasColumnName("notes");



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.SetlistId);



                entity.HasOne(e => e.Song)

                    .WithMany()

                    .HasForeignKey(e => e.SongId)

                    .OnDelete(DeleteBehavior.Restrict);

            });



            // Configure FellowshipGroup entity

            modelBuilder.Entity<FellowshipGroup>(entity =>

            {

                entity.ToTable("FellowshipGroups");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.Name).HasColumnName("name").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Description).HasColumnName("description");

                entity.Property(e => e.GroupType).HasColumnName("group_type").HasConversion<string>().IsRequired();

                entity.Property(e => e.LeaderId).HasColumnName("leader_id");

                entity.Property(e => e.LeaderName).HasColumnName("leader_name").HasMaxLength(255);

                entity.Property(e => e.MeetingSchedule).HasColumnName("meeting_schedule").HasMaxLength(255);

                entity.Property(e => e.Location).HasColumnName("location").HasMaxLength(255);

                entity.Property(e => e.IsPrivate).HasColumnName("is_private").IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.GroupType);



                entity.HasMany(e => e.Members)

                    .WithOne(m => m.FellowshipGroup!)

                    .HasForeignKey(m => m.FellowshipGroupId)

                    .OnDelete(DeleteBehavior.Cascade);



                entity.HasMany(e => e.Posts)

                    .WithOne(p => p.FellowshipGroup!)

                    .HasForeignKey(p => p.FellowshipGroupId)

                    .OnDelete(DeleteBehavior.Cascade);

            });



            // Configure FellowshipMember entity

            modelBuilder.Entity<FellowshipMember>(entity =>

            {

                entity.ToTable("FellowshipMembers");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.FellowshipGroupId).HasColumnName("fellowship_group_id").IsRequired();

                entity.Property(e => e.MemberId).HasColumnName("member_id").IsRequired();

                entity.Property(e => e.MemberName).HasColumnName("member_name").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Role).HasColumnName("role").IsRequired().HasMaxLength(50);

                entity.Property(e => e.JoinedAt).HasColumnName("joined_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.FellowshipGroupId);

                entity.HasIndex(e => new { e.FellowshipGroupId, e.MemberId }).IsUnique();

            });



            // Configure FellowshipPost entity

            modelBuilder.Entity<FellowshipPost>(entity =>

            {

                entity.ToTable("FellowshipPosts");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.FellowshipGroupId).HasColumnName("fellowship_group_id").IsRequired();

                entity.Property(e => e.AuthorId).HasColumnName("author_id").IsRequired();

                entity.Property(e => e.AuthorName).HasColumnName("author_name").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);

                entity.Property(e => e.Content).HasColumnName("content").IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.FellowshipGroupId);

                entity.HasIndex(e => e.CreatedAt);

            });





            // Configure Family entity

            modelBuilder.Entity<Family>(entity =>

            {

                entity.ToTable("Families");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.FamilyName).HasColumnName("family_name").IsRequired().HasMaxLength(255);

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();



                entity.HasIndex(e => e.TenantId);



                entity.HasMany(f => f.Members)

                    .WithOne(m => m.Family)

                    .HasForeignKey(m => m.FamilyId)

                    .OnDelete(DeleteBehavior.SetNull);

            });



            // Configure Member entity

            modelBuilder.Entity<Member>(entity =>

            {

                entity.ToTable("Members");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();

                entity.Ignore(e => e.ChurchId);

                entity.Property(e => e.FirstName).HasColumnName("first_name").IsRequired().HasMaxLength(100);

                entity.Property(e => e.LastName).HasColumnName("last_name").IsRequired().HasMaxLength(100);

                entity.Property(e => e.Email).HasColumnName("email").IsRequired().HasMaxLength(255);

                entity.Property(e => e.PhoneNumber).HasColumnName("phone_number").HasMaxLength(50);

                entity.Property(e => e.AvatarUrl).HasColumnName("avatar_url").HasMaxLength(500);

                entity.Property(e => e.DateOfBirth).HasColumnName("date_of_birth");

                entity.Property(e => e.AnniversaryDate).HasColumnName("anniversary_date");

                entity.Property(e => e.Address).HasColumnName("address").HasMaxLength(500);

                entity.Property(e => e.FamilyId).HasColumnName("family_id");

                entity.Property(e => e.FamilyRole).HasColumnName("family_role").HasConversion<string>().IsRequired();

                entity.Property(e => e.DirectoryVisibility).HasColumnName("directory_visibility").HasConversion<string>().IsRequired();

                entity.Property(e => e.ShowPhoneNumber).HasColumnName("show_phone_number").IsRequired();

                entity.Property(e => e.ShowEmail).HasColumnName("show_email").IsRequired();

                entity.Property(e => e.ShowAddress).HasColumnName("show_address").IsRequired();

                entity.Property(e => e.ShowBirthDayAndMonth).HasColumnName("show_birthday_and_month").IsRequired();

                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();

                entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").IsRequired();



                entity.HasIndex(e => e.TenantId);

                entity.HasIndex(e => e.FamilyId);

                entity.HasIndex(e => new { e.TenantId, e.Email });

            });



            // Configure Contribution entity
            modelBuilder.Entity<Contribution>(entity =>
            {
                entity.ToTable("Contributions");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Property(e => e.MemberId).HasColumnName("member_id").IsRequired();
                entity.Property(e => e.MemberName).HasColumnName("member_name").HasMaxLength(255).IsRequired();
                entity.Property(e => e.FundType).HasColumnName("fund_type").IsRequired();
                entity.Property(e => e.Amount).HasColumnName("amount").HasPrecision(18, 2).IsRequired();
                entity.Property(e => e.Currency).HasColumnName("currency").HasMaxLength(10).IsRequired();
                entity.Property(e => e.TransactionReference).HasColumnName("transaction_reference").HasMaxLength(100);
                entity.Property(e => e.UpiPayeeId).HasColumnName("upi_payee_id").HasMaxLength(100).IsRequired();
                entity.Property(e => e.PaymentNote).HasColumnName("payment_note").HasMaxLength(500);
                entity.Property(e => e.Status).HasColumnName("status").IsRequired();
                entity.Property(e => e.VerifiedBy).HasColumnName("verified_by").HasMaxLength(255);
                entity.Property(e => e.VerifiedAt).HasColumnName("verified_at");
                entity.Property(e => e.ReceiptNumber).HasColumnName("receipt_number").HasMaxLength(50).IsRequired();
                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();
                entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").IsRequired();

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => new { e.TenantId, e.MemberId });
                entity.HasIndex(e => new { e.TenantId, e.Status });
                entity.HasIndex(e => new { e.TenantId, e.CreatedAt });
            });

            // Apply multi-tenancy filter to all entities implementing IMultiTenantEntity

            foreach (var entityType in modelBuilder.Model.GetEntityTypes())

            {

                if (typeof(IMultiTenantEntity).IsAssignableFrom(entityType.ClrType))

                {

                    modelBuilder.Entity(entityType.ClrType).HasQueryFilter(

                        ConvertFilterExpression<IMultiTenantEntity>(e => e.TenantId == CurrentTenantId, entityType.ClrType)

                    );

                }

            }

        }



        private static System.Linq.Expressions.LambdaExpression ConvertFilterExpression<TInterface>(

            System.Linq.Expressions.Expression<Func<TInterface, bool>> filterExpression, Type entityType)

        {

            var newParam = System.Linq.Expressions.Expression.Parameter(entityType);

            var newBody = ReplacingExpressionVisitor.Replace(filterExpression.Parameters[0], newParam, filterExpression.Body);

            return System.Linq.Expressions.Expression.Lambda(newBody, newParam);

        }

    }



    internal class ReplacingExpressionVisitor : System.Linq.Expressions.ExpressionVisitor

    {

        private readonly System.Linq.Expressions.Expression _oldValue;

        private readonly System.Linq.Expressions.Expression _newValue;



        public ReplacingExpressionVisitor(System.Linq.Expressions.Expression oldValue, System.Linq.Expressions.Expression newValue)

        {

            _oldValue = oldValue;

            _newValue = newValue;

        }



        public override System.Linq.Expressions.Expression Visit(System.Linq.Expressions.Expression node)

        {

            if (node == _oldValue)

                return _newValue;

            return base.Visit(node);

        }



        public static System.Linq.Expressions.Expression Replace(System.Linq.Expressions.Expression oldValue, System.Linq.Expressions.Expression newValue, System.Linq.Expressions.Expression expression)

        {

            return new ReplacingExpressionVisitor(oldValue, newValue).Visit(expression);

        }

    }

}

