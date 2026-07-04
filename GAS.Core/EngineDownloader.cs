using System;
using System.IO;
using System.IO.Compression;
using System.Formats.Tar;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace GAS.Core
{
    public class EngineDownloader
    {
        public event Action<double>? ProgressChanged;
        public event Action<string>? StatusChanged;

        public async Task DownloadAsync()
        {
            StatusChanged?.Invoke("Checking latest version...");
            ProgressChanged?.Invoke(0);

            using var client = new HttpClient();
            // User-Agent header is required by npm registry
            client.DefaultRequestHeaders.Add("User-Agent", "GAS-App-Downloader");

            string tarballUrl;
            try
            {
                var responseString = await client.GetStringAsync("https://registry.npmjs.org/opencode-win32-x64/latest");
                using var doc = JsonDocument.Parse(responseString);
                var root = doc.RootElement;
                if (root.TryGetProperty("dist", out var dist) && dist.TryGetProperty("tarball", out var tarball))
                {
                    tarballUrl = tarball.GetString() ?? throw new Exception("Tarball URL not found in metadata");
                }
                else
                {
                    throw new Exception("Invalid response from NPM registry");
                }
            }
            catch (Exception ex)
            {
                throw new Exception($"Failed to resolve latest package version: {ex.Message}", ex);
            }

            StatusChanged?.Invoke("Downloading AI engine...");
            ProgressChanged?.Invoke(10);

            var tempTgzPath = Path.Combine(BinaryManager.AppSupportDirectory, "opencode_temp.tgz");
            if (!Directory.Exists(BinaryManager.AppSupportDirectory))
            {
                Directory.CreateDirectory(BinaryManager.AppSupportDirectory);
            }

            try
            {
                // Download tarball with progress tracking
                using (var response = await client.GetAsync(tarballUrl, HttpCompletionOption.ResponseHeadersRead))
                {
                    response.EnsureSuccessStatusCode();
                    var totalBytes = response.Content.Headers.ContentLength ?? -1L;
                    
                    using var contentStream = await response.Content.ReadAsStreamAsync();
                    using var fileStream = new FileStream(tempTgzPath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);
                    
                    var buffer = new byte[8192];
                    var totalRead = 0L;
                    int bytesRead;
                    while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                    {
                        await fileStream.WriteAsync(buffer, 0, bytesRead);
                        totalRead += bytesRead;
                        if (totalBytes > 0)
                        {
                            // Map progress to 10% - 80% range for downloading phase
                            var progress = 10 + ((double)totalRead / totalBytes) * 70;
                            ProgressChanged?.Invoke(progress);
                        }
                    }
                }

                StatusChanged?.Invoke("Extracting files...");
                ProgressChanged?.Invoke(85);

                var destPath = Path.Combine(BinaryManager.AppSupportDirectory, "opencode.exe");
                if (File.Exists(destPath))
                {
                    File.Delete(destPath);
                }

                // Decompress tgz and extract opencode.exe
                using (var fileStream = new FileStream(tempTgzPath, FileMode.Open, FileAccess.Read))
                using (var gzipStream = new GZipStream(fileStream, CompressionMode.Decompress))
                using (var tarReader = new TarReader(gzipStream))
                {
                    bool found = false;
                    while (await tarReader.GetNextEntryAsync() is TarEntry entry)
                    {
                        // Check if entry is a file and ends with opencode.exe
                        if (entry.EntryType == TarEntryType.RegularFile && entry.Name.EndsWith("opencode.exe", StringComparison.OrdinalIgnoreCase))
                        {
                            await entry.ExtractToFileAsync(destPath, overwrite: true);
                            found = true;
                            break;
                        }
                    }

                    if (!found)
                    {
                        throw new Exception("opencode.exe was not found inside the downloaded archive.");
                    }
                }

                ProgressChanged?.Invoke(100);
                StatusChanged?.Invoke("Done!");
            }
            finally
            {
                if (File.Exists(tempTgzPath))
                {
                    try
                    {
                        File.Delete(tempTgzPath);
                    }
                    catch
                    {
                        // Ignore cleanup errors
                    }
                }
            }
        }
    }
}
