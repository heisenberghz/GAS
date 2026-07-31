using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GAS.Core
{
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
            var response = await PostJsonAsync(url, payload, directory);
            response.EnsureSuccessStatusCode();

            var respJson = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<OpenCodeSessionInfo>(respJson) 
                   ?? throw new InvalidOperationException("Failed to decode session info.");
        }

        /// <summary>
        /// Aborts an active session on the OpenCode server.
        /// </summary>
        public async Task AbortSessionAsync(string sessionId, string? directory = null)
        {
            var url = $"{_serverUrl}/session/{sessionId}/abort";
            var response = await PostJsonAsync(url, new { }, directory);
            response.EnsureSuccessStatusCode();
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

            var response = await PostJsonAsync(url, bodyDict, directory);
            response.EnsureSuccessStatusCode();
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
                        var request = new HttpRequestMessage(HttpMethod.Get, url);
                        request.Headers.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));
                        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };

                        if (!string.IsNullOrEmpty(directory))
                        {
                            request.Headers.Add("x-opencode-directory", directory);
                        }

                        using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
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
                                        EventReceived?.Invoke(ev);
                                    }
                                }
                                catch (Exception ex)
                                {
                                    System.Diagnostics.Debug.WriteLine($"SSE parsing error: {ex.Message}");
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        if (token.IsCancellationRequested) break;
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
            object payload = !string.IsNullOrEmpty(message) ? new { reply, message } : new { reply };
            var response = await PostJsonAsync(url, payload, directory);
            response.EnsureSuccessStatusCode();
        }

        /// <summary>
        /// Replies to an OpenCode native question tool request.
        /// </summary>
        public async Task ReplyToQuestionAsync(string requestId, string[][] answers, string? directory = null)
        {
            var url = $"{_serverUrl}/question/{requestId}/reply";
            var payload = new { answers };
            var response = await PostJsonAsync(url, payload, directory);
            response.EnsureSuccessStatusCode();
        }

        /// <summary>
        /// Rejects an OpenCode native question tool request (user cancelled).
        /// </summary>
        public async Task RejectQuestionAsync(string requestId, string? directory = null)
        {
            var url = $"{_serverUrl}/question/{requestId}/reject";
            var response = await PostJsonAsync(url, new { }, directory);
            response.EnsureSuccessStatusCode();
        }

        private async Task<HttpResponseMessage> PostJsonAsync(string url, object payload, string? directory)
        {
            var json = JsonSerializer.Serialize(payload);
            var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };

            if (!string.IsNullOrEmpty(directory))
            {
                request.Headers.Add("x-opencode-directory", directory);
            }

            return await _httpClient.SendAsync(request);
        }

        public void Dispose()
        {
            StopStreaming();
            _httpClient.Dispose();
        }
    }
}
