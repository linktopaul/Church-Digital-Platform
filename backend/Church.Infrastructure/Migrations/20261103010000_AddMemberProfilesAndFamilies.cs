using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Church.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMemberProfilesAndFamilies : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Families",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    family_name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Families", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Members",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    first_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    last_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    email = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    phone_number = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    avatar_url = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    date_of_birth = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    anniversary_date = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    family_id = table.Column<Guid>(type: "uuid", nullable: true),
                    family_role = table.Column<string>(type: "text", nullable: false),
                    directory_visibility = table.Column<string>(type: "text", nullable: false),
                    show_phone_number = table.Column<bool>(type: "boolean", nullable: false),
                    show_email = table.Column<bool>(type: "boolean", nullable: false),
                    show_address = table.Column<bool>(type: "boolean", nullable: false),
                    show_birthday_and_month = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Members", x => x.id);
                    table.ForeignKey(
                        name: "FK_Members_Families_family_id",
                        column: x => x.family_id,
                        principalTable: "Families",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Families_church_id",
                table: "Families",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_Members_church_id",
                table: "Members",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_Members_family_id",
                table: "Members",
                column: "family_id");

            migrationBuilder.CreateIndex(
                name: "IX_Members_church_id_email",
                table: "Members",
                columns: new[] { "church_id", "email" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Members");

            migrationBuilder.DropTable(
                name: "Families");
        }
    }
}
