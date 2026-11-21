using System.Runtime.InteropServices;
using Glance.Core.Logging;
using SkiaSharp;

namespace Glance.Core.Imaging;

/// <summary>
/// Image Inspect's pixel work (port of macOS <c>ImageExporter</c> / <c>CaptureFreeze</c>):
/// orientation, resize, crop, compare composites and PNG / JPEG / WebP / ICO encoding through
/// SkiaSharp (WIC has no WebP encoder). Pure functions; safe on any thread. Never touches the
/// source file. Colors are ARGB (0xAARRGGBB).
/// </summary>
public static class ImageCodec
{
    /// <summary>Longest side of a compare composite (bounds memory for huge images).</summary>
    public const int MaxCompositeSide = 12_000;
    private static readonly SKSamplingOptions Sampling = new(SKFilterMode.Linear, SKMipmapMode.Linear);

    // ───────────────────────────── Transforms ─────────────────────────────

    /// <summary>The image as the viewport shows it: flips on the image axes first, then clockwise quarter turns.</summary>
    public static PixelImage Orient(PixelImage image, int quarters, bool flipX = false, bool flipY = false)
    {
        var result = flipX || flipY ? Flip(image, flipX, flipY) : image;
        var q = ViewportMath.NormalizeQuarters(quarters);
        return q == 0 ? result : Rotate(result, q);
    }

    public static PixelImage Rotate(PixelImage image, int quarters)
    {
        var q = ViewportMath.NormalizeQuarters(quarters);
        if (q == 0) return image;
        var swapped = q % 2 == 1;
        var outW = swapped ? image.Height : image.Width;
        var outH = swapped ? image.Width : image.Height;
        return Draw(outW, outH, null, (canvas, source) =>
        {
            switch (q)
            {
                case 1: canvas.Translate(outW, 0); canvas.RotateDegrees(90); break;
                case 2: canvas.Translate(outW, outH); canvas.RotateDegrees(180); break;
                case 3: canvas.Translate(0, outH); canvas.RotateDegrees(270); break;
            }
            canvas.DrawImage(source, SKRect.Create(image.Width, image.Height), Sampling);
        }, image);
    }

    public static PixelImage Flip(PixelImage image, bool horizontal, bool vertical) =>
        Draw(image.Width, image.Height, null, (canvas, source) =>
        {
            canvas.Translate(horizontal ? image.Width : 0, vertical ? image.Height : 0);
            canvas.Scale(horizontal ? -1 : 1, vertical ? -1 : 1);
            canvas.DrawImage(source, SKRect.Create(image.Width, image.Height), Sampling);
        }, image);

    public static PixelImage Resize(PixelImage image, int width, int height) =>
        Draw(Math.Max(1, width), Math.Max(1, height), null, (canvas, source) =>
            canvas.DrawImage(source, SKRect.Create(Math.Max(1, width), Math.Max(1, height)), Sampling), image);

    /// <summary>Top-left pixel crop, clamped to the image.</summary>
    public static PixelImage Crop(PixelImage image, RectD rect)
    {
        var x = (int)Math.Clamp(Math.Floor(rect.X), 0, image.Width - 1);
        var y = (int)Math.Clamp(Math.Floor(rect.Y), 0, image.Height - 1);
        var w = (int)Math.Clamp(Math.Ceiling(rect.Width), 1, image.Width - x);
        var h = (int)Math.Clamp(Math.Ceiling(rect.Height), 1, image.Height - y);
        if (x == 0 && y == 0 && w == image.Width && h == image.Height) return image;
        var pixels = new byte[w * h * 4];
        for (var row = 0; row < h; row++)
            Buffer.BlockCopy(image.Pixels, ((y + row) * image.Width + x) * 4, pixels, row * w * 4, w * 4);
        return new PixelImage(w, h, pixels);
    }

    /// <summary>Scales down so the longest side is at most <paramref name="maxSide"/>.</summary>
    public static PixelImage LimitSide(PixelImage image, int maxSide)
    {
        var longest = Math.Max(image.Width, image.Height);
        if (longest <= maxSide) return image;
        var scale = (double)maxSide / longest;
        return Resize(image, (int)Math.Round(image.Width * scale), (int)Math.Round(image.Height * scale));
    }

    // ───────────────────────────── Compare composites ─────────────────────────────

    /// <summary>Compare ▸ Side by side: both images at a common height with a 2 px gap.</summary>
    public static PixelImage SideBySide(PixelImage a, PixelImage b, uint background, int maxHeight = 4096, int maxWidth = 8192)
    {
        double height = Math.Min(maxHeight, Math.Max(a.Height, b.Height));
        var aWidth = a.Width * height / a.Height;
        var bWidth = b.Width * height / b.Height;
        double gap = 2;
        if (aWidth + bWidth + gap > maxWidth)
        {
            var scale = (maxWidth - gap) / (aWidth + bWidth);
            height *= scale;
            aWidth *= scale;
            bWidth *= scale;
        }
        var outW = (int)Math.Ceiling(aWidth + gap + bWidth);
        var outH = (int)Math.Ceiling(height);
        using var aSkia = ToSkImage(a);
        using var bSkia = ToSkImage(b);
        return Draw(outW, outH, background, (canvas, _) =>
        {
            canvas.DrawImage(aSkia, SKRect.Create(0, 0, (float)aWidth, (float)height), Sampling);
            canvas.DrawImage(bSkia, SKRect.Create((float)(aWidth + gap), 0, (float)bWidth, (float)height), Sampling);
        });
    }

    /// <summary>
    /// Compare ▸ Slider: A fills the picture, B covers the part left of the divider, which sits
    /// at <paramref name="fraction"/> of the width (2 px, <paramref name="divider"/> color).
    /// </summary>
    public static PixelImage Slider(PixelImage a, PixelImage b, double fraction, uint background, uint divider, int maxSide = 4096)
    {
        var rawW = Math.Max(a.Width, b.Width);
        var rawH = Math.Max(a.Height, b.Height);
        var scale = Math.Min(1.0, (double)maxSide / Math.Max(rawW, rawH));
        var outW = Math.Max(1, (int)Math.Ceiling(rawW * scale));
        var outH = Math.Max(1, (int)Math.Ceiling(rawH * scale));
        using var aSkia = ToSkImage(a);
        using var bSkia = ToSkImage(b);
        var split = (float)(Math.Clamp(fraction, 0, 1) * outW);
        return Draw(outW, outH, background, (canvas, _) =>
        {
            var area = SKRect.Create(outW, outH);
            canvas.DrawImage(aSkia, AspectFit(a, area), Sampling);
            canvas.Save();
            canvas.ClipRect(SKRect.Create(0, 0, split, outH));
            canvas.DrawImage(bSkia, AspectFit(b, area), Sampling);
            canvas.Restore();
            using var paint = new SKPaint { Color = new SKColor(divider), IsAntialias = false };
            canvas.DrawRect(SKRect.Create(Math.Max(0, split - 1), 0, 2, outH), paint);
        });
    }

    /// <summary>
    /// Capture of a slider comparison from two already-cropped visible parts: the divider position
    /// is converted from pane fraction to the visible image so it lands on the same content.
    /// </summary>
    public static PixelImage SliderCapture(PixelImage baseCrop, RectD baseDisplayed, double paneWidth, PixelImage overlayCrop,
        double fraction, uint background, uint divider)
    {
        var scale = Math.Min(1.0, (double)MaxCompositeSide / Math.Max(baseCrop.Width, baseCrop.Height));
        var outW = Math.Max(1, (int)Math.Ceiling(baseCrop.Width * scale));
        var outH = Math.Max(1, (int)Math.Ceiling(baseCrop.Height * scale));
        var paneSplit = Math.Clamp(fraction, 0, 1) * paneWidth;
        var relative = baseDisplayed.Width > 0 ? Math.Clamp((paneSplit - baseDisplayed.X) / baseDisplayed.Width, 0, 1) : fraction;
        var split = (float)(relative * outW);
        using var aSkia = ToSkImage(baseCrop);
        using var bSkia = ToSkImage(overlayCrop);
        return Draw(outW, outH, background, (canvas, _) =>
        {
            var area = SKRect.Create(outW, outH);
            canvas.DrawImage(aSkia, AspectFit(baseCrop, area), Sampling);
            canvas.Save();
            canvas.ClipRect(SKRect.Create(0, 0, split, outH));
            canvas.DrawImage(bSkia, AspectFit(overlayCrop, area), Sampling);
            canvas.Restore();
            using var paint = new SKPaint { Color = new SKColor(divider) };
            canvas.DrawRect(SKRect.Create(Math.Max(0, split - 1), 0, 2, outH), paint);
        });
    }

    /// <summary>
    /// Capture of a side-by-side comparison: both visible parts at a common height with a gap
    /// (2 px for images; Video Compare passes its on-screen seam scaled to the frame's pixels).
    /// </summary>
    public static PixelImage SideBySideCapture(PixelImage a, PixelImage b, uint background, double gap = 2)
    {
        double height = Math.Max(a.Height, b.Height);
        var aWidth = a.Width * height / a.Height;
        var bWidth = b.Width * height / b.Height;
        gap = Math.Max(0, gap);
        var scale = Math.Max(0.0001, Math.Min(1, MaxCompositeSide / Math.Max(aWidth + gap + bWidth, height)));
        height *= scale; aWidth *= scale; bWidth *= scale;
        var outW = (int)Math.Ceiling(aWidth + gap * scale + bWidth);
        var outH = (int)Math.Ceiling(height);
        using var aSkia = ToSkImage(a);
        using var bSkia = ToSkImage(b);
        return Draw(Math.Max(1, outW), Math.Max(1, outH), background, (canvas, _) =>
        {
            canvas.DrawImage(aSkia, SKRect.Create(0, 0, (float)aWidth, (float)height), Sampling);
            canvas.DrawImage(bSkia, SKRect.Create((float)(aWidth + gap * scale), 0, (float)bWidth, (float)height), Sampling);
        });
    }

    // ───────────────────────────── Encoding ─────────────────────────────

    /// <summary>Encoded file bytes, or null when the encoder fails. JPEG is flattened onto <paramref name="matte"/>.</summary>
    public static byte[]? Encode(PixelImage image, ImageExportFormat format, double quality = 0.9, uint matte = 0xFFFFFFFF)
    {
        try
        {
            if (format == ImageExportFormat.Ico) return EncodeIco(image);
            if (format == ImageExportFormat.WebP && (image.Width > 16_383 || image.Height > 16_383))
            {
                Log.Warning($"ImageCodec: WebP can't hold {image.Width} × {image.Height}");
                return null;
            }
            var source = format == ImageExportFormat.Jpeg ? Flatten(image, matte) : image;
            using var skImage = ToSkImage(source);
            var skFormat = format switch
            {
                ImageExportFormat.Jpeg => SKEncodedImageFormat.Jpeg,
                ImageExportFormat.WebP => SKEncodedImageFormat.Webp,
                _ => SKEncodedImageFormat.Png,
            };
            var q = (int)Math.Round(Math.Clamp(quality, 0, 1) * 100);
            using var data = skImage.Encode(skFormat, format == ImageExportFormat.Png ? 100 : q);
            return data?.ToArray();
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or OutOfMemoryException)
        {
            Log.Warning($"ImageCodec: encode {format} failed: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Compressed copy near <paramref name="targetBytes"/> (macOS <c>writeCompressed</c>). Lossy
    /// formats search the highest quality that fits; PNG reduces color precision. With
    /// <paramref name="allowResizing"/> the image may also shrink, keeping its aspect ratio.
    /// </summary>
    public static byte[]? Compress(PixelImage image, ImageExportFormat format, double quality, long targetBytes, bool allowResizing)
    {
        var target = Math.Max(1024, targetBytes);
        var current = image;
        var data = CompressedData(current, format, quality, target);
        if (data is null) return null;
        for (var attempt = 0; allowResizing && attempt < 6 && data.LongLength > (long)(target * 1.08); attempt++)
        {
            var ratio = Math.Sqrt((double)target / data.LongLength);
            var scale = Math.Clamp(ratio * 0.98, 0.35, 0.98);
            var w = Math.Max(1, (int)Math.Round(current.Width * scale));
            var h = Math.Max(1, (int)Math.Round(current.Height * scale));
            if (w >= current.Width && h >= current.Height) break;
            var resized = Resize(current, w, h);
            var resizedData = CompressedData(resized, format, quality, target);
            if (resizedData is null) break;
            current = resized;
            data = resizedData;
        }
        return data;
    }

    private static byte[]? CompressedData(PixelImage image, ImageExportFormat format, double quality, long target)
    {
        var upper = (long)(target * 1.08);
        if (format is ImageExportFormat.Jpeg or ImageExportFormat.WebP)
        {
            var maxQuality = Math.Clamp(quality, 0.03, 1);
            var smallest = Encode(image, format, maxQuality);
            if (smallest is null || smallest.LongLength <= upper) return smallest;
            double low = 0.03, high = maxQuality;
            byte[]? best = null;
            for (var i = 0; i < 8; i++)
            {
                var candidateQuality = (low + high) / 2;
                var candidate = Encode(image, format, candidateQuality);
                if (candidate is null) break;
                if (candidate.Length < smallest.Length) smallest = candidate;
                if (candidate.LongLength <= upper) { best = candidate; low = candidateQuality; }
                else high = candidateQuality;
            }
            return best ?? smallest;
        }
        if (format == ImageExportFormat.Png)
        {
            // PNG ignores quality: reduce color precision instead; dimensions never change here.
            var startBits = Math.Clamp((int)Math.Round(quality * 7) + 1, 2, 8);
            byte[]? smallest = null;
            for (var bits = startBits; bits >= 2; bits--)
            {
                var data = Encode(Quantize(image, bits), ImageExportFormat.Png);
                if (data is null) continue;
                if (smallest is null || data.Length < smallest.Length) smallest = data;
                if (data.LongLength <= upper) return data;
            }
            return smallest;
        }
        return null;
    }

    /// <summary>Keeps the top <paramref name="bitsPerChannel"/> bits of each color channel.</summary>
    public static PixelImage Quantize(PixelImage image, int bitsPerChannel)
    {
        var shift = Math.Max(0, 8 - bitsPerChannel);
        if (shift == 0) return image;
        var mask = (byte)(0xFF << shift);
        var pixels = (byte[])image.Pixels.Clone();
        for (var i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] &= mask;
            pixels[i + 1] &= mask;
            pixels[i + 2] &= mask;
        }
        return new PixelImage(image.Width, image.Height, pixels);
    }

    /// <summary>
    /// Multi-size Windows icon (16–256 px, PNG-compressed entries). Non-square sources are
    /// aspect-fitted on a transparent square, never stretched or cropped.
    /// </summary>
    public static byte[] EncodeIco(PixelImage image)
    {
        int[] sides = [16, 24, 32, 48, 64, 128, 256];
        using var source = ToSkImage(image);
        var entries = new List<byte[]>();
        foreach (var side in sides)
        {
            var square = Draw(side, side, null, (canvas, _) =>
                canvas.DrawImage(source, AspectFit(image, SKRect.Create(side, side)), Sampling));
            entries.Add(Encode(square, ImageExportFormat.Png) ?? throw new InvalidOperationException("PNG encoder failed"));
        }

        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write((ushort)0);            // reserved
        writer.Write((ushort)1);            // type: icon
        writer.Write((ushort)sides.Length);
        var offset = 6 + 16 * sides.Length;
        for (var i = 0; i < sides.Length; i++)
        {
            var side = sides[i];
            writer.Write((byte)(side >= 256 ? 0 : side)); // 0 means 256
            writer.Write((byte)(side >= 256 ? 0 : side));
            writer.Write((byte)0);          // palette colors
            writer.Write((byte)0);          // reserved
            writer.Write((ushort)1);        // planes
            writer.Write((ushort)32);       // bits per pixel
            writer.Write(entries[i].Length);
            writer.Write(offset);
            offset += entries[i].Length;
        }
        foreach (var entry in entries) writer.Write(entry);
        writer.Flush();
        return stream.ToArray();
    }

    /// <summary>Decodes encoded bytes (Base64 paste, clipboard PNG) with Skia; null if not an image.</summary>
    public static PixelImage? Decode(byte[] data)
    {
        try
        {
            using var decoded = SKBitmap.Decode(data);
            if (decoded is null || decoded.Width <= 0 || decoded.Height <= 0) return null;
            using var converted = new SKBitmap(new SKImageInfo(decoded.Width, decoded.Height, SKColorType.Bgra8888, SKAlphaType.Premul));
            using (var canvas = new SKCanvas(converted))
            {
                canvas.Clear(SKColors.Transparent);
                canvas.DrawBitmap(decoded, 0, 0);
            }
            return FromBitmap(converted);
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
        {
            return null;
        }
    }

    // ───────────────────────────── Helpers ─────────────────────────────

    private static PixelImage Flatten(PixelImage image, uint matte) =>
        Draw(image.Width, image.Height, matte, (canvas, source) => canvas.DrawImage(source, 0, 0), image);

    private static SKRect AspectFit(PixelImage image, SKRect area)
    {
        var scale = Math.Min(area.Width / image.Width, area.Height / image.Height);
        var w = image.Width * scale;
        var h = image.Height * scale;
        return SKRect.Create(area.MidX - w / 2, area.MidY - h / 2, w, h);
    }

    /// <summary>Renders into a new BGRA premultiplied bitmap; <paramref name="background"/> null = transparent.</summary>
    private static PixelImage Draw(int width, int height, uint? background, Action<SKCanvas, SKImage> paint, PixelImage? source = null)
    {
        using var target = new SKBitmap(new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul));
        using var sourceImage = source is null ? null : ToSkImage(source);
        using (var canvas = new SKCanvas(target))
        {
            canvas.Clear(background is { } color ? new SKColor(color) : SKColors.Transparent);
            paint(canvas, sourceImage!);
            canvas.Flush();
        }
        return FromBitmap(target);
    }

    private static SKImage ToSkImage(PixelImage image)
    {
        var info = new SKImageInfo(image.Width, image.Height, SKColorType.Bgra8888, SKAlphaType.Premul);
        using var data = SKData.CreateCopy(image.Pixels);
        return SKImage.FromPixels(info, data, image.Stride)
            ?? throw new InvalidOperationException("Could not wrap pixels in an SKImage");
    }

    private static PixelImage FromBitmap(SKBitmap bitmap)
    {
        var width = bitmap.Width;
        var height = bitmap.Height;
        var pixels = new byte[width * height * 4];
        var source = bitmap.GetPixels();
        var rowBytes = bitmap.RowBytes;
        for (var row = 0; row < height; row++)
            Marshal.Copy(source + row * rowBytes, pixels, row * width * 4, width * 4);
        return new PixelImage(width, height, pixels);
    }
}
