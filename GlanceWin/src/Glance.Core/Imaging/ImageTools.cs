namespace Glance.Core.Imaging;

/// <summary>Formats Image Inspect writes. ICO replaces the macOS ICNS export on Windows.</summary>
public enum ImageExportFormat { Png, Jpeg, WebP, Ico }

public static class ImageExportFormats
{
    public static string Extension(this ImageExportFormat format) => format switch
    {
        ImageExportFormat.Jpeg => "jpg",
        ImageExportFormat.WebP => "webp",
        ImageExportFormat.Ico => "ico",
        _ => "png",
    };

    public static string DisplayName(this ImageExportFormat format) => format switch
    {
        ImageExportFormat.Jpeg => "JPG",
        ImageExportFormat.WebP => "WebP",
        ImageExportFormat.Ico => "ICO",
        _ => "PNG",
    };

    /// <summary>
    /// Format a compressed / resized copy keeps (macOS <c>ImageCompressionFormat</c>): the source's
    /// own format when it can be re-encoded, null for formats Glance can't write.
    /// </summary>
    public static ImageExportFormat? ForSource(string pathOrUrl)
    {
        var ext = FileKindsExtension(pathOrUrl);
        return ext switch
        {
            "jpg" or "jpeg" or "jpe" or "jfif" => ImageExportFormat.Jpeg,
            "png" or "apng" or "bmp" or "tif" or "tiff" or "gif" => ImageExportFormat.Png,
            "webp" => ImageExportFormat.WebP,
            _ => null,
        };
    }

    private static string FileKindsExtension(string pathOrUrl)
    {
        var cut = pathOrUrl.IndexOfAny(['?', '#']);
        var path = cut >= 0 && pathOrUrl.Contains("://", StringComparison.Ordinal) ? pathOrUrl[..cut] : pathOrUrl;
        return Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
    }
}

/// <summary>Size estimates and naming shared by the compress / resize / capture flows.</summary>
public static class ImageTools
{
    /// <summary>Displayed target size for a quality (macOS <c>CompressionSizeEstimate</c>).</summary>
    public static long CompressedByteEstimate(long sourceBytes, double quality)
    {
        var q = Math.Clamp(quality, 0.1, 1);
        var factor = 0.18 + 0.82 * Math.Pow(q, 1.45);
        return Math.Max(1024, (long)(Math.Max(1, sourceBytes) * factor));
    }

    /// <summary>Scaled dimensions, or null when the scale would not shrink the image.</summary>
    public static (int Width, int Height)? ResizedDimensions(int width, int height, double scale)
    {
        if (width <= 0 || height <= 0 || scale <= 0 || scale >= 1) return null;
        var w = Math.Max(1, (int)Math.Round(width * scale, MidpointRounding.AwayFromZero));
        var h = Math.Max(1, (int)Math.Round(height * scale, MidpointRounding.AwayFromZero));
        return w < width || h < height ? (w, h) : null;
    }

    public static long ResizedByteEstimate(long sourceBytes, double scale)
    {
        var s = Math.Clamp(scale, 0.0001, 1);
        return Math.Max(1, (long)Math.Round(Math.Max(1, sourceBytes) * s * s));
    }

    /// <summary>Rough encoded size when the real file size is unknown (remote / pasted images).</summary>
    public static long FallbackByteCount(int width, int height) =>
        Math.Max(1_048_576, (long)(Math.Max(1L, (long)width * height) * 0.5));

    /// <summary>"4 : 3" for small ratios, otherwise the decimal ratio (Image Information).</summary>
    public static string? AspectRatioText(int? width, int? height)
    {
        if (width is not > 0 || height is not > 0) return null;
        int Gcd(int a, int b) => b == 0 ? a : Gcd(b, a % b);
        var divisor = Math.Max(1, Gcd(width.Value, height.Value));
        int rw = width.Value / divisor, rh = height.Value / divisor;
        return rw <= 32 && rh <= 32
            ? $"{rw} : {rh}"
            : ((double)width.Value / height.Value).ToString("0.000", System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>"<paramref name="baseName"/>.ext", then "-1", "-2"… until the name is free.</summary>
    public static string UniquePath(string directory, string baseName, string extension, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;
        var path = Path.Combine(directory, $"{baseName}.{extension}");
        for (var counter = 1; exists(path); counter++)
            path = Path.Combine(directory, $"{baseName}-{counter}.{extension}");
        return path;
    }

    /// <summary>Capture file stem from the source name: no extension, no path characters, ≤ 80 chars.</summary>
    public static string CaptureStem(string? sourceName, int width, int height)
    {
        // Sanitize first: on Windows "a:b.png" would otherwise lose "a:" as a drive prefix.
        var name = sourceName ?? "";
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '-');
        var stem = Path.GetFileNameWithoutExtension(name);
        stem = stem.Trim();
        if (stem.Length == 0) stem = "Capture";
        if (stem.Length > 80) stem = stem[..80];
        return $"{stem}-capture-{width}x{height}";
    }

    /// <summary>
    /// Bytes of a pasted Base64 image: plain Base64 or a <c>data:image/…;base64,</c> URL,
    /// whitespace ignored. Null when it isn't valid Base64.
    /// </summary>
    public static byte[]? DecodeBase64Payload(string raw)
    {
        var text = raw.Trim();
        var comma = text.IndexOf(',');
        if (comma > 0 && text[..comma].Contains("base64", StringComparison.OrdinalIgnoreCase)) text = text[(comma + 1)..];
        var compact = new string(text.Where(c => !char.IsWhiteSpace(c)).ToArray());
        // URL-safe alphabet and missing padding are common in pasted payloads.
        compact = compact.Replace('-', '+').Replace('_', '/');
        if (compact.Length % 4 != 0) compact = compact.PadRight(compact.Length + (4 - compact.Length % 4), '=');
        try
        {
            var bytes = Convert.FromBase64String(compact);
            return bytes.Length == 0 ? null : bytes;
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
