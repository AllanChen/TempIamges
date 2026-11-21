using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Glance.Core.Account;
using Glance.Core.Logging;
using Glance.Core.Widgets;

namespace Glance.Core.Tasks;

/// <summary>
/// Widget task HTTP calls (port of macOS <c>WidgetTaskClient</c>, base <c>/api/v2</c>, bearer token):
/// uploads, create (with <c>Idempotency-Key</c>), poll, cancel, settle / abandon, result links and
/// result downloads. 40 s per request.
/// </summary>
public sealed class WidgetTaskClient(HttpClient http, AuthService auth, WidgetRegistry registry)
{
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(40);
    private static readonly TimeSpan TransferTimeout = TimeSpan.FromSeconds(180);

    /// <summary>The service's idea of the user's country (<c>GET /location</c>), "Unknown" on failure.</summary>
    public async Task<string> FetchCountryAsync(CancellationToken ct)
    {
        try
        {
            var result = await SendAsync(HttpMethod.Get, "/location", null, ct, timeout: TimeSpan.FromSeconds(5)).ConfigureAwait(false);
            var location = ApiEnvelope.Text(result?["location"]);
            return location is null or "Unknown" ? "Unknown" : location;
        }
        catch (WidgetTaskException)
        {
            return "Unknown";
        }
    }

    /// <summary>Uploads one local file (<c>POST /uploads</c>, multipart <c>file</c>) and returns its URL. Retries twice on network errors.</summary>
    public async Task<string> UploadAsync(string path, CancellationToken ct)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                await using var stream = File.OpenRead(path);
                using var content = new MultipartFormDataContent($"Boundary-{Guid.NewGuid()}");
                var file = new StreamContent(stream);
                file.Headers.ContentType = new MediaTypeHeaderValue(MimeTypes.ForPath(path));
                content.Add(file, "file", Path.GetFileName(path));
                var result = await SendAsync(HttpMethod.Post, "/uploads", content, ct, timeout: TransferTimeout).ConfigureAwait(false);
                return ApiEnvelope.Text(result?["url"]) ?? throw new WidgetTaskException("Could not read server response.", "bad_response");
            }
            catch (WidgetTaskException ex) when (ex.Code == "network" && attempt < 2)
            {
                Log.Info($"WidgetTaskClient: upload retry {attempt + 1}: {ex.Message}");
                await Task.Delay(TimeSpan.FromSeconds(attempt + 1), ct).ConfigureAwait(false);
            }
        }
    }

    public async Task<WidgetTaskResult> CreateAsync(JsonObject body, string requestKey, string widgetId, CancellationToken ct)
    {
        try
        {
            var content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
            var result = await SendAsync(HttpMethod.Post, "/tasks", content, ct, idempotencyKey: requestKey).ConfigureAwait(false);
            return WidgetTaskResult.From(result);
        }
        catch (WidgetTaskException ex) when (ex.Status == 429)
        {
            throw new WidgetTaskException("The service is busy right now. Please try again later.", "service_busy", 429);
        }
        catch (WidgetTaskException ex) when (ex.Code is "widget_unavailable" or "widget_not_found")
        {
            registry.MarkDelisted(widgetId);
            throw new WidgetTaskException("This Widget is no longer available.", ex.Code, ex.Status);
        }
    }

    public async Task<WidgetTaskResult> GetAsync(string taskId, CancellationToken ct) =>
        WidgetTaskResult.From(await SendAsync(HttpMethod.Get, $"/tasks/{Uri.EscapeDataString(taskId)}", null, ct).ConfigureAwait(false));

    public async Task CancelAsync(string taskId)
    {
        try
        {
            await SendAsync(HttpMethod.Delete, $"/tasks/{Uri.EscapeDataString(taskId)}", null, CancellationToken.None).ConfigureAwait(false);
        }
        catch (WidgetTaskException ex)
        {
            Log.Info($"WidgetTaskClient: cancel request failed: {ex.Message}");
        }
    }

    public async Task<WidgetTaskResult> SettleAsync(string taskId, CancellationToken ct)
    {
        var content = new StringContent("{\"outcome\":\"delivered\"}", Encoding.UTF8, "application/json");
        return WidgetTaskResult.From(await SendAsync(HttpMethod.Post, $"/tasks/{Uri.EscapeDataString(taskId)}/settle", content, ct).ConfigureAwait(false));
    }

    public async Task<WidgetTaskResult> AbandonAsync(string requestKey, CancellationToken ct)
    {
        var content = new StringContent("{\"outcome\":\"failed\"}", Encoding.UTF8, "application/json");
        return WidgetTaskResult.From(await SendAsync(HttpMethod.Post, $"/task-requests/{Uri.EscapeDataString(requestKey)}/abandon", content, ct).ConfigureAwait(false));
    }

    /// <summary>A fresh signed link for a completed task's first result (R2 links last an hour).</summary>
    public async Task<string> FetchResultUrlAsync(string taskId, CancellationToken ct)
    {
        var result = await GetAsync(taskId, ct).ConfigureAwait(false);
        var url = result.Artifacts.FirstOrDefault()?.Url ?? result.ResultUrl;
        if (!result.IsSuccess || url is null || !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            throw new WidgetTaskException("Could not refresh result URL", "no_result");
        return url;
    }

    /// <summary>Downloads a remote file (inputs or results) to <paramref name="destination"/>; returns the MIME type.</summary>
    public async Task<(string Path, string? MimeType)> DownloadAsync(string url, string folder, string baseName, CancellationToken ct, bool authenticated = false)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TransferTimeout);
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.UserAgent.ParseAdd("Glance/2.0");
        if (authenticated && GlanceApi.IsFirstParty(url) && auth.Session?.Token is { } token)
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException || ex is OperationCanceledException && !ct.IsCancellationRequested)
        {
            throw new WidgetTaskException("The result could not be downloaded. Please check your connection and try again.", "network");
        }
        using (response)
        {
            if (!response.IsSuccessStatusCode)
                throw new WidgetTaskException("The result could not be downloaded. Please check your connection and try again.", "download_failed", (int)response.StatusCode);
            var mime = response.Content.Headers.ContentType?.MediaType;
            var suggested = response.Content.Headers.ContentDisposition?.FileNameStar ?? response.Content.Headers.ContentDisposition?.FileName;
            var extension = MimeTypes.Extension(suggested?.Trim('"'), mime, url);
            Directory.CreateDirectory(folder);
            var target = UniqueFile(folder, baseName, extension);
            var temp = target + ".download";
            try
            {
                await using (var output = File.Create(temp))
                    await response.Content.CopyToAsync(output, timeout.Token).ConfigureAwait(false);
                File.Move(temp, target, overwrite: false);
            }
            catch (Exception ex) when (ex is IOException or HttpRequestException || ex is OperationCanceledException && !ct.IsCancellationRequested)
            {
                TryDelete(temp);
                throw new WidgetTaskException("The result could not be downloaded. Please check your connection and try again.", "download_failed");
            }
            return (target, mime);
        }
    }

    /// <summary>"name.ext", then "name 2.ext", "name 3.ext"… (macOS naming).</summary>
    public static string UniqueFile(string folder, string baseName, string extension)
    {
        var safe = string.Concat(baseName.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '-' : c)).Trim();
        if (safe.Length == 0) safe = "Widget Result";
        if (safe.Length > 120) safe = safe[..120];
        var ext = extension.TrimStart('.');
        var candidate = Path.Combine(folder, $"{safe}.{ext}");
        for (var n = 2; File.Exists(candidate) || File.Exists(candidate + ".download"); n++)
            candidate = Path.Combine(folder, $"{safe} {n}.{ext}");
        return candidate;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (IOException)
        {
        }
    }

    private async Task<JsonNode?> SendAsync(HttpMethod method, string path, HttpContent? content, CancellationToken ct, string? idempotencyKey = null, TimeSpan? timeout = null)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct);
        linked.CancelAfter(timeout ?? RequestTimeout);
        using var request = new HttpRequestMessage(method, GlanceApi.ApiV2 + path) { Content = content };
        var token = auth.Session?.Token;
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (idempotencyKey is not null) request.Headers.Add("Idempotency-Key", idempotencyKey);
        try
        {
            return await ApiEnvelope.SendAsync(http, request, linked.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new WidgetTaskException("The request timed out.", "network");
        }
        catch (ApiException ex)
        {
            var status = ex.Status is { } s ? (int)s : (int?)null;
            if (ex.Status == HttpStatusCode.Unauthorized)
            {
                if (token is not null) auth.InvalidateOnlineSession(token);
                throw new WidgetTaskException("Please sign in to use Widgets.", "unauthorized", 401);
            }
            if (ex.Code == "network") throw new WidgetTaskException(ex.Message, "network");
            var message = ex.Message.StartsWith("Request failed with HTTP", StringComparison.Ordinal) && status is { } code
                ? $"Widget request failed (HTTP {code})."
                : ex.Message;
            throw new WidgetTaskException(message, ex.Code, status);
        }
    }
}

/// <summary>MIME types and file extensions for uploads and downloads.</summary>
public static class MimeTypes
{
    private static readonly Dictionary<string, string> ByExtension = new(StringComparer.OrdinalIgnoreCase)
    {
        ["png"] = "image/png", ["jpg"] = "image/jpeg", ["jpeg"] = "image/jpeg", ["gif"] = "image/gif",
        ["webp"] = "image/webp", ["bmp"] = "image/bmp", ["heic"] = "image/heic", ["heif"] = "image/heif",
        ["tif"] = "image/tiff", ["tiff"] = "image/tiff", ["avif"] = "image/avif",
        ["mp4"] = "video/mp4", ["m4v"] = "video/x-m4v", ["mov"] = "video/quicktime", ["webm"] = "video/webm",
        ["mkv"] = "video/x-matroska", ["avi"] = "video/x-msvideo", ["wmv"] = "video/x-ms-wmv",
        ["mp3"] = "audio/mpeg", ["m4a"] = "audio/mp4", ["wav"] = "audio/wav", ["txt"] = "text/plain",
    };

    public static string ForPath(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.');
        return ByExtension.TryGetValue(ext, out var mime) ? mime : "application/octet-stream";
    }

    /// <summary>Extension from the suggested filename, then the MIME type, then the URL; else "bin".</summary>
    public static string Extension(string? suggestedName, string? mime, string? url)
    {
        var fromName = suggestedName is null ? "" : Path.GetExtension(suggestedName).TrimStart('.');
        if (fromName.Length is > 0 and <= 5) return fromName.ToLowerInvariant();
        if (mime is not null)
        {
            var hit = ByExtension.FirstOrDefault(p => p.Value.Equals(mime, StringComparison.OrdinalIgnoreCase));
            if (hit.Key is not null) return hit.Key == "jpeg" ? "jpg" : hit.Key;
            if (mime.StartsWith("audio/", StringComparison.OrdinalIgnoreCase)) return "m4a";
            if (mime.StartsWith("video/", StringComparison.OrdinalIgnoreCase)) return "mp4";
            if (mime.StartsWith("image/", StringComparison.OrdinalIgnoreCase)) return "png";
        }
        if (url is not null && Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            var fromUrl = Path.GetExtension(uri.AbsolutePath).TrimStart('.');
            if (fromUrl.Length is > 0 and <= 5) return fromUrl.ToLowerInvariant();
        }
        return "bin";
    }
}
