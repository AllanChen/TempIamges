using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Imaging;

namespace Glance.App.Inspect;

/// <summary>
/// Full-window capture overlay (port of macOS <c>CaptureEditorView</c>, Figma Shizuka
/// <c>24 · Capture</c>): the frozen picture where it was on screen, a dim outside the crop
/// frame, thirds and 8 handles, the pixel size tag, the capture bar (Ratio segments | close |
/// Save) below the frame and the shortcut hint pill. Enter saves, Esc cancels.
/// </summary>
internal sealed class CaptureEditor : Canvas
{
    private const double HandleSize = 7;
    private const double BarGap = 14;
    private const double HintBottomInset = 31;
    private readonly BitmapSource _frozen;
    private readonly Rect? _displayRect;
    private readonly Action _cancel;
    private readonly Action<RectD> _capture;
    private readonly Border _bar;
    private readonly Border _hint;
    private readonly Dictionary<CaptureRatio, Button> _segments = [];
    private readonly Typeface _monoFace;
    private CaptureRatio _ratio = CaptureRatio.Free;
    private RectD _unit; // selection as a unit rect over the displayed picture, so it survives resizes
    private DragKind _drag;
    private CaptureHandle _dragHandle;
    private RectD _dragStart;
    private Point _dragOrigin;

    private enum DragKind { None, Handle, Move, Fresh }

    public CaptureEditor(BitmapSource frozen, Rect? displayRect, Action cancel, Action<RectD> capture)
    {
        _frozen = frozen;
        _displayRect = displayRect;
        _cancel = cancel;
        _capture = capture;
        _unit = CaptureGeometry.InitialUnitSelection(new SizeD(frozen.PixelWidth, frozen.PixelHeight));
        _monoFace = new Typeface(Ui.CodeFont, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        Background = Ui.Brush("InspectInk0Brush");
        Focusable = true;
        ClipToBounds = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);

        _bar = BuildBar();
        _hint = new Border
        {
            Background = Ui.Brush("InspectInk1Brush"),
            CornerRadius = Ui.Corner("CornerControl"),
            Padding = new Thickness(10, 5, 10, 5),
            IsHitTestVisible = false,
            Child = new TextBlock { Text = L.T("Drag to select · Enter save · Esc cancel"), FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText2Brush") },
        };
        Children.Add(_bar);
        Children.Add(_hint);
        SizeChanged += (_, _) => LayoutChrome();
        Loaded += (_, _) => { LayoutChrome(); Keyboard.Focus(this); };
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(this, true);
    }

    private SizeD Pixels => new(_frozen.PixelWidth, _frozen.PixelHeight);

    private RectD ImageRect
    {
        get
        {
            var area = _displayRect is { } r && r.Width > 0 && r.Height > 0
                ? new RectD(r.X, r.Y, r.Width, r.Height)
                : new RectD(0, 0, ActualWidth, ActualHeight);
            return CaptureGeometry.AspectFit(Pixels, area);
        }
    }

    private RectD Selection
    {
        get
        {
            var r = ImageRect;
            return new RectD(r.X + _unit.X * r.Width, r.Y + _unit.Y * r.Height, _unit.Width * r.Width, _unit.Height * r.Height);
        }
        set
        {
            var r = ImageRect;
            if (r.IsEmpty) return;
            _unit = new RectD((value.X - r.X) / r.Width, (value.Y - r.Y) / r.Height, value.Width / r.Width, value.Height / r.Height);
            InvalidateVisual();
            LayoutChrome();
        }
    }

    private RectD PixelCrop => CaptureGeometry.CropRect(Selection, ImageRect, Pixels);

    public void Commit() => _capture(PixelCrop);

    // ───────────────────────────── Drawing ─────────────────────────────

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var image = ImageRect;
        if (image.IsEmpty) return;
        dc.DrawImage(_frozen, new Rect(image.X, image.Y, image.Width, image.Height));

        var box = Selection;
        var boxRect = new Rect(box.X, box.Y, box.Width, box.Height);
        var mask = new GeometryGroup { FillRule = FillRule.EvenOdd };
        mask.Children.Add(new RectangleGeometry(new Rect(0, 0, ActualWidth, ActualHeight)));
        mask.Children.Add(new RectangleGeometry(boxRect));
        dc.DrawGeometry(Ui.Brush("CaptureDimBrush"), null, mask);

        var thirds = Ui.Brush("CaptureThirdsBrush");
        for (var i = 1; i <= 2; i++)
        {
            var x = Math.Floor(box.X + box.Width * i / 3);
            var y = Math.Floor(box.Y + box.Height * i / 3);
            dc.DrawRectangle(thirds, null, new Rect(x, box.Y, 1, box.Height));
            dc.DrawRectangle(thirds, null, new Rect(box.X, y, box.Width, 1));
        }

        var mark = Ui.Brush("CaptureMarkBrush");
        dc.DrawRectangle(null, new Pen(mark, 1), new Rect(box.X + 0.5, box.Y + 0.5, Math.Max(0, box.Width - 1), Math.Max(0, box.Height - 1)));
        foreach (var handle in Enum.GetValues<CaptureHandle>())
        {
            var p = handle.Position(box);
            dc.DrawRectangle(mark, null, new Rect(p.X - HandleSize / 2, p.Y - HandleSize / 2, HandleSize, HandleSize));
        }

        // Size tag: ink/0, radius 3, mono 11 text/1, its foot 6 pt above the frame.
        var crop = PixelCrop;
        var text = new FormattedText($"{(int)crop.Width} × {(int)crop.Height}", CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            _monoFace, 11, Ui.Brush("InspectText1Brush"), VisualTreeHelper.GetDpi(this).PixelsPerDip);
        var tag = new Rect(box.X, Math.Max(8, box.Y - 26), text.Width + 16, 20);
        dc.DrawRoundedRectangle(Ui.Brush("InspectInk0Brush"), null, tag, 3, 3);
        dc.DrawText(text, new Point(tag.X + 8, tag.Y + (tag.Height - text.Height) / 2));
    }

    // ───────────────────────────── Chrome ─────────────────────────────

    private Border BuildBar()
    {
        var label = new TextBlock { Text = L.T("Ratio"), FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 8, 0) };
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(label);
        foreach (var ratio in CaptureRatioExtensions.SegmentOrder)
        {
            var segment = new Button
            {
                // The tile template has no padding: the label carries the Figma 10 pt sides.
                Content = new TextBlock { Text = ratio == CaptureRatio.Free ? L.T("Free") : ratio.Label(), Margin = new Thickness(10, 0, 10, 0) },
                Style = Ui.Style("InspectIconButton"),
                Width = double.NaN,
                Height = 25,
                Margin = new Thickness(0, 0, 4, 0),
                FontFamily = Ui.UiFont,
                FontSize = 12,
                Foreground = Ui.Brush("InspectText2Brush"),
            };
            segment.Click += (_, _) => Pick(ratio);
            _segments[ratio] = segment;
            row.Children.Add(segment);
        }
        row.Children.Add(new Border { Width = 1, Height = 18, Background = Ui.Brush("InspectLineStrongBrush"), Margin = new Thickness(0, 0, 4, 0) });
        var close = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(Ui.IconClose, 16, "InspectText2Brush"), ToolTip = L.T("Cancel"), Margin = new Thickness(0, 0, 4, 0) };
        close.Click += (_, _) => _cancel();
        row.Children.Add(close);
        var save = new Button { Content = L.T("Save"), Style = Ui.Style("InspectPrimaryButton") };
        save.Click += (_, _) => Commit();
        row.Children.Add(save);
        UpdateSegments();
        return new Border
        {
            Height = 46,
            Padding = new Thickness(7, 0, 7, 0),
            Background = Ui.Brush("InspectInk1Brush"),
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerSmall"),
            Child = row,
        };
    }

    private void UpdateSegments()
    {
        foreach (var (ratio, button) in _segments)
        {
            var selected = ratio == _ratio;
            button.Background = selected ? Ui.Brush("InspectInk4Brush") : Brushes.Transparent;
            button.Foreground = Ui.Brush(selected ? "InspectText1Brush" : "InspectText2Brush");
            button.FontWeight = selected ? FontWeights.Medium : FontWeights.Normal;
        }
    }

    private void Pick(CaptureRatio ratio)
    {
        _ratio = ratio;
        UpdateSegments();
        var image = ImageRect;
        var room = image.Inflate(-image.Width * 0.15, -image.Height * 0.15);
        if (CaptureGeometry.Fit(ratio, new PointD(image.MidX, image.MidY), room) is { } fitted) Selection = fitted;
        Keyboard.Focus(this);
    }

    /// <summary>Bar below the frame, right-aligned with it; above when there's no room; hint pill at the foot.</summary>
    private void LayoutChrome()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        _hint.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var hint = _hint.DesiredSize;
        SetLeft(_hint, Math.Round((ActualWidth - hint.Width) / 2));
        SetTop(_hint, ActualHeight - HintBottomInset - hint.Height);

        _bar.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = _bar.DesiredSize;
        var box = Selection;
        var floor = ActualHeight - HintBottomInset - hint.Height - 8;
        var y = box.Bottom + BarGap;
        if (y + size.Height > floor)
        {
            y = box.Top - BarGap - size.Height;
            if (y < 8) y = Math.Min(box.Bottom, floor) - BarGap - size.Height;
        }
        var x = Math.Min(Math.Max(8, box.Right - size.Width), ActualWidth - size.Width - 8);
        SetLeft(_bar, Math.Round(x));
        SetTop(_bar, Math.Round(Math.Max(8, y)));
    }

    // ───────────────────────────── Input ─────────────────────────────

    private CaptureHandle? HandleAt(Point p)
    {
        var box = Selection;
        foreach (var handle in Enum.GetValues<CaptureHandle>())
        {
            var hp = handle.Position(box);
            if (Math.Abs(hp.X - p.X) <= 9 && Math.Abs(hp.Y - p.Y) <= 9) return handle;
        }
        return null;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.Handled) return;
        Keyboard.Focus(this);
        var p = e.GetPosition(this);
        var point = new PointD(p.X, p.Y);
        if (HandleAt(p) is { } handle)
        {
            _drag = DragKind.Handle;
            _dragHandle = handle;
            _dragStart = Selection;
        }
        else if (Selection.Contains(point))
        {
            _drag = DragKind.Move;
            _dragStart = Selection;
            _dragOrigin = p;
        }
        else if (ImageRect.Contains(point))
        {
            _drag = DragKind.Fresh;
            _dragOrigin = p;
        }
        else
        {
            _drag = DragKind.None;
            return;
        }
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var p = e.GetPosition(this);
        var point = new PointD(p.X, p.Y);
        var area = ImageRect;
        switch (_drag)
        {
            case DragKind.Handle:
                Selection = CaptureGeometry.Resize(_dragStart, _dragHandle, point, _ratio.Aspect(), area);
                break;
            case DragKind.Move:
                Selection = CaptureGeometry.Move(_dragStart, new PointD(p.X - _dragOrigin.X, p.Y - _dragOrigin.Y), area);
                break;
            case DragKind.Fresh:
                var right = p.X >= _dragOrigin.X;
                var down = p.Y >= _dragOrigin.Y;
                var corner = right ? (down ? CaptureHandle.BottomRight : CaptureHandle.TopRight) : (down ? CaptureHandle.BottomLeft : CaptureHandle.TopLeft);
                Selection = CaptureGeometry.Resize(new RectD(_dragOrigin.X, _dragOrigin.Y, 0, 0), corner, point, _ratio.Aspect(), area);
                break;
            default:
                Cursor = HandleAt(p) is { } h
                    ? h.IsCorner()
                        ? (h is CaptureHandle.TopLeft or CaptureHandle.BottomRight ? Cursors.SizeNWSE : Cursors.SizeNESW)
                        : (h.MovesLeft() || h.MovesRight() ? Cursors.SizeWE : Cursors.SizeNS)
                    : Selection.Contains(point) ? Cursors.SizeAll
                    : area.Contains(point) ? Cursors.Cross : Cursors.Arrow;
                break;
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        _drag = DragKind.None;
        if (IsMouseCaptured) ReleaseMouseCapture();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key == Key.Escape) { _cancel(); e.Handled = true; }
        else if (e.Key == Key.Enter) { Commit(); e.Handled = true; }
    }
}
