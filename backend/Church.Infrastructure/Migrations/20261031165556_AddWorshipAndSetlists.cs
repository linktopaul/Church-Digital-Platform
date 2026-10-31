using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Church.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddWorshipAndSetlists : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Setlists",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    service_date = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Setlists", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Songs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    artist = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    default_key = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    tempo_bpm = table.Column<int>(type: "integer", nullable: true),
                    lyrics = table.Column<string>(type: "text", nullable: false),
                    chords = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Songs", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "SetlistItems",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    setlist_id = table.Column<Guid>(type: "uuid", nullable: false),
                    song_id = table.Column<Guid>(type: "uuid", nullable: false),
                    order = table.Column<int>(type: "integer", nullable: false),
                    key_override = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SetlistItems", x => x.id);
                    table.ForeignKey(
                        name: "FK_SetlistItems_Setlists_setlist_id",
                        column: x => x.setlist_id,
                        principalTable: "Setlists",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_SetlistItems_Songs_song_id",
                        column: x => x.song_id,
                        principalTable: "Songs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SetlistItems_church_id",
                table: "SetlistItems",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_SetlistItems_setlist_id",
                table: "SetlistItems",
                column: "setlist_id");

            migrationBuilder.CreateIndex(
                name: "IX_SetlistItems_song_id",
                table: "SetlistItems",
                column: "song_id");

            migrationBuilder.CreateIndex(
                name: "IX_Setlists_church_id",
                table: "Setlists",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_Setlists_service_date",
                table: "Setlists",
                column: "service_date");

            migrationBuilder.CreateIndex(
                name: "IX_Songs_church_id",
                table: "Songs",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_Songs_title",
                table: "Songs",
                column: "title");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SetlistItems");

            migrationBuilder.DropTable(
                name: "Setlists");

            migrationBuilder.DropTable(
                name: "Songs");
        }
    }
}
