namespace Glance.Core.Detection;

public enum MediaKind { Image, Video, Markdown, Text, Pdf, WebPage, Other, Folder }

/// <summary>
/// What a Peek tile/viewer shows (port of macOS <c>MediaInfo</c>). <see cref="Location"/> is a
/// full path when <see cref="IsLocal"/>, otherwise an absolute URL.
/// </summary>
public sealed record MediaInfo(string Location, bool IsLocal, MediaKind Kind)
{
    public int? PixelWidth { get; init; }
    public int? PixelHeight { get; init; }
    /// <summary>Bytes. Local files, or remote files once downloaded.</summary>
    public long? FileSize { get; init; }
    public TimeSpan? Duration { get; init; }
    /// <summary>Where the file lives, e.g. "~\Desktop\work", to tell same-named search hits apart.</summary>
    public string? DisambiguationHint { get; init; }
    /// <summary>The search token that led to this tile (bare filename etc.).</summary>
    public string? SearchToken { get; init; }
    public string? SourceAppName { get; init; }

    public string FileName
    {
        get
        {
            if (IsLocal)
            {
                var trimmed = Location.TrimEnd('\\', '/');
                var name = Path.GetFileName(trimmed);
                return string.IsNullOrEmpty(name) ? Location : name;
            }
            if (!Uri.TryCreate(Location, UriKind.Absolute, out var uri)) return Location;
            var segment = uri.Segments.Length > 0 ? uri.Segments[^1].Trim('/') : "";
            return segment.Length > 0 ? Uri.UnescapeDataString(segment) : uri.Host;
        }
    }

    public string Extension => FileKinds.ExtensionOf(IsLocal ? Location : StripQuery(Location));

    public string FormatName => Extension.ToUpperInvariant();

    /// <summary>Kinds without an inline Peek preview; clicking opens a viewer.</summary>
    public bool OpensInViewer => Kind is MediaKind.Markdown or MediaKind.Text or MediaKind.WebPage or MediaKind.Pdf;

    public bool HasIconContent => OpensInViewer || Kind is MediaKind.Other or MediaKind.Folder;

    public static MediaInfo? From(DetectedPath path)
    {
        if (path.MediaKind is not { } kind) return null;
        return new MediaInfo(path.Value, path.IsLocal, kind);
    }

    private static string StripQuery(string url)
    {
        var cut = url.IndexOfAny(['?', '#']);
        return cut >= 0 ? url[..cut] : url;
    }
}
