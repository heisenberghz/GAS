using System;

namespace GAS.Core.Models
{
    public class ScheduledTask
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Name { get; set; } = string.Empty;
        public string Prompt { get; set; } = string.Empty;
        public ScheduledTaskScheduleType ScheduleType { get; set; } = ScheduledTaskScheduleType.Once;
        public string SchedulePayload { get; set; } = string.Empty; // JSON settings
        public string TimezoneIdentifier { get; set; } = string.Empty;
        public bool IsEnabled { get; set; } = true;
        public string? ProjectPath { get; set; }
        public string? Agent { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? LastRunAt { get; set; }
        public DateTime? NextRunAt { get; set; }
        public string? LastError { get; set; }
    }
}

