using System;
using System.IO;
using Microsoft.EntityFrameworkCore;
using GAS.Core.Models;

namespace GAS.Core.Data
{
    public class GASDbContext : DbContext
    {
        public DbSet<Session> Sessions { get; set; } = null!;
        public DbSet<LogEntry> LogEntries { get; set; } = null!;
        public DbSet<ScheduledTask> ScheduledTasks { get; set; } = null!;
        public DbSet<ScheduledTaskRun> ScheduledTaskRuns { get; set; } = null!;

        public GASDbContext()
        {
        }

        public GASDbContext(DbContextOptions<GASDbContext> options)
            : base(options)
        {
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
                var dir = BinaryManager.AppSupportDirectory;
                
                // Ensure AppData directory exists
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                var dbPath = Path.Combine(dir, "GAS.db");
                optionsBuilder.UseSqlite($"Data Source={dbPath}");
            }
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Configure Session -> LogEntry Cascade Delete relationship
            modelBuilder.Entity<Session>()
                .HasMany(s => s.Logs)
                .WithOne(l => l.Session)
                .HasForeignKey(l => l.SessionId)
                .OnDelete(DeleteBehavior.Cascade);

            // Configure Indexes
            modelBuilder.Entity<Session>()
                .HasIndex(s => s.CreatedAt);

            modelBuilder.Entity<LogEntry>()
                .HasIndex(l => l.CreatedAt);

            modelBuilder.Entity<ScheduledTask>()
                .HasIndex(t => t.NextRunAt);

            modelBuilder.Entity<ScheduledTaskRun>()
                .HasIndex(r => r.TriggeredAt);
        }
    }
}

