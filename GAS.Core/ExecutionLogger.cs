using System;
using System.IO;
using System.Text;

namespace GAS.Core
{
    public static class ExecutionLogger
    {
        private static readonly object LogLock = new();
        private static readonly string LogFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gas-execution-trace.log");

        public static void Log(string category, string message)
        {
            var formatted = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [{category}] {message}";
            System.Diagnostics.Debug.WriteLine(formatted);

            lock (LogLock)
            {
                try
                {
                    File.AppendAllText(LogFilePath, formatted + Environment.NewLine, Encoding.UTF8);
                }
                catch
                {
                    // Non-blocking log write fallback
                }
            }
        }

        public static void LogRequest(string method, string url, string? directory, string? jsonBody)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"--> HTTP {method} {url}");
            if (!string.IsNullOrEmpty(directory))
            {
                sb.AppendLine($"    Header x-opencode-directory: {directory}");
            }
            if (!string.IsNullOrEmpty(jsonBody))
            {
                sb.AppendLine($"    Body: {jsonBody}");
            }
            Log("HTTP_REQ", sb.ToString().TrimEnd());
        }

        public static void LogResponse(string url, int statusCode, string? responseBody)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"<-- HTTP {statusCode} for {url}");
            if (!string.IsNullOrEmpty(responseBody))
            {
                sb.AppendLine($"    Response Payload: {responseBody}");
            }
            Log("HTTP_RESP", sb.ToString().TrimEnd());
        }

        public static void LogSSE(string eventType, string rawJson)
        {
            Log("SSE_EVENT", $"Event: {eventType} | Data: {rawJson}");
        }

        public static void LogException(string context, Exception ex)
        {
            Log("ERROR", $"Exception in {context}: {ex.Message}\n{ex.StackTrace}");
        }
    }
}
