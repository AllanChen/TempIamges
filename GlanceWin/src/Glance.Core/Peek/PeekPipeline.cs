using Glance.Core.Detection;
using Glance.Core.Logging;
using Glance.Core.Search;

namespace Glance.Core.Peek;

/// <summary>Detection result: concrete hits plus unique tokens that still need searching.</summary>
public sealed record PeekDetection(IReadOnlyList<DetectedPath> Resolved, IReadOnlyList<string> UnresolvedTokens)
{
    public bool IsEmpty => Resolved.Count == 0 && UnresolvedTokens.Count == 0;
    public bool NeedsSearch => UnresolvedTokens.Count > 0;
}

/// <summary>One item to show, with a location hint for search hits.</summary>
public sealed record PeekItem(DetectedPath Path, string? Hint);

/// <summary>
/// Platform-neutral part of the macOS <c>AppDelegate</c> preview flow:
/// selection text → detection → search for unresolved tokens → merged, ordered items.
/// </summary>
public sealed class PeekPipeline
{
    public const int MaxItems = 24;

    private readonly PathDetector _detector;
    private readonly FileNameResolver _resolver;
    private readonly string _home;

    public PeekPipeline(PathDetector detector, FileNameResolver resolver, string home)
    {
        _detector = detector;
        _resolver = resolver;
        _home = home;
    }

    public PeekDetection Detect(string text)
    {
        var hits = _detector.DetectAll(text);
        var resolved = hits.Where(h => h.IsResolved).ToList();
        var tokens = hits.Where(h => h.IsUnresolved).Select(h => h.Value).Distinct(StringComparer.Ordinal).ToList();
        Log.Info($"PeekPipeline: {resolved.Count} resolved + {tokens.Count} unresolved");
        return new PeekDetection(resolved, tokens);
    }

    /// <summary>
    /// Searches every token in parallel and merges results round-robin (one match per token
    /// per pass) after the already-resolved hits, capped at <see cref="MaxItems"/>.
    /// </summary>
    public async Task<IReadOnlyList<PeekItem>> ResolveAsync(PeekDetection detection, CancellationToken cancellationToken)
    {
        var items = detection.Resolved.Select(p => new PeekItem(p, null)).ToList();
        if (!detection.NeedsSearch) return items;

        var searches = detection.UnresolvedTokens
            .Select(t => _resolver.ResolveAsync(t, cancellationToken: cancellationToken))
            .ToList();
        var results = await Task.WhenAll(searches);
        cancellationToken.ThrowIfCancellationRequested();

        var seen = new HashSet<string>(items.Select(i => i.Path.Key), StringComparer.Ordinal);
        var budget = Math.Max(0, MaxItems - items.Count);
        var cursors = new int[results.Length];
        var advanced = true;
        while (budget > 0 && advanced)
        {
            advanced = false;
            for (var i = 0; i < results.Length && budget > 0; i++)
            {
                if (cursors[i] >= results[i].Count) continue;
                var match = results[i][cursors[i]++];
                advanced = true;
                var path = _detector.LocalKind(match.Path);
                if (!seen.Add(path.Key)) continue;
                items.Add(new PeekItem(path, DisambiguationHint(match.Path, _home)));
                budget--;
            }
        }
        return items;
    }

    /// <summary>
    /// Short "where is it" hint: <c>C:\Users\me\Desktop\work\img.png</c> → <c>~\Desktop\work</c>;
    /// long paths keep the last two folders (<c>…\Project\assets</c>).
    /// </summary>
    public static string DisambiguationHint(string filePath, string home)
    {
        var parent = Path.GetDirectoryName(filePath) ?? filePath;
        var h = home.TrimEnd('\\');
        var display = parent.Equals(h, StringComparison.OrdinalIgnoreCase) ? "~"
            : parent.StartsWith(h + "\\", StringComparison.OrdinalIgnoreCase) ? "~" + parent[h.Length..]
            : parent;
        if (display.Length <= 24) return display;
        var parts = display.Split('\\', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 3 ? "…\\" + string.Join('\\', parts[^2..]) : display;
    }

    /// <summary>Selection normalization used to decide whether a repeat hotkey press means "close".</summary>
    public static string NormalizeSelection(string text) =>
        string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
}
