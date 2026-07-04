using System;

namespace Motive.Core.Models
{
    public class ScheduledTaskRun
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public Guid TaskId { get; set; }
        public DateTime TriggeredAt { get; set; } = DateTime.UtcNow;
        public ScheduledTaskRunStatus Status { get; set; } = ScheduledTaskRunStatus.Submitted;
        public string? SessionId { get; set; }
        public string? ErrorMessage { get; set; }
        public int? DurationMs { get; set; }
    }
}
