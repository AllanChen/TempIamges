using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Glance.App.Localization;
using Glance.App.Media;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Platform;

namespace Glance.App.Peek;

/// <summary>
/// The Peek panel (port of macOS <c>PreviewPanel</c>): loading / failure states, a single card
/// for one item, an image grid for several images, and a split view (sidebar + preview) for
/// mixed sets. Never takes focus; Esc and the hotkey close it via <see cref="PeekController"/>.
/// </summary>
internal sealed class PeekWindow : FloatingWindow
{
    // Geometry from PreviewPanel.swift.
    private const double PanelRadius = 20;
    private const double HeaderHeight = 52;
    private const double SingleCardWidth = 320;
    private const double CardInset = 16;
    private const double MetaHeight = 56;
    private const double SplitWidth = 652;
    private const double SplitHeight = 460;
    private const double SidebarWidth = 200;
    private const double SidebarRowHeight = 64;
    private const double GridTileHeight = 240;
    private const double GridGap = 10;
    private const double GridPadding = 12;

    private readonly Border _shadow;
    private readonly Border _surface;
    private List<MediaInfo> _infos = [];
    private readonly Dictionary<int, LoadedMedia> _loaded = [];
    private List<Action<LoadedMedia>>[] _updaters = [];

    public PeekWindow()
    {
        Title = "Glance Peek";
        _shadow = new Border
        {
            CornerRadius = new CornerRadius(PanelRadius),
            Background = Ui.Brush("SurfaceBrush"),
            Effect = Ui.Effect("PanelShadow"),
        };
        _surface = new Border
        {
            CornerRadius = new CornerRadius(PanelRadius),
            Background = Ui.Brush("SurfaceBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(1),
        };
        // Shadow and content are siblings so the DropShadowEffect never re-renders the images.
        var root = new Grid { Margin = new Thickness(ShadowMargin) };
        root.Children.Add(_shadow);
        root.Children.Add(_surface);
        Content = root;
    }

    public event Action<MediaInfo>? OpenRequested;

    /// <summary>The items currently shown (with any dimensions / sizes discovered while loading).</summary>
    public IReadOnlyList<MediaInfo> Items => _infos;
    public event Action<MediaInfo>? RevealRequested;
    public event Action? CloseRequested;

    public bool HasItems => _infos.Count > 0;

    // ---- states ------------------------------------------------------------------------------

    /// <param name="caption">Overrides the caption (e.g. "Searching…" while the selection is read).</param>
    public void ShowLoading(string? searchToken, string? caption = null)
    {
        ResetItems();
        caption ??= searchToken is null ? L.T("Preparing preview") : L.F("Searching for '%@'…", searchToken);
        var glyph = Ui.Glyph(Ui.GlyphSearch, 28, "TextTertiaryBrush");
        glyph.BeginAnimation(OpacityProperty, new DoubleAnimation(0.3, 1, TimeSpan.FromSeconds(0.8))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
        });
        SetContent(MessageBody(glyph, caption), new Size(SingleCardWidth, 180));
    }

    public void ShowFailure(string message)
    {
        ResetItems();
        SetContent(MessageBody(Ui.Glyph(Ui.GlyphWarning, 28, "FailureBrush"), message), new Size(SingleCardWidth, 180));
    }

    public void ShowItems(IReadOnlyList<MediaInfo> infos)
    {
        ResetItems();
        _infos = infos.ToList();
        _updaters = Enumerable.Range(0, _infos.Count).Select(_ => new List<Action<LoadedMedia>>()).ToArray();
        if (_infos.Count == 1) BuildSingleCard(_infos[0]);
        else if (_infos.All(i => i.Kind == MediaKind.Image)) BuildGrid();
        else BuildSplit(0);
    }

    public void UpdateItem(int index, LoadedMedia media)
    {
        if (index < 0 || index >= _infos.Count) return;
        _infos[index] = media.Info;
        _loaded[index] = media;
        foreach (var update in _updaters[index].ToList()) update(media);
    }

    private void ResetItems()
    {
        _infos = [];
        _loaded.Clear();
        _updaters = [];
    }

    // ---- single card -----------------------------------------------------------------------------

    private void BuildSingleCard(MediaInfo info)
    {
        var isVisual = info.Kind is MediaKind.Image or MediaKind.Video;
        var bodyHeight = isVisual ? 216.0 : 200.0;

        var preview = new MediaPreview(info, fill: false);
        var body = new Border
        {
            Height = bodyHeight,
            Margin = new Thickness(CardInset, 0, CardInset, 0),
            CornerRadius = new CornerRadius(14),
            Child = preview,
            Cursor = Cursors.Hand,
            ToolTip = OpenTooltip(info),
        };
        Ui.RoundClip(body, 14);
        body.MouseLeftButtonUp += (_, _) => OpenRequested?.Invoke(_infos.Count > 0 ? _infos[0] : info);

        var meta = Ui.Text(MetaLine(info), "CaptionText");
        meta.Margin = new Thickness(CardInset, 0, CardInset, 0);

        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(HeaderHeight) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(MetaHeight) });
        var header = Header(info.FileName, Subtitle(info), () => _infos.Count > 0 ? _infos[0] : info);
        Grid.SetRow(header, 0);
        Grid.SetRow(body, 1);
        Grid.SetRow(meta, 2);
        layout.Children.Add(header);
        layout.Children.Add(body);
        layout.Children.Add(meta);

        Size SizeFor(double h) => new(SingleCardWidth, HeaderHeight + h + MetaHeight);
        SetContent(layout, SizeFor(bodyHeight));

        _updaters[0].Add(media =>
        {
            preview.Apply(media);
            meta.Text = MetaLine(media.Info);
            if (isVisual && !media.IsIcon && media.Info is { PixelWidth: int w and > 0, PixelHeight: int h and > 0 })
            {
                var available = SingleCardWidth - CardInset * 2;
                var fitted = Math.Clamp(available * h / w, 160, 420);
                if (Math.Abs(fitted - body.Height) > 1)
                {
                    body.Height = fitted;
                    Relayout(SizeFor(fitted));
                }
            }
        });
    }

    // ---- image grid --------------------------------------------------------------------------------

    private void BuildGrid()
    {
        var count = _infos.Count;
        var shown = Math.Min(count, 6);
        var mediaCount = count > 6 ? 5 : shown;
        var columns = shown <= 2 ? shown : shown <= 4 ? 2 : 3;
        var rows = (int)Math.Ceiling(shown / (double)columns);
        var tileWidth = columns == 3 ? 220.0 : 300.0;
        var width = columns * tileWidth + (columns - 1) * GridGap + GridPadding * 2;
        var gridHeight = rows * GridTileHeight + (rows - 1) * GridGap + GridPadding * 2;

        var canvas = new Canvas { Width = width, Height = gridHeight };
        for (var index = 0; index < mediaCount; index++)
        {
            var i = index;
            var tile = GridTile(i, tileWidth);
            Canvas.SetLeft(tile, GridPadding + (i % columns) * (tileWidth + GridGap));
            Canvas.SetTop(tile, GridPadding + (i / columns) * (GridTileHeight + GridGap));
            canvas.Children.Add(tile);
        }
        if (count > 6)
        {
            var more = new Border
            {
                Width = tileWidth,
                Height = GridTileHeight,
                CornerRadius = Ui.Corner("CornerMedium"),
                Background = Ui.Brush("ControlFillBrush"),
                Cursor = Cursors.Hand,
                ToolTip = L.T("Show all"),
                Child = new TextBlock
                {
                    Text = $"+{count - 5}",
                    FontFamily = Ui.UiFont,
                    FontSize = 28,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = Ui.Brush("TextPrimaryBrush"),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            };
            more.MouseLeftButtonUp += (_, _) => BuildSplit(5);
            Canvas.SetLeft(more, GridPadding + (5 % columns) * (tileWidth + GridGap));
            Canvas.SetTop(more, GridPadding + (5 / columns) * (GridTileHeight + GridGap));
            canvas.Children.Add(more);
        }

        var layout = new DockPanel();
        var header = Header(L.F("%d images", count), _infos[0].SourceAppName, null);
        DockPanel.SetDock(header, Dock.Top);
        layout.Children.Add(header);
        layout.Children.Add(canvas);
        SetContent(layout, new Size(width, HeaderHeight + gridHeight));
        ReplayLoaded();
    }

    private FrameworkElement GridTile(int index, double width)
    {
        var info = _infos[index];
        var preview = new MediaPreview(info, fill: true);
        var name = new TextBlock
        {
            Text = info.FileName,
            FontFamily = Ui.UiFont,
            FontSize = Ui.Number("LabelSize"),
            FontWeight = FontWeights.SemiBold,
            Foreground = Ui.Brush("OnImageTextBrush"),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var meta = new TextBlock
        {
            Text = TileMeta(info),
            FontFamily = Ui.UiFont,
            FontSize = Ui.Number("CaptionSize"),
            Foreground = Ui.Brush("OnImageSecondaryTextBrush"),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var caption = new Border
        {
            VerticalAlignment = VerticalAlignment.Bottom,
            Background = Ui.Brush("ImageScrimBrush"),
            Padding = new Thickness(12, 28, 12, 10),
            Child = new StackPanel { Children = { name, meta } },
        };
        var tile = new Grid { Width = width, Height = GridTileHeight, Cursor = Cursors.Hand, ToolTip = OpenTooltip(info) };
        tile.Children.Add(preview);
        tile.Children.Add(caption);
        Ui.RoundClip(tile, Ui.Corner("CornerMedium").TopLeft);
        tile.MouseLeftButtonUp += (_, _) => OpenRequested?.Invoke(_infos[index]);

        _updaters[index].Add(media =>
        {
            preview.Apply(media);
            meta.Text = TileMeta(media.Info);
        });
        return tile;
    }

    // ---- split view --------------------------------------------------------------------------------

    private int _selected;
    private Action<int>? _selectSplit;

    private void BuildSplit(int initialSelection)
    {
        foreach (var handlers in _updaters) handlers.Clear();

        var rows = new List<Border>();
        var list = new StackPanel { Margin = new Thickness(8) };
        for (var index = 0; index < _infos.Count; index++)
        {
            var row = SidebarRow(index);
            rows.Add(row);
            list.Children.Add(row);
        }
        var sidebar = new Border
        {
            Width = SidebarWidth,
            Background = Ui.Brush("ChromeBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Focusable = false,
                Content = list,
            },
        };

        var detail = new Grid();
        detail.RowDefinitions.Add(new RowDefinition { Height = new GridLength(HeaderHeight) });
        detail.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        detail.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });

        var layout = new DockPanel();
        DockPanel.SetDock(sidebar, Dock.Left);
        layout.Children.Add(sidebar);
        layout.Children.Add(detail);

        _selectSplit = index =>
        {
            _selected = index;
            for (var i = 0; i < rows.Count; i++) SetRowSelected(rows[i], i == index);
            rows[index].BringIntoView();

            var info = _infos[index];
            detail.Children.Clear();
            var header = Header(info.FileName, Subtitle(info), () => _infos[_selected]);
            Grid.SetRow(header, 0);
            detail.Children.Add(header);

            var preview = new MediaPreview(info, fill: false);
            var body = new Border
            {
                Margin = new Thickness(CardInset, 0, CardInset, 0),
                CornerRadius = new CornerRadius(14),
                Child = preview,
                Cursor = Cursors.Hand,
                ToolTip = OpenTooltip(info),
            };
            Ui.RoundClip(body, 14);
            body.MouseLeftButtonUp += (_, _) => OpenRequested?.Invoke(_infos[_selected]);
            Grid.SetRow(body, 1);
            detail.Children.Add(body);

            var meta = Ui.Text(MetaLine(info), "CaptionText");
            meta.Margin = new Thickness(CardInset, 0, CardInset, 0);
            Grid.SetRow(meta, 2);
            detail.Children.Add(meta);

            _detailUpdate = media =>
            {
                preview.Apply(media);
                meta.Text = MetaLine(media.Info);
            };
            if (_loaded.TryGetValue(index, out var loaded)) _detailUpdate(loaded);
        };

        for (var index = 0; index < _infos.Count; index++)
        {
            var i = index;
            _updaters[i].Add(media =>
            {
                if (i == _selected) _detailUpdate?.Invoke(media);
            });
        }

        SetContent(layout, new Size(SplitWidth, SplitHeight));
        _selectSplit?.Invoke(Math.Clamp(initialSelection, 0, _infos.Count - 1));
        ReplayLoaded();
    }

    private Action<LoadedMedia>? _detailUpdate;

    private Border SidebarRow(int index)
    {
        var info = _infos[index];
        var thumb = new MediaPreview(info, fill: true, compact: true) { Width = 48, Height = 48 };
        Ui.RoundClip(thumb, 4);

        var name = Ui.Text(info.FileName, "LabelText");
        var meta = Ui.Text(SidebarMeta(info), "CaptionText");
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 8, 0) };
        text.Children.Add(name);
        text.Children.Add(meta);

        var indicator = new Border
        {
            Width = 3,
            Margin = new Thickness(0, 4, 0, 4),
            CornerRadius = new CornerRadius(1.5),
            Background = Ui.Brush("AccentBrush"),
            Visibility = Visibility.Hidden,
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(56) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        thumb.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(indicator, 0);
        Grid.SetColumn(thumb, 1);
        Grid.SetColumn(text, 2);
        grid.Children.Add(indicator);
        grid.Children.Add(thumb);
        grid.Children.Add(text);

        var row = new Border
        {
            Height = SidebarRowHeight,
            Margin = new Thickness(0, 0, 0, 2),
            CornerRadius = new CornerRadius(6),
            Background = Brushes.Transparent,
            Child = grid,
            Cursor = Cursors.Hand,
            Tag = indicator,
        };
        row.MouseEnter += (_, _) => { if (_selected != index) row.Background = Ui.Brush("RowHoverBrush"); };
        row.MouseLeave += (_, _) => { if (_selected != index) row.Background = Brushes.Transparent; };
        row.MouseLeftButtonUp += (_, e) =>
        {
            if (e.ClickCount >= 2) OpenRequested?.Invoke(_infos[index]);
            else _selectSplit?.Invoke(index);
        };

        _updaters[index].Add(media =>
        {
            thumb.Apply(media);
            meta.Text = SidebarMeta(media.Info);
        });
        return row;
    }

    private static void SetRowSelected(Border row, bool selected)
    {
        row.Background = selected ? Ui.Brush("ControlFillBrush") : Brushes.Transparent;
        if (row.Tag is Border indicator) indicator.Visibility = selected ? Visibility.Visible : Visibility.Hidden;
    }

    // ---- shared pieces ---------------------------------------------------------------------------------

    /// <summary>52-pt header: title/subtitle on the left, Open / Show in folder / Close on the right. Drags the window.</summary>
    private FrameworkElement Header(string title, string? subtitle, Func<MediaInfo>? target)
    {
        var grid = new Grid { Height = HeaderHeight, Background = Brushes.Transparent };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var identity = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 12, 0) };
        identity.Children.Add(Ui.Text(title, "HeadlineText"));
        if (!string.IsNullOrEmpty(subtitle)) identity.Children.Add(Ui.Text(subtitle, "CaptionText"));
        grid.Children.Add(identity);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        if (target is not null)
        {
            var info = target();
            buttons.Children.Add(Spaced(Ui.IconButton(Ui.GlyphOpen, OpenTooltip(info), () => OpenRequested?.Invoke(target()))));
            if (info.IsLocal)
                buttons.Children.Add(Spaced(Ui.IconButton(Ui.GlyphFolder, L.T("Show in Explorer"), () => RevealRequested?.Invoke(target()))));
        }
        buttons.Children.Add(Ui.IconButton(Ui.GlyphClose, L.T("Close"), () => CloseRequested?.Invoke()));
        Grid.SetColumn(buttons, 1);
        grid.Children.Add(buttons);

        Ui.DragsWindow(grid, this);
        return grid;

        static Button Spaced(Button b)
        {
            b.Margin = new Thickness(0, 0, 6, 0);
            return b;
        }
    }

    private FrameworkElement MessageBody(UIElement icon, string message)
    {
        var layout = new DockPanel();
        var header = Header("Glance", null, null);
        DockPanel.SetDock(header, Dock.Top);
        layout.Children.Add(header);

        var text = Ui.Text(message, "BodyText", TextTrimming.None);
        text.TextWrapping = TextWrapping.Wrap;
        text.TextAlignment = TextAlignment.Center;
        text.Foreground = Ui.Brush("TextSecondaryBrush");
        text.Margin = new Thickness(24, 12, 24, 0);
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, HeaderHeight / 2) };
        stack.Children.Add(icon);
        stack.Children.Add(text);
        layout.Children.Add(stack);
        return layout;
    }

    private void ReplayLoaded()
    {
        foreach (var (index, media) in _loaded.ToList())
            foreach (var update in _updaters[index].ToList())
                update(media);
    }

    private void SetContent(UIElement content, Size size)
    {
        var clipHost = new Border { Child = content };
        Ui.RoundClip(clipHost, PanelRadius - 1);
        _surface.Child = clipHost;
        _surface.Width = _shadow.Width = size.Width;
        _surface.Height = _shadow.Height = size.Height;
        Place(size);
    }

    private void Relayout(Size size)
    {
        _surface.Width = _shadow.Width = size.Width;
        _surface.Height = _shadow.Height = size.Height;
        Place(size);
    }

    /// <summary>Centered on the cursor's monitor on first show; on the panel's own monitor afterwards.</summary>
    private void Place(Size size)
    {
        var monitor = IsVisible
            ? ScreenGeometry.MonitorOf(new WindowInteropHelper(this).Handle)
            : ScreenGeometry.MonitorAtCursor();
        ShowAt(ScreenManager.CenterFrame(WithMargin(size), monitor));
    }

    public void Dismiss(Action? completed = null)
    {
        ResetItems();
        FadeOut(close: false, completed);
    }

    // ---- text helpers ------------------------------------------------------------------------------------

    private static string? Subtitle(MediaInfo info)
    {
        if (!string.IsNullOrEmpty(info.DisambiguationHint)) return info.DisambiguationHint;
        if (info.IsLocal) return Path.GetDirectoryName(info.Location.TrimEnd('\\'));
        return Uri.TryCreate(info.Location, UriKind.Absolute, out var uri) ? uri.Host : null;
    }

    private static string OpenTooltip(MediaInfo info) =>
        info.IsLocal ? L.T("Open") : L.T("Open in browser");

    internal static string MetaLine(MediaInfo info)
    {
        var parts = new List<string>();
        if (info.PixelWidth is > 0 && info.PixelHeight is > 0) parts.Add($"{info.PixelWidth} × {info.PixelHeight}");
        if (info.Duration is { } d) parts.Add(d.TotalHours >= 1 ? d.ToString(@"h\:mm\:ss") : d.ToString(@"m\:ss"));
        if (info.FileSize is { } bytes) parts.Add(Ui.FormatBytes(bytes));
        if (info.Kind == MediaKind.Folder) parts.Add(L.T("Folder"));
        else if (info.Kind == MediaKind.WebPage) parts.Add(L.T("Web page"));
        else if (info.FormatName.Length > 0) parts.Add(info.FormatName);
        if (!string.IsNullOrEmpty(info.SourceAppName)) parts.Add(L.F("from %@", info.SourceAppName));
        return string.Join(" · ", parts);
    }

    private static string TileMeta(MediaInfo info)
    {
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(info.DisambiguationHint)) parts.Add(info.DisambiguationHint);
        if (info.PixelWidth is > 0 && info.PixelHeight is > 0) parts.Add($"{info.PixelWidth} × {info.PixelHeight}");
        if (info.FileSize is { } bytes) parts.Add(Ui.FormatBytes(bytes));
        return string.Join(" · ", parts);
    }

    private static string SidebarMeta(MediaInfo info)
    {
        var parts = new List<string>();
        if (info.PixelWidth is > 0 && info.PixelHeight is > 0) parts.Add($"{info.PixelWidth} × {info.PixelHeight}");
        if (info.FileSize is { } bytes) parts.Add(Ui.FormatBytes(bytes));
        if (parts.Count == 0) parts.Add(info.DisambiguationHint ?? info.FormatName);
        return string.Join(" · ", parts);
    }
}
