namespace Glance.Core.Imaging;

/// <summary>Aspect presets of the capture bar (Figma <c>24 · Capture</c>).</summary>
public enum CaptureRatio { Free, Square, ThreeFour, FourThree, NineSixteen, SixteenNine }

/// <summary>The eight crop handles.</summary>
public enum CaptureHandle { TopLeft, Top, TopRight, Left, Right, BottomLeft, Bottom, BottomRight }

public static class CaptureRatioExtensions
{
    /// <summary>Figma's segment order: Free, square, landscape before portrait.</summary>
    public static IReadOnlyList<CaptureRatio> SegmentOrder { get; } =
        [CaptureRatio.Free, CaptureRatio.Square, CaptureRatio.FourThree, CaptureRatio.ThreeFour, CaptureRatio.SixteenNine, CaptureRatio.NineSixteen];

    /// <summary>Width / height; null for a free-form selection.</summary>
    public static double? Aspect(this CaptureRatio ratio) => ratio switch
    {
        CaptureRatio.Square => 1,
        CaptureRatio.ThreeFour => 3.0 / 4.0,
        CaptureRatio.FourThree => 4.0 / 3.0,
        CaptureRatio.NineSixteen => 9.0 / 16.0,
        CaptureRatio.SixteenNine => 16.0 / 9.0,
        _ => null,
    };

    /// <summary>Segment label; "Free" is localized by the caller.</summary>
    public static string Label(this CaptureRatio ratio) => ratio switch
    {
        CaptureRatio.Square => "1:1",
        CaptureRatio.ThreeFour => "3:4",
        CaptureRatio.FourThree => "4:3",
        CaptureRatio.NineSixteen => "9:16",
        CaptureRatio.SixteenNine => "16:9",
        _ => "Free",
    };

    public static bool MovesLeft(this CaptureHandle h) => h is CaptureHandle.TopLeft or CaptureHandle.Left or CaptureHandle.BottomLeft;
    public static bool MovesRight(this CaptureHandle h) => h is CaptureHandle.TopRight or CaptureHandle.Right or CaptureHandle.BottomRight;
    public static bool MovesTop(this CaptureHandle h) => h is CaptureHandle.TopLeft or CaptureHandle.Top or CaptureHandle.TopRight;
    public static bool MovesBottom(this CaptureHandle h) => h is CaptureHandle.BottomLeft or CaptureHandle.Bottom or CaptureHandle.BottomRight;
    public static bool IsCorner(this CaptureHandle h) => (h.MovesLeft() || h.MovesRight()) && (h.MovesTop() || h.MovesBottom());

    /// <summary>Handle position on <paramref name="rect"/>.</summary>
    public static PointD Position(this CaptureHandle h, RectD rect) => new(
        h.MovesLeft() ? rect.Left : h.MovesRight() ? rect.Right : rect.MidX,
        h.MovesTop() ? rect.Top : h.MovesBottom() ? rect.Bottom : rect.MidY);
}

/// <summary>
/// Selection maths of the capture editor (port of macOS <c>CaptureGeometry</c>). Editor
/// coordinates are DIPs with a top-left origin; crop rects are top-left image pixels.
/// </summary>
public static class CaptureGeometry
{
    public const double MinimumSelection = 24;

    /// <summary>Largest box of <paramref name="ratio"/> inside <paramref name="area"/>, centred on <paramref name="center"/>.</summary>
    public static RectD? Fit(CaptureRatio ratio, PointD center, RectD area)
    {
        if (ratio.Aspect() is not { } aspect || area.IsEmpty) return null;
        var w = area.Width;
        var h = w / aspect;
        if (h > area.Height) { h = area.Height; w = h * aspect; }
        var x = Math.Min(Math.Max(center.X - w / 2, area.Left), area.Right - w);
        var y = Math.Min(Math.Max(center.Y - h / 2, area.Top), area.Bottom - h);
        return new RectD(x, y, w, h);
    }

    public static RectD Move(RectD rect, PointD delta, RectD area)
    {
        var x = Math.Min(Math.Max(rect.X + delta.X, area.Left), area.Right - rect.Width);
        var y = Math.Min(Math.Max(rect.Y + delta.Y, area.Top), area.Bottom - rect.Height);
        return new RectD(x, y, rect.Width, rect.Height);
    }

    /// <summary>
    /// Drags <paramref name="handle"/> to <paramref name="point"/>; the opposite side stays put.
    /// With an aspect the ratio is locked (corners grow to cover the drag, edges scale about the
    /// centre). The result stays inside <paramref name="area"/> and above the minimum size.
    /// </summary>
    public static RectD Resize(RectD rect, CaptureHandle handle, PointD point, double? aspect, RectD area)
    {
        const double minS = MinimumSelection;
        var p = new PointD(Math.Clamp(point.X, area.Left, area.Right), Math.Clamp(point.Y, area.Top, area.Bottom));
        if (aspect is not { } a)
        {
            double left = rect.Left, right = rect.Right, top = rect.Top, bottom = rect.Bottom;
            if (handle.MovesLeft()) left = Math.Min(p.X, right - minS);
            if (handle.MovesRight()) right = Math.Max(p.X, left + minS);
            if (handle.MovesTop()) top = Math.Min(p.Y, bottom - minS);
            if (handle.MovesBottom()) bottom = Math.Max(p.Y, top + minS);
            return new RectD(left, top, right - left, bottom - top);
        }

        var minW = Math.Max(minS, minS * a);
        if (handle.IsCorner())
        {
            var anchor = new PointD(handle.MovesLeft() ? rect.Right : rect.Left, handle.MovesTop() ? rect.Bottom : rect.Top);
            var dirX = handle.MovesLeft() ? -1.0 : 1.0;
            var dirY = handle.MovesTop() ? -1.0 : 1.0;
            var dx = Math.Max(0, (p.X - anchor.X) * dirX);
            var dy = Math.Max(0, (p.Y - anchor.Y) * dirY);
            var w = Math.Max(Math.Max(dx, dy * a), minW);
            var availW = dirX > 0 ? area.Right - anchor.X : anchor.X - area.Left;
            var availH = dirY > 0 ? area.Bottom - anchor.Y : anchor.Y - area.Top;
            w = Math.Min(w, Math.Min(availW, availH * a));
            var h = w / a;
            return new RectD(dirX > 0 ? anchor.X : anchor.X - w, dirY > 0 ? anchor.Y : anchor.Y - h, w, h);
        }
        if (handle.MovesLeft() || handle.MovesRight())
        {
            var anchorX = handle.MovesLeft() ? rect.Right : rect.Left;
            var dirX = handle.MovesLeft() ? -1.0 : 1.0;
            var w = Math.Max((p.X - anchorX) * dirX, minW);
            var availW = dirX > 0 ? area.Right - anchorX : anchorX - area.Left;
            var cy = rect.MidY;
            var availH = 2 * Math.Min(cy - area.Top, area.Bottom - cy);
            w = Math.Min(w, Math.Min(availW, availH * a));
            var h = w / a;
            return new RectD(dirX > 0 ? anchorX : anchorX - w, cy - h / 2, w, h);
        }
        {
            var anchorY = handle.MovesTop() ? rect.Bottom : rect.Top;
            var dirY = handle.MovesTop() ? -1.0 : 1.0;
            var h = Math.Max((p.Y - anchorY) * dirY, minW / a);
            var availH = dirY > 0 ? area.Bottom - anchorY : anchorY - area.Top;
            var cx = rect.MidX;
            var availW = 2 * Math.Min(cx - area.Left, area.Right - cx);
            h = Math.Min(h, Math.Min(availH, availW / a));
            var w = h * a;
            return new RectD(cx - w / 2, dirY > 0 ? anchorY : anchorY - h, w, h);
        }
    }

    /// <summary>Selection (editor DIPs) → top-left pixel rect of the frozen image shown at <paramref name="imageRect"/>.</summary>
    public static RectD CropRect(RectD selection, RectD imageRect, SizeD imagePixels)
    {
        if (imageRect.IsEmpty) return default;
        var sx = imagePixels.Width / imageRect.Width;
        var sy = imagePixels.Height / imageRect.Height;
        var x = Math.Max(0, Math.Floor((selection.Left - imageRect.Left) * sx));
        var y = Math.Max(0, Math.Floor((selection.Top - imageRect.Top) * sy));
        var right = Math.Min(imagePixels.Width, Math.Ceiling((selection.Right - imageRect.Left) * sx));
        var bottom = Math.Min(imagePixels.Height, Math.Ceiling((selection.Bottom - imageRect.Top) * sy));
        return new RectD(x, y, Math.Max(1, right - x), Math.Max(1, bottom - y));
    }

    /// <summary>Aspect-fit placement of <paramref name="pixels"/> inside <paramref name="area"/>.</summary>
    public static RectD AspectFit(SizeD pixels, RectD area)
    {
        if (pixels.IsEmpty || area.IsEmpty) return area;
        var scale = Math.Min(area.Width / pixels.Width, area.Height / pixels.Height);
        var w = pixels.Width * scale;
        var h = pixels.Height * scale;
        return new RectD(area.MidX - w / 2, area.MidY - h / 2, w, h);
    }

    /// <summary>The editor's starting box: 70 % of the image's short side, centred, as a unit rect.</summary>
    public static RectD InitialUnitSelection(SizeD pixels)
    {
        if (pixels.IsEmpty) return new RectD(0, 0, 1, 1);
        var side = Math.Min(pixels.Width, pixels.Height) * 0.7;
        var w = side / pixels.Width;
        var h = side / pixels.Height;
        return new RectD((1 - w) / 2, (1 - h) / 2, w, h);
    }
}
