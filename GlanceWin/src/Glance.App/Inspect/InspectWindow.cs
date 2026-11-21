using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Media;
using Glance.App.Theme;
using Glance.App.Widgets;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Inspect;
using Glance.Core.Logging;
using Glance.Platform;

namespace Glance.App.Inspect;

/// <summary>What Image Inspect hands back to the app.</summary>
internal interface IInspectHost
{
    /// <summary>A dropped / added item that isn't an image (documents, videos, web pages).</summary>
    void OpenOther(MediaInfo info);

    /// <summary>A saved capture opens in its own Inspect window, offset from <paramref name="source"/>.</summary>
    void OpenCapture(string path, Window source);

    /// <summary>Widgets (Phase 5); null until the account services are up.</summary>
    WidgetRunner? Widgets { get; }
}

/// <summary>
/// Image Inspect (port of macOS <c>ImageInspectWindow</c>, Figma Shizuka <c>03 · Image Inspect</c>):
/// a 44 pt titlebar with the mode switch (Focus / Compare / Slider) centred and Recognize Text,
/// Image information and More on the right before the window buttons; the stage with 44 / 16 pt
/// margins; a 92 pt bottom bar with the file info, the filmstrip and the zoom / position. Light
/// "Washi" palette. Images only; documents and videos dropped here go to their own viewers.
/// </summary>
internal sealed partial class InspectWindow : Window
{
    private const double TitlebarHeight = 44;
    private const double BottomBarHeight = 92;
    private const double StageMargin = 44;
    private const double StageBottomMargin = 16;
    private const double ResizeBorder = 5;
    private const int FullCacheLimit = 6;
    private static readonly Size DesignSize = new(1554, 1012);

    private readonly IInspectHost _host;
    private readonly bool _reusable;
    private readonly ImageLoader _loader = new();
    private readonly ImageLoader _thumbLoader = new();
    private readonly PathDetector _detector = new();

    private InspectSession? _session;
    private CancellationTokenSource _cts = new();
    private readonly Dictionary<string, BitmapSource> _full = [];
    private readonly List<string> _fullOrder = [];
    private readonly Dictionary<string, BitmapSource> _thumbs = [];
    private readonly HashSet<string> _failed = [];
    private readonly HashSet<string> _loadingFull = [];
    private readonly HashSet<string> _loadingThumbs = [];
    private readonly Dictionary<string, ImageDetails?> _details = [];
    private readonly HashSet<string> _loadingDetails = [];
    private readonly Dictionary<string, GifAnimation?> _gifs = [];
    private readonly HashSet<string> _loadingGifs = [];
    private (GifPlayer Player, string Key)? _primaryGif;
    private (GifPlayer Player, string Key)? _secondaryGif;

    private readonly Grid _root;
    private readonly Grid _stageBand;
    private readonly Grid _stage;
    private readonly ImageViewport _primary = new();
    private readonly ImageViewport _secondary = new();
    private readonly Canvas _tags = new() { IsHitTestVisible = false };
    private readonly CompareTag _tagA = new();
    private readonly CompareTag _tagB = new();
    private readonly LoadErrorView _loadError;
    private readonly Filmstrip _filmstrip = new();
    private readonly InspectBottomBar _bottomBar = new();
    private readonly FrameworkElement _modeSwitch;
    private readonly FrameworkElement _actions;
    private readonly Button _focusButton;
    private readonly Button _compareButton;
    private readonly Button _sliderButton;
    private readonly Button _marketButton;
    private readonly TaskRunningChip _runningChip;
    private HashSet<Guid> _handledResults = [];
    private readonly Button _ocrButton;
    private readonly Button _infoButton;
    private readonly Button _moreButton;
    private readonly TextBlock _maximizeGlyph;
    private readonly InspectToast _toast = new();
    private readonly ShortcutSheet _shortcuts = new();
    private readonly Grid _overlayHost = new();
    private readonly DispatcherTimer _hideTimer = new() { Interval = TimeSpan.FromMilliseconds(400) };

    private InspectDialog? _dialog;
    private CaptureEditor? _capture;
    private ContextMenu? _menu;
    private InspectInfoWindow? _infoWindow;
    private OcrResultWindow? _ocrWindow;
    private bool _infoVisible;
    private ImageViewport? _hovered;
    private bool _autoHide = true;
    private bool _chromeHidden;
    private bool _pinned;
    private bool _quitting;
    private SizeD? _fittedFor;

    public InspectWindow(IInspectHost host, bool reusable)
    {
        _host = host;
        _reusable = reusable;
        Title = L.T("Image Inspect");
        Width = 1100;
        Height = 760;
        MinWidth = 560;
        MinHeight = 360;
        Background = Ui.Brush("InspectInk0Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ResizeMode = ResizeMode.CanResize;
        AllowDrop = true;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = TitlebarHeight - ResizeBorder,
            ResizeBorderThickness = new Thickness(ResizeBorder),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Titlebar: mode switch centred, actions + window buttons on the right ──
        _focusButton = ToolButton(Ui.IconImage, L.T("Focus"), ExitCompare);
        _compareButton = ToolButton(Ui.IconCompare, L.T("Compare"), () => EnterCompare(CompareStyle.SideBySide));
        _sliderButton = ToolButton(Ui.IconAdjust, L.T("Slider"), () => EnterCompare(CompareStyle.Slider));
        _marketButton = ToolButton(Ui.IconGrid, L.T("Widget Market"), () => _host.Widgets?.ShowMarket(this));
        _marketButton.Visibility = host.Widgets is null ? Visibility.Collapsed : Visibility.Visible;
        var modes = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 0, 0) };
        foreach (var button in new[] { _focusButton, _compareButton, _sliderButton, _marketButton })
        {
            button.Margin = new Thickness(modes.Children.Count == 0 ? 0 : 2, 0, 0, 0);
            modes.Children.Add(button);
        }
        _modeSwitch = modes;

        _ocrButton = ToolButton(Ui.IconText, L.T("Recognize Text"), () => _ = RecognizeTextAsync());
        _infoButton = ToolButton(Ui.IconInfo, L.T("Image information"), ToggleInfo);
        _moreButton = ToolButton(Ui.IconMore, L.T("More"), ShowMoreMenu);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 12, 0) };
        foreach (var button in new[] { _ocrButton, _infoButton, _moreButton })
        {
            button.Margin = new Thickness(actions.Children.Count == 0 ? 0 : 4, 0, 0, 0);
            actions.Children.Add(button);
        }
        _actions = actions;

        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var captions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", ToggleMaximize));
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", Close));
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Children = { actions, captions } };
        var titlebar = new Grid { Height = TitlebarHeight, Children = { modes, right } };

        // ── Stage: viewports (two columns with an 8 pt gap while side by side), tags, load error ──
        _stage = new Grid();
        _stage.ColumnDefinitions.Add(new ColumnDefinition());
        _stage.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
        _stage.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
        Grid.SetColumnSpan(_primary, 1);
        Grid.SetColumn(_secondary, 2);
        _secondary.Visibility = Visibility.Collapsed;
        _stage.Children.Add(_primary);
        _stage.Children.Add(_secondary);
        _tags.Children.Add(_tagA);
        _tags.Children.Add(_tagB);
        _loadError = new LoadErrorView(RevealActive, RetryActive);
        _runningChip = new TaskRunningChip(id => _host.Widgets?.Services.Tasks.Cancel(id)) { Margin = new Thickness(0, 12, 0, 0) };
        _stageBand = new Grid { Children = { _stage, _loadError, _tags, _runningChip } };
        Grid.SetRow(_stageBand, 1);

        foreach (var viewport in new[] { _primary, _secondary })
        {
            viewport.StateChanged += OnViewportChanged;
            viewport.MenuRequested += (v, e) =>
            {
                if (_session?.IsComparing == true && _session.Style == CompareStyle.SideBySide) SelectSlot(v == _primary ? 0 : 1);
                ShowContextMenu(null);
            };
            viewport.MouseEnter += (v, _) => { _hovered = (ImageViewport)v; UpdateInfo(); };
            viewport.MouseLeave += (_, _) => { _hovered = null; UpdateInfo(); };
            viewport.PreviewMouseLeftButtonDown += (v, _) =>
            {
                if (_session?.IsComparing == true && _session.Style == CompareStyle.SideBySide) SelectSlot(v == _primary ? 0 : 1);
            };
        }

        // ── Bottom bar + filmstrip ──
        Grid.SetRow(_bottomBar, 2);
        _bottomBar.FitRequested += FitAll;
        _bottomBar.StyleRequested += EnterCompare;
        _bottomBar.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 1 && e.OriginalSource == _bottomBar) try { DragMove(); } catch (InvalidOperationException) { }
        };
        Grid.SetRow(_filmstrip, 2);
        _filmstrip.HorizontalAlignment = HorizontalAlignment.Center;
        _filmstrip.VerticalAlignment = VerticalAlignment.Bottom;
        _filmstrip.Margin = new Thickness(0, 0, 0, 22);
        _filmstrip.TileClicked += OnTileClicked;
        _filmstrip.VisibleIndicesChanged += LoadThumbnails;

        // ── Overlays (whole window): toast above the bottom bar, shortcuts, dialogs / capture ──
        _toast.Margin = new Thickness(0, 0, 0, BottomBarHeight + 12);
        foreach (var overlay in new FrameworkElement[] { _toast, _shortcuts, _overlayHost })
        {
            Grid.SetRowSpan(overlay, 3);
        }
        _shortcuts.MouseLeftButtonDown += (_, _) => _shortcuts.Visibility = Visibility.Collapsed;
        WindowChrome.SetIsHitTestVisibleInChrome(_overlayHost, true);

        _root = new Grid();
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TitlebarHeight) });
        _root.RowDefinitions.Add(new RowDefinition());
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(BottomBarHeight) });
        foreach (var child in new UIElement[] { _stageBand, _bottomBar, _filmstrip, titlebar, _toast, _shortcuts, _overlayHost })
            _root.Children.Add(child);
        Content = _root;

        SizeChanged += (_, _) => LayoutStage();
        StateChanged += (_, _) => OnStateChanged();
        MouseLeave += (_, _) => { if (_autoHide) _hideTimer.Start(); };
        MouseMove += (_, _) => ShowChrome();
        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            if (!IsMouseOver && _menu?.IsOpen != true && _dialog is null && _capture is null) HideChrome();
        };
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

    public InspectSession? Session => _session;

    /// <summary>Opens a new session (replacing any current one). An exact pair can start in Compare.</summary>
    public void Show(IReadOnlyList<MediaInfo> images, int focusedIndex, InspectMode mode = InspectMode.Focus)
    {
        if (images.Count == 0) return;
        ResetSession();
        _session = new InspectSession(images, focusedIndex, mode);
        _handledResults = _host.Widgets?.CompletedIds() ?? [];
        Log.Info($"Inspect: opened {images.Count} image(s) in {mode} mode");
        _fittedFor = null;
        CloseInfo();
        _ocrWindow?.Dismiss();

        var wasVisible = IsVisible;
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        if (!wasVisible)
        {
            PlaceDesignFrame();
            base.Show();
            PlaceDesignFrame();
        }
        Activate();
        ShowChrome();
        Render();
        LoadActive();
    }

    /// <summary>Adds an image to the current session (or opens one) and focuses it.</summary>
    public void Append(MediaInfo info)
    {
        if (_session is null || !IsVisible)
        {
            Show([info], 0);
            return;
        }
        _session.AppendOrFocus(info);
        Render();
        LoadActive();
        Activate();
    }

    /// <summary>App exit: really close (the reusable window otherwise only hides).</summary>
    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    public void ShowToast(string message, bool error = false) => _toast.Show(message, error);

    // ───────────────────────────── Rendering ─────────────────────────────

    private void Render()
    {
        if (_session is not { } s) return;
        var comparing = s.IsComparing;
        var sideBySide = comparing && s.Style == CompareStyle.SideBySide;

        SetActive(_focusButton, !comparing);
        SetActive(_compareButton, sideBySide);
        SetActive(_sliderButton, comparing && !sideBySide);
        _compareButton.IsEnabled = s.CanCompare;
        _sliderButton.IsEnabled = s.CanCompare;
        _ocrButton.IsEnabled = ActiveBitmap() is not null;
        SetActive(_infoButton, _infoVisible);

        _loadError.Visibility = Visibility.Collapsed;
        if (comparing)
        {
            var (a, b) = s.Pair!.Value;
            SetColumns(sideBySide);
            ShowItem(_primary, a);
            if (sideBySide)
            {
                _primary.SetSlider(false, null);
                ShowItem(_secondary, b);
                _primary.Dimmed = s.ActiveSlot != 0;
                _secondary.Dimmed = s.ActiveSlot != 1;
            }
            else
            {
                _primary.SetSlider(true, Bitmap(b));
                _primary.Dimmed = false;
            }
        }
        else
        {
            SetColumns(false);
            _primary.SetSlider(false, null);
            _primary.Dimmed = false;
            var index = s.FocusedIndex;
            ShowItem(_primary, index);
            if (Bitmap(index) is null && _failed.Contains(ItemKey(index)))
            {
                _loadError.Configure(s[index].FileName, s[index].IsLocal, s.Count > 1);
                _loadError.Visibility = Visibility.Visible;
            }
        }

        var showStrip = s.Count >= 2;
        _filmstrip.Visibility = showStrip ? Visibility.Visible : Visibility.Collapsed;
        if (showStrip)
        {
            _filmstrip.SetCount(s.Items.Select(i => i.FileName).ToList());
            _filmstrip.SetState(s.FocusedIndex, s.Pair, i => _failed.Contains(ItemKey(i)) && Bitmap(i) is null);
            for (var i = 0; i < s.Count; i++)
            {
                if (_thumbs.TryGetValue(ItemKey(i), out var thumb)) _filmstrip.SetThumbnail(i, thumb);
                else if (_full.TryGetValue(ItemKey(i), out var full)) _filmstrip.SetThumbnail(i, full);
            }
            _filmstrip.Reveal(comparing ? (s.ActiveSlot == 0 ? s.Pair!.Value.A : s.Pair!.Value.B) : s.FocusedIndex);
        }

        UpdateBottomBar();
        LayoutStage();
        Dispatcher.BeginInvoke(new Action(UpdateTags), DispatcherPriority.Loaded);
        UpdateInfo();
        RefreshOcrPanel();
        UpdateRunningChip();
    }

    // ───────────────────────────── Widgets ─────────────────────────────

    /// <summary>The running chip for the visible image (macOS <c>InspectRunningPill</c>).</summary>
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
    /// A finished Widget task on one of this session's images (macOS <c>widgetTasksDidChange</c>):
    /// image results are inserted after their source and compared with it; video and text results
    /// open in their viewers.
    /// </summary>
    private void OnTasksChanged(object? sender, EventArgs e)
    {
        if (_session is not { } s || !IsVisible || _host.Widgets is not { } widgets) return;
        UpdateRunningChip();
        foreach (var record in widgets.NewResults(s.Items.Select(i => i.Location), _handledResults))
        {
            var kind = WidgetRunner.ResultKind(record);
            if (kind == MediaKind.Image)
            {
                var source = Enumerable.Range(0, s.Count).FirstOrDefault(i => Glance.Core.Tasks.WidgetTaskManager.IsSameMedia(s[i].Location, record.SourceUrl), s.FocusedIndex);
                s.InsertDerived(new MediaInfo(record.OutputPath!, true, MediaKind.Image), source);
                _fittedFor = null;
                Render();
                LoadActive();
                _toast.Show(L.T("Widget completed"));
            }
            else
            {
                widgets.OpenResult(record);
            }
        }
    }

    private void ShowItem(ImageViewport viewport, int index)
    {
        var key = ItemKey(index);
        var bitmap = Bitmap(index);
        viewport.SetImage(bitmap, key, loading: !_failed.Contains(key), failed: _failed.Contains(key));
        UpdateGif(viewport, key);
    }

    /// <summary>Plays an animated GIF in a viewport (macOS 7f399a7); zoom / pan stay while frames change.</summary>
    private void UpdateGif(ImageViewport viewport, string? key)
    {
        var current = viewport == _primary ? _primaryGif : _secondaryGif;
        var animation = key is not null && _gifs.TryGetValue(key, out var a) ? a : null;
        if (current is { } c && c.Key == key && animation is not null && c.Player.Animation == animation) return;
        current?.Player.Dispose();
        (GifPlayer, string)? next = null;
        if (animation is not null && key is not null)
        {
            var player = new GifPlayer(animation, frame => viewport.SetImage(frame, key, loading: false, failed: false));
            player.Start();
            next = (player, key);
        }
        if (viewport == _primary) _primaryGif = next;
        else _secondaryGif = next;
    }

    private void StopGifs()
    {
        _primaryGif?.Player.Dispose();
        _secondaryGif?.Player.Dispose();
        _primaryGif = null;
        _secondaryGif = null;
    }

    private async Task LoadGifAsync(string key, MediaInfo info)
    {
        if (_gifs.ContainsKey(key) || !_loadingGifs.Add(key)) return;
        var session = _session;
        try
        {
            var animation = await GifAnimation.LoadAsync(info, InspectImages.DisplayMaxSide, _cts.Token);
            if (session != _session) return;
            _gifs[key] = animation;
            if (animation is not null && IsVisible) Render();
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            _loadingGifs.Remove(key);
        }
    }

    private void SetColumns(bool sideBySide)
    {
        _stage.ColumnDefinitions[1].Width = new GridLength(sideBySide ? 8 : 0);
        _stage.ColumnDefinitions[2].Width = sideBySide ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        Grid.SetColumnSpan(_primary, sideBySide ? 1 : 3);
        _secondary.Visibility = sideBySide ? Visibility.Visible : Visibility.Collapsed;
        if (!sideBySide) UpdateGif(_secondary, null);
        if (!sideBySide) _secondary.Dimmed = false;
    }

    private void UpdateBottomBar()
    {
        if (_session is not { } s) return;
        if (s.IsComparing)
        {
            var (a, b) = s.Pair!.Value;
            _bottomBar.ShowPair(s[a].FileName, s[b].FileName, s.Style);
            return;
        }
        var index = s.FocusedIndex;
        var info = s[index];
        var failed = _failed.Contains(ItemKey(index)) && Bitmap(index) is null;
        var parts = new List<string>();
        if (failed) parts.Add(L.T("Load failed"));
        else if (info.PixelWidth is { } w && info.PixelHeight is { } h) parts.Add($"{w} × {h}");
        if (!string.IsNullOrEmpty(info.FormatName)) parts.Add(info.FormatName);
        if (info.FileSize is { } bytes) parts.Add(Ui.FormatBytes(bytes));
        var zoom = failed || _primary.Image is null ? "" : _primary.IsZoomedIn ? $"{_primary.ZoomPercent}%" : L.T("Fit");
        _bottomBar.ShowSingle(info.FileName, string.Join(failed ? "  ·  " : "   ", parts), zoom,
            s.Count > 1 ? $"{index + 1} / {s.Count}" : null);
    }

    /// <summary>
    /// Figma stage margins: 44 pt at the top and sides, 16 pt above the bottom bar, smaller on
    /// small windows. Filmstrip: up to 8½ tiles, leaving 120–240 pt for the info on each side.
    /// </summary>
    private void LayoutStage()
    {
        var width = _root.ActualWidth;
        var height = _root.ActualHeight;
        if (width <= 0 || height <= 0) return;
        var bandH = Math.Max(0, height - TitlebarHeight - BottomBarHeight);
        var margin = Math.Min(StageMargin, Math.Max(16, Math.Floor(Math.Min(width, bandH) * 0.08)));
        var bottom = Math.Min(StageBottomMargin, margin);
        _stageBand.Margin = new Thickness(margin, margin, margin, bottom);

        if (_filmstrip.Visibility == Visibility.Visible && _session is { } s)
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
        Dispatcher.BeginInvoke(new Action(UpdateTags), DispatcherPriority.Loaded);
    }

    /// <summary>Compare labels 12 pt inside the top corners of the images (slider: B left, A right).</summary>
    private void UpdateTags()
    {
        _tagA.Visibility = Visibility.Collapsed;
        _tagB.Visibility = Visibility.Collapsed;
        if (_session is not { IsComparing: true } s) return;
        var (a, b) = s.Pair!.Value;
        _tagA.Configure("A", s[a].FileName);
        _tagB.Configure("B", s[b].FileName);
        var sideBySide = s.Style == CompareStyle.SideBySide;
        var leftRect = Shown(_primary);
        var rightRect = sideBySide ? Shown(_secondary) : leftRect;
        var leftTag = sideBySide ? _tagA : _tagB;
        var rightTag = sideBySide ? _tagB : _tagA;
        Place(leftTag, leftRect, alignRight: false);
        Place(rightTag, rightRect, alignRight: true);
        if (!sideBySide && _tagA.Visibility == Visibility.Visible && _tagB.Visibility == Visibility.Visible
            && Canvas.GetLeft(_tagB) + _tagB.DesiredSize.Width + 8 > Canvas.GetLeft(_tagA))
            _tagB.Visibility = Visibility.Collapsed;

        Rect? Shown(ImageViewport viewport)
        {
            if (viewport.Visibility != Visibility.Visible || viewport.DisplayedImageRect() is not { } r) return null;
            var origin = viewport.TranslatePoint(r.TopLeft, _tags);
            return new Rect(origin, r.Size);
        }

        static void Place(CompareTag tag, Rect? rect, bool alignRight)
        {
            tag.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var size = tag.DesiredSize;
            if (rect is not { } r || r.Width < size.Width + 24 || r.Height < size.Height + 24) return;
            Canvas.SetLeft(tag, Math.Round(alignRight ? r.Right - 12 - size.Width : r.Left + 12));
            Canvas.SetTop(tag, Math.Round(r.Top + 12));
            tag.Visibility = Visibility.Visible;
        }
    }

    private void OnViewportChanged(ImageViewport source, ViewportState state)
    {
        if (_session is { IsComparing: true, Style: CompareStyle.SideBySide })
        {
            var other = source == _primary ? _secondary : _primary;
            other.SetState(state, notify: false);
        }
        UpdateBottomBar();
        UpdateTags();
    }

    // ───────────────────────────── Loading ─────────────────────────────

    private string ItemKey(int index) => _session is { } s && index >= 0 && index < s.Count ? InspectSession.Identity(s[index]) : "";

    private BitmapSource? Bitmap(int index)
    {
        var key = ItemKey(index);
        if (_full.TryGetValue(key, out var full)) return full;
        return _thumbs.TryGetValue(key, out var thumb) ? thumb : null;
    }

    private BitmapSource? ActiveBitmap() => _session is { } s ? Bitmap(s.ActiveIndex) : null;

    private int IndexOfKey(string key) =>
        _session is { } s ? Enumerable.Range(0, s.Count).FirstOrDefault(i => InspectSession.Identity(s[i]) == key, -1) : -1;

    /// <summary>Full-resolution display bitmaps and details for what's on screen.</summary>
    private void LoadActive()
    {
        if (_session is not { } s) return;
        var indices = s.IsComparing ? new[] { s.Pair!.Value.A, s.Pair!.Value.B } : new[] { s.FocusedIndex };
        foreach (var index in indices)
        {
            // A small decode first so something shows while a large photo decodes.
            _ = LoadThumbnailAsync(index);
            _ = LoadFullAsync(index);
            _ = LoadDetailsAsync(index);
        }
        LoadThumbnails(_filmstrip.VisibleIndices());
    }

    private async Task LoadFullAsync(int index)
    {
        if (_session is not { } session) return;
        var key = ItemKey(index);
        if (key.Length == 0 || _full.ContainsKey(key) || _failed.Contains(key) || !_loadingFull.Add(key)) return;
        var info = session[index];
        var ct = _cts.Token;
        try
        {
            var media = await _loader.LoadAsync(info, InspectImages.DisplayMaxSide, ct);
            if (session != _session) return;
            var current = IndexOfKey(key);
            if (media is { IsIcon: false, Image: BitmapSource bitmap })
            {
                _full[key] = bitmap;
                _fullOrder.Remove(key);
                _fullOrder.Add(key);
                _failed.Remove(key);
                if (current >= 0)
                {
                    session.Replace(current, session[current] with
                    {
                        PixelWidth = media.Info.PixelWidth ?? bitmap.PixelWidth,
                        PixelHeight = media.Info.PixelHeight ?? bitmap.PixelHeight,
                        FileSize = media.Info.FileSize ?? session[current].FileSize,
                    });
                    if (!session.IsComparing && current == session.FocusedIndex) FitWindowToImage(session[current]);
                }
                TrimCache();
                if (GifAnimation.IsCandidate(info)) _ = LoadGifAsync(key, info);
            }
            else
            {
                _failed.Add(key);
                if (current >= 0 && media.Info.FileSize is { } size) session.Replace(current, session[current] with { FileSize = size });
                Log.Info($"Inspect: could not decode '{Log.Redact(info.Location)}': {media.Error}");
            }
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception ex)
        {
            Log.Warning($"Inspect: load failed for '{Log.Redact(info.Location)}': {ex.Message}");
            _failed.Add(key);
        }
        finally
        {
            _loadingFull.Remove(key);
        }
        if (session == _session) Render();
    }

    private void LoadThumbnails(IReadOnlyList<int> indices)
    {
        foreach (var index in indices) _ = LoadThumbnailAsync(index);
    }

    private async Task LoadThumbnailAsync(int index)
    {
        if (_session is not { } session) return;
        var key = ItemKey(index);
        if (key.Length == 0 || _thumbs.ContainsKey(key) || _failed.Contains(key) || !_loadingThumbs.Add(key)) return;
        var info = session[index];
        try
        {
            var media = await _thumbLoader.LoadAsync(info, InspectImages.ThumbnailMaxSide, _cts.Token);
            if (session != _session) return;
            var current = IndexOfKey(key);
            if (media is { IsIcon: false, Image: BitmapSource bitmap })
            {
                _thumbs[key] = bitmap;
                if (current >= 0)
                {
                    _filmstrip.SetThumbnail(current, bitmap);
                    if (!_full.ContainsKey(key) && IsOnScreen(current)) Render();
                }
            }
            else if (!_full.ContainsKey(key))
            {
                _failed.Add(key);
                if (current >= 0) Render();
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex)
        {
            Log.Warning($"Inspect: thumbnail failed: {ex.Message}");
        }
        finally
        {
            _loadingThumbs.Remove(key);
        }
    }

    private async Task LoadDetailsAsync(int index)
    {
        if (_session is not { } session) return;
        var key = ItemKey(index);
        if (key.Length == 0 || _details.ContainsKey(key) || !_loadingDetails.Add(key)) return;
        try
        {
            var details = await InspectImages.ReadDetailsAsync(session[index]);
            if (session != _session) return;
            _details[key] = details;
            UpdateInfo();
        }
        finally
        {
            _loadingDetails.Remove(key);
        }
    }

    private bool IsOnScreen(int index) =>
        _session is { } s && (s.IsComparing ? s.Pair!.Value.A == index || s.Pair!.Value.B == index : s.FocusedIndex == index);

    /// <summary>Keeps the display bitmaps of what's on screen plus the most recent few (big photos are large).</summary>
    private void TrimCache()
    {
        if (_session is not { } s) return;
        var keep = s.IsComparing ? new HashSet<string> { ItemKey(s.Pair!.Value.A), ItemKey(s.Pair!.Value.B) } : new HashSet<string> { ItemKey(s.FocusedIndex) };
        while (_fullOrder.Count > FullCacheLimit)
        {
            var victim = _fullOrder.FirstOrDefault(k => !keep.Contains(k));
            if (victim is null) break;
            _fullOrder.Remove(victim);
            _full.Remove(victim);
        }
    }

    private void Forget(string key)
    {
        _gifs.Remove(key);
        _full.Remove(key);
        _fullOrder.Remove(key);
        _thumbs.Remove(key);
        _failed.Remove(key);
        _details.Remove(key);
        _ocr.Remove(key);
    }

    private void ResetSession()
    {
        _cts.Cancel();
        _cts.Dispose();
        _cts = new CancellationTokenSource();
        _session = null;
        _full.Clear();
        _fullOrder.Clear();
        _thumbs.Clear();
        _failed.Clear();
        _loadingFull.Clear();
        _loadingThumbs.Clear();
        _details.Clear();
        _loadingDetails.Clear();
        _ocr.Clear();
        _ocrShownKey = null;
        StopGifs();
        _gifs.Clear();
        _loadingGifs.Clear();
        _primary.SetImage(null, null, false, false);
        _secondary.SetImage(null, null, false, false);
        _filmstrip.SetCount([]);
        CloseOverlays();
    }

    // ───────────────────────────── Window frame ─────────────────────────────

    /// <summary>Figma design size (1554 × 1012) shrunk to the cursor's monitor, centred.</summary>
    private void PlaceDesignFrame()
    {
        if (WindowState != WindowState.Normal) return;
        var monitor = ScreenGeometry.MonitorAtCursor();
        var workDip = new Size(monitor.WorkArea.Width / monitor.Scale, monitor.WorkArea.Height / monitor.Scale);
        var scale = Math.Min(1, Math.Min(workDip.Width / DesignSize.Width, workDip.Height / DesignSize.Height));
        ScreenManager.Place(this, ScreenManager.CenterFrame(new Size(DesignSize.Width * scale, DesignSize.Height * scale), monitor));
    }

    /// <summary>
    /// Fits the window to the focused image (macOS <c>fitWindowToImage</c>): one image pixel per
    /// screen pixel when it fits, otherwise scaled into 96 % of the work area; the titlebar, bottom
    /// bar and stage margins come on top. Stays centred where it is.
    /// </summary>
    private void FitWindowToImage(MediaInfo info)
    {
        if (WindowState != WindowState.Normal || info.PixelWidth is not > 0 || info.PixelHeight is not > 0) return;
        var pixels = new SizeD(info.PixelWidth.Value, info.PixelHeight.Value);
        if (_fittedFor == pixels) return;
        _fittedFor = pixels;

        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        var monitor = ScreenGeometry.MonitorOf(hwnd);
        var scale = monitor.Scale;
        var work = monitor.WorkArea;
        double chromeW = StageMargin * 2, chromeH = TitlebarHeight + BottomBarHeight + StageMargin + StageBottomMargin;
        var maximum = new SizeD(work.Width / scale * 0.96 - chromeW, work.Height / scale * 0.96 - chromeH);
        var minimum = new SizeD(MinWidth - chromeW, MinHeight - chromeH);
        var media = ViewportMath.MediaWindowSize(new SizeD(pixels.Width / scale, pixels.Height / scale), minimum, maximum);
        var w = (int)Math.Round((media.Width + chromeW) * scale);
        var h = (int)Math.Round((media.Height + chromeH) * scale);
        var current = ScreenGeometry.WindowRect(hwnd);
        var target = ScreenManager.Clamp(new PixelRect(current.CenterX - w / 2, current.CenterY - h / 2, w, h), work);
        ScreenGeometry.SetWindowRect(hwnd, target);
    }

    private void OnStateChanged()
    {
        _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
        _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
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
            // Reused for the next Peek: hide, drop the session and its bitmaps.
            e.Cancel = true;
            CloseInfo();
            _ocrWindow?.Dismiss();
            Hide();
            ResetSession();
            WindowState = WindowState.Normal;
            return;
        }
        _cts.Cancel();
    }

    // ───────────────────────────── Chrome auto-hide ─────────────────────────────

    /// <summary>The toolbar and bottom bar fade when the pointer leaves; the window buttons stay.</summary>
    private void HideChrome()
    {
        if (_chromeHidden || !_autoHide) return;
        _chromeHidden = true;
        foreach (var element in ChromeElements()) Fade(element, 0);
    }

    private void ShowChrome()
    {
        _hideTimer.Stop();
        if (!_chromeHidden) return;
        _chromeHidden = false;
        foreach (var element in ChromeElements()) Fade(element, 1);
    }

    private IEnumerable<UIElement> ChromeElements() => [_modeSwitch, _actions, _bottomBar, _filmstrip, _runningChip];

    private static void Fade(UIElement element, double to)
    {
        element.IsHitTestVisible = to > 0;
        element.BeginAnimation(OpacityProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(to > 0 ? 160 : 260)));
    }

    // ───────────────────────────── Builders ─────────────────────────────

    private static Button ToolButton(string icon, string tooltip, Action onClick)
    {
        var button = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(icon, 16, "InspectText2Brush"), ToolTip = tooltip };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }

    /// <summary>Figma Shizuka IconButton: ink/4 tile and text/1 glyph when selected.</summary>
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
        var button = new Button { Content = glyph, ToolTip = tooltip, Style = Ui.Style(styleKey), Height = TitlebarHeight };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }
}
