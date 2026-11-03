using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Church.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddDigitalOfferingsAndLedger : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Contributions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    church_id = table.Column<Guid>(type: "uuid", nullable: false),
                    member_id = table.Column<Guid>(type: "uuid", nullable: false),
                    member_name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    fund_type = table.Column<int>(type: "integer", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    currency = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    transaction_reference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    upi_payee_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    payment_note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    verified_by = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    verified_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    receipt_number = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Contributions", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Contributions_church_id",
                table: "Contributions",
                column: "church_id");

            migrationBuilder.CreateIndex(
                name: "IX_Contributions_church_id_created_at",
                table: "Contributions",
                columns: new[] { "church_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "IX_Contributions_church_id_member_id",
                table: "Contributions",
                columns: new[] { "church_id", "member_id" });

            migrationBuilder.CreateIndex(
                name: "IX_Contributions_church_id_status",
                table: "Contributions",
                columns: new[] { "church_id", "status" });

            migrationBuilder.CreateIndex(
                name: "IX_Contributions_receipt_number",
                table: "Contributions",
                column: "receipt_number",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Contributions");
        }
    }
}
