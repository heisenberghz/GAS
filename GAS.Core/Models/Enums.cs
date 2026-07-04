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

