using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Inspect;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Widgets;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Inspect;
using Glance.Core.Logging;
using Glance.Core.Video;
using Glance.Platform;

namespace Glance.App.Video;

/// <summary>
/// Video Inspect (port of macOS <c>VideoCompareWindow</c>, Figma Shizuka <c>08 · Video Inspect</c>
/// and <c>27 · Video Compare</c>) on Image Inspect's chrome: the 44 pt titlebar with the mode switch
/// (Focus, Capture, Compare) centred and Information / More on the right, the stage, the 28 pt
/// transport row and the 92 pt bottom bar with the file info, filmstrip and position. Compare plays
/// two videos side by side in sync. Capture freezes the frame into the shared capture editor.
/// </summary>
internal sealed class VideoWindow : Window
{
    private const double ResizeBorder = 5;
    private static readonly Size DesignSize = new(1554, 1012);

    private readonly IInspectHost _host;
    private readonly bool _reusable;
    private readonly string _webDataFolder;
    private readonly PathDetector _detector = new();

    private InspectSession? _session;
    private CancellationTokenSource _cts = new();
    private readonly List<VideoPane> _panes = [];
    private readonly Dictionary<string, VideoDetails> _details = [];
    private readonly Dictionary<string, ImageSource> _thumbs = [];
    private readonly HashSet<string> _loadingThumbs = [];
    private readonly HashSet<string> _loadingDetails = [];
    private readonly HashSet<string> _failed = [];

    private readonly Grid _root;
    private readonly Canvas _canvas = new();
    private readonly VideoTransport _transport;
    private readonly VideoCompareCaption[] _captions = [new(), new()];
    private readonly CaptureFlash _flash = new();
    private readonly InspectBottomBar _bottomBar = new();
    private readonly Filmstrip _filmstrip = new();
    private readonly VideoInfoPanel _infoPanel = new();
    private readonly Button _focusButton;
    private readonly Button _captureButton;
    private readonly Button _compareButton;
    private readonly Button _marketButton;
    private readonly TaskRunningChip _runningChip;
    private HashSet<Guid> _handledResults = [];
    private readonly Button _infoButton;
    private readonly Button _moreButton;
    private readonly TextBlock _maximizeGlyph;
    private readonly InspectToast _toast = new();
    private readonly Grid _overlayHost = new();
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromMilliseconds(33) };

    private CaptureEditor? _capture;
    private bool _resumeAfterCapture;
    private ContextMenu? _menu;
    private bool _playing;
    private bool _ended;
    private double _currentTime;
    private bool _infoVisible;
    private bool _pinned;
    private bool _quitting;
    private int _generation;
    private string _fittedSignature = "";

    public VideoWindow(IInspectHost host, bool reusable, string webDataFolder)
    {
        _host = host;
        _reusable = reusable;
        _webDataFolder = webDataFolder;
        Title = L.T("Video Inspect");
        Width = 1120;
        Height = 760;
        MinWidth = 560;
        MinHeight = 488;
        Background = Ui.Brush("InspectInk0Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ResizeMode = ResizeMode.CanResize;
        AllowDrop = true;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = VideoChromeLayout.TitlebarHeight - ResizeBorder,
            ResizeBorderThickness = new Thickness(ResizeBorder),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Titlebar: Focus / Capture / Compare centred; Information, More and the window buttons right ──
        _focusButton = ToolButton(Ui.IconVideo, L.T("Focus"), ExitCompare);
        _captureButton = ToolButton(Ui.IconCamera, L.T("Capture frame"), () => _ = BeginCaptureAsync());
        _compareButton = ToolButton(Ui.IconCompare, L.T("Compare"), EnterCompare);
        _marketButton = ToolButton(Ui.IconGrid, L.T("Widget Market"), () => _host.Widgets?.ShowMarket(this));
        _marketButton.Visibility = host.Widgets is null ? Visibility.Collapsed : Visibility.Visible;
        var modes = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 0, 0) };
        foreach (var button in new[] { _focusButton, _captureButton, _compareButton, _marketButton })
        {
            button.Margin = new Thickness(modes.Children.Count == 0 ? 0 : 2, 0, 0, 0);
            modes.Children.Add(button);
        }
        _infoButton = ToolButton(Ui.IconInfo, L.T("Video information"), ToggleInfo);
        _moreButton = ToolButton(Ui.IconMore, L.T("More"), ShowMoreMenu);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 12, 0) };
        actions.Children.Add(_infoButton);
        _moreButton.Margin = new Thickness(4, 0, 0, 0);
        actions.Children.Add(_moreButton);
        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var captions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", ToggleMaximize));
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", Close));
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Children = { actions, captions } };
        var titlebar = new Grid { Height = VideoChromeLayout.TitlebarHeight, Children = { modes, right } };
        Grid.SetColumnSpan(titlebar, 2);

        // ── Canvas (stage, captions, transport), bottom bar, filmstrip, info panel ──
        _transport = new VideoTransport(TogglePlay, t => _ = ScrubAsync(t), () => _ = BeginCaptureAsync());
        _canvas.ClipToBounds = true;
        _canvas.Children.Add(_transport);
        foreach (var caption in _captions)
        {
            caption.Visibility = Visibility.Collapsed;
            _canvas.Children.Add(caption);
        }
        _canvas.Children.Add(_flash);
        Grid.SetRowSpan(_canvas, 3);

        Grid.SetRow(_bottomBar, 2);
        _bottomBar.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 1 && e.OriginalSource == _bottomBar) try { DragMove(); } catch (InvalidOperationException) { }
        };
        Grid.SetRow(_filmstrip, 2);
        _filmstrip.HorizontalAlignment = HorizontalAlignment.Center;
        _filmstrip.VerticalAlignment = VerticalAlignment.Bottom;
        _filmstrip.Margin = new Thickness(0, 0, 0, 22);
        _filmstrip.TileClicked += (index, _) => SelectVideo(index);
        _filmstrip.VisibleIndicesChanged += LoadThumbnails;

        Grid.SetColumn(_infoPanel, 1);
        Grid.SetRow(_infoPanel, 1);
        Grid.SetRowSpan(_infoPanel, 2);
        _infoPanel.Visibility = Visibility.Collapsed;

        _runningChip = new TaskRunningChip(id => _host.Widgets?.Services.Tasks.Cancel(id)) { Margin = new Thickness(0, 12, 0, 0) };
        Grid.SetRow(_runningChip, 1);
        _toast.Margin = new Thickness(0, 0, 0, VideoChromeLayout.ToastInset);
        foreach (var overlay in new FrameworkElement[] { _toast, _overlayHost })
        {
            Grid.SetRowSpan(overlay, 3);
            Grid.SetColumnSpan(overlay, 2);
        }
        WindowChrome.SetIsHitTestVisibleInChrome(_overlayHost, true);

        _root = new Grid();
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(VideoChromeLayout.TitlebarHeight) });
        _root.RowDefinitions.Add(new RowDefinition());
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(VideoChromeLayout.BottomBarHeight) });
        _root.ColumnDefinitions.Add(new ColumnDefinition());
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        foreach (var child in new UIElement[] { _canvas, _bottomBar, _filmstrip, _infoPanel, _runningChip, titlebar, _toast, _overlayHost })
            _root.Children.Add(child);
        Content = _root;

        _canvas.SizeChanged += (_, _) => LayoutContent();
        StateChanged += (_, _) => OnStateChanged();
        _clock.Tick += (_, _) => OnClock();
        PreviewKeyDown += OnPreviewKeyDown;
        DragOver += OnDragOver;
        Drop += OnDrop;
        if (host.Widgets is { } widgets)
        {
            widgets.Services.Tasks.Changed += OnTasksChanged;
            Closed += (_, _) => widgets.Services.Tasks.Changed -= OnTasksChanged;
        }
    }

    // ───────────────────────────── Public API ─────────────────────────────

    /// <summary>Opens a new session (replacing any current one); a pair can start in Compare.</summary>
    public void Show(IReadOnlyList<MediaInfo> videos, int focusedIndex, InspectMode mode = InspectMode.Focus)
    {
        if (videos.Count == 0) return;
        ResetSession();
        _session = new InspectSession(videos, focusedIndex, mode);
        _handledResults = _host.Widgets?.CompletedIds() ?? [];
        Log.Info($"VideoInspect: opened {videos.Count} video(s) in {mode} mode");
        _fittedSignature = "";
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        if (!IsVisible)
        {
            PlaceDesignFrame();
            base.Show();
            PlaceDesignFrame();
        }
        Activate();
        Render(autoplay: true);
    }

    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    public void ShowToast(string message, bool error = false) => _toast.Show(message, error);

    // ───────────────────────────── Rendering ─────────────────────────────

    private IReadOnlyList<int> ActiveIndices =>
        _session is not { } s ? Array.Empty<int>() : s.IsComparing ? new[] { s.Pair!.Value.A, s.Pair!.Value.B } : new[] { s.FocusedIndex };

    private static string KeyOf(MediaInfo info) => InspectSession.Identity(info);

    private VideoDetails Details(MediaInfo info) => _details.TryGetValue(KeyOf(info), out var d) ? d : VideoDetails.Empty;

    /// <summary>Rebuilds the stage for the current mode (panes are reused when their video stays on screen).</summary>
    private void Render(bool autoplay)
    {
        if (_session is not { } s) return;
        _generation++;
        PausePlayback();
        _ended = false;
        _currentTime = 0;

        var wanted = ActiveIndices.Select(i => s[i]).ToList();
        var keep = new List<VideoPane>();
        foreach (var info in wanted)
        {
            var pane = _panes.FirstOrDefault(p => KeyOf(p.Info) == KeyOf(info) && !keep.Contains(p)) ?? CreatePane(info);
            keep.Add(pane);
        }
        foreach (var stale in _panes.Except(keep).ToList())
        {
            _canvas.Children.Remove(stale);
            stale.Dispose();
        }
        _panes.Clear();
        _panes.AddRange(keep);
        foreach (var pane in _panes)
        {
            pane.ResetZoom();
            pane.SetWebVisible(true);
            if (pane.IsReady) _ = pane.SeekAsync(0);
        }

        SetActive(_focusButton, !s.IsComparing);
        SetActive(_compareButton, s.IsComparing);
        _compareButton.IsEnabled = s.CanCompare;
        SetActive(_infoButton, _infoVisible);
        _transport.ShowsCapture = !s.IsComparing;
        UpdateDimming();

        var showStrip = s.Count > 1;
        _filmstrip.Visibility = showStrip ? Visibility.Visible : Visibility.Collapsed;
        if (showStrip)
        {
            _filmstrip.SetCount(s.Items.Select(i => i.FileName).ToList());
            _filmstrip.SetState(s.FocusedIndex, s.IsComparing ? s.Pair : null, i => _failed.Contains(KeyOf(s[i])));
            for (var i = 0; i < s.Count; i++)
                if (_thumbs.TryGetValue(KeyOf(s[i]), out var thumb)) _filmstrip.SetThumbnail(i, thumb);
            _filmstrip.Reveal(s.ActiveIndex);
        }

        foreach (var index in ActiveIndices) _ = LoadDetailsAsync(s[index]);
        LoadThumbnails(_filmstrip.VisibleIndices());
        FitWindowToVideos();
        LayoutContent();
        UpdateTransport();
        RefreshInfo();
        UpdateRunningChip();
        if (autoplay) StartPlayback();
    }

    // ───────────────────────────── Widgets ─────────────────────────────

    private void UpdateRunningChip()
    {
        if (_session is not { } s || _host.Widgets is not { } widgets)
        {
            _runningChip.Show(null);
            return;
        }
        _runningChip.Show(widgets.Services.Tasks.ActiveRecords(s[s.ActiveIndex].Location).FirstOrDefault());
    }

    /// <summary>
    /// macOS <c>widgetTasksDidChange</c>: a video result is inserted after its source and shown;
    /// image and text results open in their viewers.
    /// </summary>
    private void OnTasksChanged(object? sender, EventArgs e)
    {
        if (_session is not { } s || !IsVisible || _host.Widgets is not { } widgets) return;
        UpdateRunningChip();
        foreach (var record in widgets.NewResults(s.Items.Select(i => i.Location), _handledResults))
        {
            if (WidgetRunner.ResultKind(record) == MediaKind.Video)
            {
                var source = Enumerable.Range(0, s.Count).FirstOrDefault(i => Glance.Core.Tasks.WidgetTaskManager.IsSameMedia(s[i].Location, record.SourceUrl), s.FocusedIndex);
                s.InsertDerived(new MediaInfo(record.OutputPath!, true, MediaKind.Video), source, compare: false);
                _fittedSignature = "";
                Render(autoplay: true);
                _toast.Show(L.T("Widget completed"));
            }
            else
            {
                widgets.OpenResult(record);
            }
        }
    }

    private VideoPane CreatePane(MediaInfo info)
    {
        var pane = new VideoPane(info, _webDataFolder);
        pane.Ready += p =>
        {
            var key = KeyOf(p.Info);
            var current = Details(p.Info);
            var size = p.NaturalSize;
            _details[key] = current with
            {
                Width = current.Width ?? (size is { } s1 ? (int)s1.Width : null),
                Height = current.Height ?? (size is { } s2 ? (int)s2.Height : null),
                Duration = p.Duration > 0 ? p.Duration : current.Duration,
            };
            _failed.Remove(key);
            FitWindowToVideos();
            LayoutContent();
            UpdateTransport();
            RefreshInfo();
            UpdateBottomBar();
            if (_playing) p.Play();
            if (!_thumbs.ContainsKey(key)) _ = ThumbnailFromPaneAsync(p);
        };
        pane.Failed += p =>
        {
            _failed.Add(KeyOf(p.Info));
            RefreshStripState();
        };
        pane.Ended += _ => PlaybackDidEnd();
        pane.Activated += p => ActivatePane(p);
        pane.MenuRequested += _ => ShowContextMenu();
        _canvas.Children.Insert(0, pane);
        return pane;
    }

    private void ActivatePane(VideoPane pane)
    {
        if (_session is not { IsComparing: true } s) return;
        var slot = _panes.IndexOf(pane);
        if (slot >= 0 && s.SelectSlot(slot))
        {
            UpdateDimming();
            RefreshInfo();
            _filmstrip.Reveal(s.ActiveIndex);
        }
    }

    private void UpdateDimming()
    {
        var comparing = _session is { IsComparing: true };
        for (var i = 0; i < _panes.Count; i++) _panes[i].Dimmed = comparing && i != _session!.ActiveSlot;
    }

    private void RefreshStripState()
    {
        if (_session is not { } s || _filmstrip.Visibility != Visibility.Visible) return;
        _filmstrip.SetState(s.FocusedIndex, s.IsComparing ? s.Pair : null, i => _failed.Contains(KeyOf(s[i])));
    }

    /// <summary>Stage, compare panes and captions, transport (macOS <c>layoutContent</c>).</summary>
    private void LayoutContent()
    {
        var width = _canvas.ActualWidth;
        var height = _canvas.ActualHeight;
        if (width <= 0 || height <= 0 || _session is not { } s) return;
        var layout = VideoChromeLayout.For(new SizeD(width, height));
        var stage = layout.Stage;
        RectD shown;
        if (s.IsComparing && _panes.Count == 2)
        {
            var (left, right) = VideoChromeLayout.CompareFrames(stage, NaturalSize(0), NaturalSize(1));
            Place(_panes[0], left);
            Place(_panes[1], right);
            shown = left.Union(right);
        }
        else
        {
            shown = VideoChromeLayout.FocusFrame(stage, NaturalSize(0));
            if (_panes.Count > 0) Place(_panes[0], shown);
        }
        LayoutCaptions();

        var (x, w) = VideoChromeLayout.TransportSpan(stage, shown, s.IsComparing);
        _transport.Width = Math.Max(0, w);
        Canvas.SetLeft(_transport, Math.Round(x));
        Canvas.SetTop(_transport, layout.Transport.Y - 2);

        var flash = shown.Width > 0 ? shown : stage;
        Place(_flash, flash);

        if (_filmstrip.Visibility == Visibility.Visible)
        {
            var side = Math.Min(240, Math.Max(120, width * 0.22));
            var strip = Math.Max(Filmstrip.TileSize, Math.Min(Filmstrip.PreferredWidth(s.Count), width - side * 2));
            _filmstrip.Width = Math.Round(strip);
            _bottomBar.InfoMaxWidth = (width - strip) / 2 - 16;
        }
        else
        {
            _bottomBar.InfoMaxWidth = width * 0.6;
        }
        UpdateBottomBar();
    }

    private SizeD? NaturalSize(int slot)
    {
        if (_session is not { } s || slot >= ActiveIndices.Count) return null;
        var details = Details(s[ActiveIndices[slot]]);
        if (details.Width is > 0 && details.Height is > 0) return new SizeD(details.Width.Value, details.Height.Value);
        return slot < _panes.Count ? _panes[slot].NaturalSize : null;
    }

    private static void Place(FrameworkElement element, RectD rect)
    {
        element.Width = Math.Max(0, Math.Round(rect.Width));
        element.Height = Math.Max(0, Math.Round(rect.Height));
        Canvas.SetLeft(element, Math.Round(rect.X));
        Canvas.SetTop(element, Math.Round(rect.Y));
    }

    /// <summary>Figma <c>27 · Video Compare</c>: each pane's caption 16 pt below the video.</summary>
    private void LayoutCaptions()
    {
        foreach (var caption in _captions) caption.Visibility = Visibility.Collapsed;
        if (_session is not { IsComparing: true } s || _panes.Count != 2) return;
        var (a, b) = s.Pair!.Value;
        int[] indices = [a, b];
        for (var slot = 0; slot < 2; slot++)
        {
            var pane = _panes[slot];
            if (pane.Width is not > 0) continue;
            var info = s[indices[slot]];
            var details = Details(info);
            var meta = new List<string>();
            if (details.Width is { } w && details.Height is { } h) meta.Add($"{w} × {h}");
            if (details.VideoCodec is { } codec) meta.Add(codec);
            if (VideoFormat.Bitrate(details.VideoBitrate) is { } bitrate) meta.Add(bitrate);
            var caption = _captions[slot];
            caption.Configure(slot == 0 ? "A" : "B", info.FileName, L.T(pane.IsMuted ? "Muted" : "Sound on"), string.Join(" · ", meta), pane.Width);
            Canvas.SetLeft(caption, Canvas.GetLeft(pane));
            Canvas.SetTop(caption, Canvas.GetTop(pane) + pane.Height + VideoChromeLayout.CaptionGap);
            caption.Visibility = Visibility.Visible;
        }
    }

    /// <summary>Figma <c>file info</c> and <c>position</c> in Focus; Compare names each pane instead.</summary>
    private void UpdateBottomBar()
    {
        if (_session is not { } s) return;
        if (s.IsComparing)
        {
            _bottomBar.ShowSingle("", "", "", null);
            return;
        }
        var info = s[s.FocusedIndex];
        var details = Details(info);
        var parts = new List<string>();
        if (_failed.Contains(KeyOf(info))) parts.Add(L.T("Can’t play"));
        if (details.Width is { } w && details.Height is { } h) parts.Add($"{w} × {h}");
        if (details.VideoCodec is { } codec) parts.Add(codec);
        if (details.Duration > 0) parts.Add(VideoFormat.Time(details.Duration));
        _bottomBar.ShowSingle(info.FileName, string.Join("   ", parts), "", s.Count > 1 ? $"{s.FocusedIndex + 1} / {s.Count}" : null);
    }

    // ───────────────────────────── Playback ─────────────────────────────

    private double MaximumDuration =>
        _session is not { } s ? 0 : ActiveIndices.Select(i => Details(s[i]).Duration).DefaultIfEmpty(0).Max();

    private void StartPlayback()
    {
        if (_panes.Count == 0) return;
        _playing = true;
        foreach (var pane in _panes) pane.Play();
        _clock.Start();
        UpdateTransport();
    }

    private void PausePlayback()
    {
        foreach (var pane in _panes) pane.Pause();
        _playing = false;
        _clock.Stop();
        UpdateTransport();
    }

    private bool ShouldReplay => _ended || _panes.Any(p => p.HasReachedEnd);

    private void TogglePlay()
    {
        if (_playing && !ShouldReplay) PausePlayback();
        else _ = PlayAsync();
    }

    /// <summary>Replays every visible video together after the end; ordinary pauses resume in place.</summary>
    private async Task PlayAsync()
    {
        var generation = _generation;
        await SeekAllAsync(ShouldReplay ? 0 : _currentTime);
        if (generation != _generation) return;
        StartPlayback();
    }

    private void Replay()
    {
        PausePlayback();
        _currentTime = 0;
        _ended = true;
        _ = PlayAsync();
    }

    private void PlaybackDidEnd()
    {
        _ended = true;
        PausePlayback();
    }

    private async Task ScrubAsync(double seconds)
    {
        var wasPlaying = _playing;
        if (wasPlaying)
        {
            foreach (var pane in _panes) pane.Pause();
        }
        await SeekAllAsync(seconds);
        if (wasPlaying && _playing)
        {
            foreach (var pane in _panes) pane.Play();
        }
    }

    private async Task SeekAllAsync(double seconds)
    {
        _ended = false;
        _currentTime = Math.Clamp(seconds, 0, Math.Max(0, MaximumDuration));
        UpdateTransport();
        var tasks = new List<Task>();
        for (var i = 0; i < _panes.Count; i++)
        {
            var limit = _panes[i].Duration > 0 ? _panes[i].Duration : MaximumDuration;
            tasks.Add(_panes[i].SeekAsync(Math.Min(_currentTime, limit)));
        }
        await Task.WhenAll(tasks);
    }

    private void OnClock()
    {
        if (!_playing || _panes.Count == 0) return;
        _currentTime = Math.Clamp(_panes[0].Position, 0, Math.Max(0, MaximumDuration));
        UpdateTransport();
    }

    private void UpdateTransport() => _transport.Update(_currentTime, MaximumDuration, _playing);

    private void ToggleMute(int slot)
    {
        if (slot < 0 || slot >= _panes.Count) return;
        _panes[slot].SetMuted(!_panes[slot].IsMuted);
        LayoutCaptions();
    }

    // ───────────────────────────── Modes & navigation ─────────────────────────────

    private void EnterCompare()
    {
        if (_session is not { CanCompare: true } s) return;
        if (s.EnterCompare(CompareStyle.SideBySide)) Render(autoplay: false);
    }

    private void ExitCompare()
    {
        if (_session is not { IsComparing: true } s) return;
        s.ExitCompare();
        Render(autoplay: false);
    }

    private void SelectVideo(int index)
    {
        if (_session is not { } s) return;
        if (s.Select(index)) Render(autoplay: false);
    }

    private void Navigate(int delta)
    {
        if (_session is not { } s) return;
        if (s.Navigate(delta)) Render(autoplay: false);
    }

    // ───────────────────────────── Loading ─────────────────────────────

    private async Task LoadDetailsAsync(MediaInfo info)
    {
        var key = KeyOf(info);
        if (!info.IsLocal || !_loadingDetails.Add(key)) return;
        var session = _session;
        var metadata = await VideoMetadataReader.ReadAsync(info.Location, _cts.Token);
        if (session != _session || metadata is null) return;
        var current = Details(info);
        _details[key] = current with
        {
            Width = metadata.Width ?? current.Width,
            Height = metadata.Height ?? current.Height,
            Duration = current.Duration > 0 ? current.Duration : metadata.DurationSeconds ?? 0,
            FramesPerSecond = metadata.FramesPerSecond,
            VideoCodec = metadata.VideoCodec,
            AudioCodec = metadata.AudioCodec,
            VideoBitrate = metadata.VideoBitrate,
        };
        FitWindowToVideos();
        LayoutContent();
        UpdateTransport();
        RefreshInfo();
    }

    private void LoadThumbnails(IReadOnlyList<int> indices)
    {
        if (_session is not { } s) return;
        foreach (var index in indices)
            if (index >= 0 && index < s.Count) _ = LoadThumbnailAsync(s[index]);
    }

    /// <summary>Local videos use the shell thumbnail; remote ones get a frame once their pane plays.</summary>
    private async Task LoadThumbnailAsync(MediaInfo info)
    {
        var key = KeyOf(info);
        if (!info.IsLocal || _thumbs.ContainsKey(key) || !_loadingThumbs.Add(key)) return;
        var session = _session;
        try
        {
            var thumb = await ShellThumbnails.GetAsync(info.Location, 128, thumbnailOnly: true);
            if (session != _session || thumb is null) return;
            SetThumbnail(key, thumb);
        }
        finally
        {
            _loadingThumbs.Remove(key);
        }
    }

    private async Task ThumbnailFromPaneAsync(VideoPane pane)
    {
        await Task.Delay(800);
        var key = KeyOf(pane.Info);
        if (_thumbs.ContainsKey(key) || !_panes.Contains(pane)) return;
        if (await pane.CaptureFrameAsync() is not { } frame) return;
        var scale = Math.Min(1, 128.0 / Math.Max(frame.PixelWidth, frame.PixelHeight));
        ImageSource thumb = frame;
        if (scale < 1)
        {
            var scaled = new TransformedBitmap(frame, new ScaleTransform(scale, scale));
            scaled.Freeze();
            thumb = scaled;
        }
        SetThumbnail(key, thumb);
    }

    private void SetThumbnail(string key, ImageSource thumb)
    {
        _thumbs[key] = thumb;
        if (_session is not { } s) return;
        for (var i = 0; i < s.Count; i++)
            if (KeyOf(s[i]) == key) _filmstrip.SetThumbnail(i, thumb);
    }

    private void ResetSession()
    {
        _cts.Cancel();
        _cts.Dispose();
        _cts = new CancellationTokenSource();
        _generation++;
        _clock.Stop();
        _playing = false;
        foreach (var pane in _panes)
        {
            _canvas.Children.Remove(pane);
            pane.Dispose();
        }
        _panes.Clear();
        _session = null;
        _details.Clear();
        _thumbs.Clear();
        _loadingThumbs.Clear();
        _loadingDetails.Clear();
        _failed.Clear();
        _filmstrip.SetCount([]);
        EndCapture();
        if (_menu is { IsOpen: true }) _menu.IsOpen = false;
        _toast.Hide();
    }

    // ───────────────────────────── Information ─────────────────────────────

    private void ToggleInfo()
    {
        _infoVisible = !_infoVisible;
        _infoPanel.Visibility = _infoVisible ? Visibility.Visible : Visibility.Collapsed;
        SetActive(_infoButton, _infoVisible);
        RefreshInfo();
    }

    private void RefreshInfo()
    {
        if (!_infoVisible || _session is not { } s) return;
        _infoPanel.Update(Details(s[s.ActiveIndex]));
    }

    // ───────────────────────────── Menus ─────────────────────────────

    private void ShowMoreMenu()
    {
        var menu = BuildMenu();
        menu.PlacementTarget = _moreButton;
        menu.Placement = PlacementMode.Custom;
        // Figma `21 · More menu`: 6 pt below the ⋯ button, right-aligned with it (the template adds a 12 pt shadow margin).
        menu.CustomPopupPlacementCallback = (popup, target, _) =>
            [new CustomPopupPlacement(new Point(target.Width - popup.Width + 12, target.Height + 6 - 12), PopupPrimaryAxis.Horizontal)];
        Open(menu);
    }

    private void ShowContextMenu()
    {
        var menu = BuildMenu();
        menu.Placement = PlacementMode.MousePoint;
        Open(menu);
    }

    private void Open(ContextMenu menu)
    {
        if (_menu is { IsOpen: true }) _menu.IsOpen = false;
        _menu = menu;
        menu.IsOpen = true;
    }

    /// <summary>macOS <c>buildMoreEntries</c>: information, sound, playback, window, Widgets.</summary>
    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();
        MenuItem Item(string title, Action action, bool enabled = true, string? gesture = null)
        {
            var item = new MenuItem { Header = title, IsEnabled = enabled, InputGestureText = gesture ?? "" };
            item.Click += (_, _) => action();
            return item;
        }
        var s = _session;
        menu.Items.Add(Item(L.T("Video information"), ToggleInfo, s is not null, "Ctrl+I"));
        menu.Items.Add(new Separator());
        if (s is { IsComparing: true } && _panes.Count == 2)
        {
            menu.Items.Add(Item(L.T(_panes[0].IsMuted ? "Unmute Left" : "Mute Left"), () => ToggleMute(0)));
            menu.Items.Add(Item(L.T(_panes[1].IsMuted ? "Unmute Right" : "Mute Right"), () => ToggleMute(1)));
        }
        else if (_panes.Count > 0)
        {
            menu.Items.Add(Item(L.T(_panes[0].IsMuted ? "Unmute" : "Mute"), () => ToggleMute(0), gesture: "M"));
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("Replay"), Replay, _panes.Count > 0));
        menu.Items.Add(Item(L.T("Capture frame"), () => _ = BeginCaptureAsync(), _panes.Any(p => p.IsReady), "Ctrl+Shift+X"));
        var canReveal = s is not null && ActiveIndices.Any(i => s[i].IsLocal);
        menu.Items.Add(Item(L.T("Reveal in File Explorer"), RevealActive, canReveal));
        menu.Items.Add(Item(L.T(_pinned ? "Unpin" : "Pin on Top"), TogglePin));
        _host.Widgets?.AddMenuItems(menu, "video", s is null ? null : s[s.ActiveIndex], this, message => _toast.Show(message, error: true));
        return menu;
    }

    private void RevealActive()
    {
        if (_session is not { } s) return;
        var info = s[s.ActiveIndex];
        if (!info.IsLocal) info = ActiveIndices.Select(i => s[i]).FirstOrDefault(i => i.IsLocal) ?? info;
        if (info.IsLocal) ShellActions.RevealInExplorer(info.Location);
    }

    private void TogglePin()
    {
        _pinned = !_pinned;
        Topmost = _pinned;
    }

    // ───────────────────────────── Frame capture ─────────────────────────────

    /// <summary>
    /// Freezes the visible frame (Compare: both panes seeked to the same time, composited with the
    /// on-screen seam) and opens the capture editor over the video. Playback stays paused until the
    /// editor closes, then resumes if it was playing.
    /// </summary>
    private async Task BeginCaptureAsync()
    {
        if (_capture is not null || _session is not { } s || _panes.Count == 0 || !_panes.Any(p => p.IsReady)) return;
        var generation = _generation;
        var resume = _playing;
        var time = _panes[0].Position;
        PausePlayback();
        if (s.IsComparing) await SeekAllAsync(time);
        else await Task.Delay(40);
        if (generation != _generation) return;

        var frames = new List<BitmapSource>();
        foreach (var pane in _panes)
            if (await pane.CaptureFrameAsync() is { } frame) frames.Add(frame);
        if (generation != _generation) return;
        if (frames.Count == 0)
        {
            _toast.Show(L.T("Couldn’t capture this frame."), error: true);
            if (resume) StartPlayback();
            return;
        }

        PixelImage frozen;
        try
        {
            var pixels = frames.Select(InspectImages.ToPixels).ToList();
            var seam = _panes.Count == 2 ? Math.Max(0, Canvas.GetLeft(_panes[1]) - (Canvas.GetLeft(_panes[0]) + _panes[0].Width)) : 0;
            var paneHeight = _panes[0].Height;
            var background = Ui.Argb("InspectInk0Color");
            frozen = await Task.Run(() =>
            {
                if (pixels.Count == 1) return pixels[0];
                var height = Math.Max(pixels[0].Height, pixels[1].Height);
                var gap = paneHeight > 0 && seam > 0 ? Math.Round(seam * height / paneHeight) : 2;
                return ImageCodec.SideBySideCapture(pixels[0], pixels[1], background, gap);
            });
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException or OutOfMemoryException)
        {
            Log.Warning($"VideoInspect: capture freeze failed: {ex.Message}");
            _toast.Show(L.T("Couldn’t capture this frame."), error: true);
            if (resume) StartPlayback();
            return;
        }
        if (generation != _generation) return;

        _flash.Flash();
        _resumeAfterCapture = resume;
        var sourceName = s[s.ActiveIndex].FileName;
        var left = _panes[0];
        var shown = new Rect(Canvas.GetLeft(left), Canvas.GetTop(left), left.Width, left.Height);
        if (_panes.Count == 2)
        {
            var right = _panes[1];
            shown.Union(new Rect(Canvas.GetLeft(right), Canvas.GetTop(right), right.Width, right.Height));
        }
        var display = new Rect(_canvas.TranslatePoint(shown.TopLeft, _overlayHost), shown.Size);
        foreach (var pane in _panes) pane.SetWebVisible(false);
        _capture = new CaptureEditor(InspectImages.ToBitmap(frozen), display, EndCapture, crop => _ = FinishCaptureAsync(frozen, crop, sourceName));
        _overlayHost.Children.Add(_capture);
    }

    private void EndCapture()
    {
        if (_capture is null) return;
        _overlayHost.Children.Remove(_capture);
        _capture = null;
        foreach (var pane in _panes) pane.SetWebVisible(true);
        Focus();
        if (_resumeAfterCapture) StartPlayback();
        _resumeAfterCapture = false;
    }

    private async Task FinishCaptureAsync(PixelImage frozen, RectD crop, string sourceName)
    {
        EndCapture();
        var path = await Task.Run(() =>
        {
            try
            {
                var cropped = ImageCodec.Crop(frozen, crop);
                var target = ImageTools.UniquePath(InspectImages.CaptureFolder, ImageTools.CaptureStem(sourceName, cropped.Width, cropped.Height), "png");
                if (ImageCodec.Encode(cropped, ImageExportFormat.Png) is not { } bytes) return null;
                InspectImages.WriteFile(target, bytes);
                return target;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
            {
                Log.Warning($"VideoInspect: capture save failed: {ex.Message}");
                return null;
            }
        });
        if (path is null)
        {
            _toast.Show(L.T("Could not save capture"), error: true);
            return;
        }
        Log.Info($"VideoInspect: capture saved to '{Log.Redact(path)}'");
        _host.OpenCapture(path, this);
    }

    // ───────────────────────────── Keyboard ─────────────────────────────

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_capture is not null)
        {
            if (e.Key == Key.Escape) { EndCapture(); e.Handled = true; }
            else if (e.Key == Key.Enter) { _capture.Commit(); e.Handled = true; }
            return;
        }
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        switch (e.Key)
        {
            case Key.Space when Keyboard.Modifiers == ModifierKeys.None && !e.IsRepeat:
                TogglePlay();
                break;
            case Key.Escape:
                HandleEscape();
                break;
            case Key.W when ctrl:
                Close();
                break;
            case Key.V when ctrl:
                Paste();
                break;
            case Key.I when ctrl:
                ToggleInfo();
                break;
            case Key.X when ctrl && shift:
                _ = BeginCaptureAsync();
                break;
            case Key.M when Keyboard.Modifiers == ModifierKeys.None:
                ToggleMute(_session is { IsComparing: true } s ? s.ActiveSlot : 0);
                break;
            case Key.Left when Keyboard.Modifiers == ModifierKeys.None:
                Navigate(-1);
                break;
            case Key.Right when Keyboard.Modifiers == ModifierKeys.None:
                Navigate(1);
                break;
            default:
                return;
        }
        e.Handled = true;
    }

    /// <summary>Esc leaves Compare, then closes the information panel, then the window.</summary>
    private void HandleEscape()
    {
        if (_session is { IsComparing: true })
        {
            ExitCompare();
            return;
        }
        if (_infoVisible)
        {
            ToggleInfo();
            return;
        }
        Close();
    }

    // ───────────────────────────── Paste & drop ─────────────────────────────

    /// <summary>Ctrl+V: a video path / URL in the clipboard text joins the session (duplicates focus the existing one).</summary>
    private void Paste()
    {
        var text = InspectImages.ClipboardText();
        var info = text is null ? null : _detector.DetectAll(text).Select(MediaInfo.From).FirstOrDefault(i => i?.Kind == MediaKind.Video);
        if (info is null)
        {
            _toast.Show(L.T("No video link on the clipboard"), error: true);
            return;
        }
        AddVideo(info, slot: 1);
        Log.Info("VideoInspect: pasted a video");
    }

    private void AddVideo(MediaInfo info, int slot)
    {
        if (_session is not { } s)
        {
            Show([info], 0);
            return;
        }
        s.AddDropped(info, slot);
        _fittedSignature = "";
        Render(autoplay: true);
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        var ok = _capture is null && (e.Data.GetDataPresent(DataFormats.FileDrop) || e.Data.GetDataPresent(DataFormats.UnicodeText) || e.Data.GetDataPresent(DataFormats.Text));
        e.Effects = ok ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    /// <summary>Videos join the session (Compare: replacing the pane they landed on); other items open in their viewers.</summary>
    private void OnDrop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (_capture is not null) return;
        var slot = _panes.Count == 2 && IsOver(_panes[0], e) ? 0 : 1;
        var items = new List<MediaInfo>();
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            items.AddRange(files.Select(f => MediaInfo.From(_detector.LocalKind(f))).OfType<MediaInfo>());
        }
        else if ((e.Data.GetData(DataFormats.UnicodeText) as string ?? e.Data.GetData(DataFormats.Text) as string) is { } text && !string.IsNullOrWhiteSpace(text))
        {
            if (_detector.DetectAll(text).Select(MediaInfo.From).FirstOrDefault(i => i is not null) is { } detected) items.Add(detected);
        }
        if (items.Count == 0)
        {
            _toast.Show(L.T("Nothing Glance can open was dropped."), error: true);
            return;
        }
        foreach (var info in items)
        {
            if (info.Kind == MediaKind.Video) AddVideo(info, slot);
            else if (info.Kind == MediaKind.Folder) ShellActions.RevealInExplorer(info.Location);
            else _host.OpenOther(info);
        }
    }

    private static bool IsOver(FrameworkElement element, DragEventArgs e)
    {
        var p = e.GetPosition(element);
        return p.X >= 0 && p.Y >= 0 && p.X <= element.ActualWidth && p.Y <= element.ActualHeight;
    }

    // ───────────────────────────── Window frame ─────────────────────────────

    private void PlaceDesignFrame()
    {
        if (WindowState != WindowState.Normal) return;
        var monitor = ScreenGeometry.MonitorAtCursor();
        var workDip = new Size(monitor.WorkArea.Width / monitor.Scale, monitor.WorkArea.Height / monitor.Scale);
        var scale = Math.Min(1, Math.Min(workDip.Width / DesignSize.Width, workDip.Height / DesignSize.Height));
        ScreenManager.Place(this, ScreenManager.CenterFrame(new Size(DesignSize.Width * scale, DesignSize.Height * scale), monitor));
    }

    /// <summary>
    /// macOS <c>fitWindowToActiveVideosIfNeeded</c>: once every visible video's size is known, the
    /// window takes the Focus reference size (landscape 1120 × 700, portrait 560 × 900) or the
    /// pair's size in Compare, within 96 % of the work area, centred where it is. Once per layout.
    /// </summary>
    private void FitWindowToVideos()
    {
        if (WindowState != WindowState.Normal || _session is not { } s) return;
        var sizes = Enumerable.Range(0, ActiveIndices.Count).Select(NaturalSize).ToList();
        if (sizes.Count == 0 || sizes.Any(z => z is null)) return;
        var compare = s.IsComparing && sizes.Count == 2;
        var preferred = VideoChromeLayout.PreferredWindowSize(compare, sizes[0]!.Value, compare ? sizes[1] : null);
        var signature = $"{compare}-{Math.Round(preferred.Width)}x{Math.Round(preferred.Height)}";
        if (signature == _fittedSignature) return;
        _fittedSignature = signature;

        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        var monitor = ScreenGeometry.MonitorOf(hwnd);
        var scale = monitor.Scale;
        var work = monitor.WorkArea;
        var maximum = new SizeD(work.Width / scale * 0.96, work.Height / scale * 0.96);
        var minimum = new SizeD(Math.Min(MinWidth, maximum.Width), Math.Min(MinHeight, maximum.Height));
        var content = ViewportMath.MediaWindowSize(preferred, minimum, maximum);
        var extra = _infoVisible ? VideoChromeLayout.InfoPanelWidth : 0;
        var w = (int)Math.Round((content.Width + extra) * scale);
        var h = (int)Math.Round(content.Height * scale);
        var current = ScreenGeometry.WindowRect(hwnd);
        ScreenGeometry.SetWindowRect(hwnd, ScreenManager.Clamp(new PixelRect(current.CenterX - w / 2, current.CenterY - h / 2, w, h), work));
    }

    private void OnStateChanged()
    {
        _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
        _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
        if (WindowState == WindowState.Minimized && _playing) PausePlayback();
    }

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel) return;
        if (_session is { } closing) _host.Widgets?.Services.Tasks.ClearFailed(closing.Items.Select(i => i.Location));
        if (_reusable && !_quitting)
        {
            // Reused for the next video: hide and release the players.
            e.Cancel = true;
            Hide();
            ResetSession();
            WindowState = WindowState.Normal;
            return;
        }
        ResetSession();
    }

    // ───────────────────────────── Builders ─────────────────────────────

    private static Button ToolButton(string icon, string tooltip, Action onClick)
    {
        var button = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(icon, 16, "InspectText2Brush"), ToolTip = tooltip };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }

    private static void SetActive(Button button, bool active)
    {
        button.Background = active ? Ui.Brush("InspectInk4Brush") : Brushes.Transparent;
        if (button.Content is Viewbox { Child: Canvas canvas } && canvas.Children.Count > 0 && canvas.Children[0] is System.Windows.Shapes.Path path)
            path.Stroke = Ui.Brush(active ? "InspectText1Brush" : "InspectText2Brush");
    }

    private static TextBlock CaptionGlyph(string glyph) => new()
    {
        Text = glyph,
        FontFamily = Ui.IconFont,
        FontSize = 10,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static Button CaptionButton(TextBlock glyph, string tooltip, string styleKey, Action onClick)
    {
        var button = new Button { Content = glyph, ToolTip = tooltip, Style = Ui.Style(styleKey), Height = VideoChromeLayout.TitlebarHeight };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }
}
