using System;
using System.Collections.Generic;

namespace Motive.Core.Models
{
    public class Session
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Intent { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public string? OpenCodeSessionId { get; set; }
        public SessionStatus Status { get; set; } = SessionStatus.Running;
        public string ProjectPath { get; set; } = string.Empty;

        // Navigation property for cascade delete relationship
        public List<LogEntry> Logs { get; set; } = new List<LogEntry>();

        public byte[]? MessagesData { get; set; }
        public int? ContextTokens { get; set; }
    }
}
