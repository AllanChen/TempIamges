using System.Net.Http;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.Core.Detection;
using Glance.Core.Logging;
using Glance.Platform;

namespace Glance.App.Media;

/// <summary>Result of loading one tile. <see cref="Info"/> carries any discovered dimensions/size.</summary>
internal sealed record LoadedMedia(MediaInfo Info, ImageSource? Image, bool IsIcon, string? Error)
{
    public bool Failed => Image is null && Error is not null;
}

/// <summary>
/// Async media loading for Peek (port of macOS <c>ImageLoader</c>): bounded decode size,
/// EXIF orientation, remote download with a size cap, shell thumbnails for video/documents,
/// file-type icons as the last resort. At most four loads run at once. Results are frozen.
/// </summary>
internal sealed class ImageLoader
{
    private const long MaxRemoteBytes = 30L * 1024 * 1024;
    private static readonly HttpClient Http = CreateClient();
    private readonly SemaphoreSlim _gate = new(4, 4);

    public async Task<LoadedMedia> LoadAsync(MediaInfo info, int maxPixelSide, CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            return info.Kind switch
            {
                MediaKind.Image => info.IsLocal ? await LoadLocalImage(info, maxPixelSide) : await LoadRemoteImage(info, maxPixelSide, ct),
                MediaKind.Video => await LoadVideo(info),
                MediaKind.WebPage => new LoadedMedia(info, null, true, null),
                _ => await LoadFileIcon(info),
            };
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            Log.Warning($"ImageLoader: failed for '{Log.Redact(info.Location)}': {ex.Message}");
            return new LoadedMedia(info, await IconFor(info), true, ex.Message);
        }
        finally
        {
            _gate.Release();
        }
    }

    private static async Task<LoadedMedia> LoadLocalImage(MediaInfo info, int maxSide)
    {
        var size = TryFileSize(info.Location);
        var decoded = await Task.Run(() =>
        {
            using var stream = new FileStream(info.Location, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return TryDecode(stream, maxSide);
        });
        if (decoded is { } d)
            return new LoadedMedia(info with { PixelWidth = d.Width, PixelHeight = d.Height, FileSize = size }, d.Image, false, null);

        // No WIC codec (e.g. HEIC/AVIF without the Store extension, RAW, PSD): try Explorer's thumbnail.
        var thumb = await ShellThumbnails.GetAsync(info.Location, maxSide, thumbnailOnly: true);
        if (thumb is not null) return new LoadedMedia(info with { FileSize = size }, thumb, false, null);
        return new LoadedMedia(info with { FileSize = size }, await IconFor(info), true, "No decoder for this image format");
    }

    private static async Task<LoadedMedia> LoadRemoteImage(MediaInfo info, int maxSide, CancellationToken ct)
    {
        var bytes = await DownloadAsync(info.Location, ct);
        var decoded = await Task.Run(() =>
        {
            using var stream = new MemoryStream(bytes, writable: false);
            return TryDecode(stream, maxSide);
        }, ct);
        var withSize = info with { FileSize = bytes.LongLength };
        if (decoded is { } d)
            return new LoadedMedia(withSize with { PixelWidth = d.Width, PixelHeight = d.Height }, d.Image, false, null);
        return new LoadedMedia(withSize, await IconFor(info), true, "Unsupported image data");
    }

    private static async Task<LoadedMedia> LoadVideo(MediaInfo info)
    {
        if (!info.IsLocal) return new LoadedMedia(info, await IconFor(info), true, null);
        var size = TryFileSize(info.Location);
        var thumb = await ShellThumbnails.GetAsync(info.Location, 640, thumbnailOnly: true);
        return thumb is not null
            ? new LoadedMedia(info with { FileSize = size }, thumb, false, null)
            : new LoadedMedia(info with { FileSize = size }, await IconFor(info), true, null);
    }

    private static async Task<LoadedMedia> LoadFileIcon(MediaInfo info)
    {
        long? size = info.IsLocal && info.Kind != MediaKind.Folder ? TryFileSize(info.Location) : null;
        if (info.IsLocal)
        {
            var thumb = await ShellThumbnails.GetAsync(info.Location, 256);
            if (thumb is not null) return new LoadedMedia(info with { FileSize = size }, thumb, true, null);
        }
        return new LoadedMedia(info with { FileSize = size }, await IconFor(info), true, null);
    }

    /// <summary>File-type icon by extension (works for remote and missing files).</summary>
    public static Task<ImageSource?> IconFor(MediaInfo info) =>
        Task.Run<ImageSource?>(() => ShellThumbnails.IconForExtension(info.Kind == MediaKind.Folder ? "folder" : "." + info.Extension));

    private readonly record struct Decoded(BitmapSource Image, int Width, int Height);

    /// <summary>Decodes at most <paramref name="maxSide"/> pixels on the long edge, honoring EXIF orientation.</summary>
    private static Decoded? TryDecode(Stream stream, int maxSide)
    {
        try
        {
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
            var frame = decoder.Frames[0];
            int width = frame.PixelWidth, height = frame.PixelHeight;
            var orientation = ReadOrientation(frame);

            stream.Position = 0;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = stream;
            if (Math.Max(width, height) > maxSide)
            {
                if (width >= height) image.DecodePixelWidth = maxSide;
                else image.DecodePixelHeight = maxSide;
            }
            image.EndInit();

            BitmapSource result = image;
            var transform = OrientationTransform(orientation);
            if (transform is not null) result = new TransformedBitmap(image, transform);
            result.Freeze();

            var swapped = orientation is >= 5 and <= 8;
            return new Decoded(result, swapped ? height : width, swapped ? width : height);
        }
        catch (Exception ex) when (ex is NotSupportedException or FileFormatException or ArgumentException
                                       or InvalidOperationException or System.Runtime.InteropServices.COMException or OverflowException)
        {
            Log.Info($"ImageLoader: WIC could not decode: {ex.GetType().Name}");
            return null;
        }
    }

    private static int ReadOrientation(BitmapFrame frame)
    {
        try
        {
            if (frame.Metadata is BitmapMetadata meta && meta.GetQuery("System.Photo.Orientation") is ushort value)
                return value;
        }
        catch (Exception ex) when (ex is NotSupportedException or InvalidOperationException or ArgumentException)
        {
            // Format without metadata support.
        }
        return 1;
    }

    /// <summary>EXIF orientation 2–8 as a WPF transform (RotateTransform angles are clockwise).</summary>
    private static Transform? OrientationTransform(int orientation)
    {
        Transform Group(bool flip, double angle)
        {
            var group = new TransformGroup();
            if (flip) group.Children.Add(new ScaleTransform(-1, 1));
            if (angle != 0) group.Children.Add(new RotateTransform(angle));
            return group;
        }

        return orientation switch
        {
            2 => new ScaleTransform(-1, 1),
            3 => new RotateTransform(180),
            4 => new ScaleTransform(1, -1),
            5 => Group(true, 270),
            6 => new RotateTransform(90),
            7 => Group(true, 90),
            8 => new RotateTransform(270),
            _ => null,
        };
    }

    /// <summary>GET with a size cap (shared with the content viewer).</summary>
    internal static async Task<byte[]> DownloadAsync(string url, CancellationToken ct, long maxBytes = MaxRemoteBytes)
    {
        using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > maxBytes)
            throw new InvalidDataException("Remote file is too large to preview");
        await using var source = await response.Content.ReadAsStreamAsync(ct);
        using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        int read;
        while ((read = await source.ReadAsync(chunk, ct)) > 0)
        {
            buffer.Write(chunk, 0, read);
            if (buffer.Length > maxBytes) throw new InvalidDataException("Remote file is too large to preview");
        }
        return buffer.ToArray();
    }

    private static long? TryFileSize(string path)
    {
        try { return new FileInfo(path).Length; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Glance/0.1 (Windows)");
        return client;
    }
}
