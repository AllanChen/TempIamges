using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Account;
using Glance.App.Inspect;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.Logging;
using Glance.Core.Widgets;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App.Shell;

/// <summary>
/// Glance Home, implemented from the Figma Washi frames <c>02 · Home</c> (30:2347),
/// <c>46 · Home / Folder loaded</c> (30:7143) and <c>47 · Empty states</c> (30:7454):
/// <list type="bullet">
/// <item>44 DIP titlebar: "Glance" (Inter Medium 13, text/2) centred; Tasks / History / Preferences
/// icon buttons (28, 4 apart) on the right, before the Windows caption buttons.</item>
/// <item>Main area (window width − 360): an 856-wide column, centred. Open state: eyebrow, Mincho 34
/// title, Inter 14 subtitle, the 300 DIP dashed drop zone, then the last folder's 72 DIP strip.
/// Folder state: eyebrow, "N images ready." with Choose another / Inspect all, a 132 × 99 grid.</item>
/// <item>1 DIP line/hair divider, the Recent column (312 wide at x + 23, y + 27): header with
/// search, 56 DIP FileRows (radius 8, 40 DIP thumb, name 13, mono meta 11, time 12).</item>
/// <item>32 DIP status bar with a hairline, the status text and the shortcuts.</item>
/// </list>
/// Behaviour follows macOS <c>HomeWindow</c>: drop anywhere, Ctrl+O, Ctrl+Shift+O, Ctrl+V, Ctrl+,,
/// right-click for Widgets and open commands; Home hides after handing items to an inspector.
/// </summary>
internal sealed class HomeWindow : Window
{
    private const double TitlebarHeight = 44;
    private const double StatusHeight = 32;
    private const double RecentWidth = 359;
    private const double MainMaxWidth = 856;
    private const double DropZoneHeight = 300;
    private const double GridTileWidth = 132;
    private const double GridTileHeight = 99;
    private const double GridGap = 12;
    private const double StripTile = 72;
    private const int StripCount = 10;
    private const int MaxFolderImages = 2000;
    private const double StrokeWidth = 2.25; // Figma icons: 1.5 px at 16 px.

    private readonly IAppShell _shell;
    private readonly PathDetector _detector = new();
    private readonly SemaphoreSlim _thumbGate = new(4, 4);
    private readonly Dictionary<string, ImageSource?> _thumbs = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _metaCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly Grid _root = new();
    private readonly Grid _mainHost = new();
    private readonly StackPanel _recentList = new();
    private readonly ScrollViewer _recentScroll;
    private readonly Grid _recentEmpty;
    private readonly TextBox _recentSearch;
    private readonly TextBlock _status;
    private readonly InspectToast _toast = new();
    private readonly Border _dropZone;
    private readonly FrameworkElement _openState;
    private readonly StackPanel _stripSection;
    private readonly TextBlock _stripPath;
    private readonly TextBlock _stripCount;
    private readonly StackPanel _strip = new() { Orientation = Orientation.Horizontal };
    private readonly TextBlock _maximizeGlyph;
    private bool _quitting;
    private bool _recentDirty = true;

    private string? _folder;
    private IReadOnlyList<string> _folderImages = [];
    private CancellationTokenSource _folderCts = new();
    private WrapPanel? _grid;
    private ScrollViewer? _gridScroll;
    private string? _stripFolder;
    private IReadOnlyList<string> _stripImages = [];

    public HomeWindow(IAppShell shell)
    {
        _shell = shell;
        Title = "Glance";
        MinWidth = 900;
        MinHeight = 580;
        Background = Ui.Brush("InspectInk1Brush");
        FontFamily = Ui.InterFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        AllowDrop = true;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = TitlebarHeight - 5,
            ResizeBorderThickness = new Thickness(5),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Titlebar ──
        var title = new TextBlock
        {
            Text = "Glance",
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.Brush("InspectText2Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 13, 0, 0),
            IsHitTestVisible = false,
        };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 12, 0) };
        actions.Children.Add(IconButton(Ui.IconTasks, L.T("Tasks"), () => _shell.Widgets.ShowTaskCenter()));
        actions.Children.Add(IconButton(Ui.IconHistory, L.T("Recent"), FocusRecentSearch, 4));
        actions.Children.Add(IconButton(Ui.IconAdjust, L.T("Preferences"), _shell.ShowPreferences, 4));
        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var captions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized));
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", Close));
        var titlebar = new Grid
        {
            Height = TitlebarHeight,
            Children = { title, new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Children = { actions, captions } } },
        };
        Grid.SetColumnSpan(titlebar, 3);

        // ── Open state (02 · Home main column) ──
        _dropZone = BuildDropZone();
        _stripPath = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush("InspectText2Brush"), TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(12, 0, 0, 0) };
        _stripCount = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText3Brush") };
        var stripHeader = new DockPanel();
        DockPanel.SetDock(_stripCount, Dock.Right);
        stripHeader.Children.Add(_stripCount);
        stripHeader.Children.Add(new TextBlock { Text = L.T("Folder"), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush") });
        stripHeader.Children.Add(_stripPath);
        stripHeader.Cursor = Cursors.Hand;
        stripHeader.MouseLeftButtonUp += (_, _) =>
        {
            if (_stripFolder is not null) _ = LoadFolderAsync(_stripFolder);
        };
        _stripSection = new StackPanel { Margin = new Thickness(0, 56, 0, 0), Visibility = Visibility.Collapsed };
        _stripSection.Children.Add(stripHeader);
        _strip.Margin = new Thickness(0, 14, 0, 0);
        _strip.ClipToBounds = true;
        _stripSection.Children.Add(_strip);

        var open = new StackPanel { MaxWidth = MainMaxWidth, VerticalAlignment = VerticalAlignment.Center };
        open.Children.Add(Eyebrow("GLANCE  ·  " + string.Concat((char)0x898B, (char)0x308B), 1.32));
        open.Children.Add(Heading(L.T("Open an image to begin."), 20));
        open.Children.Add(new TextBlock
        {
            Text = L.T("Drop images or a folder anywhere in this window. Glance reads every image inside."),
            FontSize = 14,
            LineHeight = 22,
            Foreground = Ui.Brush("InspectText2Brush"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 10, 0, 0),
        });
        _dropZone.Margin = new Thickness(0, 40, 0, 0);
        open.Children.Add(_dropZone);
        open.Children.Add(_stripSection);
        _openState = open;
        _mainHost.Children.Add(_openState);
        _mainHost.Margin = new Thickness(40, 0, 40, 0);
        Grid.SetRow(_mainHost, 1);

        // ── Divider + Recent column ──
        var divider = new Border { Width = 1, Background = Ui.Brush("InspectLineBrush") };
        Grid.SetRow(divider, 1);
        Grid.SetColumn(divider, 1);

        _recentSearch = new TextBox
        {
            Style = Ui.Style("FieldBox"),
            Height = 28,
            FontSize = 12,
            Visibility = Visibility.Collapsed,
            Margin = new Thickness(12, 0, 0, 0),
            ToolTip = L.T("Search Recent"),
        };
        _recentSearch.TextChanged += (_, _) => RenderRecent();
        _recentSearch.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            _recentSearch.Clear();
            _recentSearch.Visibility = Visibility.Collapsed;
            e.Handled = true;
        };
        var recentTitle = new TextBlock { Text = L.T("Recent"), FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), VerticalAlignment = VerticalAlignment.Center };
        var searchButton = IconButton(Ui.IconSearch, L.T("Search Recent"), FocusRecentSearch);
        var header = new DockPanel { Margin = new Thickness(12, 0, 0, 12), LastChildFill = true };
        DockPanel.SetDock(searchButton, Dock.Right);
        DockPanel.SetDock(recentTitle, Dock.Left);
        header.Children.Add(searchButton);
        header.Children.Add(recentTitle);
        header.Children.Add(_recentSearch);
        _recentScroll = new ScrollViewer { Content = _recentList, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        _recentEmpty = BuildRecentEmpty();
        var recentBody = new Grid { Children = { _recentScroll, _recentEmpty } };
        var recent = new DockPanel { Width = 312, Margin = new Thickness(23, 27, 0, 0), HorizontalAlignment = HorizontalAlignment.Left };
        DockPanel.SetDock(header, Dock.Top);
        recent.Children.Add(header);
        recent.Children.Add(recentBody);
        Grid.SetRow(recent, 1);
        Grid.SetColumn(recent, 2);

        // ── Status bar ──
        _status = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(20, 9, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis };
        var shortcuts = new TextBlock
        {
            Text = L.T("Ctrl+O  open     Ctrl+Shift+O  folder     Ctrl+,  preferences"),
            FontFamily = Ui.CodeFont,
            FontSize = 11,
            Foreground = Ui.Brush("InspectText3Brush"),
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 10, 20, 0),
        };
        var status = new Grid
        {
            Height = StatusHeight,
            Children = { new Border { Height = 1, Background = Ui.Brush("InspectLineBrush"), VerticalAlignment = VerticalAlignment.Top }, _status, shortcuts },
        };
        Grid.SetRow(status, 2);
        Grid.SetColumnSpan(status, 3);

        _toast.Margin = new Thickness(0, 0, 0, StatusHeight + 16);
        Grid.SetRowSpan(_toast, 3);
        Grid.SetColumnSpan(_toast, 3);

        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TitlebarHeight) });
        _root.RowDefinitions.Add(new RowDefinition());
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(StatusHeight) });
        _root.ColumnDefinitions.Add(new ColumnDefinition());
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(RecentWidth) });
        foreach (var child in new UIElement[] { titlebar, _mainHost, divider, recent, status, _toast }) _root.Children.Add(child);
        Content = new Border { BorderBrush = Ui.Brush("InspectLineStrongBrush"), BorderThickness = new Thickness(1), Child = _root };

        UpdateStatus();
        SizeChanged += (_, _) => LayoutMain();
        StateChanged += (_, _) =>
        {
            _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
            _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
        };
        Activated += (_, _) =>
        {
            if (_recentDirty) RenderRecent();
        };
        PreviewKeyDown += OnKeyDown;
        DragOver += OnDragOver;
        DragLeave += (_, _) => SetDropHover(false);
        Drop += OnDrop;
        MouseRightButtonUp += (_, e) =>
        {
            if (e.OriginalSource is DependencyObject source && FindAncestor<TextBox>(source) is not null) return;
            ShowContextMenu();
            e.Handled = true;
        };
        _shell.History.Changed += (_, _) => Dispatcher.BeginInvoke(new Action(() =>
        {
            _recentDirty = true;
            if (IsVisible) RenderRecent();
        }));
    }

    // ───────────────────────────── Public API ─────────────────────────────

    public void Present()
    {
        if (!IsVisible)
        {
            var settings = _shell.Settings.Current;
            var size = settings.HomeWidth is >= 900 && settings.HomeHeight is >= 580
                ? new Size(settings.HomeWidth.Value, settings.HomeHeight.Value)
                : new Size(1080, 720);
            var monitor = ScreenGeometry.MonitorAtCursor();
            var work = new Size(monitor.WorkArea.Width / monitor.Scale, monitor.WorkArea.Height / monitor.Scale);
            size = new Size(Math.Min(size.Width, work.Width * 0.96), Math.Min(size.Height, work.Height * 0.96));
            ScreenManager.Place(this, ScreenManager.CenterFrame(size, monitor));
            Show();
            LoadStripFolder();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        if (_recentDirty) RenderRecent();
    }

    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    public void ShowToast(string message, bool error = false) => _toast.Show(message, error);

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel) return;
        if (WindowState == WindowState.Normal && ActualWidth >= 900 && ActualHeight >= 580)
        {
            var (w, h) = (ActualWidth, ActualHeight);
            _shell.Settings.Update(s => s with { HomeWidth = w, HomeHeight = h });
        }
        if (_quitting) return;
        e.Cancel = true;
        Hide();
    }

    // ───────────────────────────── Builders ─────────────────────────────

    /// <summary>Figma <c>drop zone</c>: ink/2, 1 DIP dashed line/strong, radius 12, 300 high.</summary>
    private Border BuildDropZone()
    {
        var content = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var icon = Ui.LineIcon(Ui.IconImage, 24, "InspectText3Brush", StrokeWidth);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        content.Children.Add(icon);
        content.Children.Add(new TextBlock { Text = L.T("Drop images or a folder"), FontSize = 15, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 20, 0, 0) });
        content.Children.Add(new TextBlock { Text = "PNG  JPEG  HEIC  WebP  TIFF  RAW", FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 28, 0, 0) };
        buttons.Children.Add(MakeButton(L.T("Open Files…"), primary: true, OpenFiles));
        var folder = MakeButton(L.T("Open Folder…"), primary: false, OpenFolder);
        folder.Margin = new Thickness(8, 0, 0, 0);
        buttons.Children.Add(folder);
        content.Children.Add(buttons);
        var dash = new Rectangle
        {
            Stroke = Ui.Brush("InspectLineStrongBrush"),
            StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 4, 4 },
            RadiusX = 12,
            RadiusY = 12,
            IsHitTestVisible = false,
        };
        return new Border
        {
            Height = DropZoneHeight,
            CornerRadius = new CornerRadius(12),
            Background = Ui.Brush("InspectInk2Brush"),
            Child = new Grid { Children = { dash, content } },
        };
    }

    /// <summary>Figma <c>47 · Empty states</c> "Nothing here yet", centred in the Recent column.</summary>
    private Grid BuildRecentEmpty()
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(28, 0, 28, 48) };
        var icon = Ui.LineIcon(Ui.IconHistory, 24, "InspectText3Brush", StrokeWidth);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(icon);
        stack.Children.Add(new TextBlock { Text = L.T("Nothing here yet"), FontFamily = Ui.TitleFont, FontSize = 20, LineHeight = 28, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 16, 0, 0) });
        stack.Children.Add(new TextBlock { Text = L.T("Inspected files show up here."), FontSize = 12, LineHeight = 19, Foreground = Ui.Brush("InspectText3Brush"), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxWidth = 254, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 0) });
        var open = MakeButton(L.T("Open Files…"), primary: false, OpenFiles);
        open.HorizontalAlignment = HorizontalAlignment.Center;
        open.Margin = new Thickness(0, 18, 0, 0);
        stack.Children.Add(open);
        return new Grid { Children = { stack }, Visibility = Visibility.Collapsed };
    }

    private static TextBlock Eyebrow(string text, double trackingPx) => new()
    {
        Text = text,
        FontFamily = Ui.CodeFont,
        FontSize = 11,
        Foreground = Ui.Brush("InspectText3Brush"),
        TextTrimming = TextTrimming.CharacterEllipsis,
        // Figma tracks the eyebrow by trackingPx; WPF TextBlock has no letter spacing, so the mono
        // font's own spacing stands in for it.
    };

    private static TextBlock Heading(string text, double top) => new()
    {
        Text = text,
        FontFamily = Ui.TitleFont,
        FontSize = 34,
        LineHeight = 44,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        Foreground = Ui.Brush("InspectText1Brush"),
        TextTrimming = TextTrimming.CharacterEllipsis,
        Margin = new Thickness(0, top, 0, 0),
    };

    /// <summary>Figma <c>Button</c>: 32 high, 16 side padding, radius 6, Inter Medium 13.</summary>
    private static Button MakeButton(string text, bool primary, Action onClick)
    {
        var button = new Button { Content = text, Style = Ui.Style(primary ? "InspectPrimaryButton" : "InspectQuietButton"), Height = 32, Padding = new Thickness(16, 0, 16, 0), FontFamily = Ui.InterFont, FontSize = 13 };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static Button IconButton(string icon, string tooltip, Action onClick, double leftMargin = 0)
    {
        var button = new Button
        {
            Style = Ui.Style("InspectIconButton"),
            Width = 28,
            Height = 28,
            Content = Ui.LineIcon(icon, 16, "InspectText2Brush", StrokeWidth),
            ToolTip = tooltip,
            Margin = new Thickness(leftMargin, 0, 0, 0),
        };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
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

    private void FocusRecentSearch()
    {
        _recentSearch.Visibility = Visibility.Visible;
        _recentSearch.Focus();
        _recentSearch.SelectAll();
    }

    // ───────────────────────────── Layout ─────────────────────────────

    /// <summary>The main column is 856 wide (or the area minus 40 on each side); the drop zone shrinks on short windows.</summary>
    private void LayoutMain()
    {
        var bodyHeight = Math.Max(0, ActualHeight - TitlebarHeight - StatusHeight);
        var stripRoom = _stripSection.Visibility == Visibility.Visible ? 56 + 14 + 14 + StripTile : 0;
        _dropZone.Height = Math.Clamp(bodyHeight - 150 - stripRoom - 48, 160, DropZoneHeight);
        if (_grid is not null) UpdateVisibleTiles();
    }

    // ───────────────────────────── Recent ─────────────────────────────

    private void RenderRecent()
    {
        _recentDirty = false;
        var filter = _recentSearch.Text.Trim();
        var items = new List<MediaInfo>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var record in _shell.History.Records)
            foreach (var item in record.Items)
            {
                if (MediaInfo.From(item.ToDetectedPath()) is not { } info || !seen.Add(info.Location)) continue;
                if (filter.Length > 0 && !info.FileName.Contains(filter, StringComparison.OrdinalIgnoreCase)) continue;
                items.Add(info);
            }
        _recentList.Children.Clear();
        foreach (var info in items.Take(200)) _recentList.Children.Add(FileRow(info));
        _recentEmpty.Visibility = items.Count == 0 && filter.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        _recentScroll.Visibility = _recentEmpty.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Figma <c>FileRow</c>: 56 high, 12 padding, radius 8, ink/3 on hover; rows 2 apart.</summary>
    private Border FileRow(MediaInfo info)
    {
        var thumb = new Border { Width = 40, Height = 40, CornerRadius = new CornerRadius(4), Background = Ui.Brush("InspectInk3Brush"), ClipToBounds = true };
        var image = new Image { Stretch = Stretch.UniformToFill };
        thumb.Child = image;
        thumb.Loaded += (_, _) => Ui.RoundClip(thumb, 4);
        if (info.IsLocal && info.Kind is MediaKind.Image or MediaKind.Video)
        {
            _ = LoadThumbAsync(info.Location, 80, image, thumb, info);
        }
        else
        {
            thumb.Child = Glyph(info);
        }
        var name = new TextBlock { Text = info.FileName, FontSize = 13, Foreground = Ui.Brush("InspectText1Brush"), TextTrimming = TextTrimming.CharacterEllipsis };
        var meta = new TextBlock { Text = MetaFor(info, null), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 3, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis };
        if (info.IsLocal && info.Kind != MediaKind.Folder) _ = LoadMetaAsync(info, meta);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 12, 0), Children = { name, meta } };
        var time = new TextBlock { Text = RelativeTime(LastSeen(info)), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center, MaxWidth = 96 };
        var row = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(thumb, Dock.Left);
        DockPanel.SetDock(time, Dock.Right);
        row.Children.Add(thumb);
        row.Children.Add(time);
        row.Children.Add(text);
        var border = new Border
        {
            Height = 56,
            Padding = new Thickness(12, 8, 12, 8),
            CornerRadius = new CornerRadius(8),
            Background = Brushes.Transparent,
            Margin = new Thickness(0, 0, 0, 2),
            Child = row,
            Cursor = Cursors.Hand,
            ToolTip = info.IsLocal ? info.Location : info.Location,
        };
        border.MouseEnter += (_, _) => border.Background = Ui.Brush("InspectInk3Brush");
        border.MouseLeave += (_, _) => border.Background = Brushes.Transparent;
        border.MouseLeftButtonUp += (_, _) =>
        {
            if (info.Kind == MediaKind.Folder) _ = LoadFolderAsync(info.Location);
            else _shell.OpenItems([info]);
        };
        return border;
    }

    private static FrameworkElement Glyph(MediaInfo info)
    {
        var glyph = info.Kind switch
        {
            MediaKind.Video => Ui.GlyphPlay,
            MediaKind.WebPage => Ui.GlyphGlobe,
            MediaKind.Folder => Ui.GlyphFolder,
            MediaKind.Image => Ui.GlyphPhoto,
            _ => Ui.GlyphDocument,
        };
        var text = Ui.Glyph(glyph, 15, "InspectText3Brush");
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.VerticalAlignment = VerticalAlignment.Center;
        return text;
    }

    private DateTime? LastSeen(MediaInfo info)
    {
        foreach (var record in _shell.History.Records)
            if (record.Items.Any(i => string.Equals(i.Value, info.Location, StringComparison.OrdinalIgnoreCase))) return record.Timestamp;
        return null;
    }

    /// <summary>Today "2m" / "1h", "Yesterday", the weekday within a week, else "MMM d".</summary>
    private static string RelativeTime(DateTime? time)
    {
        if (time is not { } t) return "";
        var local = t.Kind == DateTimeKind.Utc ? t.ToLocalTime() : t;
        var now = DateTime.Now;
        if (local.Date == now.Date)
        {
            var span = now - local;
            return span.TotalHours >= 1 ? L.F("%dh", (int)span.TotalHours) : L.F("%dm", Math.Max(1, (int)span.TotalMinutes));
        }
        if (local.Date == now.Date.AddDays(-1)) return L.T("Yesterday");
        if ((now.Date - local.Date).TotalDays < 7) return local.ToString("ddd", L.Culture);
        return local.ToString(L.T("MMM d"), L.Culture);
    }

    /// <summary>"FORMAT · size" (JPG → JPEG, WEBP → WebP, MD → Markdown; folders "Folder", web pages the host).</summary>
    private static string MetaFor(MediaInfo info, long? bytes)
    {
        if (info.Kind == MediaKind.Folder) return L.T("Folder");
        if (!info.IsLocal) return Uri.TryCreate(info.Location, UriKind.Absolute, out var uri) ? uri.Host : "";
        var format = info.FormatName switch { "JPG" => "JPEG", "WEBP" => "WebP", "MD" => "Markdown", var f => f };
        return bytes is { } b ? $"{format} · {Ui.FormatBytes(b)}" : format;
    }

    private async Task LoadMetaAsync(MediaInfo info, TextBlock target)
    {
        if (_metaCache.TryGetValue(info.Location, out var cached))
        {
            target.Text = cached;
            return;
        }
        var bytes = await Task.Run(() =>
        {
            try
            {
                return File.Exists(info.Location) ? new FileInfo(info.Location).Length : (long?)null;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return null;
            }
        });
        var text = MetaFor(info, bytes);
        _metaCache[info.Location] = text;
        target.Text = text;
    }

    // ───────────────────────────── Thumbnails ─────────────────────────────

    /// <summary>Shell thumbnails off the UI thread (4 at a time), cached per path.</summary>
    private async Task LoadThumbAsync(string path, int sizePx, Image target, Border? frame = null, MediaInfo? fallback = null)
    {
        var key = $"{sizePx}|{path}";
        if (!_thumbs.TryGetValue(key, out var thumb))
        {
            await _thumbGate.WaitAsync();
            try
            {
                if (!_thumbs.TryGetValue(key, out thumb))
                {
                    thumb = await ShellThumbnails.GetAsync(path, sizePx, thumbnailOnly: false);
                    _thumbs[key] = thumb;
                }
            }
            finally
            {
                _thumbGate.Release();
            }
        }
        if (thumb is not null) target.Source = thumb;
        else if (frame is not null && fallback is not null) frame.Child = Glyph(fallback);
    }

    // ───────────────────────────── Folder strip (open state) ─────────────────────────────

    /// <summary>The last folder opened from Home, as the 72 DIP strip under the drop zone.</summary>
    private void LoadStripFolder()
    {
        var folder = _shell.Settings.Current.HomeLastFolder;
        if (string.IsNullOrEmpty(folder) || _folder is not null)
        {
            if (string.IsNullOrEmpty(folder)) _stripSection.Visibility = Visibility.Collapsed;
            return;
        }
        _ = LoadStripAsync(folder);
    }

    private async Task LoadStripAsync(string folder)
    {
        var images = await Task.Run(() => EnumerateImages(folder));
        if (images.Count == 0)
        {
            _stripSection.Visibility = Visibility.Collapsed;
            LayoutMain();
            return;
        }
        _stripFolder = folder;
        _stripImages = images;
        _stripPath.Text = DisplayPath(folder);
        _stripCount.Text = images.Count == 1 ? L.T("1 image") : L.F("%d images", images.Count);
        _strip.Children.Clear();
        for (var i = 0; i < Math.Min(StripCount, images.Count); i++)
        {
            var index = i;
            var tile = new Border { Width = StripTile, Height = StripTile, CornerRadius = new CornerRadius(4), Background = Ui.Brush("InspectInk3Brush"), Margin = new Thickness(i == 0 ? 0 : 8, 0, 0, 0), ClipToBounds = true, Cursor = Cursors.Hand, ToolTip = System.IO.Path.GetFileName(images[i]) };
            var image = new Image { Stretch = Stretch.UniformToFill };
            tile.Child = image;
            tile.Loaded += (_, _) => Ui.RoundClip(tile, 4);
            tile.MouseLeftButtonUp += (_, _) => OpenFolderImage(_stripImages, index);
            _ = LoadThumbAsync(images[i], 144, image);
            _strip.Children.Add(tile);
        }
        _stripSection.Visibility = Visibility.Visible;
        LayoutMain();
    }

    // ───────────────────────────── Folder state (46) ─────────────────────────────

    private async Task LoadFolderAsync(string folder)
    {
        _folderCts.Cancel();
        _folderCts = new CancellationTokenSource();
        var ct = _folderCts.Token;
        IReadOnlyList<string> images;
        try
        {
            images = await Task.Run(() => EnumerateImages(folder), ct);
        }
        catch (OperationCanceledException)
        {
            return;
        }
        if (ct.IsCancellationRequested) return;
        if (images.Count == 0)
        {
            _status.Text = L.T("No images in that folder");
            ShowToast(L.T("No images in that folder"));
            return;
        }
        Log.Info($"Home: folder with {images.Count} image(s) '{Log.Redact(folder)}'");
        _folder = folder;
        _folderImages = images;
        _shell.Settings.Update(s => s with { HomeLastFolder = folder });
        ShowFolderState();
        UpdateStatus();
    }

    private void ShowFolderState()
    {
        var column = new Grid { MaxWidth = MainMaxWidth, Margin = new Thickness(0, 75, 0, 0) };
        column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        column.RowDefinitions.Add(new RowDefinition());
        column.Children.Add(Eyebrow(L.T("FOLDER") + "  ·  " + DisplayPath(_folder!), 1.1));

        var headerRow = new DockPanel { Margin = new Thickness(0, 18, 0, 0), LastChildFill = true };
        var inspectAll = MakeButton(L.F("Inspect all %d images", _folderImages.Count), primary: true, () => OpenFolderImage(_folderImages, 0));
        var another = MakeButton(L.T("Choose another"), primary: false, OpenFolder);
        another.Margin = new Thickness(16, 0, 16, 0);
        inspectAll.VerticalAlignment = VerticalAlignment.Bottom;
        another.VerticalAlignment = VerticalAlignment.Bottom;
        DockPanel.SetDock(inspectAll, Dock.Right);
        DockPanel.SetDock(another, Dock.Right);
        headerRow.Children.Add(inspectAll);
        headerRow.Children.Add(another);
        headerRow.Children.Add(Heading(_folderImages.Count == 1 ? L.T("1 image ready.") : L.F("%d images ready.", _folderImages.Count), 0));
        Grid.SetRow(headerRow, 1);
        column.Children.Add(headerRow);

        _grid = new WrapPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, -GridGap, 0) };
        for (var i = 0; i < _folderImages.Count; i++)
        {
            var index = i;
            var tile = new Border
            {
                Width = GridTileWidth,
                Height = GridTileHeight,
                Margin = new Thickness(0, 0, GridGap, GridGap),
                CornerRadius = new CornerRadius(4),
                Background = Ui.Brush("InspectInk3Brush"),
                ClipToBounds = true,
                Cursor = Cursors.Hand,
                ToolTip = System.IO.Path.GetFileName(_folderImages[i]),
                Child = new Image { Stretch = Stretch.UniformToFill },
                Tag = false,
            };
            tile.Loaded += (_, _) => Ui.RoundClip(tile, 4);
            tile.MouseLeftButtonUp += (_, _) => OpenFolderImage(_folderImages, index);
            _grid.Children.Add(tile);
        }
        _gridScroll = new ScrollViewer { Content = _grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 32, 0, 24) };
        _gridScroll.ScrollChanged += (_, _) => UpdateVisibleTiles();
        Grid.SetRow(_gridScroll, 2);
        column.Children.Add(_gridScroll);

        _mainHost.Children.Clear();
        _mainHost.Children.Add(column);
        Dispatcher.BeginInvoke(new Action(UpdateVisibleTiles), DispatcherPriority.Loaded);
    }

    /// <summary>Loads thumbnails for the visible grid rows plus two rows of buffer (macOS behaviour).</summary>
    private void UpdateVisibleTiles()
    {
        if (_grid is null || _gridScroll is null || _grid.ActualWidth <= 0) return;
        var columns = Math.Max(1, (int)((_grid.ActualWidth) / (GridTileWidth + GridGap)));
        var rowHeight = GridTileHeight + GridGap;
        var firstRow = Math.Max(0, (int)(_gridScroll.VerticalOffset / rowHeight) - 2);
        var lastRow = (int)((_gridScroll.VerticalOffset + _gridScroll.ViewportHeight) / rowHeight) + 2;
        for (var i = firstRow * columns; i < Math.Min(_grid.Children.Count, (lastRow + 1) * columns); i++)
        {
            if (_grid.Children[i] is not Border { Tag: false } tile || tile.Child is not Image image) continue;
            tile.Tag = true;
            _ = LoadThumbAsync(_folderImages[i], 264, image);
        }
    }

    private void OpenFolderImage(IReadOnlyList<string> images, int index)
    {
        if (images.Count == 0) return;
        var infos = images.Select(p => new MediaInfo(p, true, MediaKind.Image)).ToList();
        // The clicked image first keeps the rest of the folder in the Inspect filmstrip.
        var ordered = infos.Skip(index).Concat(infos.Take(index)).ToList();
        _shell.OpenItems(ordered);
    }

    private static IReadOnlyList<string> EnumerateImages(string folder)
    {
        try
        {
            var options = new EnumerationOptions { RecurseSubdirectories = false, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.Hidden | FileAttributes.System };
            return Directory.EnumerateFiles(folder, "*", options)
                .Where(f => FileKinds.Image.Contains(FileKinds.ExtensionOf(f)))
                .OrderBy(f => System.IO.Path.GetFileName(f), StringComparer.CurrentCultureIgnoreCase)
                .Take(MaxFolderImages)
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            Log.Info($"Home: couldn't read folder '{Log.Redact(folder)}': {ex.Message}");
            return [];
        }
    }

    /// <summary>"~\Pictures\Kyoto" for folders under the user profile.</summary>
    private static string DisplayPath(string path)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return path.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + path[home.Length..] : path;
    }

    private void UpdateStatus() =>
        _status.Text = _folder is null
            ? L.T("No file open")
            : (_folderImages.Count == 1 ? L.T("1 image") : L.F("%d images", _folderImages.Count)) + "  ·  " + DisplayPath(_folder);

    // ───────────────────────────── Open, drop, paste ─────────────────────────────

    private void OpenFiles()
    {
        var dialog = new OpenFileDialog { Multiselect = true, Filter = L.T("All files") + "|*.*" };
        if (dialog.ShowDialog(this) != true) return;
        OpenPaths(dialog.FileNames);
    }

    private void OpenFolder()
    {
        var dialog = new OpenFolderDialog { Multiselect = false };
        if (dialog.ShowDialog(this) != true) return;
        _ = LoadFolderAsync(dialog.FolderName);
    }

    /// <summary>A single folder loads the folder state; anything else opens like a Peek click.</summary>
    private void OpenPaths(IReadOnlyList<string> paths)
    {
        if (paths.Count == 1 && Directory.Exists(paths[0]))
        {
            _ = LoadFolderAsync(paths[0]);
            return;
        }
        var infos = paths.Select(p => MediaInfo.From(_detector.LocalKind(p))).OfType<MediaInfo>().ToList();
        if (infos.Count == 0)
        {
            ShowToast(L.T("Nothing Glance can open was dropped."), error: true);
            return;
        }
        _shell.OpenItems(infos);
    }

    private void SetDropHover(bool hover)
    {
        _dropZone.Background = Ui.Brush(hover ? "InspectInk3Brush" : "InspectInk2Brush");
        if (_dropZone.Child is Grid { Children.Count: > 0 } grid && grid.Children[0] is Rectangle dash)
            dash.Stroke = Ui.Brush(hover ? "InspectText2Brush" : "InspectLineStrongBrush");
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        var ok = e.Data.GetDataPresent(DataFormats.FileDrop) || e.Data.GetDataPresent(DataFormats.UnicodeText);
        e.Effects = ok ? DragDropEffects.Copy : DragDropEffects.None;
        SetDropHover(ok);
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetDropHover(false);
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            OpenPaths(files);
            return;
        }
        if (e.Data.GetData(DataFormats.UnicodeText) is string text) OpenText(text);
    }

    private bool OpenText(string text)
    {
        var detected = _detector.DetectAll(text).Select(MediaInfo.From).OfType<MediaInfo>().ToList();
        if (detected.Count == 0) return false;
        if (detected.Count == 1 && detected[0].Kind == MediaKind.Folder) _ = LoadFolderAsync(detected[0].Location);
        else _shell.OpenItems(detected);
        return true;
    }

    /// <summary>Ctrl+V: files, then a path / link in the text, then a clipboard image.</summary>
    private async Task PasteAsync()
    {
        try
        {
            if (Clipboard.ContainsFileDropList())
            {
                var files = Clipboard.GetFileDropList().Cast<string>().ToList();
                if (files.Count > 0)
                {
                    OpenPaths(files);
                    return;
                }
            }
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            // Clipboard busy: fall through.
        }
        if (InspectImages.ClipboardText() is { } text && OpenText(text)) return;
        if (InspectImages.ClipboardImage() is { } image && await InspectImages.SaveTempPngAsync(image, "pasted") is { } path)
        {
            _shell.OpenItems([new MediaInfo(path, true, MediaKind.Image)]);
            return;
        }
        ShowToast(L.T("Nothing to paste"));
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.OriginalSource is TextBox) return;
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        switch (e.Key)
        {
            case Key.O when ctrl && shift:
                OpenFolder();
                break;
            case Key.O when ctrl:
                OpenFiles();
                break;
            case Key.V when ctrl:
                _ = PasteAsync();
                break;
            case Key.OemComma when ctrl:
                _shell.ShowPreferences();
                break;
            case Key.W when ctrl:
                Close();
                break;
            case Key.Escape when _folder is not null:
                // Back to the open state.
                _folder = null;
                _folderImages = [];
                _grid = null;
                _gridScroll = null;
                _mainHost.Children.Clear();
                _mainHost.Children.Add(_openState);
                LoadStripFolder();
                UpdateStatus();
                break;
            default:
                return;
        }
        e.Handled = true;
    }

    // ───────────────────────────── Context menu ─────────────────────────────

    /// <summary>macOS Home right-click: Widgets (with costs), then Open Files / Open Folder.</summary>
    private void ShowContextMenu()
    {
        var menu = new ContextMenu();
        var language = _shell.Account.Language;
        var widgets = new MenuItem { Header = L.T("Widgets") };
        foreach (var widget in _shell.Account.Registry.Available.Where(w => w.Commands.Any(c => !c.IsTextOnly)))
        {
            var item = new MenuItem { Header = widget.DisplayName(language), InputGestureText = WidgetText.MenuBadge(widget) };
            item.Click += (_, _) => ShowToast(WidgetHint(widget));
            widgets.Items.Add(item);
        }
        var text = _shell.Account.Registry.Available.Where(w => w.HasTextOnlyCommand).ToList();
        if (text.Count > 0)
        {
            if (widgets.Items.Count > 0) widgets.Items.Add(new Separator());
            foreach (var widget in text)
            {
                var command = widget.Commands.First(c => c.IsTextOnly);
                var item = new MenuItem { Header = widget.DisplayName(language), InputGestureText = WidgetText.MenuBadge(widget) };
                item.Click += (_, _) => _shell.Widgets.RunText(widget, command, this);
                widgets.Items.Add(item);
            }
        }
        var market = new MenuItem { Header = L.T("Widget Market…") };
        market.Click += (_, _) => _shell.Widgets.ShowMarket(this);
        if (widgets.Items.Count == 0)
        {
            menu.Items.Add(market);
        }
        else
        {
            widgets.Items.Add(new Separator());
            widgets.Items.Add(market);
            menu.Items.Add(widgets);
        }
        menu.Items.Add(new Separator());
        var files = new MenuItem { Header = L.T("Open Files…"), InputGestureText = "Ctrl+O" };
        files.Click += (_, _) => OpenFiles();
        var folder = new MenuItem { Header = L.T("Open Folder…"), InputGestureText = "Ctrl+Shift+O" };
        folder.Click += (_, _) => OpenFolder();
        menu.Items.Add(files);
        menu.Items.Add(folder);
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.IsOpen = true;
    }

    private static string WidgetHint(WidgetManifest widget)
    {
        var image = widget.IsCompatible("image");
        var video = widget.IsCompatible("video");
        return image && video ? L.T("Open an image or video to use this Widget.")
            : image ? L.T("Open an image to use this Widget.")
            : video ? L.T("Open a video to use this Widget.")
            : L.T("Open a compatible file to use this Widget.");
    }

    private static T? FindAncestor<T>(DependencyObject? node) where T : DependencyObject
    {
        while (node is not null)
        {
            if (node is T match) return match;
            node = node is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(node) : LogicalTreeHelper.GetParent(node);
        }
        return null;
    }
}
