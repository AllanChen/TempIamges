namespace Glance.Core.Detection;

public enum DetectedKind
{
    LocalImage, RemoteImage,
    LocalVideo, RemoteVideo,
    LocalMarkdown, RemoteMarkdown,
    LocalText, RemoteText,
    LocalPdf, RemotePdf,
    WebPage,
    LocalOther, RemoteOther,
    LocalFolder,
    /// <summary>Bare filename (no separators), e.g. "screenshot.png". Resolved by search.</summary>
    UnresolvedFilename,
    /// <summary>Relative path with a separator, e.g. "assets\foo.png". Resolved by search.</summary>
    UnresolvedRelativePath,
}

/// <summary>
/// One hit from <see cref="PathDetector"/> (port of the macOS <c>DetectedPath</c> enum).
/// <see cref="Value"/> is a full Windows path for local kinds, an absolute URL for remote
/// kinds, and the raw token for unresolved kinds.
/// </summary>
public sealed record DetectedPath(DetectedKind Kind, string Value)
{
    public bool IsUnresolved => Kind is DetectedKind.UnresolvedFilename or DetectedKind.UnresolvedRelativePath;

    public bool IsLocal => Kind is DetectedKind.LocalImage or DetectedKind.LocalVideo or DetectedKind.LocalMarkdown
        or DetectedKind.LocalText or DetectedKind.LocalPdf or DetectedKind.LocalOther or DetectedKind.LocalFolder;

    public bool IsResolved => !IsUnresolved;

    public string? UnresolvedToken => IsUnresolved ? Value : null;

    /// <summary>Dedup key: local paths compare case-insensitively, URLs and tokens exactly.</summary>
    public string Key => IsLocal ? "file:" + Value.ToUpperInvariant() : Value;

    public MediaKind? MediaKind => Kind switch
    {
        DetectedKind.LocalImage or DetectedKind.RemoteImage => Detection.MediaKind.Image,
        DetectedKind.LocalVideo or DetectedKind.RemoteVideo => Detection.MediaKind.Video,
        DetectedKind.LocalMarkdown or DetectedKind.RemoteMarkdown => Detection.MediaKind.Markdown,
        DetectedKind.LocalText or DetectedKind.RemoteText => Detection.MediaKind.Text,
        DetectedKind.LocalPdf or DetectedKind.RemotePdf => Detection.MediaKind.Pdf,
        DetectedKind.WebPage => Detection.MediaKind.WebPage,
        DetectedKind.LocalOther or DetectedKind.RemoteOther => Detection.MediaKind.Other,
        DetectedKind.LocalFolder => Detection.MediaKind.Folder,
        _ => null,
    };

    public static DetectedKind LocalKindFor(MediaKind kind) => kind switch
    {
        Detection.MediaKind.Image => DetectedKind.LocalImage,
        Detection.MediaKind.Video => DetectedKind.LocalVideo,
        Detection.MediaKind.Markdown => DetectedKind.LocalMarkdown,
        Detection.MediaKind.Text => DetectedKind.LocalText,
        Detection.MediaKind.Pdf => DetectedKind.LocalPdf,
        Detection.MediaKind.Folder => DetectedKind.LocalFolder,
        _ => DetectedKind.LocalOther,
    };

    public static DetectedKind RemoteKindFor(MediaKind kind) => kind switch
    {
        Detection.MediaKind.Image => DetectedKind.RemoteImage,
        Detection.MediaKind.Video => DetectedKind.RemoteVideo,
        Detection.MediaKind.Markdown => DetectedKind.RemoteMarkdown,
        Detection.MediaKind.Text => DetectedKind.RemoteText,
        Detection.MediaKind.Pdf => DetectedKind.RemotePdf,
        Detection.MediaKind.Other => DetectedKind.RemoteOther,
        _ => DetectedKind.WebPage,
    };
}
