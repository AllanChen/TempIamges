namespace Glance.Core.Imaging;

/// <summary>
/// A decoded picture as 32-bit BGRA, premultiplied alpha, rows packed (stride = width × 4).
/// The hand-off format between WPF decoding (App) and the SkiaSharp encoders here; immutable
/// by convention so it can cross threads.
/// </summary>
public sealed class PixelImage
{
    public PixelImage(int width, int height, byte[] pixels)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width));
        if (pixels.Length < (long)width * height * 4) throw new ArgumentException("Pixel buffer is too small", nameof(pixels));
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    public int Width { get; }
    public int Height { get; }
    public int Stride => Width * 4;
    public byte[] Pixels { get; }

    public SizeD Size => new(Width, Height);

    public static PixelImage Solid(int width, int height, uint bgra)
    {
        var pixels = new byte[width * height * 4];
        for (var i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = (byte)bgra;
            pixels[i + 1] = (byte)(bgra >> 8);
            pixels[i + 2] = (byte)(bgra >> 16);
            pixels[i + 3] = (byte)(bgra >> 24);
        }
        return new PixelImage(width, height, pixels);
    }
}
