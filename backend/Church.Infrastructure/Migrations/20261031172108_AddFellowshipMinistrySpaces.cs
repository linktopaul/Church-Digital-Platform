using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Church.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddFellowshipMinistrySpaces : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "FellowshipGroups",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    group_type = table.Column<string>(type: "text", nullable: false),
                    leader_id = table.Column<Guid>(type: "uuid", nullable: true),
                    leader_name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    meeting_schedule = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    location = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    is_private = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FellowshipGroups", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "FellowshipMembers",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    fellowship_group_id = table.Column<Guid>(type: "uuid", nullable: false),
                    member_id = table.Column<Guid>(type: "uuid", nullable: false),
                    member_name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    role = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    joined_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FellowshipMembers", x => x.id);
                    table.ForeignKey(
                        name: "FK_FellowshipMembers_FellowshipGroups_fellowship_group_id",
                        column: x => x.fellowship_group_id,
                        principalTable: "FellowshipGroups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "FellowshipPosts",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    fellowship_group_id = table.Column<Guid>(type: "uuid", nullable: false),
                    author_id = table.Column<Guid>(type: "uuid", nullable: false),
                    author_name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    title = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    content = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FellowshipPosts", x => x.id);
                    table.ForeignKey(
                        name: "FK_FellowshipPosts_FellowshipGroups_fellowship_group_id",
                        column: x => x.fellowship_group_id,
                        principalTable: "FellowshipGroups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipGroups_church_id",
                table: "FellowshipGroups",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipGroups_group_type",
                table: "FellowshipGroups",
                column: "group_type");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipMembers_church_id",
                table: "FellowshipMembers",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipMembers_fellowship_group_id",
                table: "FellowshipMembers",
                column: "fellowship_group_id");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipMembers_fellowship_group_id_member_id",
                table: "FellowshipMembers",
                columns: new[] { "fellowship_group_id", "member_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipPosts_church_id",
                table: "FellowshipPosts",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipPosts_created_at",
                table: "FellowshipPosts",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "IX_FellowshipPosts_fellowship_group_id",
                table: "FellowshipPosts",
                column: "fellowship_group_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "FellowshipMembers");

            migrationBuilder.DropTable(
                name: "FellowshipPosts");

            migrationBuilder.DropTable(
                name: "FellowshipGroups");
        }
    }
}
