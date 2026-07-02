using System;
using System.IO;
using Microsoft.EntityFrameworkCore;
using Motive.Core.Models;

namespace Motive.Core.Data
{
    public class MotiveDbContext : DbContext
    {
        public DbSet<Session> Sessions { get; set; } = null!;
        public DbSet<LogEntry> LogEntries { get; set; } = null!;
        public DbSet<ScheduledTask> ScheduledTasks { get; set; } = null!;
        public DbSet<ScheduledTaskRun> ScheduledTaskRuns { get; set; } = null!;

        public MotiveDbContext()
        {
        }

        public MotiveDbContext(DbContextOptions<MotiveDbContext> options)
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

                var dbPath = Path.Combine(dir, "motive.db");
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
