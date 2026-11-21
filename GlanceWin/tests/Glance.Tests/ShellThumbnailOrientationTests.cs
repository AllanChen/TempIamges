using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.Platform;
using Xunit;
using Xunit.Abstractions;

namespace Glance.Tests;

public class ShellThumbnailOrientationTests(ITestOutputHelper output)
{
    [Fact]
    public async Task ThumbnailIsUpright()
    {
        // Red top half, blue bottom half.
        const int w = 64, h = 64;
        var pixels = new byte[w * h * 4];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var i = (y * w + x) * 4;
                if (y < h / 2) { pixels[i + 2] = 255; } else { pixels[i] = 255; }
                pixels[i + 3] = 255;
            }
        var dir = Path.Combine(Path.GetTempPath(), "glance-thumb-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "orientation.png");
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, pixels, w * 4)));
        using (var stream = File.Create(file)) encoder.Save(stream);
        try
        {
            foreach (var thumbnailOnly in new[] { false, true })
            {
                var thumb = await ShellThumbnails.GetAsync(file, 64, thumbnailOnly);
                Assert.NotNull(thumb);
                var converted = new FormatConvertedBitmap(thumb, PixelFormats.Bgra32, null, 0);
                var top = new byte[4];
                var bottom = new byte[4];
                converted.CopyPixels(new System.Windows.Int32Rect(converted.PixelWidth / 2, 2, 1, 1), top, 4, 0);
                converted.CopyPixels(new System.Windows.Int32Rect(converted.PixelWidth / 2, converted.PixelHeight - 3, 1, 1), bottom, 4, 0);
                output.WriteLine($"thumbnailOnly={thumbnailOnly} size={converted.PixelWidth}x{converted.PixelHeight} top BGRA={string.Join(",", top)} bottom BGRA={string.Join(",", bottom)}");
                Assert.True(top[2] > 200 && top[0] < 60, "top should be red");
                Assert.True(bottom[0] > 200 && bottom[2] < 60, "bottom should be blue");
            }
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
}
