namespace Glance.Core.Detection;

/// <summary>
/// Extension tables, ported from macOS <c>ImageFormatSupport</c> / <c>PathDetector</c>.
/// Classification only — whether Windows can actually decode a format is decided at load
/// time (WIC codec, shell thumbnail, or a file card as the last resort).
/// </summary>
public static class FileKinds
{
    private static HashSet<string> Set(params string[] items) => new(items, StringComparer.OrdinalIgnoreCase);

    public static readonly IReadOnlySet<string> Image = Set(
        // Web and general-purpose raster
        "jpg", "jpeg", "jpe", "jfif", "png", "apng", "gif", "webp",
        "heic", "heif", "heics", "avif", "avifs", "jxl",
        "bmp", "dib", "tif", "tiff",
        // JPEG 2000 and multi-picture
        "jp2", "j2k", "jpf", "jpx", "jpm", "mj2", "mpo",
        // Vector, design, HDR, and legacy workstation formats
        "svg", "svgz", "psd", "psb", "ai", "eps", "exr", "hdr", "rgbe",
        "tga", "targa", "sgi", "rgb", "rgba", "bw", "pict", "pct", "pic",
        // Icons and GPU textures
        "ico", "cur", "icns", "dds", "ktx", "ktx2", "astc", "pvr",
        // Portable anymap family
        "pbm", "pgm", "ppm", "pnm",
        // Camera RAW families
        "3fr", "ari", "arw", "bay", "bmq", "cap", "cr2", "cr3", "crw",
        "cs1", "dc2", "dcr", "dng", "drf", "eip", "erf", "fff", "iiq",
        "k25", "kdc", "mdc", "mef", "mos", "mrw", "nef", "nrw", "obm",
        "orf", "pef", "ptx", "pxn", "qtk", "raf", "raw", "rdc", "rw2",
        "rwl", "rwz", "sr2", "srf", "srw", "x3f");

    // Deviation from macOS: "ts" is TypeScript (Text) here, not MPEG-TS video —
    // TypeScript paths are far more common in selected text on developer machines.
    public static readonly IReadOnlySet<string> Video = Set(
        "mp4", "mov", "m4v", "mpg", "mpeg", "mpe", "m2v",
        "m2ts", "mts", "3gp", "3gpp", "3g2",
        "webm", "mkv", "avi", "wmv");

    public static readonly IReadOnlySet<string> Markdown = Set("md", "markdown");

    public static readonly IReadOnlySet<string> Text = Set(
        // Data / config
        "txt", "json", "xml", "yaml", "yml", "toml", "ini", "conf", "env",
        "properties", "cfg", "csv", "tsv", "sql", "log",
        // Markup / web
        "html", "htm", "css", "scss", "sass", "less", "styl",
        "tex", "rst", "adoc", "asciidoc", "org",
        // Programming languages
        "py", "js", "mjs", "cjs", "ts", "tsx", "jsx",
        "swift", "java", "kt", "m", "mm",
        "c", "cpp", "cc", "cxx", "h", "hpp",
        "rb", "go", "rs", "php", "cs", "vb", "scala", "lua", "pl", "r",
        "dart", "ex", "exs", "erl", "hs", "ml", "fs", "jl",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
        "graphql", "gql", "proto", "vue", "svelte", "astro",
        // Windows additions
        "psm1", "psd1", "reg", "vbs", "xaml", "csproj", "sln", "slnx", "props", "targets");

    public static readonly IReadOnlySet<string> Pdf = Set("pdf");

    /// <summary>Known files with no inline preview: shown as a file card (open / show in folder).</summary>
    public static readonly IReadOnlySet<string> Other = Set(
        // Documents
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "odt", "ods", "odp", "rtf",
        "epub", "mobi",
        // Design project formats that aren't directly image-decodable
        "sketch", "fig", "xd", "indd", "afdesign",
        // Audio
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff",
        // Archives / disk images
        "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "dmg", "iso",
        // Binaries / installers
        "exe", "app", "deb", "rpm", "pkg", "msi", "msix", "appimage",
        // Fonts
        "ttf", "otf", "woff", "woff2");

    /// <summary>Every extension the local-path regexes accept.</summary>
    public static readonly IReadOnlySet<string> AllLocal =
        new HashSet<string>(Image.Concat(Video).Concat(Markdown).Concat(Text).Concat(Pdf).Concat(Other),
            StringComparer.OrdinalIgnoreCase);

    public static MediaKind KindForExtension(string extension)
    {
        if (Video.Contains(extension)) return MediaKind.Video;
        if (Image.Contains(extension)) return MediaKind.Image;
        if (Markdown.Contains(extension)) return MediaKind.Markdown;
        if (Text.Contains(extension)) return MediaKind.Text;
        if (Pdf.Contains(extension)) return MediaKind.Pdf;
        return MediaKind.Other;
    }

    /// <summary>Extension of the last path segment without the dot, or "" (no IO, safe for URLs).</summary>
    public static string ExtensionOf(string path)
    {
        var end = path.Length;
        while (end > 0 && (path[end - 1] == '\\' || path[end - 1] == '/')) end--;
        var start = path.LastIndexOfAny(['\\', '/'], Math.Max(0, end - 1)) + 1;
        var dot = path.LastIndexOf('.', Math.Max(0, end - 1));
        // dot == start is a dotfile (".gitignore"): no extension, same as NSString.pathExtension.
        if (dot <= start || dot >= end - 1) return "";
        var ext = path[(dot + 1)..end];
        return ext.Length <= 10 && ext.All(char.IsLetterOrDigit) ? ext.ToLowerInvariant() : "";
    }
}
