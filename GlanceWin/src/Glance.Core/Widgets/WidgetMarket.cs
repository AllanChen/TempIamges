using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Glance.Core.Account;
using Glance.Core.Logging;

namespace Glance.Core.Widgets;

/// <summary>
/// Ed25519 manifest signatures (macOS <c>WidgetManifestVerifier</c>). The signed bytes are the
/// manifest re-encoded the way Swift's <c>JSONEncoder</c> does with sorted keys and unescaped
/// slashes: only the fields the client models, nil optionals omitted, <c>signature</c> removed.
/// </summary>
public static class WidgetSignature
{
    public const string DeveloperKeyId = "glance-market-2026-02";
    private const string DeveloperKey = "F4eg6N56Z8z3CC7E4CUV0YecA6NpeHpAtx0/NFsUGFs=";
    private const string MarketKey = "zFrAHRuvuZVpWbAFaetTG+d27XeLkxicodlTFt1+cv8=";

    /// <summary>True when the signature verifies — or the manifest is official (accepted unverified, as on macOS).</summary>
    public static bool IsTrusted(WidgetManifest manifest) => manifest.Official || Verify(manifest.Raw);

    public static bool Verify(JsonObject manifest)
    {
        var signature = manifest["signature"] as JsonObject;
        if (ApiEnvelope.Text(signature?["algorithm"]) != "Ed25519" || ApiEnvelope.Text(signature?["value"]) is not { } value) return false;
        var keyId = ApiEnvelope.Text(signature?["keyID"]);
        try
        {
            var key = Convert.FromBase64String(keyId == DeveloperKeyId ? DeveloperKey : MarketKey);
            var sig = FromBase64Url(value);
            var message = Encoding.UTF8.GetBytes(Canonical(manifest));
            return Ed25519.Verify(key, message, sig);
        }
        catch (Exception ex) when (ex is FormatException or ArgumentException)
        {
            Log.Info($"WidgetSignature: malformed signature: {ex.Message}");
            return false;
        }
    }

    public static byte[] FromBase64Url(string value)
    {
        var s = value.Trim().Replace('-', '+').Replace('_', '/');
        s = s.PadRight(s.Length + (4 - s.Length % 4) % 4, '=');
        return Convert.FromBase64String(s);
    }

    // ───────────────────────────── Canonical JSON ─────────────────────────────

    private enum Kind { String, Int, Bool, Any, Strings }

    private static readonly (string Key, Kind Kind)[] TopLevel =
    [
        ("schemaVersion", Kind.Int), ("id", Kind.String), ("version", Kind.String), ("name", Kind.String),
        ("summary", Kind.String), ("author", Kind.String), ("iconURL", Kind.String), ("official", Kind.Bool),
        ("minimumGlanceVersion", Kind.String), ("updatedAt", Kind.String), ("creditCost", Kind.Int),
    ];

    private static readonly (string Key, Kind Kind)[] CommandFields =
    [
        ("id", Kind.String), ("name", Kind.String), ("description", Kind.String), ("inputTypes", Kind.Strings),
        ("inputMimeTypes", Kind.Strings), ("outputs", Kind.Strings), ("showResultURL", Kind.Bool),
        ("taskType", Kind.String), ("requiresUpload", Kind.Bool), ("parameterSchema", Kind.Any),
    ];

    /// <summary>The bytes the server signed (see the class summary).</summary>
    public static string Canonical(JsonObject manifest)
    {
        var projected = new SortedDictionary<string, JsonNode?>(StringComparer.Ordinal);
        foreach (var (key, kind) in TopLevel) Copy(manifest, projected, key, kind);
        if (manifest["execution"] is JsonObject execution)
            projected["execution"] = Object(execution, ("mode", Kind.String));
        if (manifest["privacy"] is JsonObject privacy)
            projected["privacy"] = Object(privacy, ("uploadsMedia", Kind.Bool), ("notice", Kind.String));
        if (manifest["billing"] is JsonObject billing)
            projected["billing"] = Object(billing, ("mode", Kind.String), ("unitSeconds", Kind.Int));
        if (manifest["commands"] is JsonArray commands)
            projected["commands"] = new JsonArray(commands.Select(c => (JsonNode?)(c is JsonObject o ? Object(o, CommandFields) : null)).ToArray());
        if (manifest["localizations"] is JsonObject localizations)
        {
            var locs = new JsonObject();
            foreach (var (tag, value) in localizations)
            {
                if (value is not JsonObject loc) continue;
                var projectedLoc = Object(loc, ("name", Kind.String), ("summary", Kind.String));
                if (loc["commands"] is JsonObject locCommands)
                {
                    var cmds = new JsonObject();
                    foreach (var (id, command) in locCommands)
                        if (command is JsonObject c) cmds[id] = Object(c, ("name", Kind.String), ("description", Kind.String));
                    projectedLoc["commands"] = cmds;
                }
                locs[tag] = projectedLoc;
            }
            projected["localizations"] = locs;
        }
        var builder = new StringBuilder();
        var root = new JsonObject();
        foreach (var (key, value) in projected) root[key] = value;
        Write(builder, root, inSchema: false);
        return builder.ToString();
    }

    private static JsonObject Object(JsonObject source, params (string Key, Kind Kind)[] fields)
    {
        var target = new SortedDictionary<string, JsonNode?>(StringComparer.Ordinal);
        foreach (var (key, kind) in fields) Copy(source, target, key, kind);
        var result = new JsonObject();
        foreach (var (key, value) in target) result[key] = value;
        return result;
    }

    private static void Copy(JsonObject source, IDictionary<string, JsonNode?> target, string key, Kind kind)
    {
        if (!source.TryGetPropertyValue(key, out var node) || node is null) return;
        if (kind == Kind.Any)
        {
            target[key] = node.DeepClone();
            return;
        }
        if (kind == Kind.Strings)
        {
            if (node is JsonArray array) target[key] = new JsonArray(array.Select(n => (JsonNode?)(n?.DeepClone())).ToArray());
            return;
        }
        if (node is JsonValue value) target[key] = value.DeepClone();
    }

    /// <summary>Swift <c>JSONEncoder</c> output: sorted keys, no spaces, '/' unescaped, non-ASCII as UTF-8.</summary>
    private static void Write(StringBuilder sb, JsonNode? node, bool inSchema)
    {
        switch (node)
        {
            case null:
                sb.Append("null");
                break;
            case JsonObject obj:
                sb.Append('{');
                var first = true;
                foreach (var (key, value) in obj.OrderBy(p => p.Key, StringComparer.Ordinal))
                {
                    if (!first) sb.Append(',');
                    first = false;
                    WriteString(sb, key);
                    sb.Append(':');
                    Write(sb, value, inSchema || key == "parameterSchema");
                }
                sb.Append('}');
                break;
            case JsonArray array:
                sb.Append('[');
                for (var i = 0; i < array.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    Write(sb, array[i], inSchema);
                }
                sb.Append(']');
                break;
            case JsonValue value:
                switch (value.GetValueKind())
                {
                    case JsonValueKind.String:
                        WriteString(sb, value.GetValue<string>());
                        break;
                    case JsonValueKind.True:
                        sb.Append("true");
                        break;
                    case JsonValueKind.False:
                        sb.Append("false");
                        break;
                    case JsonValueKind.Number:
                        sb.Append(Number(value));
                        break;
                    default:
                        sb.Append("null");
                        break;
                }
                break;
        }
    }

    /// <summary>Integers as integers; other numbers as Swift prints a Double (shortest round-trip).</summary>
    private static string Number(JsonValue value)
    {
        if (value.TryGetValue<long>(out var integer)) return integer.ToString(CultureInfo.InvariantCulture);
        var d = value.TryGetValue<double>(out var parsed) ? parsed : ApiEnvelope.Double(value) ?? 0;
        if (d == Math.Floor(d) && Math.Abs(d) < 1e15) return ((long)d).ToString(CultureInfo.InvariantCulture);
        return d.ToString("R", CultureInfo.InvariantCulture).Replace("E+", "e+").Replace("E-", "e-");
    }

    private static void WriteString(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (var c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}

/// <summary>
/// Installed Widgets (macOS <c>WidgetRegistry</c>): manifests stored as JSON in
/// <c>%APPDATA%\Glance\widgets.json</c> plus the ids the Market no longer lists ("delisted").
/// Thread-safe; <see cref="Changed"/> may fire on any thread.
/// </summary>
public sealed class WidgetRegistry
{
    private readonly string _file;
    private readonly object _gate = new();
    private List<WidgetManifest> _installed = [];
    private HashSet<string> _delisted = [];

    public WidgetRegistry(string file)
    {
        _file = file;
        Load();
    }

    public event EventHandler? Changed;

    public IReadOnlyList<WidgetManifest> Installed
    {
        get
        {
            lock (_gate) return _installed.ToList();
        }
    }

    /// <summary>Installed and still listed.</summary>
    public IReadOnlyList<WidgetManifest> Available
    {
        get
        {
            lock (_gate) return _installed.Where(w => !_delisted.Contains(w.Id)).ToList();
        }
    }

    public IReadOnlyList<WidgetManifest> Compatible(string inputType) => Available.Where(w => w.IsCompatible(inputType)).ToList();

    public WidgetManifest? Find(string id)
    {
        lock (_gate) return _installed.FirstOrDefault(w => w.Id == id);
    }

    public bool IsInstalled(string id) => Find(id) is not null;

    public bool IsAvailable(string id)
    {
        lock (_gate) return _installed.Any(w => w.Id == id) && !_delisted.Contains(id);
    }

    public void Install(WidgetManifest manifest)
    {
        lock (_gate)
        {
            _installed.RemoveAll(w => w.Id == manifest.Id);
            _installed.Add(manifest);
            _delisted.Remove(manifest.Id);
            Save();
        }
        Log.Info($"Widgets: installed {manifest.Id} v{manifest.Version}");
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Uninstall(string id)
    {
        lock (_gate)
        {
            _installed.RemoveAll(w => w.Id == id);
            _delisted.Remove(id);
            Save();
        }
        Log.Info($"Widgets: removed {id}");
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>A complete catalog snapshot: installed Widgets missing from it are delisted.</summary>
    public void Reconcile(IEnumerable<string> publishedIds)
    {
        var published = publishedIds.ToHashSet();
        bool changed;
        lock (_gate)
        {
            var delisted = _installed.Select(w => w.Id).Where(id => !published.Contains(id)).ToHashSet();
            changed = !delisted.SetEquals(_delisted);
            if (changed)
            {
                _delisted = delisted;
                Save();
            }
        }
        if (changed) Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>The service refused to run it (<c>widget_unavailable</c> / <c>widget_not_found</c>).</summary>
    public void MarkDelisted(string id)
    {
        lock (_gate)
        {
            if (!_delisted.Add(id)) return;
            Save();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_file)) return;
            var root = JsonNode.Parse(File.ReadAllText(_file));
            _installed = (root?["installed"] as JsonArray ?? [])
                .Select(WidgetManifest.TryParse).OfType<WidgetManifest>()
                .GroupBy(w => w.Id).Select(g => g.Last()).ToList();
            _delisted = WidgetCommand.Strings(root?["delisted"]).ToHashSet();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            Log.Warning($"Widgets: could not read installed Widgets: {ex.Message}");
        }
    }

    private void Save()
    {
        try
        {
            var root = new JsonObject
            {
                ["installed"] = new JsonArray(_installed.Select(w => (JsonNode?)w.Raw.DeepClone()).ToArray()),
                ["delisted"] = new JsonArray(_delisted.OrderBy(s => s, StringComparer.Ordinal).Select(s => (JsonNode?)s).ToArray()),
            };
            AtomicFile.WriteAllText(_file, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Warning($"Widgets: could not save installed Widgets: {ex.Message}");
        }
    }
}

/// <summary>Market catalog page (<c>GET /api/v2/widgets</c>).</summary>
public sealed record WidgetCatalog(IReadOnlyList<WidgetManifest> Widgets, int Page, int TotalPages, int Total)
{
    public bool IsComplete => Page >= TotalPages && Widgets.Count >= Total;
}

/// <summary>Widget Market networking (macOS <c>WidgetMarketClient</c>): catalog and verified install.</summary>
public sealed class WidgetMarketClient(HttpClient http, WidgetRegistry registry)
{
    public const string UnavailableMessage = "The Widget Market is unavailable.";
    public const string InvalidManifestMessage = "The Widget manifest is invalid.";
    public const string InvalidSignatureMessage = "The Widget signature could not be verified.";

    public async Task<WidgetCatalog> FetchCatalogAsync(CancellationToken ct = default)
    {
        var result = await GetAsync($"{GlanceApi.ApiV2}/widgets", ct).ConfigureAwait(false);
        if (result?["widgets"] is not JsonArray widgets) throw new ApiException(UnavailableMessage, "unavailable");
        var list = widgets.Select(WidgetManifest.TryParse).OfType<WidgetManifest>().ToList();
        var pagination = result["pagination"];
        var catalog = new WidgetCatalog(list, ApiEnvelope.Int(pagination?["page"]) ?? 1, ApiEnvelope.Int(pagination?["totalPages"]) ?? 1, ApiEnvelope.Int(pagination?["total"]) ?? list.Count);
        if (catalog.IsComplete) registry.Reconcile(list.Select(w => w.Id));
        return catalog;
    }

    /// <summary>Fetches the published manifest, checks its signature and installs it (install and update are the same).</summary>
    public async Task<WidgetManifest> InstallAsync(string id, CancellationToken ct = default)
    {
        var result = await GetAsync($"{GlanceApi.ApiV2}/widgets/{Uri.EscapeDataString(id)}", ct).ConfigureAwait(false);
        var manifest = WidgetManifest.TryParse(result) ?? throw new ApiException(InvalidManifestMessage, "invalid_manifest");
        if (!WidgetSignature.IsTrusted(manifest))
        {
            Log.Warning($"WidgetMarket: signature check failed for {id}");
            throw new ApiException(InvalidSignatureMessage, "invalid_signature");
        }
        registry.Install(manifest);
        return manifest;
    }

    private async Task<JsonNode?> GetAsync(string url, CancellationToken ct)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(8));
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        try
        {
            return await ApiEnvelope.SendAsync(http, request, timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new ApiException(UnavailableMessage, "unavailable");
        }
        catch (ApiException ex) when (ex.Code is "network" or "request_failed" or "bad_response" or "empty_response")
        {
            throw new ApiException(UnavailableMessage, "unavailable", ex.Status);
        }
    }
}

/// <summary>Write-to-temp-then-replace so a crash never leaves a half-written JSON file.</summary>
public static class AtomicFile
{
    public static void WriteAllText(string path, string contents)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temp, contents, new UTF8Encoding(false));
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            try
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
            catch (IOException)
            {
            }
        }
    }
}
