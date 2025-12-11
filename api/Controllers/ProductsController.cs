using CsvHelper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using predicthrAPI.Data;
using predicthrAPI.Models;
using System.Data;
using System.Formats.Asn1;
using System.Globalization;

namespace predicthrAPI.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ProductsController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly IWebHostEnvironment _env;
        private readonly IConfiguration _config;

        public ProductsController(AppDbContext context, IWebHostEnvironment env, IConfiguration config)
        {
            _context = context;
            _env = env;
            _config = config;
        }

        // ================================================================
        // GET Flight Report
        // ================================================================
        [HttpGet("flight")]
        public async Task<IActionResult> GetFlightReport([FromQuery] string clientId)
        {
            if (string.IsNullOrWhiteSpace(clientId))
                return BadRequest("ClientId is required.");

            var result = await _context.FlightReportRecords
                .FromSqlRaw("EXEC dbo.usp_report_flight @client_id = {0}", clientId)
                .ToListAsync();

            return Ok(result);
        }

        // ================================================================
        // HYBRID CSV Loader
        // ================================================================
        [HttpPost("load-csv-hybrid")]
        [Consumes("multipart/form-data")]
        public async Task<IActionResult> LoadDataHybrid([FromForm] ClientUploadRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ClientId) ||
                request.CsvFile == null || request.CsvFile.Length == 0)
            {
                return BadRequest("Client ID and CSV file are required.");
            }

            string connectionKey = _config["ActiveConnection"];

            if (string.IsNullOrWhiteSpace(connectionKey))
                throw new Exception("ActiveConnection not configured!");

            string connString = _config.GetConnectionString(connectionKey);

            if (string.IsNullOrWhiteSpace(connString))
                throw new Exception($"Connection string '{connectionKey}' not found in appsettings.json");



            Guid batchId = Guid.NewGuid();

            try
            {
                // ====================================================
                // 1. BULK → attendance_staging
                // ====================================================
                using (var conn = new SqlConnection(connString))
                {
                    await conn.OpenAsync();

                    using (var bulk = new SqlBulkCopy(conn))
                    {
                        bulk.DestinationTableName = "dbo.attendance_staging";
                        bulk.BulkCopyTimeout = 0;

                        for (int i = 1; i <= 9; i++)
                        {
                            bulk.ColumnMappings.Add("t" + i, "t" + i);
                        }
                        bulk.ColumnMappings.Add("batch_id", "batch_id");
                        bulk.ColumnMappings.Add("client_id", "client_id");

                        // Build DataTable
                        DataTable table = new DataTable();
                        table.Columns.Add("batch_id", typeof(Guid));
                        table.Columns.Add("client_id", typeof(string));

                        for (int i = 1; i <= 9; i++)
                            table.Columns.Add("t" + i, typeof(string));

                        using var reader = new StreamReader(request.CsvFile.OpenReadStream());
                        using var csv = new CsvReader(reader, CultureInfo.InvariantCulture);

                        bool first = true;
                        while (await csv.ReadAsync())
                        {
                            if (first && request.HasHeader)
                            {
                                first = false;
                                continue;
                            }

                            DataRow row = table.NewRow();
                            row["batch_id"] = batchId;
                            row["client_id"] = request.ClientId;

                            for (int i = 1; i <= 9; i++)
                                row["t" + i] = csv.GetField(i - 1);

                            table.Rows.Add(row);

                            if (table.Rows.Count >= 5000)
                            {
                                await bulk.WriteToServerAsync(table);
                                table.Clear();
                            }
                        }

                        if (table.Rows.Count > 0)
                            await bulk.WriteToServerAsync(table);
                    }

                    // ====================================================
                    // 2. CALL Hybrid SP
                    // ====================================================
                    using var cmd = new SqlCommand("dbo.usp_load_client_data_v2", conn);
                    cmd.CommandType = CommandType.StoredProcedure;

                    cmd.Parameters.AddWithValue("@client_id", request.ClientId);
                    cmd.Parameters.AddWithValue("@batch_id", batchId);
                    cmd.Parameters.AddWithValue("@has_header", request.HasHeader);
                    cmd.Parameters.AddWithValue("@date_format", request.DateFormat ?? "auto");

                    await cmd.ExecuteNonQueryAsync();
                }

                return Accepted(new
                {
                    clientId = request.ClientId,
                    batchId,
                    message = "Hybrid load completed."
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }
    }
}
