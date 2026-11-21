namespace Glance.Core.Imaging;

/// <summary>
/// What an image viewport shows: zoom relative to "fit" (1 = whole image visible) and the
/// point of the (rotated) image at the pane centre, normalized 0…1 with a top-left origin.
/// Port of macOS <c>InspectViewportState</c>; side-by-side panes share it.
/// </summary>
public readonly record struct ViewportState(double Zoom, double CenterX, double CenterY)
{
    public static ViewportState Fit { get; } = new(1, 0.5, 0.5);
}

/// <summary>
/// Zoom / pan maths of the Image Inspect viewport (port of <c>InspectImageViewport</c> and the
/// viewport half of <c>CaptureGeometry</c>). Sizes are image pixels and pane DIPs.
/// </summary>
public static class ViewportMath
{
    public const double MinZoom = 1;
    public const double MaxZoom = 20;

    public static SizeD Oriented(SizeD pixels, int quarters) =>
        IsOdd(quarters) ? new SizeD(pixels.Height, pixels.Width) : pixels;

    /// <summary>DIPs per image pixel when the whole (rotated) image fits the pane.</summary>
    public static double FitScale(SizeD pixels, int quarters, SizeD pane)
    {
        var oriented = Oriented(pixels, quarters);
        if (oriented.IsEmpty || pane.IsEmpty) return 1;
        return Math.Min(pane.Width / oriented.Width, pane.Height / oriented.Height);
    }

    /// <summary>On-screen size of the rotated image at <paramref name="zoom"/>.</summary>
    public static SizeD Rendered(SizeD pixels, int quarters, SizeD pane, double zoom)
    {
        var oriented = Oriented(pixels, quarters);
        var scale = FitScale(pixels, quarters, pane) * zoom;
        return new SizeD(oriented.Width * scale, oriented.Height * scale);
    }

    public static double ClampZoom(double zoom) => Math.Clamp(double.IsFinite(zoom) ? zoom : 1, MinZoom, MaxZoom);

    /// <summary>Keeps the image covering the pane: no empty band appears while zoomed in.</summary>
    public static ViewportState Clamp(ViewportState state, SizeD rendered, SizeD pane)
    {
        var zoom = ClampZoom(state.Zoom);
        double Axis(double center, double renderedLength, double paneLength)
        {
            if (renderedLength <= 0) return 0.5;
            var maxPan = Math.Max(0, (renderedLength - paneLength) / 2);
            var pan = Math.Clamp((0.5 - center) * renderedLength, -maxPan, maxPan);
            return 0.5 - pan / renderedLength;
        }
        return new ViewportState(zoom, Axis(state.CenterX, rendered.Width, pane.Width), Axis(state.CenterY, rendered.Height, pane.Height));
    }

    /// <summary>Where the rotated image sits in the pane (may extend past it when zoomed).</summary>
    public static RectD ImageRect(ViewportState state, SizeD rendered, SizeD pane)
    {
        var cx = pane.Width / 2 + (0.5 - state.CenterX) * rendered.Width;
        var cy = pane.Height / 2 + (0.5 - state.CenterY) * rendered.Height;
        return new RectD(cx - rendered.Width / 2, cy - rendered.Height / 2, rendered.Width, rendered.Height);
    }

    /// <summary>
    /// New zoom keeping the image point under <paramref name="anchor"/> (pane DIPs) in place —
    /// wheel / pinch zoom around the cursor.
    /// </summary>
    public static ViewportState ZoomAt(ViewportState state, double newZoom, PointD anchor, SizeD pixels, int quarters, SizeD pane)
    {
        var before = Rendered(pixels, quarters, pane, state.Zoom);
        if (before.IsEmpty) return state;
        var rect = ImageRect(state, before, pane);
        var ix = (anchor.X - rect.X) / before.Width;
        var iy = (anchor.Y - rect.Y) / before.Height;

        var zoom = ClampZoom(newZoom);
        var after = Rendered(pixels, quarters, pane, zoom);
        var cx = 0.5 - (anchor.X - pane.Width / 2 - (ix - 0.5) * after.Width) / after.Width;
        var cy = 0.5 - (anchor.Y - pane.Height / 2 - (iy - 0.5) * after.Height) / after.Height;
        return Clamp(new ViewportState(zoom, cx, cy), after, pane);
    }

    /// <summary>Drag-to-pan by a pane delta in DIPs.</summary>
    public static ViewportState Pan(ViewportState state, double dx, double dy, SizeD pixels, int quarters, SizeD pane)
    {
        var rendered = Rendered(pixels, quarters, pane, state.Zoom);
        if (rendered.IsEmpty) return state;
        var moved = new ViewportState(state.Zoom, state.CenterX - dx / rendered.Width, state.CenterY - dy / rendered.Height);
        return Clamp(moved, rendered, pane);
    }

    /// <summary>Zoom at which one image pixel covers one screen pixel (never below fit).</summary>
    public static double ActualSizeZoom(SizeD pixels, int quarters, SizeD pane, double dpiScale)
    {
        var fit = FitScale(pixels, quarters, pane) * Math.Max(dpiScale, 0.01);
        return ClampZoom(1 / Math.Max(fit, 0.0001));
    }

    /// <summary>Screen pixels per image pixel as a percentage (the bottom bar readout).</summary>
    public static int ZoomPercent(SizeD pixels, int quarters, SizeD pane, double zoom, double dpiScale) =>
        (int)Math.Round(FitScale(pixels, quarters, pane) * zoom * dpiScale * 100);

    /// <summary>
    /// The part of the image a viewport shows, in oriented image pixels, top-left origin
    /// (macOS <c>CaptureGeometry.visibleRect</c>; the capture editor crops this).
    /// </summary>
    public static RectD VisibleRect(SizeD orientedPixels, SizeD pane, double zoom, PointD center)
    {
        if (orientedPixels.IsEmpty || pane.IsEmpty) return new RectD(0, 0, orientedPixels.Width, orientedPixels.Height);
        var fit = Math.Min(pane.Width / orientedPixels.Width, pane.Height / orientedPixels.Height);
        var scale = fit * Math.Max(zoom, 0.0001);
        var fracW = Math.Min(1, pane.Width / (orientedPixels.Width * scale));
        var fracH = Math.Min(1, pane.Height / (orientedPixels.Height * scale));
        var x0 = Math.Clamp(center.X - fracW / 2, 0, 1 - fracW);
        var y0 = Math.Clamp(center.Y - fracH / 2, 0, 1 - fracH);
        var left = Math.Max(0, Math.Floor(x0 * orientedPixels.Width));
        var top = Math.Max(0, Math.Floor(y0 * orientedPixels.Height));
        var right = Math.Min(orientedPixels.Width, Math.Ceiling((x0 + fracW) * orientedPixels.Width));
        var bottom = Math.Min(orientedPixels.Height, Math.Ceiling((y0 + fracH) * orientedPixels.Height));
        return new RectD(left, top, Math.Max(1, right - left), Math.Max(1, bottom - top));
    }

    /// <summary>Where the visible image sits inside the pane: the pane itself, or a letterboxed rect.</summary>
    public static RectD DisplayedRect(SizeD orientedPixels, SizeD pane, double zoom)
    {
        if (orientedPixels.IsEmpty) return new RectD(0, 0, pane.Width, pane.Height);
        var fit = Math.Min(pane.Width / orientedPixels.Width, pane.Height / orientedPixels.Height);
        var scale = fit * Math.Max(zoom, 0.0001);
        var w = Math.Min(pane.Width, orientedPixels.Width * scale);
        var h = Math.Min(pane.Height, orientedPixels.Height * scale);
        return new RectD((pane.Width - w) / 2, (pane.Height - h) / 2, w, h);
    }

    /// <summary>
    /// Media area for a window fitted to an image (macOS <c>ScreenManager.mediaWindowSize</c>):
    /// the image size, scaled down to fit <paramref name="maximum"/>, never below <paramref name="minimum"/>.
    /// </summary>
    public static SizeD MediaWindowSize(SizeD preferred, SizeD minimum, SizeD maximum)
    {
        var ceilW = Math.Max(1, maximum.Width);
        var ceilH = Math.Max(1, maximum.Height);
        var floorW = Math.Min(minimum.Width, ceilW);
        var floorH = Math.Min(minimum.Height, ceilH);
        if (!double.IsFinite(preferred.Width) || !double.IsFinite(preferred.Height) || preferred.IsEmpty)
            return new SizeD(floorW, floorH);
        var scale = Math.Min(1, Math.Min(ceilW / preferred.Width, ceilH / preferred.Height));
        return new SizeD(
            Math.Min(ceilW, Math.Max(floorW, Math.Round(preferred.Width * scale))),
            Math.Min(ceilH, Math.Max(floorH, Math.Round(preferred.Height * scale))));
    }

    public static int NormalizeQuarters(int quarters) => ((quarters % 4) + 4) % 4;

    private static bool IsOdd(int quarters) => NormalizeQuarters(quarters) % 2 == 1;
}
