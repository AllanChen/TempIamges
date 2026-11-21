using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Inspect;
using Xunit;

namespace Glance.Tests;

public sealed class ViewportMathTests
{
    private static readonly SizeD Pixels = new(4000, 2000);
    private static readonly SizeD Pane = new(800, 600);

    [Fact]
    public void FitUsesTheLimitingSide()
    {
        Assert.Equal(0.2, ViewportMath.FitScale(Pixels, 0, Pane), 6);
        // A quarter turn makes it 2000 × 4000: height limits.
        Assert.Equal(0.15, ViewportMath.FitScale(Pixels, 1, Pane), 6);
    }

    [Fact]
    public void FitStateCannotPan()
    {
        var rendered = ViewportMath.Rendered(Pixels, 0, Pane, 1);
        var clamped = ViewportMath.Clamp(new ViewportState(1, 0.1, 0.9), rendered, Pane);
        Assert.Equal(0.5, clamped.CenterX, 6);
        Assert.Equal(0.5, clamped.CenterY, 6);
    }

    [Fact]
    public void ZoomAtKeepsThePointUnderTheCursor()
    {
        var anchor = new PointD(200, 150);
        var start = ViewportState.Fit;
        var before = ViewportMath.ImageRect(start, ViewportMath.Rendered(Pixels, 0, Pane, 1), Pane);
        var ix = (anchor.X - before.X) / before.Width;
        var iy = (anchor.Y - before.Y) / before.Height;

        var zoomed = ViewportMath.ZoomAt(start, 4, anchor, Pixels, 0, Pane);
        var after = ViewportMath.ImageRect(zoomed, ViewportMath.Rendered(Pixels, 0, Pane, 4), Pane);
        Assert.Equal(4, zoomed.Zoom);
        Assert.Equal(anchor.X, after.X + ix * after.Width, 3);
        Assert.Equal(anchor.Y, after.Y + iy * after.Height, 3);
    }

    [Fact]
    public void PanStopsAtTheImageEdge()
    {
        var zoomed = new ViewportState(2, 0.5, 0.5);
        var panned = ViewportMath.Pan(zoomed, 100_000, 0, Pixels, 0, Pane);
        var rect = ViewportMath.ImageRect(panned, ViewportMath.Rendered(Pixels, 0, Pane, 2), Pane);
        Assert.Equal(0, rect.X, 6); // left edge of the image reached the left edge of the pane
    }

    [Fact]
    public void ZoomIsClamped()
    {
        Assert.Equal(ViewportMath.MaxZoom, ViewportMath.ClampZoom(999));
        Assert.Equal(ViewportMath.MinZoom, ViewportMath.ClampZoom(0.01));
        Assert.Equal(1, ViewportMath.ClampZoom(double.NaN));
    }

    [Fact]
    public void ActualSizeAccountsForDisplayScale()
    {
        // Fit 0.2 DIP/px at 150 % → 0.3 screen px per image px; 1:1 needs zoom 1/0.3.
        var zoom = ViewportMath.ActualSizeZoom(Pixels, 0, Pane, 1.5);
        Assert.Equal(1 / 0.3, zoom, 6);
        Assert.Equal(100, ViewportMath.ZoomPercent(Pixels, 0, Pane, zoom, 1.5));
    }

    [Fact]
    public void VisibleRectAtFitIsTheWholeImage()
    {
        Assert.Equal(new RectD(0, 0, 4000, 2000), ViewportMath.VisibleRect(Pixels, Pane, 1, new PointD(0.5, 0.5)));
    }

    [Fact]
    public void VisibleRectWhenZoomedIsTheCentreWindow()
    {
        var rect = ViewportMath.VisibleRect(Pixels, Pane, 4, new PointD(0.5, 0.5));
        // Rendered 3200 × 1600 in an 800 × 600 pane: 1/4 of the width, 3/8 of the height.
        Assert.Equal(new RectD(1500, 625, 1000, 750), rect);
    }

    [Fact]
    public void MediaWindowSizeShrinksToTheScreen()
    {
        var size = ViewportMath.MediaWindowSize(new SizeD(6000, 3000), new SizeD(400, 200), new SizeD(1600, 1000));
        Assert.Equal(new SizeD(1600, 800), size);
        var small = ViewportMath.MediaWindowSize(new SizeD(100, 50), new SizeD(400, 200), new SizeD(1600, 1000));
        Assert.Equal(new SizeD(400, 200), small);
    }
}

public sealed class CaptureGeometryTests
{
    private static readonly RectD Area = new(0, 0, 400, 300);

    [Fact]
    public void FreeResizeKeepsTheOppositeCorner()
    {
        var rect = CaptureGeometry.Resize(new RectD(100, 100, 100, 100), CaptureHandle.BottomRight, new PointD(250, 260), null, Area);
        Assert.Equal(new RectD(100, 100, 150, 160), rect);
    }

    [Fact]
    public void ResizeRespectsTheMinimumSize()
    {
        var rect = CaptureGeometry.Resize(new RectD(100, 100, 100, 100), CaptureHandle.Left, new PointD(500, 150), null, Area);
        Assert.Equal(CaptureGeometry.MinimumSelection, rect.Width);
        Assert.Equal(176, rect.X);
    }

    [Fact]
    public void LockedCornerResizeKeepsTheRatioInsideTheArea()
    {
        var rect = CaptureGeometry.Resize(new RectD(0, 0, 100, 100), CaptureHandle.BottomRight, new PointD(1000, 1000), 16.0 / 9.0, Area);
        Assert.Equal(16.0 / 9.0, rect.Width / rect.Height, 6);
        Assert.True(rect.Right <= Area.Right + 1e-9 && rect.Bottom <= Area.Bottom + 1e-9);
    }

    [Fact]
    public void MoveIsClampedToTheArea()
    {
        var rect = CaptureGeometry.Move(new RectD(10, 10, 100, 100), new PointD(1000, -1000), Area);
        Assert.Equal(new RectD(300, 0, 100, 100), rect);
    }

    [Fact]
    public void FitCentresTheLargestBox()
    {
        var rect = CaptureGeometry.Fit(CaptureRatio.Square, new PointD(200, 150), Area);
        Assert.Equal(new RectD(50, 0, 300, 300), rect);
        Assert.Null(CaptureGeometry.Fit(CaptureRatio.Free, new PointD(0, 0), Area));
    }

    [Fact]
    public void CropRectMapsToPixels()
    {
        var crop = CaptureGeometry.CropRect(new RectD(50, 50, 100, 50), new RectD(0, 0, 400, 200), new SizeD(800, 400));
        Assert.Equal(new RectD(100, 100, 200, 100), crop);
    }
}

public sealed class OcrLayoutTests
{
    private static OcrLayout.Fragment F(string text, double x, double y, double w, double h = 20) => new(text, new RectD(x, y, w, h));

    [Fact]
    public void LinesAreReadTopToBottom()
    {
        var (order, text) = OcrLayout.Layout([F("second", 0, 25, 100), F("first", 0, 0, 100)]);
        Assert.Equal("first\nsecond", text);
        Assert.Equal(new[] { 1, 0 }, order);
    }

    [Fact]
    public void FragmentsOnOneRowStayOnOneLine()
    {
        var (_, text) = OcrLayout.Layout([F("value", 300, 2, 60), F("Label", 0, 0, 60)]);
        Assert.Equal("Label\tvalue", text);
    }

    [Fact]
    public void ColumnsAreReadOneAfterTheOther()
    {
        var (_, text) = OcrLayout.Layout([
            F("left one", 0, 0, 100), F("left two", 0, 30, 100),
            F("right one", 400, 10, 100), F("right two", 400, 40, 100),
        ]);
        Assert.Equal("left one\nleft two\n\nright one\nright two", text);
    }

    [Fact]
    public void WideGapStartsAParagraph()
    {
        var (_, text) = OcrLayout.Layout([F("a", 0, 0, 50), F("b", 0, 100, 50)]);
        Assert.Equal("a\n\nb", text);
    }

    [Fact]
    public void ChineseWordsJoinWithoutSpaces()
    {
        Assert.Equal("中文识别 OK", OcrLayout.JoinWords(["中", "文", "识", "别", "OK"]));
        Assert.Equal("hello world", OcrLayout.JoinWords(["hello", " world "]));
    }
}

public sealed class ImageToolsTests
{
    [Fact]
    public void CompressionEstimateFollowsQuality()
    {
        var high = ImageTools.CompressedByteEstimate(1_000_000, 1);
        var low = ImageTools.CompressedByteEstimate(1_000_000, 0.1);
        Assert.Equal(1_000_000, high);
        Assert.True(low < high / 4);
        Assert.Equal(1024, ImageTools.CompressedByteEstimate(10, 0.5));
    }

    [Fact]
    public void ResizedDimensionsKeepTheRatio()
    {
        Assert.Equal<(int, int)?>((1000, 500), ImageTools.ResizedDimensions(2000, 1000, 0.5));
        Assert.Null(ImageTools.ResizedDimensions(2000, 1000, 1));
        Assert.Null(ImageTools.ResizedDimensions(1, 1, 0.4));
    }

    [Theory]
    [InlineData(1920, 1080, "16 : 9")]
    [InlineData(1000, 1000, "1 : 1")]
    [InlineData(1001, 1000, "1.001")]
    public void AspectRatioText(int w, int h, string expected) => Assert.Equal(expected, ImageTools.AspectRatioText(w, h));

    [Fact]
    public void UniquePathCountsUp()
    {
        var taken = new HashSet<string> { Path.Combine("C:\\out", "a.png"), Path.Combine("C:\\out", "a-1.png") };
        Assert.Equal(Path.Combine("C:\\out", "a-2.png"), ImageTools.UniquePath("C:\\out", "a", "png", taken.Contains));
    }

    [Fact]
    public void CaptureStemIsSafe()
    {
        Assert.Equal("my photo-capture-10x20", ImageTools.CaptureStem("my photo.jpg", 10, 20));
        Assert.Equal("Capture-capture-1x1", ImageTools.CaptureStem(null, 1, 1));
        Assert.Equal("a-b-capture-1x1", ImageTools.CaptureStem("a:b.png", 1, 1));
    }

    [Fact]
    public void Base64AcceptsDataUrlsAndWhitespace()
    {
        var bytes = new byte[] { 1, 2, 3, 4, 5 };
        var plain = Convert.ToBase64String(bytes);
        Assert.Equal(bytes, ImageTools.DecodeBase64Payload(plain));
        Assert.Equal(bytes, ImageTools.DecodeBase64Payload($"data:image/png;base64,{plain[..4]}\n {plain[4..]}"));
        Assert.Null(ImageTools.DecodeBase64Payload("not base64 !!"));
    }

    [Theory]
    [InlineData(@"C:\a\b.JPG", ImageExportFormat.Jpeg)]
    [InlineData("https://x.test/i.webp?w=1", ImageExportFormat.WebP)]
    [InlineData(@"C:\a\b.bmp", ImageExportFormat.Png)]
    [InlineData(@"C:\a\b.heic", null)]
    public void CompressionKeepsTheSourceFormat(string path, ImageExportFormat? expected) =>
        Assert.Equal(expected, ImageExportFormats.ForSource(path));
}

public sealed class ImageCodecTests
{
    // Opaque red 0xFFFF0000 / blue 0xFF0000FF as ARGB.
    private static PixelImage Red(int w, int h) => PixelImage.Solid(w, h, 0xFFFF0000);

    private static (byte B, byte G, byte R, byte A) At(PixelImage image, int x, int y)
    {
        var i = (y * image.Width + x) * 4;
        return (image.Pixels[i], image.Pixels[i + 1], image.Pixels[i + 2], image.Pixels[i + 3]);
    }

    [Fact]
    public void RotateSwapsDimensionsAndMovesPixels()
    {
        var image = Red(4, 2);
        image.Pixels[0] = 255; image.Pixels[1] = 255; image.Pixels[2] = 255; // top-left white
        var rotated = ImageCodec.Rotate(image, 1);
        Assert.Equal((2, 4), (rotated.Width, rotated.Height));
        Assert.Equal(255, At(rotated, 1, 0).B); // clockwise: top-left goes to top-right
    }

    [Fact]
    public void CropCopiesTheRegion()
    {
        var crop = ImageCodec.Crop(Red(10, 10), new RectD(2, 3, 4, 5));
        Assert.Equal((4, 5), (crop.Width, crop.Height));
        Assert.Equal((byte)255, At(crop, 0, 0).R);
    }

    [Theory]
    [InlineData(ImageExportFormat.Png, new byte[] { 0x89, 0x50, 0x4E, 0x47 })]
    [InlineData(ImageExportFormat.Jpeg, new byte[] { 0xFF, 0xD8, 0xFF })]
    [InlineData(ImageExportFormat.WebP, new byte[] { 0x52, 0x49, 0x46, 0x46 })]
    [InlineData(ImageExportFormat.Ico, new byte[] { 0, 0, 1, 0 })]
    public void EncodesEachFormat(ImageExportFormat format, byte[] magic)
    {
        var data = ImageCodec.Encode(Red(40, 30), format);
        Assert.NotNull(data);
        Assert.Equal(magic, data![..magic.Length]);
    }

    [Fact]
    public void DecodeRoundTripsPng()
    {
        var png = ImageCodec.Encode(Red(8, 6), ImageExportFormat.Png)!;
        var decoded = ImageCodec.Decode(png);
        Assert.NotNull(decoded);
        Assert.Equal((8, 6), (decoded!.Width, decoded.Height));
        Assert.Equal((byte)255, At(decoded, 3, 3).R);
        Assert.Null(ImageCodec.Decode([1, 2, 3]));
    }

    [Fact]
    public void SideBySideUsesACommonHeight()
    {
        var composite = ImageCodec.SideBySide(Red(100, 50), Red(50, 100), 0xFF000000);
        Assert.Equal(100, composite.Height);
        Assert.Equal(200 + 2 + 50, composite.Width);
    }

    [Fact]
    public void CompressWithResizingShrinksLargeLossyImages()
    {
        var noisy = Red(600, 400);
        var random = new Random(1);
        for (var i = 0; i < noisy.Pixels.Length; i += 4)
        {
            noisy.Pixels[i] = (byte)random.Next(256);
            noisy.Pixels[i + 1] = (byte)random.Next(256);
        }
        var data = ImageCodec.Compress(noisy, ImageExportFormat.Jpeg, 0.9, 20_000, allowResizing: true);
        Assert.NotNull(data);
        Assert.True(data!.Length <= 20_000 * 1.08 || data.Length < 120_000);
    }
}

public sealed class InspectSessionTests
{
    private static MediaInfo Img(string name) => new($@"C:\pics\{name}", true, MediaKind.Image);

    private static InspectSession Session(int count, int focused = 0) =>
        new(Enumerable.Range(0, count).Select(i => Img($"{i}.png")), focused);

    [Fact]
    public void NavigateWraps()
    {
        var session = Session(3, 2);
        Assert.True(session.Navigate(1));
        Assert.Equal(0, session.FocusedIndex);
        session.Navigate(-1);
        Assert.Equal(2, session.FocusedIndex);
    }

    [Fact]
    public void EnterCompareUsesTheFocusedImageAsA()
    {
        var session = Session(3, 2);
        Assert.True(session.EnterCompare(CompareStyle.Slider));
        Assert.Equal<(int, int)?>((2, 0), session.Pair);
        Assert.Equal(1, session.ActiveSlot);
        Assert.Equal(0, session.ActiveIndex);
        Assert.False(Session(1).EnterCompare(CompareStyle.SideBySide));
    }

    [Fact]
    public void SelectReplacesTheActiveSlotButNeverDuplicates()
    {
        var session = Session(4);
        session.EnterCompare(CompareStyle.SideBySide);
        Assert.True(session.Select(3));
        Assert.Equal<(int, int)?>((0, 3), session.Pair);
        Assert.False(session.Select(0)); // already A
        session.SelectSlot(0);
        Assert.True(session.Select(2));
        Assert.Equal<(int, int)?>((2, 3), session.Pair);
    }

    [Fact]
    public void NavigateInCompareCyclesB()
    {
        var session = Session(3);
        session.EnterCompare(CompareStyle.SideBySide);
        session.Navigate(1);
        Assert.Equal<(int, int)?>((0, 2), session.Pair);
        session.Navigate(1);
        Assert.Equal<(int, int)?>((0, 1), session.Pair);
    }

    [Fact]
    public void AppendOrFocusDeduplicatesAcrossSpellings()
    {
        var session = Session(2);
        session.EnterCompare(CompareStyle.SideBySide);
        Assert.Equal(1, session.AppendOrFocus(new MediaInfo(@"c:\PICS\1.png", true, MediaKind.Image)));
        Assert.False(session.IsComparing);
        Assert.Equal(2, session.AppendOrFocus(Img("new.png")));
        Assert.Equal(3, session.Count);
    }

    [Fact]
    public void DropOnSideBySideReplacesThatSlot()
    {
        var session = Session(2);
        session.EnterCompare(CompareStyle.SideBySide);
        var index = session.AddDropped(Img("drop.png"), dropSlot: 0);
        Assert.Equal<(int, int)?>((index, 1), session.Pair);
        Assert.Equal(0, session.ActiveSlot);
    }

    [Fact]
    public void DerivedCopyComparesWithItsSource()
    {
        var session = Session(3, 1);
        var index = session.InsertDerived(Img("1.compressed.png"), 1);
        Assert.Equal(2, index);
        Assert.Equal(4, session.Count);
        Assert.Equal<(int, int)?>((1, 2), session.Pair);
        Assert.Equal(CompareStyle.SideBySide, session.Style);
        Assert.Equal(@"C:\pics\2.png", session[3].Location);
    }
}
