using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

using System.Text.Json.Serialization;

namespace GAS.Core
{
    // ─────────────────────────────────────────────────────────────
    //  Strongly-typed Payload Models for UI Events
    // ─────────────────────────────────────────────────────────────

    public class UserTurnPayload
    {
        [JsonPropertyName("text")]
        public string Text { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public string Timestamp { get; set; } = string.Empty;
    }

    public class TextPartPayload
    {
        [JsonPropertyName("partID")]
        public string PartID { get; set; } = string.Empty;

        [JsonPropertyName("delta")]
        public string Delta { get; set; } = string.Empty;

        [JsonPropertyName("fullText")]
        public string FullText { get; set; } = string.Empty;

        [JsonPropertyName("isReasoning")]
        public bool IsReasoning { get; set; }

        [JsonPropertyName("isFinalized")]
        public bool IsFinalized { get; set; }
    }

    public class ToolPartPayload
    {
        [JsonPropertyName("toolID")]
        public string ToolID { get; set; } = string.Empty;

        [JsonPropertyName("toolName")]
        public string ToolName { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public string Status { get; set; } = string.Empty;

        [JsonPropertyName("displayLabel")]
        public string DisplayLabel { get; set; } = string.Empty;

        [JsonPropertyName("icon")]
        public string Icon { get; set; } = "⚙️";

        [JsonPropertyName("formattedOutput")]
        public string FormattedOutput { get; set; } = string.Empty;
    }

    // ─────────────────────────────────────────────────────────────
    //  Conversation State Machine
    // ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Manages the state of active conversation turns, cleans up raw SSE events,
    /// suppresses prompt echoes, normalizes tool outputs, and emits clean payloads to UI listeners.
    /// </summary>
    public class ConversationState
    {
        // ── Events ───────────────────────────────────────────────────
        public event Action<UserTurnPayload>? OnUserTurnAdded;
        public event Action? OnAgentTurnStarted;
        public event Action<TextPartPayload>? OnTextPartUpdated;
        public event Action<ToolPartPayload>? OnToolPartUpdated;
        public event Action? OnConversationCleared;

        // ── Active State ─────────────────────────────────────────────
        private string _lastUserPrompt = string.Empty;
        private bool _agentTurnActive = false;

        // Part tracking: PartID -> accumulated text/tool details
        private readonly Dictionary<string, string> _textParts = new();
        private readonly Dictionary<string, string> _reasoningParts = new();
        private readonly Dictionary<string, ToolPartPayload> _toolParts = new();

        public void Clear()
        {
            _lastUserPrompt = string.Empty;
            _agentTurnActive = false;
            _textParts.Clear();
            _reasoningParts.Clear();
            _toolParts.Clear();
            OnConversationCleared?.Invoke();
        }

        public void AddUserTurn(string prompt, string? timestamp = null)
        {
            _lastUserPrompt = (prompt ?? string.Empty).Trim();
            _agentTurnActive = false;
            _textParts.Clear();
            _reasoningParts.Clear();
            _toolParts.Clear();

            OnUserTurnAdded?.Invoke(new UserTurnPayload
            {
                Text = prompt ?? string.Empty,
                Timestamp = timestamp ?? DateTime.Now.ToString("h:mm tt")
            });
        }

        public void ProcessEvent(OpenCodeEvent ev)
        {
            if (ev == null) return;

            switch (ev.type)
            {
                case "message.part.delta":
                    HandlePartDelta(ev.properties);
                    break;
                case "message.part.updated":
                    HandlePartUpdated(ev.properties);
                    break;
                case "session.error":
                case "auth.error":
                case "engine.error":
                    EnsureAgentTurnStarted();
                    var errId = "err_" + Guid.NewGuid().ToString("N")[..8];
                    OnTextPartUpdated?.Invoke(new TextPartPayload
                    {
                        PartID = errId,
                        FullText = $"⚠️ **Error** `{ev.type}`: {ev.ExtractErrorMessage()}",
                        IsReasoning = false,
                        IsFinalized = true
                    });
                    break;
            }
        }

        private void EnsureAgentTurnStarted()
        {
            if (!_agentTurnActive)
            {
                _agentTurnActive = true;
                OnAgentTurnStarted?.Invoke();
            }
        }

        private void HandlePartDelta(JsonElement props)
        {
            var partID = GetStr(props, "partID");
            var field  = GetStr(props, "field");
            var delta  = GetStr(props, "delta");
            if (string.IsNullOrEmpty(partID) || string.IsNullOrEmpty(delta)) return;

            EnsureAgentTurnStarted();

            bool isReasoning = field == "reasoning";
            var targetDict   = isReasoning ? _reasoningParts : _textParts;

            if (!targetDict.ContainsKey(partID))
                targetDict[partID] = string.Empty;

            targetDict[partID] += delta;
            var currentFull = targetDict[partID];

            // Filter out prompt echoes in initial text part
            if (!isReasoning && IsPromptEcho(currentFull))
            {
                return;
            }

            OnTextPartUpdated?.Invoke(new TextPartPayload
            {
                PartID = partID,
                Delta = delta,
                FullText = currentFull,
                IsReasoning = isReasoning,
                IsFinalized = false
            });
        }

        private void HandlePartUpdated(JsonElement props)
        {
            var part = props.TryGetProperty("part", out var p) ? p : props;
            var type = GetStr(part, "type");
            var id   = GetStr(part, "id") ?? GetStr(props, "partID");
            if (string.IsNullOrEmpty(id)) return;

            EnsureAgentTurnStarted();

            if (type == "text" || type == "reasoning")
            {
                bool isReasoning = type == "reasoning";
                var text = GetStr(part, "text") ?? string.Empty;

                if (!isReasoning && IsPromptEcho(text))
                {
                    return;
                }

                var targetDict = isReasoning ? _reasoningParts : _textParts;
                targetDict[id] = text;

                OnTextPartUpdated?.Invoke(new TextPartPayload
                {
                    PartID = id,
                    FullText = text,
                    IsReasoning = isReasoning,
                    IsFinalized = true
                });
            }
            else if (type == "tool")
            {
                var state    = part.TryGetProperty("state", out var s) ? s : part;
                var rawName  = GetStr(state, "tool") ?? GetStr(state, "name") ?? "Tool";
                var status   = GetStr(state, "status") ?? "running";
                var input    = state.TryGetProperty("input",  out var inp) ? SafeStr(inp)  : null;
                var output   = state.TryGetProperty("output", out var out_) ? SafeStr(out_) : null;

                var normalized = NormalizeToolPart(id, rawName, status, input, output);
                _toolParts[id] = normalized;

                OnToolPartUpdated?.Invoke(normalized);
            }
        }

        private bool IsPromptEcho(string text)
        {
            if (string.IsNullOrWhiteSpace(_lastUserPrompt) || string.IsNullOrWhiteSpace(text))
                return false;

            var trimmedText = text.Trim();
            if (trimmedText.Equals(_lastUserPrompt, StringComparison.OrdinalIgnoreCase))
                return true;

            if (_lastUserPrompt.StartsWith(trimmedText, StringComparison.OrdinalIgnoreCase) && trimmedText.Length > 5)
                return true;

            return false;
        }

        // ─────────────────────────────────────────────────────────────
        //  Tool Output Normalizer
        // ─────────────────────────────────────────────────────────────

        public static ToolPartPayload NormalizeToolPart(string id, string rawName, string status, string? input, string? output)
        {
            var (icon, label) = GetToolMeta(rawName);
            var rawContent    = output ?? input ?? string.Empty;
            var formatted     = FormatToolContent(rawContent);

            return new ToolPartPayload
            {
                ToolID          = id,
                ToolName        = rawName,
                Status          = status,
                DisplayLabel    = label,
                Icon            = icon,
                FormattedOutput = formatted
            };
        }

        private static (string icon, string label) GetToolMeta(string name)
        {
            var n = (name ?? string.Empty).ToLowerInvariant();
            if (n.Contains("read"))   return ("📄", "Reading file");
            if (n.Contains("write"))  return ("✏️", "Writing file");
            if (n.Contains("create")) return ("📝", "Creating file");
            if (n.Contains("delete")) return ("🗑️", "Deleting");
            if (n.Contains("list") || n.Contains("dir")) return ("📁", "Listing directory");
            if (n.Contains("search") || n.Contains("grep")) return ("🔍", "Searching");
            if (n.Contains("bash") || n.Contains("run") || n.Contains("exec") || n.Contains("command")) return ("⚡", "Running command");
            if (n.Contains("browser")) return ("🌐", "Browser");
            if (n.Contains("git"))    return ("🔀", "Git");
            if (n.Contains("patch") || n.Contains("edit")) return ("✏️", "Editing file");
            return ("⚙️", string.IsNullOrEmpty(name) ? "Tool" : name);
        }

        private static string FormatToolContent(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "No output details";
            var str = raw.Trim();

            // XML format from OpenCode tool output
            if (str.Contains("<path>") || str.Contains("<entries>") || str.Contains("<content>"))
            {
                var sb = new System.Text.StringBuilder();

                var pathMatch    = Regex.Match(str, @"<path>([\s\S]*?)<\/path>", RegexOptions.IgnoreCase);
                var typeMatch    = Regex.Match(str, @"<type>([\s\S]*?)<\/type>", RegexOptions.IgnoreCase);
                var entriesMatch = Regex.Match(str, @"<entries>([\s\S]*?)<\/entries>", RegexOptions.IgnoreCase);
                var contentMatch = Regex.Match(str, @"<content>([\s\S]*?)<\/content>", RegexOptions.IgnoreCase);

                if (pathMatch.Success) sb.AppendLine($"Path: {pathMatch.Groups[1].Value.Trim()}");
                if (typeMatch.Success) sb.AppendLine($"Type: {typeMatch.Groups[1].Value.Trim()}");

                if (entriesMatch.Success)
                {
                    var items = Regex.Split(entriesMatch.Groups[1].Value.Trim(), @"\s+")
                                     .Where(i => !string.IsNullOrWhiteSpace(i)).ToList();
                    sb.AppendLine($"\nEntries ({items.Count}):");
                    foreach (var item in items)
                        sb.AppendLine($"  • {item}");
                }
                else if (contentMatch.Success)
                {
                    sb.AppendLine($"\nContent:\n{contentMatch.Groups[1].Value.Trim()}");
                }
                else
                {
                    var clean = Regex.Replace(str, @"<[^>]+>", "").Trim();
                    if (!string.IsNullOrEmpty(clean))
                        sb.AppendLine($"\n{clean}");
                }

                return sb.ToString().Trim();
            }

            // JSON format
            if ((str.StartsWith("{") && str.EndsWith("}")) || (str.StartsWith("[") && str.EndsWith("]")))
            {
                try
                {
                    using var doc = JsonDocument.Parse(str);
                    return JsonSerializer.Serialize(doc, new JsonSerializerOptions { WriteIndented = true });
                }
                catch { }
            }

            return str;
        }

        // ─────────────────────────────────────────────────────────────
        //  JSON parsing helpers
        // ─────────────────────────────────────────────────────────────
        private static string? GetStr(JsonElement el, string key) =>
            el.TryGetProperty(key, out var v) ? v.GetString() : null;

        private static string? SafeStr(JsonElement el) =>
            el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
    }
}
