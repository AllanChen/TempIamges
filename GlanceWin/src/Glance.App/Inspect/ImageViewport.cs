using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.App.Content;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Imaging;

namespace Glance.App.Inspect;

/// <summary>
/// One Image Inspect pane (port of macOS <c>InspectImageViewport</c> and, in slider mode,
/// <c>ImageRevealView</c>). Draws the image itself with zoom, pan, quarter turns and flips;
/// the file is never changed. Mouse: wheel zooms around the cursor, drag pans while zoomed,
/// double-click toggles Fit / 100 %. In slider mode image B covers the part left of the
/// divider; dragging moves the divider (or pans when zoomed and away from the handle).
/// </summary>
internal sealed class ImageViewport : Grid
{
    private const double HandleSize = 28;
    private readonly LoadingSweep _loading = new() { Width = 160, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel _failure;
    private readonly Brush _dim = Ui.Brush("InspectDimBrush");
    private readonly Pen _dividerPen;
    private readonly Brush _handleFill = Ui.Brush("InspectInk0Brush");
    private readonly Pen _handlePen;

    private BitmapSource? _image;
    private BitmapSource? _overlay;
    private string? _itemKey;
    private ViewportState _state = ViewportState.Fit;
    private Point _lastMouse;
    private DragKind _drag;
    private BitmapScalingMode _scalingMode = BitmapScalingMode.HighQuality;

    private enum DragKind { None, Pan, Divider }

    public ImageViewport()
    {
        Background = Brushes.Transparent; // hit-testable across the whole pane
        ClipToBounds = true;
        Focusable = false;
        _dividerPen = new Pen(Ui.Brush("InspectDividerBrush"), 1);
        _dividerPen.Freeze();
        _handlePen = new Pen(Ui.Brush("InspectText1Brush"), 1);
        _handlePen.Freeze();
        RenderOptions.SetBitmapScalingMode(this, _scalingMode);

        var failureText = Ui.Text(L.T("Load failed"), "LabelText");
        failureText.Foreground = Ui.Brush("InspectText2Brush");
        failureText.HorizontalAlignment = HorizontalAlignment.Center;
        _failure = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false,
            Children = { Ui.Glyph(Ui.GlyphWarning, 22, "InspectShuBrush"), failureText },
        };
        failureText.Margin = new Thickness(0, 8, 0, 0);
        _loading.Visibility = Visibility.Collapsed;
        _loading.IsHitTestVisible = false;
        Children.Add(_loading);
        Children.Add(_failure);
        SizeChanged += (_, _) => ApplyState(_state, notify: false);
    }

    /// <summary>User zoom / pan / rotation (not programmatic <see cref="SetState"/>).</summary>
    public event Action<ImageViewport, ViewportState>? StateChanged;

    /// <summary>Right-click anywhere on the pane (the window shows the actions menu).</summary>
    public event Action<ImageViewport, MouseButtonEventArgs>? MenuRequested;

    public BitmapSource? Image => _image;
    public BitmapSource? Overlay => _overlay;
    public ViewportState State => _state;
    public int Quarters { get; private set; }
    public bool FlipX { get; private set; }
    public bool FlipY { get; private set; }
    public bool SliderMode { get; private set; }
    public double RevealFraction { get; private set; } = 0.5;
    public bool IsZoomedIn => _image is not null && _state.Zoom > 1.001;

    private bool _dimmed;
    public bool Dimmed
    {
        get => _dimmed;
        set { if (_dimmed != value) { _dimmed = value; InvalidateVisual(); } }
    }

    /// <summary>
    /// Shows an item. A new <paramref name="itemKey"/> resets zoom, rotation and flips (like a
    /// newly assigned macOS image); the same key with a sharper bitmap keeps the view.
    /// </summary>
    public void SetImage(BitmapSource? image, string? itemKey, bool loading, bool failed)
    {
        if (itemKey != _itemKey)
        {
            _itemKey = itemKey;
            Quarters = 0;
            FlipX = FlipY = false;
            _state = ViewportState.Fit;
        }
        _image = image;
        _loading.Visibility = image is null && loading && !failed ? Visibility.Visible : Visibility.Collapsed;
        _failure.Visibility = image is null && failed ? Visibility.Visible : Visibility.Collapsed;
        ApplyState(_state, notify: false);
    }

    /// <summary>Slider compare: <paramref name="overlay"/> (B) is revealed left of the divider.</summary>
    public void SetSlider(bool enabled, BitmapSource? overlay)
    {
        SliderMode = enabled;
        _overlay = enabled ? overlay : null;
        InvalidateVisual();
    }

    public void SetState(ViewportState state, bool notify) => ApplyState(state, notify);

    public void FitToView() => ApplyState(ViewportState.Fit, notify: true);

    public void ActualSize()
    {
        if (_image is null) return;
        var zoom = ViewportMath.ActualSizeZoom(PixelSize(_image), Quarters, Pane, Dpi);
        ApplyState(new ViewportState(zoom, 0.5, 0.5), notify: true);
    }

    public void ZoomBy(double factor)
    {
        if (_image is null) return;
        ApplyState(_state with { Zoom = ViewportMath.ClampZoom(_state.Zoom * factor) }, notify: true);
    }

    public void Rotate(int deltaQuarters)
    {
        if (_image is null) return;
        Quarters = ViewportMath.NormalizeQuarters(Quarters + deltaQuarters);
        ApplyState(_state, notify: true);
    }

    public void Flip(bool horizontal)
    {
        if (_image is null) return;
        if (horizontal) FlipX = !FlipX; else FlipY = !FlipY;
        ApplyState(_state, notify: true);
    }

    /// <summary>Bottom-bar readout: "Fit" while fitted, otherwise the 1:1-pixel percentage.</summary>
    public int ZoomPercent => _image is null ? 100 : ViewportMath.ZoomPercent(PixelSize(_image), Quarters, Pane, _state.Zoom, Dpi);

    /// <summary>Where image A shows inside the pane (clipped to it), local DIPs; null without an image.</summary>
    public Rect? DisplayedImageRect()
    {
        if (_image is null || ActualWidth <= 0 || ActualHeight <= 0) return null;
        var rect = ImageRect(_image).Intersect(new RectD(0, 0, ActualWidth, ActualHeight));
        return rect.IsEmpty ? null : new Rect(rect.X, rect.Y, rect.Width, rect.Height);
    }

    public SizeD Pane => new(ActualWidth, ActualHeight);

    private double Dpi => VisualTreeHelper.GetDpi(this).DpiScaleX;

    private static SizeD PixelSize(BitmapSource image) => new(image.PixelWidth, image.PixelHeight);

    private RectD ImageRect(BitmapSource image)
    {
        var rendered = ViewportMath.Rendered(PixelSize(image), Quarters, Pane, _state.Zoom);
        return ViewportMath.ImageRect(_state, rendered, Pane);
    }

    private void ApplyState(ViewportState state, bool notify)
    {
        if (_image is not null && ActualWidth > 0 && ActualHeight > 0)
        {
            var rendered = ViewportMath.Rendered(PixelSize(_image), Quarters, Pane, state.Zoom);
            state = ViewportMath.Clamp(state, rendered, Pane);
            // Smooth when shrinking, crisp pixels when inspecting closely.
            var pixelScale = ViewportMath.FitScale(PixelSize(_image), Quarters, Pane) * state.Zoom * Dpi;
            var mode = pixelScale >= 3 ? BitmapScalingMode.NearestNeighbor : BitmapScalingMode.HighQuality;
            if (mode != _scalingMode)
            {
                _scalingMode = mode;
                RenderOptions.SetBitmapScalingMode(this, mode);
            }
        }
        else
        {
            state = new ViewportState(ViewportMath.ClampZoom(state.Zoom), state.CenterX, state.CenterY);
        }
        _state = state;
        InvalidateVisual();
        if (notify) StateChanged?.Invoke(this, state);
    }

    // ───────────────────────────── Rendering ─────────────────────────────

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (_image is null || ActualWidth <= 0 || ActualHeight <= 0) return;

        DrawImage(dc, _image);
        if (SliderMode && _overlay is not null)
        {
            var split = Math.Round(ActualWidth * RevealFraction);
            dc.PushClip(new RectangleGeometry(new Rect(0, 0, split, ActualHeight)));
            DrawImage(dc, _overlay);
            dc.Pop();
            DrawDivider(dc, split);
        }
        if (_dimmed) dc.DrawRectangle(_dim, null, new Rect(0, 0, ActualWidth, ActualHeight));
    }

    private void DrawImage(DrawingContext dc, BitmapSource image)
    {
        var pixels = PixelSize(image);
        var rendered = ViewportMath.Rendered(pixels, Quarters, Pane, _state.Zoom);
        var rect = ViewportMath.ImageRect(_state, rendered, Pane);
        var scale = ViewportMath.FitScale(pixels, Quarters, Pane) * _state.Zoom;
        double w = pixels.Width * scale, h = pixels.Height * scale; // unrotated content size

        dc.PushTransform(new TranslateTransform(rect.MidX, rect.MidY));
        dc.PushTransform(new RotateTransform(90 * Quarters));
        dc.PushTransform(new ScaleTransform(FlipX ? -1 : 1, FlipY ? -1 : 1));
        dc.DrawImage(image, new Rect(-w / 2, -h / 2, w, h));
        dc.Pop();
        dc.Pop();
        dc.Pop();
    }

    /// <summary>Figma split line (1 pt across the image only) and the 28 pt ‹ › handle.</summary>
    private void DrawDivider(DrawingContext dc, double x)
    {
        var span = DisplayedImageRect() ?? new Rect(0, 0, ActualWidth, ActualHeight);
        dc.DrawLine(_dividerPen, new Point(x + 0.5, span.Top), new Point(x + 0.5, span.Bottom));
        var center = new Point(x + 0.5, Math.Round(span.Top + span.Height / 2));
        dc.DrawEllipse(_handleFill, _handlePen, center, HandleSize / 2 - 0.5, HandleSize / 2 - 0.5);
        var chevrons = new StreamGeometry();
        using (var g = chevrons.Open())
        {
            g.BeginFigure(new Point(center.X - 2, center.Y - 3), false, false);
            g.LineTo(new Point(center.X - 5, center.Y), true, true);
            g.LineTo(new Point(center.X - 2, center.Y + 3), true, true);
            g.BeginFigure(new Point(center.X + 2, center.Y - 3), false, false);
            g.LineTo(new Point(center.X + 5, center.Y), true, true);
            g.LineTo(new Point(center.X + 2, center.Y + 3), true, true);
        }
        chevrons.Freeze();
        var chevronPen = new Pen(_handlePen.Brush, 1.25) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        dc.DrawGeometry(null, chevronPen, chevrons);
    }

    // ───────────────────────────── Mouse ─────────────────────────────

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        if (_image is null) return;
        e.Handled = true;
        var p = e.GetPosition(this);
        var factor = Math.Pow(1.0015, e.Delta); // one notch (120) ≈ 1.2×
        ApplyState(ViewportMath.ZoomAt(_state, _state.Zoom * factor, new PointD(p.X, p.Y), PixelSize(_image), Quarters, Pane), notify: true);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (_image is null) return;
        var p = e.GetPosition(this);
        if (e.ClickCount == 2)
        {
            if (IsZoomedIn) FitToView(); else ActualSize();
            e.Handled = true;
            return;
        }
        _lastMouse = p;
        if (SliderMode && _overlay is not null)
        {
            var nearHandle = Math.Abs(p.X - ActualWidth * RevealFraction) <= HandleSize / 2 + 4;
            if (nearHandle || !IsZoomedIn)
            {
                _drag = DragKind.Divider;
                MoveDivider(p.X);
            }
            else
            {
                _drag = DragKind.Pan;
            }
        }
        else if (IsZoomedIn)
        {
            _drag = DragKind.Pan;
        }
        if (_drag != DragKind.None)
        {
            CaptureMouse();
            if (_drag == DragKind.Pan) Cursor = Cursors.SizeAll;
            e.Handled = true;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var p = e.GetPosition(this);
        if (_drag == DragKind.Pan && _image is not null)
        {
            var dx = p.X - _lastMouse.X;
            var dy = p.Y - _lastMouse.Y;
            _lastMouse = p;
            ApplyState(ViewportMath.Pan(_state, dx, dy, PixelSize(_image), Quarters, Pane), notify: true);
        }
        else if (_drag == DragKind.Divider)
        {
            MoveDivider(p.X);
        }
        else if (SliderMode && _overlay is not null)
        {
            Cursor = Math.Abs(p.X - ActualWidth * RevealFraction) <= HandleSize / 2 + 4 || !IsZoomedIn ? Cursors.SizeWE : null;
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        EndDrag();
    }

    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        _drag = DragKind.None;
        Cursor = null;
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonUp(e);
        MenuRequested?.Invoke(this, e);
        e.Handled = true;
    }

    private void EndDrag()
    {
        if (_drag == DragKind.None) return;
        _drag = DragKind.None;
        if (IsMouseCaptured) ReleaseMouseCapture();
        Cursor = null;
    }

    private void MoveDivider(double x)
    {
        RevealFraction = Math.Clamp(x / Math.Max(1, ActualWidth), 0, 1);
        InvalidateVisual();
    }
}
