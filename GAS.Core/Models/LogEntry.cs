using System;

namespace GAS.Core.Models
{
    public class LogEntry
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string RawJson { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Foreign Key
        public Guid SessionId { get; set; }
        public Session Session { get; set; } = null!;
    }
}

