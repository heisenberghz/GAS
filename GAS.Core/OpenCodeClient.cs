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
            _httpClient = new HttpClient();
            _httpClient.Timeout = Timeout.InfiniteTimeSpan;
        }

        /// <summary>
        /// Posts a request to create a new session on the OpenCode server.
        /// </summary>
        public async Task<OpenCodeSessionInfo> CreateSessionAsync(string? title = null)
        {
            var url = $"{_serverUrl}/session";
            var payload = new { title };
            var json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var response = await _httpClient.PostAsync(url, content);
            response.EnsureSuccessStatusCode();

            var respJson = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<OpenCodeSessionInfo>(respJson) 
                   ?? throw new InvalidOperationException("Failed to decode session info.");
        }

        /// <summary>
        /// Sends a prompt to the specified session. Returns immediately.
        /// </summary>
        public async Task SendPromptAsync(string sessionId, string text, string directory)
        {
            var url = $"{_serverUrl}/session/{sessionId}/prompt_async";
            var payload = new
            {
                parts = new[]
                {
                    new { type = "text", text = text }
                }
            };
            var json = JsonSerializer.Serialize(payload);
            var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            
            if (!string.IsNullOrEmpty(directory))
            {
                request.Headers.Add("x-opencode-directory", directory);
            }

            var response = await _httpClient.SendAsync(request);
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
                        // Backoff before reconnecting
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

        public void Dispose()
        {
            StopStreaming();
            _httpClient.Dispose();
        }
    }
}

