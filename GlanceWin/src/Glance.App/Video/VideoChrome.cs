using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Video;

namespace Glance.App.Video;

/// <summary>
/// Figma Shizuka <c>scrubber</c> (macOS <c>WarmVideoTimeline</c>): a 1 pt line/strong track, a 1 pt
/// text/1 played part and a 9 pt knob, inset by half the knob; the whole height takes clicks/drags.
/// </summary>
internal sealed class VideoTimeline : FrameworkElement
{
    public const double KnobSize = 9;
    private double _value;
    private double _maximum = 1;

    public VideoTimeline()
    {
        Height = 14;
        Cursor = Cursors.Hand;
        Focusable = false;
    }

    public event Action<double>? Scrubbed;

    public double Value
    {
        get => _value;
        set
        {
            _value = value;
            InvalidateVisual();
        }
    }

    public double Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        var inset = KnobSize / 2;
        var width = Math.Max(1, ActualWidth - inset * 2);
        var lineY = Math.Round(ActualHeight / 2 - 0.5);
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(RenderSize));
        dc.DrawRectangle(Ui.Brush("InspectLineStrongBrush"), null, new Rect(inset, lineY, width, 1));
        var fraction = _maximum > 0 ? Math.Clamp(_value / _maximum, 0, 1) : 0;
        var played = Ui.Brush("InspectText1Brush");
        dc.DrawRectangle(played, null, new Rect(inset, lineY, width * fraction, 1));
        dc.DrawEllipse(played, null, new Point(inset + width * fraction, ActualHeight / 2), KnobSize / 2, KnobSize / 2);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        CaptureMouse();
        Update(e.GetPosition(this).X);
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (IsMouseCaptured) Update(e.GetPosition(this).X);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        ReleaseMouseCapture();
    }

    private void Update(double x)
    {
        var inset = KnobSize / 2;
        var fraction = Math.Clamp((x - inset) / Math.Max(1, ActualWidth - inset * 2), 0, 1);
        Scrubbed?.Invoke(fraction * _maximum);
    }
}

/// <summary>
/// Figma <c>transport</c>: play (28), the current time 16 pt after it, the scrubber, the duration
/// and — in Focus — Capture frame, 16 pt apart. The row is 32 pt high.
/// </summary>
internal sealed class VideoTransport : Grid
{
    private readonly Button _play;
    private readonly TextBlock _current;
    private readonly TextBlock _duration;
    private readonly VideoTimeline _timeline = new();
    private readonly Button _capture;
    private bool? _shownPlaying;

    public VideoTransport(Action playPause, Action<double> scrub, Action capture)
    {
        Height = 32;
        foreach (var width in new[] { 28.0, 16, -1, 16 - VideoTimeline.KnobSize / 2, -2, 16 - VideoTimeline.KnobSize / 2, -1, 16, -1 })
            ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = width switch { -1 => GridLength.Auto, -2 => new GridLength(1, GridUnitType.Star), _ => new GridLength(width) },
            });

        _play = new Button { Style = Ui.Style("InspectIconButton"), Width = 28, Height = 28, VerticalAlignment = VerticalAlignment.Center };
        _play.Click += (_, _) => playPause();
        _current = TimeLabel("InspectText2Brush", TextAlignment.Left);
        _duration = TimeLabel("InspectText3Brush", TextAlignment.Right);
        _timeline.Scrubbed += scrub;
        _timeline.Margin = new Thickness(-VideoTimeline.KnobSize / 2, 0, -VideoTimeline.KnobSize / 2, 0);
        _timeline.VerticalAlignment = VerticalAlignment.Center;
        _capture = new Button { Style = Ui.Style("InspectQuietButton"), Content = L.T("Capture frame"), Height = 32 };
        _capture.Click += (_, _) => capture();

        Add(_play, 0);
        Add(_current, 2);
        Add(_timeline, 4);
        Add(_duration, 6);
        Add(_capture, 8);
        SetPlaying(false);
        foreach (UIElement child in Children) WindowChrome.SetIsHitTestVisibleInChrome(child, true);
    }

    public bool ShowsCapture
    {
        set
        {
            _capture.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
            ColumnDefinitions[7].Width = new GridLength(value ? 16 : 0);
        }
    }

    public void Update(double current, double maximum, bool playing)
    {
        _timeline.Maximum = maximum;
        _timeline.Value = current;
        _current.Text = VideoFormat.Time(current);
        _duration.Text = VideoFormat.Time(maximum);
        SetPlaying(playing);
    }

    private void SetPlaying(bool playing)
    {
        if (_shownPlaying == playing) return;
        _shownPlaying = playing;
        _play.Content = Ui.LineIcon(playing ? Ui.IconPause : Ui.IconPlay, 16, "InspectText1Brush");
        _play.ToolTip = L.T(playing ? "Pause" : "Play");
    }

    private void Add(UIElement element, int column)
    {
        SetColumn(element, column);
        Children.Add(element);
    }

    private static TextBlock TimeLabel(string brush, TextAlignment alignment) => new()
    {
        Text = "00:00",
        FontFamily = Ui.CodeFont,
        FontSize = 11,
        Foreground = Ui.Brush(brush),
        MinWidth = 33,
        TextAlignment = alignment,
        VerticalAlignment = VerticalAlignment.Center,
        IsHitTestVisible = false,
    };
}

/// <summary>
/// Figma <c>28 · Video Inspect / Info</c> (macOS <c>VideoInformationView</c>): a 320 pt ink/1 panel
/// with a line edge, the title and key (12 pt text/3) / value (mono 11 pt text/1) rows of 32 pt.
/// </summary>
internal sealed class VideoInfoPanel : Border
{
    private static readonly string[] Keys = ["Dimensions", "Duration", "Codec", "Frame rate", "Audio", "Bitrate"];
    private readonly TextBlock[] _values = new TextBlock[Keys.Length];

    public VideoInfoPanel()
    {
        Width = VideoChromeLayout.InfoPanelWidth;
        Background = Ui.Brush("InspectInk1Brush");
        BorderBrush = Ui.Brush("InspectLineBrush");
        BorderThickness = new Thickness(1, 1, 0, 0);
        var stack = new StackPanel { Margin = new Thickness(24, 28, 24, 0) };
        stack.Children.Add(new TextBlock
        {
            Text = L.T("Video Information"),
            FontSize = 20,
            Height = 28,
            Foreground = Ui.Brush("InspectText1Brush"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 0, 0, 24),
        });
        for (var i = 0; i < Keys.Length; i++)
        {
            var row = new Grid { Height = 32 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(45, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(55, GridUnitType.Star) });
            row.Children.Add(new TextBlock
            {
                Text = L.T(Keys[i]),
                FontSize = 12,
                Foreground = Ui.Brush("InspectText3Brush"),
                Margin = new Thickness(0, 8, 0, 0),
                VerticalAlignment = VerticalAlignment.Top,
            });
            var value = new TextBlock
            {
                Text = "—",
                FontFamily = Ui.CodeFont,
                FontSize = 11,
                Foreground = Ui.Brush("InspectText1Brush"),
                TextAlignment = TextAlignment.Right,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(0, 9, 0, 0),
                VerticalAlignment = VerticalAlignment.Top,
            };
            SetColumnOf(value, 1);
            row.Children.Add(value);
            var line = new Border { Height = 1, Background = Ui.Brush("InspectLineBrush"), VerticalAlignment = VerticalAlignment.Bottom };
            Grid.SetColumnSpan(line, 2);
            row.Children.Add(line);
            _values[i] = value;
            stack.Children.Add(row);
        }
        Child = stack;
    }

    public void Update(VideoDetails details)
    {
        string[] values =
        [
            details.Width is { } w && details.Height is { } h ? $"{w} × {h}" : "—",
            VideoFormat.Duration(details.Duration) ?? "—",
            details.VideoCodec ?? "—",
            VideoFormat.FrameRate(details.FramesPerSecond) ?? "—",
            details.AudioCodec ?? "—",
            VideoFormat.Bitrate(details.VideoBitrate) ?? "—",
        ];
        for (var i = 0; i < values.Length; i++)
        {
            _values[i].Text = values[i];
            _values[i].ToolTip = values[i] == "—" ? null : values[i];
        }
    }

    private static void SetColumnOf(UIElement element, int column) => Grid.SetColumn(element, column);
}

/// <summary>What Video Inspect knows about one video (player + property system).</summary>
internal sealed record VideoDetails(int? Width, int? Height, double Duration, double? FramesPerSecond, string? VideoCodec, string? AudioCodec, double? VideoBitrate)
{
    public static VideoDetails Empty { get; } = new(null, null, 0, null, null, null, null);
}

/// <summary>
/// Figma <c>27 · Video Compare</c> pane caption: "A · name" (13 pt medium) with the sound state on
/// the right (12 pt text/3), and the mono metadata (11 pt text/3) 26 pt below the top.
/// </summary>
internal sealed class VideoCompareCaption : Canvas
{
    private readonly TextBlock _name;
    private readonly TextBlock _state;
    private readonly TextBlock _meta;

    public VideoCompareCaption()
    {
        Height = VideoChromeLayout.CaptionHeight;
        IsHitTestVisible = false;
        ClipToBounds = true;
        _name = new TextBlock { FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextTrimming = TextTrimming.CharacterEllipsis };
        _state = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText3Brush") };
        _meta = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), TextTrimming = TextTrimming.CharacterEllipsis };
        SetTop(_name, 1);
        SetTop(_state, 2);
        SetTop(_meta, 25);
        Children.Add(_name);
        Children.Add(_state);
        Children.Add(_meta);
    }

    public void Configure(string letter, string name, string soundState, string meta, double width)
    {
        Width = width;
        _state.Text = soundState;
        _state.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var stateWidth = _state.DesiredSize.Width;
        SetLeft(_state, Math.Max(0, width - stateWidth));
        _name.Text = $"{letter} · {name}";
        _name.MaxWidth = Math.Max(0, width - (stateWidth > 0 ? stateWidth + 10 : 0));
        _meta.Text = meta;
        _meta.MaxWidth = width;
    }
}

/// <summary>A quiet light shutter flash over the video after a frame capture.</summary>
internal sealed class CaptureFlash : Border
{
    public CaptureFlash()
    {
        Background = Ui.Brush("InspectInk0Brush");
        CornerRadius = new CornerRadius(10);
        IsHitTestVisible = false;
        Opacity = 0;
        Visibility = Visibility.Collapsed;
    }

    public void Flash()
    {
        Visibility = Visibility.Visible;
        var animation = new DoubleAnimationUsingKeyFrames();
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(0.5, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(60))));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(300))));
        animation.Completed += (_, _) => Visibility = Visibility.Collapsed;
        BeginAnimation(OpacityProperty, animation);
    }
}
