using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GAS.Core
{
    public class OpenCodeAPIException : Exception
    {
        public int StatusCode { get; }
        public string RawBody { get; }

        public OpenCodeAPIException(int statusCode, string rawBody, string message)
            : base(message)
        {
            StatusCode = statusCode;
            RawBody = rawBody;
        }
    }

    public class OpenCodeSessionInfo
    {
        public string id { get; set; } = string.Empty;
        public string? title { get; set; }
    }

    public class OpenCodeEvent
    {
        public string type { get; set; } = string.Empty;
        public JsonElement properties { get; set; }

        public string? GetStringProperty(string propertyName)
        {
            if (properties.ValueKind == JsonValueKind.Object && properties.TryGetProperty(propertyName, out var val))
            {
                return val.GetString();
            }
            return null;
        }

        public string ExtractErrorMessage()
        {
            if (properties.ValueKind == JsonValueKind.Object)
            {
                if (properties.TryGetProperty("error", out var errObj))
                {
                    if (errObj.ValueKind == JsonValueKind.Object && errObj.TryGetProperty("message", out var msgVal))
                    {
                        return msgVal.GetString() ?? errObj.ToString();
                    }
                    if (errObj.ValueKind == JsonValueKind.String)
                    {
                        return errObj.GetString() ?? "Unknown session error";
                    }
                }
                if (properties.TryGetProperty("message", out var msgProp))
                {
                    return msgProp.GetString() ?? properties.ToString();
                }
                return properties.ToString();
            }
            return "Session error occurred";
        }
    }

    public class OpenCodeClient : IDisposable
    {
        private readonly HttpClient _httpClient;
        private readonly string _serverUrl;
        private CancellationTokenSource? _streamCts;

        public event Action<OpenCodeEvent>? EventReceived;
        public event Action<Exception>? ConnectionError;

        public OpenCodeClient(string serverUrl = "http://127.0.0.1:4096")
        {
            _serverUrl = serverUrl.TrimEnd('/');
            _httpClient = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        }

        /// <summary>
        /// Posts a request to create a new session on the OpenCode server.
        /// </summary>
        public async Task<OpenCodeSessionInfo> CreateSessionAsync(string? title = null, string? directory = null)
        {
            var url = $"{_serverUrl}/session";
            var payload = title != null ? (object)new { title } : new { };
            var responseJson = await PostJsonAsync(url, payload, directory);

            return JsonSerializer.Deserialize<OpenCodeSessionInfo>(responseJson) 
                   ?? throw new InvalidOperationException("Failed to decode session info.");
        }

        /// <summary>
        /// Aborts an active session on the OpenCode server.
        /// </summary>
        public async Task AbortSessionAsync(string sessionId, string? directory = null)
        {
            var url = $"{_serverUrl}/session/{sessionId}/abort";
            await PostJsonAsync(url, new { }, directory);
        }

        /// <summary>
        /// Sends a prompt to the specified session asynchronously (204 No Content).
        /// </summary>
        public async Task SendPromptAsync(
            string sessionId,
            string text,
            string directory,
            string? model = null,
            string? modelProviderID = null,
            string? agent = null)
        {
            var url = $"{_serverUrl}/session/{sessionId}/prompt_async";

            object? modelPayload = null;
            if (!string.IsNullOrWhiteSpace(model))
            {
                var trimmedModel = model.Trim();
                if (modelProviderID?.ToLowerInvariant() == "openrouter")
                {
                    modelPayload = new { providerID = "openrouter", modelID = trimmedModel };
                }
                else if (trimmedModel.Contains('/'))
                {
                    var parts = trimmedModel.Split('/', 2);
                    modelPayload = new { providerID = parts[0], modelID = parts[1] };
                }
                else if (!string.IsNullOrWhiteSpace(modelProviderID))
                {
                    modelPayload = new { providerID = modelProviderID.Trim(), modelID = trimmedModel };
                }
            }

            var bodyDict = new System.Collections.Generic.Dictionary<string, object>
            {
                ["parts"] = new[] { new { type = "text", text = text } }
            };

            if (!string.IsNullOrEmpty(agent))
            {
                bodyDict["agent"] = agent;
            }

            if (modelPayload != null)
            {
                bodyDict["model"] = modelPayload;
            }

            await PostJsonAsync(url, bodyDict, directory);
        }

        /// <summary>
        /// Starts streaming Server-Sent Events in a background task.
        /// </summary>
        public void StartStreaming(string directory)
        {
            StopStreaming();
            _streamCts = new CancellationTokenSource();
            var token = _streamCts.Token;

            Task.Run(async () =>
            {
                while (!token.IsCancellationRequested)
                {
                    try
                    {
                        var url = $"{_serverUrl}/event";
                        ExecutionLogger.LogRequest("GET", url, directory, null);

                        var request = new HttpRequestMessage(HttpMethod.Get, url);
                        request.Headers.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));
                        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };

                        if (!string.IsNullOrEmpty(directory))
                        {
                            request.Headers.Add("x-opencode-directory", directory);
                        }

                        using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
                        ExecutionLogger.LogResponse(url, (int)response.StatusCode, null);
                        response.EnsureSuccessStatusCode();

                        using var stream = await response.Content.ReadAsStreamAsync(token);
                        using var reader = new StreamReader(stream);

                        while (!reader.EndOfStream && !token.IsCancellationRequested)
                        {
                            var line = await reader.ReadLineAsync(token);
                            if (string.IsNullOrEmpty(line)) continue;

                            if (line.StartsWith("data:"))
                            {
                                var jsonStr = line.Substring(5).Trim();
                                try
                                {
                                    var ev = JsonSerializer.Deserialize<OpenCodeEvent>(jsonStr);
                                    if (ev != null)
                                    {
                                        ExecutionLogger.LogSSE(ev.type, jsonStr);
                                        EventReceived?.Invoke(ev);
                                    }
                                }
                                catch (Exception ex)
                                {
                                    ExecutionLogger.LogException($"SSE parse [{line}]", ex);
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        if (token.IsCancellationRequested) break;
                        ExecutionLogger.LogException("SSE Stream loop", ex);
                        ConnectionError?.Invoke(ex);
                        await Task.Delay(2000, token);
                    }
                }
            }, token);
        }

        /// <summary>
        /// Stops the background streaming task.
        /// </summary>
        public void StopStreaming()
        {
            _streamCts?.Cancel();
            _streamCts?.Dispose();
            _streamCts = null;
        }

        /// <summary>
        /// Sends a native permission reply response ("once", "always", or "reject").
        /// </summary>
        public async Task SendPermissionReplyAsync(string requestId, string reply, string? message = null, string? directory = null)
        {
            var url = $"{_serverUrl}/permission/{requestId}/reply";
            var wireReply = reply.ToLowerInvariant() switch
            {
                "allow" => "once",
                "once" => "once",
                "always" => "always",
                "deny" => "reject",
                "reject" => "reject",
                _ => "once"
            };

            object payload = !string.IsNullOrEmpty(message) ? new { reply = wireReply, message } : new { reply = wireReply };
            await PostJsonAsync(url, payload, directory);
        }

        /// <summary>
        /// Replies to an OpenCode native question tool request.
        /// </summary>
        public async Task ReplyToQuestionAsync(string requestId, string[][] answers, string? directory = null)
        {
            var url = $"{_serverUrl}/question/{requestId}/reply";
            var payload = new { answers };
            await PostJsonAsync(url, payload, directory);
        }

        /// <summary>
        /// Rejects an OpenCode native question tool request (user cancelled).
        /// </summary>
        public async Task RejectQuestionAsync(string requestId, string? directory = null)
        {
            var url = $"{_serverUrl}/question/{requestId}/reject";
            await PostJsonAsync(url, new { }, directory);
        }

        private async Task<string> PostJsonAsync(string url, object payload, string? directory)
        {
            var json = JsonSerializer.Serialize(payload);
            ExecutionLogger.LogRequest("POST", url, directory, json);

            var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };

            if (!string.IsNullOrEmpty(directory))
            {
                request.Headers.Add("x-opencode-directory", directory);
            }

            var response = await _httpClient.SendAsync(request);
            var responseBody = await response.Content.ReadAsStringAsync();
            var statusCode = (int)response.StatusCode;

            ExecutionLogger.LogResponse(url, statusCode, responseBody);

            if (!response.IsSuccessStatusCode)
            {
                string friendlyMessage = ExtractFriendlyErrorMessage(responseBody, statusCode);
                throw new OpenCodeAPIException(statusCode, responseBody, friendlyMessage);
            }

            return responseBody;
        }

        private static string ExtractFriendlyErrorMessage(string body, int statusCode)
        {
            if (string.IsNullOrWhiteSpace(body)) return $"HTTP {statusCode}: Empty response from OpenCode server";

            try
            {
                using var doc = JsonDocument.Parse(body);
                var root = doc.RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                {
                    if (root.TryGetProperty("error", out var errObj))
                    {
                        if (errObj.ValueKind == JsonValueKind.Object && errObj.TryGetProperty("message", out var msgVal))
                        {
                            return $"HTTP {statusCode}: {msgVal.GetString()}";
                        }
                    }
                    if (root.TryGetProperty("message", out var msgProp))
                    {
                        return $"HTTP {statusCode}: {msgProp.GetString()}";
                    }
                    if (root.TryGetProperty("data", out var dataObj) && dataObj.ValueKind == JsonValueKind.Object)
                    {
                        if (dataObj.TryGetProperty("message", out var dataMsg))
                        {
                            return $"HTTP {statusCode}: {dataMsg.GetString()}";
                        }
                    }
                }
            }
            catch
            {
                // Parse failure - return raw body
            }

            return $"HTTP {statusCode}: {body}";
        }

        public void Dispose()
        {
            StopStreaming();
            _httpClient.Dispose();
        }
    }
}
