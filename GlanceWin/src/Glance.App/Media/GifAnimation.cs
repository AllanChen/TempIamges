using System.IO;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Glance.Core.Detection;
using Glance.Core.Logging;

namespace Glance.App.Media;

/// <summary>
/// An animated GIF decoded into full, composed frames (port of macOS <c>ImageAnimationPlayer</c>'s
/// decoding). WIC hands out GIF frames as patches; they are composed here with their offsets and
/// disposal methods, off the UI thread, into frozen <see cref="BitmapSource"/>s. Very large
/// animations stay still (first frame) instead of using hundreds of MB.
/// </summary>
internal sealed class GifAnimation
{
    private const long MaxDecodedBytes = 192L * 1024 * 1024;
    private const int MaxFrames = 600;

    private GifAnimation(IReadOnlyList<BitmapSource> frames, IReadOnlyList<TimeSpan> delays)
    {
        Frames = frames;
        Delays = delays;
    }

    public IReadOnlyList<BitmapSource> Frames { get; }
    public IReadOnlyList<TimeSpan> Delays { get; }

    public static bool IsCandidate(MediaInfo info) => info.Kind == MediaKind.Image && info.Extension.Equals("gif", StringComparison.OrdinalIgnoreCase);

    /// <summary>Decodes a local or remote GIF; null when it has one frame or can't be animated.</summary>
    public static async Task<GifAnimation?> LoadAsync(MediaInfo info, int maxSide, CancellationToken ct)
    {
        if (!IsCandidate(info)) return null;
        try
        {
            byte[] bytes = info.IsLocal
                ? await File.ReadAllBytesAsync(info.Location, ct)
                : await ImageLoader.DownloadAsync(info.Location, ct);
            return await Task.Run(() => Decode(bytes, maxSide), ct);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or FileFormatException or ArgumentException or InvalidOperationException or System.Net.Http.HttpRequestException)
        {
            Log.Info($"GifAnimation: not animated '{Log.Redact(info.Location)}': {ex.Message}");
            return null;
        }
    }

    public static GifAnimation? Decode(byte[] bytes, int maxSide)
    {
        using var stream = new MemoryStream(bytes, writable: false);
        var decoder = new GifBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count < 2) return null;
        var width = ReadUShort(decoder.Metadata as BitmapMetadata, "/logscrdesc/Width") ?? decoder.Frames[0].PixelWidth;
        var height = ReadUShort(decoder.Metadata as BitmapMetadata, "/logscrdesc/Height") ?? decoder.Frames[0].PixelHeight;
        if (width <= 0 || height <= 0) return null;
        var count = Math.Min(decoder.Frames.Count, MaxFrames);
        var scale = Math.Min(1.0, maxSide / (double)Math.Max(width, height));
        var outW = Math.Max(1, (int)Math.Round(width * scale));
        var outH = Math.Max(1, (int)Math.Round(height * scale));
        if ((long)outW * outH * 4 * count > MaxDecodedBytes) return null;

        var stride = width * 4;
        var canvas = new byte[stride * height];
        var frames = new List<BitmapSource>(count);
        var delays = new List<TimeSpan>(count);
        for (var i = 0; i < count; i++)
        {
            var frame = decoder.Frames[i];
            var meta = frame.Metadata as BitmapMetadata;
            var left = ReadUShort(meta, "/imgdesc/Left") ?? 0;
            var top = ReadUShort(meta, "/imgdesc/Top") ?? 0;
            var disposal = ReadByte(meta, "/grctlext/Disposal") ?? 0;
            var delayCs = ReadUShort(meta, "/grctlext/Delay") ?? 10;
            byte[]? previous = disposal == 3 ? (byte[])canvas.Clone() : null;

            var patch = new FormatConvertedBitmap(frame, PixelFormats.Bgra32, null, 0);
            var pw = patch.PixelWidth;
            var ph = patch.PixelHeight;
            var pixels = new byte[pw * ph * 4];
            patch.CopyPixels(pixels, pw * 4, 0);
            for (var y = 0; y < ph; y++)
            {
                var cy = top + y;
                if (cy < 0 || cy >= height) continue;
                for (var x = 0; x < pw; x++)
                {
                    var cx = left + x;
                    if (cx < 0 || cx >= width) continue;
                    var src = (y * pw + x) * 4;
                    if (pixels[src + 3] == 0) continue; // transparent pixel: keep what's below
                    var dst = cy * stride + cx * 4;
                    canvas[dst] = pixels[src];
                    canvas[dst + 1] = pixels[src + 1];
                    canvas[dst + 2] = pixels[src + 2];
                    canvas[dst + 3] = pixels[src + 3];
                }
            }

            BitmapSource composed = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, canvas, stride);
            if (scale < 1)
                composed = new TransformedBitmap(composed, new ScaleTransform(scale, scale));
            composed.Freeze();
            frames.Add(composed);
            // Browsers treat 0–1 cs delays as 100 ms; so does macOS.
            delays.Add(TimeSpan.FromMilliseconds(delayCs <= 1 ? 100 : delayCs * 10));

            if (disposal == 2)
            {
                for (var y = Math.Max(0, top); y < Math.Min(height, top + ph); y++)
                    Array.Clear(canvas, y * stride + Math.Max(0, left) * 4, Math.Max(0, Math.Min(width, left + pw) - Math.Max(0, left)) * 4);
            }
            else if (previous is not null)
            {
                canvas = previous;
            }
        }
        return new GifAnimation(frames, delays);
    }

    /// <summary>A looping key-frame animation for <c>Image.SourceProperty</c> (Peek, Market).</summary>
    public ObjectAnimationUsingKeyFrames ToAnimation()
    {
        var animation = new ObjectAnimationUsingKeyFrames { RepeatBehavior = RepeatBehavior.Forever };
        var time = TimeSpan.Zero;
        for (var i = 0; i < Frames.Count; i++)
        {
            animation.KeyFrames.Add(new DiscreteObjectKeyFrame(Frames[i], KeyTime.FromTimeSpan(time)));
            time += Delays[i];
        }
        animation.Duration = time;
        animation.Freeze();
        return animation;
    }

    private static int? ReadUShort(BitmapMetadata? meta, string query)
    {
        try
        {
            return meta?.GetQuery(query) switch
            {
                ushort u => u,
                short s => s,
                int i => i,
                byte b => b,
                _ => null,
            };
        }
        catch (Exception ex) when (ex is NotSupportedException or ArgumentException or InvalidOperationException)
        {
            return null;
        }
    }

    private static int? ReadByte(BitmapMetadata? meta, string query) => ReadUShort(meta, query);
}

/// <summary>Plays a <see cref="GifAnimation"/> by calling back with each frame (Image Inspect's drawn viewport).</summary>
internal sealed class GifPlayer : IDisposable
{
    private readonly GifAnimation _animation;
    private readonly Action<BitmapSource> _onFrame;
    private readonly DispatcherTimer _timer = new(DispatcherPriority.Render);
    private int _index;

    public GifPlayer(GifAnimation animation, Action<BitmapSource> onFrame)
    {
        _animation = animation;
        _onFrame = onFrame;
        _timer.Tick += (_, _) => Advance();
    }

    public GifAnimation Animation => _animation;

    public void Start()
    {
        if (_timer.IsEnabled) return;
        _onFrame(_animation.Frames[_index]);
        _timer.Interval = _animation.Delays[_index];
        _timer.Start();
    }

    public void Stop() => _timer.Stop();

    private void Advance()
    {
        _index = (_index + 1) % _animation.Frames.Count;
        _timer.Interval = _animation.Delays[_index];
        _onFrame(_animation.Frames[_index]);
    }

    public void Dispose() => _timer.Stop();
}
