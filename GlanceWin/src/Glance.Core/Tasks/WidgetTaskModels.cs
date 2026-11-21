using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Glance.Core.Account;

namespace Glance.Core.Tasks;

[JsonConverter(typeof(JsonStringEnumConverter<WidgetTaskPhase>))]
public enum WidgetTaskPhase { Uploading, Submitting, Processing, Downloading, Completed, Failed, Interrupted, Cancelled, Expired }

/// <summary>What the input panel collected (macOS <c>WidgetTaskInput</c>).</summary>
public sealed record WidgetTaskInput
{
    public List<string> MediaUrls { get; init; } = [];
    public string? Prompt { get; init; }
    public string? MaskUrl { get; init; }
    public bool UsesMultipleImages { get; init; }
    public bool UsesMultipleVideos { get; init; }
}

/// <summary>
/// One Widget task (macOS <c>WidgetTaskRecord</c>), persisted in <c>widget-tasks.json</c>. Immutable:
/// the manager replaces it with <c>with</c>. <see cref="RequestKey"/> is the idempotency key, saved
/// before anything is uploaded so a crash can't create a second charge.
/// </summary>
public sealed record WidgetTaskRecord
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string WidgetId { get; init; } = "";
    public string WidgetName { get; init; } = "";
    public string CommandId { get; init; } = "";
    public string CommandName { get; init; } = "";
    public List<string>? OutputTypes { get; init; }
    public bool? ShowResultUrl { get; init; }
    /// <summary>Local path, URL, or <c>glance-text:&lt;uuid&gt;</c> for text runs.</summary>
    public string SourceUrl { get; init; } = "";
    /// <summary>"image", "video" or "text".</summary>
    public string SourceKind { get; init; } = "image";
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; init; } = DateTimeOffset.UtcNow;
    public string? RemoteTaskId { get; init; }
    public WidgetTaskPhase Phase { get; init; } = WidgetTaskPhase.Uploading;
    public double Progress { get; init; }
    public string? OutputPath { get; init; }
    public string? OutputUrlString { get; init; }
    public string? ErrorMessage { get; init; }
    public WidgetTaskInput? Input { get; init; }
    public int? QueuePosition { get; init; }
    public double? EstimatedWaitSeconds { get; init; }
    public double? QueueWaitSeconds { get; init; }
    public JsonObject? Quote { get; init; }
    public int? CreditCost { get; init; }
    public int? RefundedCredits { get; init; }
    public string? RequestKey { get; init; }
    public long? OwnerUserId { get; init; }
    /// <summary>"failed" or "delivered" until the server confirms the refund / charge; then null.</summary>
    public string? SettlementOutcome { get; init; }

    [JsonIgnore] public bool IsActive => Phase is WidgetTaskPhase.Uploading or WidgetTaskPhase.Submitting or WidgetTaskPhase.Processing or WidgetTaskPhase.Downloading;
    [JsonIgnore] public bool IsFailure => Phase is WidgetTaskPhase.Failed or WidgetTaskPhase.Interrupted or WidgetTaskPhase.Expired;
    [JsonIgnore] public bool HasPendingSettlement => SettlementOutcome is not null;
    [JsonIgnore] public bool CanCancel => Phase is WidgetTaskPhase.Uploading or WidgetTaskPhase.Submitting or WidgetTaskPhase.Processing;
    [JsonIgnore] public bool IsPreparing => Phase == WidgetTaskPhase.Uploading && Quote is null && RequestKey is null && RemoteTaskId is null;
    [JsonIgnore] public bool IsTextSource => SourceKind == "text";

    /// <summary>
    /// Credit status (macOS <c>billingStatusText</c>) as an English format and its number, for
    /// localization by the app. Null when there is nothing to say.
    /// </summary>
    [JsonIgnore]
    public (string Format, int? Value)? BillingStatus
    {
        get
        {
            if (SettlementOutcome == "failed") return ("Refund confirmation pending", null);
            if (SettlementOutcome == "delivered") return ("Confirming task result", null);
            if (RefundedCredits is > 0) return ("Refunded %d credits", RefundedCredits);
            var cost = CreditCost ?? WidgetTaskQuoteTotal;
            if (cost is > 0)
            {
                if (RemoteTaskId is null) return IsActive ? ("Estimated %d credits", cost) : ("Not charged", null);
                return ("Charged %d credits", cost);
            }
            if (cost == 0) return ("Free of charge", null);
            return null;
        }
    }

    [JsonIgnore] public int? WidgetTaskQuoteTotal => ApiEnvelope.Int(Quote?["totalCredits"]);

    /// <summary>Queue text (macOS <c>queueText</c>) as an English format with its arguments.</summary>
    [JsonIgnore]
    public (string Format, object[] Args)? QueueStatus
    {
        get
        {
            if (Phase != WidgetTaskPhase.Processing || Progress > 0 || QueuePosition is not { } position) return null;
            if (QueueWaitSeconds is >= 120) return ("Waiting for a worker · Not started", []);
            var ahead = Math.Max(0, position - 1);
            if (EstimatedWaitSeconds is { } wait && wait > 0)
            {
                var text = wait < 60 ? $"{(int)Math.Round(wait)}s" : $"{(int)Math.Round(wait / 60)} min";
                return ("Queued · %d ahead · ~%@", [ahead, text]);
            }
            return ("Queued · %d ahead", [ahead]);
        }
    }

    /// <summary>A shareable media URL of a completed image / video result, when the Widget offers one.</summary>
    public string? CopyableMediaResultUrl(bool? installedShowResultUrl, IReadOnlyList<string>? installedOutputs)
    {
        if (Phase != WidgetTaskPhase.Completed || OutputUrlString is not { } url) return null;
        var outputs = OutputTypes ?? installedOutputs?.ToList() ?? [];
        if (!outputs.Any(o => o is "image" or "video")) return null;
        if ((ShowResultUrl ?? installedShowResultUrl) != true) return null;
        return Uri.TryCreate(url, UriKind.Absolute, out var uri) && (uri.Scheme == "https" || uri.Scheme == "http") && uri.Host.Length > 0 ? url : null;
    }

    /// <summary>Identity of a source / output for matching (case-insensitive full path; URLs verbatim).</summary>
    public static string MediaKey(string location)
    {
        if (location.StartsWith("glance-text:", StringComparison.Ordinal)) return location;
        if (Uri.TryCreate(location, UriKind.Absolute, out var uri) && !uri.IsFile) return uri.AbsoluteUri;
        try
        {
            var path = uri?.IsFile == true ? uri.LocalPath : location;
            return Path.GetFullPath(path).ToUpperInvariant();
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return location;
        }
    }
}

/// <summary>One output of a finished task.</summary>
public sealed record WidgetArtifact(string Type, string? Text, string? Url);

/// <summary>A task as the service reports it (<c>POST /tasks</c>, <c>GET /tasks/{id}</c>, <c>settle</c>).</summary>
public sealed record WidgetTaskResult
{
    public string? TaskId { get; init; }
    public string Status { get; init; } = "";
    public double? Progress { get; init; }
    public double? ProcessCount { get; init; }
    public int? PollAfterMs { get; init; }
    public int? QueuePosition { get; init; }
    public double? EstimatedWaitSeconds { get; init; }
    public double? QueueWaitSeconds { get; init; }
    public string? ResultUrl { get; init; }
    public IReadOnlyList<WidgetArtifact> Artifacts { get; init; } = [];
    public string? Error { get; init; }
    public string? ErrorReason { get; init; }
    public int? CreditCost { get; init; }
    public int? RefundedCredits { get; init; }
    public int? Balance { get; init; }
    public bool? Delivered { get; init; }

    public bool IsSuccess => Status is "completed" or "succeeded";
    public bool IsTerminalFailure => Status is "failed" or "expired" or "cancelled";

    public static WidgetTaskResult From(JsonNode? node)
    {
        var artifacts = (node?["result"] as JsonArray ?? []).OfType<JsonObject>()
            .Select(a => new WidgetArtifact(ApiEnvelope.Text(a["type"]) ?? "", a["text"] is JsonValue t && t.TryGetValue<string>(out var text) ? text : null, ApiEnvelope.Text(a["url"])))
            .ToList();
        return new WidgetTaskResult
        {
            TaskId = ApiEnvelope.Text(node?["taskID"]) ?? ApiEnvelope.Int(node?["taskID"])?.ToString(CultureInfo.InvariantCulture),
            Status = (ApiEnvelope.Text(node?["status"]) ?? "").ToLowerInvariant(),
            Progress = ApiEnvelope.Double(node?["progress"]),
            ProcessCount = ApiEnvelope.Double(node?["processCount"]),
            PollAfterMs = ApiEnvelope.Int(node?["pollAfterMs"]),
            QueuePosition = ApiEnvelope.Int(node?["queuePosition"]),
            EstimatedWaitSeconds = ApiEnvelope.Double(node?["estimatedWaitSeconds"]),
            QueueWaitSeconds = ApiEnvelope.Double(node?["queueWaitSeconds"]),
            ResultUrl = ApiEnvelope.Text(node?["resultURL"]),
            Artifacts = artifacts,
            Error = ApiEnvelope.Text(node?["error"]) ?? ApiEnvelope.Text(node?["error"]?["code"]),
            ErrorReason = ApiEnvelope.Text(node?["errorReason"]),
            CreditCost = ApiEnvelope.Int(node?["creditCost"]),
            RefundedCredits = ApiEnvelope.Int(node?["refundedCredits"]),
            Balance = ApiEnvelope.Int(node?["balance"]),
            Delivered = ApiEnvelope.Bool(node?["delivered"]),
        };
    }

    /// <summary>The settlement is final: delivered and charged, or failed and fully refunded.</summary>
    public bool SettlementResolved => Delivered == true && IsSuccess || IsTerminalFailure && IsRefunded;

    public bool IsRefunded => (CreditCost ?? 0) == 0 || (RefundedCredits ?? 0) >= (CreditCost ?? 0);
}

/// <summary>A task request the service or client refused, with the message to show.</summary>
public sealed class WidgetTaskException(string message, string? code = null, int? status = null) : Exception(message)
{
    public string? Code { get; } = code;
    public int? Status { get; } = status;

    /// <summary>Pre-creation rejections that re-run the quote / top-up flow instead of failing.</summary>
    public bool RequiresRequote => Code is "insufficient_credits" or "price_changed" or "quote_expired" or "input_changed";

    /// <summary>User-facing text for a failed task (macOS <c>WidgetTaskExecutionError</c>).</summary>
    public static string ExecutionMessage(string? code, string? reason)
    {
        switch (code)
        {
            case "billing_input_mismatch" or "billing_not_verified":
                return "The video could not be verified against its quote. Review the refund status, then select the video and confirm its price again.";
            case "content_rejected":
                var detail = reason switch
                {
                    "sexual" or "possible_sexual" or "sexual_content" => " (possible sexual content)",
                    "political" or "possible_political" or "political_content" => " (possible political content)",
                    _ => "",
                };
                return $"The AI provider's safety review rejected this input{detail}. Change the image or input and try again; running the same input again will be rejected again.";
            case "worker_timeout" or "task_timeout":
                return "The Widget took too long to process this task. Try again, or use a smaller input.";
            case "widget_not_registered":
                return "This Widget is temporarily unavailable. Try again later.";
            case null or "":
                return "The Widget task failed without reporting a reason.";
            default:
                return "The Widget could not finish this task. Try again; if it keeps failing, contact support.";
        }
    }
}
