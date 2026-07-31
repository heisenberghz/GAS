namespace GAS.Core.Models
{
    public enum SessionStatus
    {
        Idle,
        Running,
        Completed,
        Failed,
        Interrupted
    }

    public enum MessageStatus
    {
        Pending,
        Running,
        Completed,
        Failed
    }

    public enum OpenCodeEventType
    {
        SessionUpdated,
        SessionCompleted,
        MessageCreated,
        MessageUpdated,
        MessageCompleted,
        MessagePartCreated,
        MessagePartUpdated,
        MessagePartDelta,
        MessagePartCompleted,
        ToolStarted,
        ToolCompleted,
        QuestionRequested,
        PermissionRequested,
        AuthError,
        SessionBind,
        Unknown
    }

    public enum ScheduledTaskScheduleType
    {
        Once,
        Interval,
        Daily,
        Weekly,
        Cron
    }

    public enum ScheduledTaskRunStatus
    {
        Submitted,
        Skipped,
        Failed
    }
}

