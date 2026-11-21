using System.Text.Json;
using System.Text.Json.Nodes;
using Glance.Core.Account;

namespace Glance.Core.Widgets;

/// <summary>What a command's parameter schema / input types allow (macOS <c>WidgetInputCapabilities</c>).</summary>
public sealed record WidgetInputCapabilities(bool AcceptsPrompt, bool AcceptsMask, int MinImages, int MaxImages, int MaxVideos)
{
    /// <summary>Image commands that open the input panel (prompt, mask or several images) instead of running at once.</summary>
    public bool NeedsImageDialog => AcceptsPrompt || AcceptsMask || MaxImages > 1;
    public bool NeedsVideoDialog => AcceptsPrompt || MaxVideos > 1;
}

/// <summary>One command of a Widget (macOS <c>WidgetCommand</c>).</summary>
public sealed class WidgetCommand
{
    private static readonly string[] MediaTypes =
        ["image", "video", "multiple_images", "multi_image", "multiple-images", "multi-image", "multiple_videos", "multi_video", "multiple-videos", "multi-video", "mask"];
    private static readonly string[] TextTypes = ["text", "txt", "prompt"];
    private static readonly string[] MultiImageTypes = ["multiple_images", "multi_image", "multiple-images", "multi-image"];
    private static readonly string[] MultiVideoTypes = ["multiple_videos", "multi_video", "multiple-videos", "multi-video"];

    public WidgetCommand(JsonObject raw)
    {
        Raw = raw;
        Id = ApiEnvelope.Text(raw["id"]) ?? "";
        Name = ApiEnvelope.Text(raw["name"]) ?? Id;
        Description = ApiEnvelope.Text(raw["description"]) ?? "";
        InputTypes = Strings(raw["inputTypes"]);
        Outputs = Strings(raw["outputs"]);
        ShowResultUrl = ApiEnvelope.Bool(raw["showResultURL"]);
        TaskType = ApiEnvelope.Text(raw["taskType"]) ?? "";
        ParameterSchema = raw["parameterSchema"] as JsonObject;
    }

    public JsonObject Raw { get; }
    public string Id { get; }
    public string Name { get; }
    public string Description { get; }
    public IReadOnlyList<string> InputTypes { get; }
    public IReadOnlyList<string> Outputs { get; }
    public bool? ShowResultUrl { get; }
    public string TaskType { get; }
    public JsonObject? ParameterSchema { get; }

    public bool Accepts(string inputType) => InputTypes.Contains(inputType, StringComparer.OrdinalIgnoreCase);

    public bool IsTextOnly =>
        InputTypes.Count > 0
        && InputTypes.All(t => TextTypes.Contains(t, StringComparer.OrdinalIgnoreCase))
        && !InputTypes.Any(t => MediaTypes.Contains(t, StringComparer.OrdinalIgnoreCase));

    private JsonObject? Properties => ParameterSchema?["properties"] as JsonObject ?? ParameterSchema;

    public JsonObject? PromptProperty => Properties?["prompt"] as JsonObject;

    public WidgetInputCapabilities InputCapabilities
    {
        get
        {
            var props = Properties;
            bool Has(string key) => props?.ContainsKey(key) == true;
            bool Declares(IEnumerable<string> types) => InputTypes.Any(t => types.Contains(t, StringComparer.OrdinalIgnoreCase));
            var acceptsPrompt = Has("prompt") || Declares(TextTypes);
            var acceptsMask = Has("mask") || Declares(["mask"]);
            var imageProperty = props?["images"] ?? props?["imageUrls"] ?? props?["multipleImages"];
            var multipleImages = imageProperty is not null || Declares(MultiImageTypes);
            var maxImages = imageProperty is JsonObject ip && ApiEnvelope.Int(ip["maxItems"]) is { } max ? Math.Clamp(max, 1, 4) : multipleImages ? 4 : 1;
            var minImages = imageProperty is JsonObject ip2 && ApiEnvelope.Int(ip2["minItems"]) is { } min ? Math.Clamp(min, 1, maxImages) : 1;
            var multipleVideos = Has("videos") || Has("videoUrls") || Has("multipleVideos") || Declares(MultiVideoTypes);
            return new WidgetInputCapabilities(acceptsPrompt, acceptsMask, minImages, maxImages, multipleVideos ? 4 : 1);
        }
    }

    internal static IReadOnlyList<string> Strings(JsonNode? node) =>
        node is JsonArray array ? array.Select(ApiEnvelope.Text).OfType<string>().ToList() : [];
}

/// <summary>
/// A Widget manifest (macOS <c>WidgetManifest</c>). The raw JSON is kept as received so the stored
/// copy round-trips exactly (signature checks and update detection compare it with the catalog).
/// </summary>
public sealed class WidgetManifest
{
    /// <summary>Duration-billed before the manifest carried <c>billing</c> (hard-coded on macOS too).</summary>
    private const string LegacyDurationWidgetId = "783745bf-501d-4cfd-b2b8-69d32a8d90a8";

    public WidgetManifest(JsonObject raw)
    {
        Raw = raw;
        Id = ApiEnvelope.Text(raw["id"]) ?? "";
        Version = ApiEnvelope.Text(raw["version"]) ?? "";
        Name = ApiEnvelope.Text(raw["name"]) ?? Id;
        Summary = ApiEnvelope.Text(raw["summary"]) ?? "";
        Author = ApiEnvelope.Text(raw["author"]) ?? "";
        IconUrl = ApiEnvelope.Text(raw["iconURL"]) is { } icon && icon.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ? icon : null;
        Official = ApiEnvelope.Bool(raw["official"]) == true;
        Commands = raw["commands"] is JsonArray commands ? commands.OfType<JsonObject>().Select(c => new WidgetCommand(c)).ToList() : [];
        PrivacyNotice = ApiEnvelope.Text(raw["privacy"]?["notice"]) ?? "";
        UploadsMedia = ApiEnvelope.Bool(raw["privacy"]?["uploadsMedia"]) == true;
        CreditCost = ApiEnvelope.Int(raw["creditCost"]);
        BillingMode = ApiEnvelope.Text(raw["billing"]?["mode"]);
        Localizations = raw["localizations"] as JsonObject;
    }

    public static WidgetManifest? TryParse(JsonNode? node) =>
        node is JsonObject obj && ApiEnvelope.Text(obj["id"]) is not null ? new WidgetManifest((JsonObject)obj.DeepClone()) : null;

    public JsonObject Raw { get; }
    public string Id { get; }
    public string Version { get; }
    public string Name { get; }
    public string Summary { get; }
    public string Author { get; }
    public string? IconUrl { get; }
    public bool Official { get; }
    public IReadOnlyList<WidgetCommand> Commands { get; }
    public string PrivacyNotice { get; }
    public bool UploadsMedia { get; }
    public int? CreditCost { get; }
    public string? BillingMode { get; }
    public JsonObject? Localizations { get; }

    public int TaskCreditCost => Math.Max(0, CreditCost ?? 1);

    public bool UsesDurationBilling => BillingMode == "duration" || Id == LegacyDurationWidgetId;

    public bool IsCompatible(string inputType) => Commands.Any(c => c.Accepts(inputType));

    public bool HasTextOnlyCommand => Commands.Any(c => c.IsTextOnly);

    public WidgetCommand? Command(string id) => Commands.FirstOrDefault(c => c.Id == id);

    // ───────────────────────────── Localization ─────────────────────────────

    /// <summary>
    /// Localized override for <paramref name="language"/> ("en", "zh-Hans", "ja", "de"): the tag, its
    /// base, then English — unless the base text is already in that language.
    /// </summary>
    private JsonObject? LocalizationFor(string language)
    {
        if (Localizations is null) return null;
        var candidates = new List<string> { language };
        var dash = language.IndexOf('-');
        if (dash > 0) candidates.Add(language[..dash]);
        foreach (var tag in candidates)
        {
            if (tag.Equals("en", StringComparison.OrdinalIgnoreCase) && !language.StartsWith("en", StringComparison.OrdinalIgnoreCase)) continue;
            foreach (var (key, value) in Localizations)
                if (key.Equals(tag, StringComparison.OrdinalIgnoreCase) && value is JsonObject obj) return obj;
        }
        if (LooksLike(Name, language)) return null;
        return Localizations["en"] as JsonObject;
    }

    private static bool LooksLike(string text, string language)
    {
        var hasHan = text.Any(c => c >= 0x4E00 && c <= 0x9FFF);
        var hasKana = text.Any(c => c >= 0x3040 && c <= 0x30FF);
        if (language.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) return hasHan && !hasKana;
        if (language.StartsWith("ja", StringComparison.OrdinalIgnoreCase)) return hasKana;
        return false;
    }

    private static string Pick(string? overrideText, string fallback) =>
        string.IsNullOrWhiteSpace(overrideText) ? fallback : overrideText;

    public string DisplayName(string language) => Pick(ApiEnvelope.Text(LocalizationFor(language)?["name"]), Name);

    public string DisplaySummary(string language) => Pick(ApiEnvelope.Text(LocalizationFor(language)?["summary"]), Summary);

    public string CommandName(WidgetCommand command, string language) =>
        Pick(ApiEnvelope.Text(LocalizationFor(language)?["commands"]?[command.Id]?["name"]), command.Name);

    public string CommandDescription(WidgetCommand command, string language) =>
        Pick(ApiEnvelope.Text(LocalizationFor(language)?["commands"]?[command.Id]?["description"]), command.Description);

    /// <summary>Name, summary, author and every command / localized text, for Market search.</summary>
    public string SearchableText
    {
        get
        {
            var parts = new List<string> { Name, Summary, Author };
            foreach (var c in Commands)
            {
                parts.Add(c.Name);
                parts.Add(c.Description);
            }
            if (Localizations is not null)
                foreach (var (_, value) in Localizations)
                {
                    if (value is not JsonObject loc) continue;
                    parts.Add(ApiEnvelope.Text(loc["name"]) ?? "");
                    parts.Add(ApiEnvelope.Text(loc["summary"]) ?? "");
                    if (loc["commands"] is JsonObject commands)
                        foreach (var (_, command) in commands)
                        {
                            parts.Add(ApiEnvelope.Text(command?["name"]) ?? "");
                            parts.Add(ApiEnvelope.Text(command?["description"]) ?? "");
                        }
                }
            return string.Join(' ', parts.Where(p => p.Length > 0));
        }
    }

    /// <summary>An installed copy differs from the catalog copy in anything the user would notice (macOS "Update").</summary>
    public bool DiffersFrom(WidgetManifest catalog) =>
        Version != catalog.Version
        || !JsonNode.DeepEquals(Raw["commands"], catalog.Raw["commands"])
        || Name != catalog.Name
        || Summary != catalog.Summary
        || !JsonNode.DeepEquals(Raw["localizations"], catalog.Raw["localizations"])
        || Author != catalog.Author
        || IconUrl != catalog.IconUrl
        || TaskCreditCost != catalog.TaskCreditCost
        || !JsonNode.DeepEquals(Raw["billing"], catalog.Raw["billing"])
        || PrivacyNotice != catalog.PrivacyNotice;

    public string ToJson() => Raw.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
}
