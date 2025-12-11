using Microsoft.EntityFrameworkCore;
using predicthrAPI.Models;


namespace predicthrAPI.Data
{
    public class AppDbContext : DbContext
    {
        public DbSet<FlightReportRecord> FlightReportRecords { get; set; }


        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {

        }

        // ⭐ This is the crucial part that resolves the 500 error ⭐
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            // 1. Identify the model that the Stored Procedure maps to
            // 2. Call .HasNoKey() to mark it as a Keyless Entity Type
            //    This tells EF Core not to look for a Primary Key, as it's only 
            //    used for query results, not database manipulation.
            modelBuilder.Entity<FlightReportRecord>().HasNoKey();

            // Always call the base implementation at the end (if you add more configuration)
            base.OnModelCreating(modelBuilder);
        }


    }
}
