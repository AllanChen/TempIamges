using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Glance.Core.Account;

/// <summary>Glance service endpoints (macOS uses the same hard-coded hosts; there is no debug switch).</summary>
public static class GlanceApi
{
    public const string BaseUrl = "https://api.glancepreview.com";
    public const string ApiV2 = BaseUrl + "/api/v2";
    public const string AuthCallback = "glance://auth/callback";

    /// <summary>First-party hosts (used to decide whether a stored media URL needs a refreshed link).</summary>
    public static IReadOnlySet<string> Hosts { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "api.glancepreview.com", "api.glance.mcreator.ai" };

    public static bool IsFirstParty(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && Hosts.Contains(uri.Host);
}

/// <summary>A failed service request with the server's error code / message when it sent one.</summary>
public sealed class ApiException(string message, string code = "request_failed", HttpStatusCode? status = null, int? attemptsRemaining = null)
    : Exception(message)
{
    public string Code { get; } = code;
    public HttpStatusCode? Status { get; } = status;
    public int? AttemptsRemaining { get; } = attemptsRemaining;
    public bool IsUnauthorized => Status == HttpStatusCode.Unauthorized;
    public bool IsInsufficientCredits => Status == HttpStatusCode.PaymentRequired || Code is "insufficient_credits" or "insufficient_balance";
}

/// <summary>
/// The service envelope <c>{ success, result, error: { code, message, details: { attemptsRemaining } } }</c>
/// with the macOS error precedence: transport → empty → HTTP error → success:false → unreadable.
/// </summary>
public static class ApiEnvelope
{
    public static async Task<JsonNode?> SendAsync(HttpClient http, HttpRequestMessage request, CancellationToken ct)
    {
        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw new ApiException(ex is TaskCanceledException ? "The request timed out." : ex.Message, "network");
        }
        using (response)
        {
            var body = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            return Parse((int)response.StatusCode, body);
        }
    }

    /// <summary>The <c>result</c> node of a response body, or throws <see cref="ApiException"/>.</summary>
    public static JsonNode? Parse(int status, string body)
    {
        var httpStatus = (HttpStatusCode)status;
        if (string.IsNullOrWhiteSpace(body))
        {
            if (status is >= 200 and < 300) throw new ApiException("Empty server response.", "empty_response", httpStatus);
            throw new ApiException($"Request failed with HTTP {status}.", "request_failed", httpStatus);
        }
        JsonNode? root;
        try
        {
            root = JsonNode.Parse(body);
        }
        catch (JsonException)
        {
            if (status is >= 200 and < 300) throw new ApiException("Could not read server response.", "bad_response", httpStatus);
            throw new ApiException($"Request failed with HTTP {status}.", "request_failed", httpStatus);
        }
        var error = root?["error"] as JsonObject;
        var message = Text(error?["message"]);
        if (status is < 200 or >= 300)
        {
            if (message is not null)
                throw new ApiException(message, Text(error?["code"]) ?? "request_failed", httpStatus, Int(error?["details"]?["attemptsRemaining"]));
            throw new ApiException($"Request failed with HTTP {status}.", "request_failed", httpStatus);
        }
        if (Bool(root?["success"]) != true)
            throw new ApiException(message ?? "Request failed.", Text(error?["code"]) ?? "request_failed", httpStatus, Int(error?["details"]?["attemptsRemaining"]));
        return root?["result"];
    }

    public static string? Text(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<string>(out var s) && !string.IsNullOrWhiteSpace(s) ? s : null;

    public static int? Int(JsonNode? node)
    {
        if (node is not JsonValue v) return null;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<long>(out var l)) return (int)Math.Clamp(l, int.MinValue, int.MaxValue);
        if (v.TryGetValue<double>(out var d) && double.IsFinite(d)) return (int)Math.Round(d);
        if (v.TryGetValue<string>(out var s) && int.TryParse(s, out var parsed)) return parsed;
        return null;
    }

    public static double? Double(JsonNode? node)
    {
        if (node is not JsonValue v) return null;
        if (v.TryGetValue<double>(out var d)) return d;
        if (v.TryGetValue<string>(out var s) && double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed)) return parsed;
        return null;
    }

    public static bool? Bool(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;
}
