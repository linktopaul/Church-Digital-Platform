using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Church.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPrayerRequests : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PrayerRequests",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    member_id = table.Column<Guid>(type: "uuid", nullable: false),
                    content = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "CURRENT_TIMESTAMP"),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "CURRENT_TIMESTAMP")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PrayerRequests", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PrayerRequests_church_id",
                table: "PrayerRequests",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_PrayerRequests_member_id",
                table: "PrayerRequests",
                column: "member_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PrayerRequests");
        }
    }
}
