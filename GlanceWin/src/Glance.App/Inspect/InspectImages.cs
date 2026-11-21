using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.App.Media;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Logging;

namespace Glance.App.Inspect;

/// <summary>Technical details for Image Information (macOS <c>ImageTechnicalMetadata</c>).</summary>
internal sealed record ImageDetails(string? ColorSpace, int? BitDepth, bool? HasAlpha, DateTime? Created);

/// <summary>
/// Bridges WPF imaging and the Core encoders: BitmapSource ↔ <see cref="PixelImage"/>, original
/// resolution decoding for exports, metadata, clipboard and temp files. Everything that touches
/// the disk or decodes runs off the UI thread; inputs are frozen bitmaps.
/// </summary>
internal static class InspectImages
{
    /// <summary>Longest side decoded for display. Exports re-decode the original.</summary>
    public const int DisplayMaxSide = 8192;
    public const int ThumbnailMaxSide = 128;
    private const int OriginalMaxSide = 30_000;

    public static string PastedImagesFolder => Path.Combine(Path.GetTempPath(), "Glance", "Images");

    public static string QuickSaveFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Glance");

    public static string CaptureFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Glance");

    public static PixelImage ToPixels(BitmapSource source)
    {
        BitmapSource converted = source.Format == PixelFormats.Pbgra32 ? source : new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
        var width = converted.PixelWidth;
        var height = converted.PixelHeight;
        var pixels = new byte[width * height * 4];
        converted.CopyPixels(pixels, width * 4, 0);
        return new PixelImage(width, height, pixels);
    }

    public static BitmapSource ToBitmap(PixelImage image)
    {
        var bitmap = BitmapSource.Create(image.Width, image.Height, 96, 96, PixelFormats.Pbgra32, null, image.Pixels, image.Stride);
        bitmap.Freeze();
        return bitmap;
    }

    /// <summary>
    /// The item at its original resolution (EXIF orientation applied) for copy / export /
    /// compress. Falls back to the displayed bitmap when the original can't be decoded again.
    /// </summary>
    public static async Task<PixelImage?> OriginalPixelsAsync(ImageLoader loader, MediaInfo info, BitmapSource? displayed, CancellationToken ct = default)
    {
        try
        {
            var media = await loader.LoadAsync(info, OriginalMaxSide, ct);
            var source = media is { IsIcon: false, Image: BitmapSource bitmap } ? bitmap : displayed;
            return source is null ? null : await Task.Run(() => ToPixels(source), ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            Log.Warning($"Inspect: original decode failed for '{Log.Redact(info.Location)}': {ex.Message}");
            return displayed is null ? null : await Task.Run(() => ToPixels(displayed), ct);
        }
    }

    public static Task<ImageDetails?> ReadDetailsAsync(MediaInfo info) => Task.Run<ImageDetails?>(() =>
    {
        if (!info.IsLocal) return null;
        try
        {
            DateTime? created = File.GetCreationTime(info.Location);
            using var stream = new FileStream(info.Location, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
            var frame = decoder.Frames[0];
            var format = frame.Format;
            var name = format.ToString();
            var hasAlpha = name is "Bgra32" or "Pbgra32" or "Rgba64" or "Prgba64" or "Rgba128Float" or "Prgba128Float";
            string colorSpace = name.StartsWith("Cmyk", StringComparison.Ordinal) ? "CMYK"
                : name.StartsWith("Gray", StringComparison.Ordinal) || name.StartsWith("BlackWhite", StringComparison.Ordinal) ? "Gray"
                : HasColorProfile(frame) ? "RGB (ICC profile)" : "sRGB";
            // Bits of the first channel mask = bits per channel (Bgr32 has an unused byte, so BitsPerPixel / channels lies).
            int? depth = name.StartsWith("Indexed", StringComparison.Ordinal) ? 8
                : format.Masks is { Count: > 0 } masks ? masks[0].Mask.Sum(b => System.Numerics.BitOperations.PopCount(b)) : null;
            return new ImageDetails(colorSpace, depth, hasAlpha, created);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or FileFormatException
                                       or ArgumentException or InvalidOperationException or COMException or OverflowException)
        {
            try { return new ImageDetails(null, null, null, File.GetCreationTime(info.Location)); }
            catch (Exception inner) when (inner is IOException or UnauthorizedAccessException) { return null; }
        }
    });

    private static bool HasColorProfile(BitmapFrame frame)
    {
        try { return frame.ColorContexts is { Count: > 0 }; }
        catch (Exception ex) when (ex is NotSupportedException or InvalidOperationException or COMException) { return false; }
    }

    /// <summary>Copies an image as PNG (keeps transparency) plus a DIB for apps that only read bitmaps.</summary>
    public static bool CopyToClipboard(BitmapSource image, byte[] png)
    {
        try
        {
            var data = new DataObject();
            data.SetImage(image);
            data.SetData("PNG", new MemoryStream(png), false);
            Clipboard.SetDataObject(data, copy: true);
            return true;
        }
        catch (Exception ex) when (ex is COMException or ExternalException)
        {
            Log.Warning($"Inspect: clipboard is busy: {ex.Message}");
            return false;
        }
    }

    public static bool CopyText(string text)
    {
        try
        {
            Clipboard.SetDataObject(text, copy: true);
            return true;
        }
        catch (Exception ex) when (ex is COMException or ExternalException)
        {
            Log.Warning($"Inspect: clipboard is busy: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Image data on the clipboard (screenshots, "Copy image" in browsers): the PNG stream when
    /// present (keeps alpha), otherwise the bitmap. Read once on a user Ctrl+V, never polled.
    /// </summary>
    public static PixelImage? ClipboardImage()
    {
        try
        {
            if (Clipboard.GetData("PNG") is MemoryStream png && ImageCodec.Decode(png.ToArray()) is { } decoded) return decoded;
            if (Clipboard.ContainsImage() && Clipboard.GetImage() is { } bitmap)
            {
                // CF_DIB has no real alpha: force opaque so screenshots don't turn transparent.
                var pixels = ToPixels(bitmap);
                for (var i = 3; i < pixels.Pixels.Length; i += 4) pixels.Pixels[i] = 255;
                return pixels;
            }
        }
        catch (Exception ex) when (ex is COMException or ExternalException or OutOfMemoryException)
        {
            Log.Warning($"Inspect: clipboard image unreadable: {ex.Message}");
        }
        return null;
    }

    /// <summary>Clipboard text or the first copied file path; null when there is neither.</summary>
    public static string? ClipboardText()
    {
        try
        {
            if (Clipboard.ContainsText()) return Clipboard.GetText();
            if (Clipboard.ContainsFileDropList() && Clipboard.GetFileDropList() is { Count: > 0 } files) return files[0];
        }
        catch (Exception ex) when (ex is COMException or ExternalException)
        {
            Log.Warning($"Inspect: clipboard text unreadable: {ex.Message}");
        }
        return null;
    }

    /// <summary>Writes a pasted / dropped / Base64 image to a temp PNG so it behaves like a file.</summary>
    public static Task<string?> SaveTempPngAsync(PixelImage image, string prefix) => Task.Run<string?>(() =>
    {
        try
        {
            var png = ImageCodec.Encode(image, ImageExportFormat.Png);
            if (png is null) return null;
            Directory.CreateDirectory(PastedImagesFolder);
            var path = Path.Combine(PastedImagesFolder, $"{prefix}-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid().ToString("N")[..6]}.png");
            File.WriteAllBytes(path, png);
            return path;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Warning($"Inspect: temp image write failed: {ex.Message}");
            return null;
        }
    });

    /// <summary>Writes bytes atomically enough for exports: temp file in the same folder, then move.</summary>
    public static void WriteFile(string path, byte[] bytes)
    {
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid().ToString("N")[..8]}.tmp");
        try
        {
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch (IOException) { }
        }
    }

    /// <summary>Folder for compressed / resized copies: next to a local source, else Downloads.</summary>
    public static string OutputFolder(MediaInfo source)
    {
        if (source.IsLocal && Path.GetDirectoryName(source.Location) is { Length: > 0 } folder) return folder;
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }
}
