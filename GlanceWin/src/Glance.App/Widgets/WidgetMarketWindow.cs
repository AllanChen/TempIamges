using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using Glance.App.Account;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Account;
using Glance.Core.Logging;
using Glance.Core.Widgets;
using Glance.Platform;

namespace Glance.App.Widgets;

/// <summary>
/// The Widget Market (port of macOS <c>WidgetMarketPanel</c>, Figma Shizuka <c>09 · Widget Market</c>):
/// a 44 pt titlebar with the centred title and Refresh; on the left the search field, the
/// Marketplace / Installed / Updates tabs and 56 pt Widget rows; on the right the selected Widget's
/// detail with Remove / Install or Update / Run and its spec rows. Installed Widgets stay listed
/// offline. Reusable: closing hides it.
/// </summary>
internal sealed class WidgetMarketWindow : Window
{
    private const double TitlebarHeight = 44;
    private const double ResizeBorder = 5;
    private const double RowHeight = 56;
    private static readonly Size DesignSize = new(1440, 900);

    private enum Tab { Marketplace, Installed, Updates }

    /// <summary>One listed Widget: the catalog copy and / or the installed copy.</summary>
    private sealed record Entry(string Id, WidgetManifest? Catalog, WidgetManifest? Installed)
    {
        public WidgetManifest Display => Installed is not null && Catalog is not null && !HasUpdate ? Installed : Catalog ?? Installed!;
        public bool IsInstalled => Installed is not null;
        public bool HasUpdate => Installed is not null && Catalog is not null && Installed.DiffersFrom(Catalog);
        public bool CanInstall => Catalog is not null && (Installed is null || HasUpdate);
    }

    private readonly AccountServices _services;
    private readonly IWidgetHost _host;
    private readonly Grid _root;
    private readonly TextBox _search;
    private readonly TextBlock _searchPlaceholder;
    private readonly Button _clearSearch;
    private readonly StackPanel _tabs = new() { Orientation = Orientation.Horizontal };
    private readonly Button _sortButton;
    private readonly StackPanel _list = new();
    private readonly ScrollViewer _listScroll;
    private readonly StackPanel _empty;
    private readonly TextBlock _emptyTitle;
    private readonly TextBlock _emptyHint;
    private readonly TextBlock _loadingLabel;
    private readonly StackPanel _detail = new();
    private readonly ScrollViewer _detailScroll;
    private readonly TextBlock _maximizeGlyph;

    private readonly Dictionary<string, ImageSource> _icons = [];
    private readonly HashSet<string> _loadingIcons = [];
    private readonly HashSet<string> _installing = [];
    private readonly Dictionary<string, string> _actionErrors = [];
    private List<WidgetManifest> _catalog = [];
    private bool _loaded;
    private bool _loading;
    private string? _loadError;
    private Tab _tab = Tab.Marketplace;
    private bool _sortByName;
    private string? _selectedId;
    private bool _quitting;

    public WidgetMarketWindow(AccountServices services, IWidgetHost host)
    {
        _services = services;
        _host = host;
        Title = L.T("Widgets");
        Width = DesignSize.Width;
        Height = DesignSize.Height;
        MinWidth = 900;
        MinHeight = 600;
        Background = Ui.Brush("InspectInk0Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ResizeMode = ResizeMode.CanResize;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = TitlebarHeight - ResizeBorder,
            ResizeBorderThickness = new Thickness(ResizeBorder),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Titlebar: centred "Widgets", Refresh, window buttons ──
        var title = new TextBlock
        {
            Text = L.T("Widgets"),
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.Brush("InspectText1Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
        };
        var refresh = new Button
        {
            Style = Ui.Style("InspectIconButton"),
            Content = Ui.Glyph(((char)0xE72C).ToString(), 13, "InspectText2Brush"),
            ToolTip = L.T("Refresh"),
            Margin = new Thickness(0, 8, 12, 0),
            VerticalAlignment = VerticalAlignment.Top,
        };
        refresh.Click += (_, _) => _ = LoadCatalogAsync(silent: false);
        WindowChrome.SetIsHitTestVisibleInChrome(refresh, true);
        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
        right.Children.Add(refresh);
        right.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        right.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", ToggleMaximize));
        right.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", Close));
        var titlebar = new Grid { Height = TitlebarHeight, Children = { title, right } };
        Grid.SetColumnSpan(titlebar, 3);

        // ── Left column (x 16, 388 wide): search, tabs + sort, list ──
        _search = new TextBox { Style = Ui.Style("FieldBox"), Height = 34, VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(30, 0, 30, 0) };
        _search.TextChanged += (_, _) => RenderList();
        _search.PreviewKeyDown += OnSearchKeyDown;
        _searchPlaceholder = new TextBlock
        {
            FontSize = 13,
            Foreground = Ui.Brush("InspectText3Brush"),
            Margin = new Thickness(32, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
        };
        _clearSearch = new Button
        {
            Style = Ui.Style("InspectIconButton"),
            Content = Ui.Glyph(Ui.GlyphClose, 10, "InspectText3Brush"),
            ToolTip = L.T("Clear"),
            Width = 24,
            Height = 24,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 5, 0),
            Visibility = Visibility.Collapsed,
        };
        _clearSearch.Click += (_, _) => { _search.Clear(); _search.Focus(); };
        var searchIcon = Ui.Glyph(Ui.GlyphSearch, 12, "InspectText3Brush");
        searchIcon.HorizontalAlignment = HorizontalAlignment.Left;
        searchIcon.VerticalAlignment = VerticalAlignment.Center;
        searchIcon.Margin = new Thickness(11, 0, 0, 0);
        searchIcon.IsHitTestVisible = false;
        var searchBox = new Grid { Height = 34, Margin = new Thickness(0, 16, 0, 0), VerticalAlignment = VerticalAlignment.Top, Children = { _search, searchIcon, _searchPlaceholder, _clearSearch } };

        _sortButton = new Button
        {
            Style = Ui.Style("InspectIconButton"),
            Content = Ui.Glyph(((char)0xE8CB).ToString(), 12, "InspectText2Brush"),
            ToolTip = L.T("Sort by name"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _sortButton.Click += (_, _) =>
        {
            _sortByName = !_sortByName;
            RenderList();
        };
        var tabRow = new Grid { Height = 28, Margin = new Thickness(0, 16, 0, 6), Children = { _tabs, _sortButton } };

        _listScroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _list,
            Focusable = false,
        };
        _emptyTitle = new TextBlock { FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap };
        _emptyHint = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) };
        _empty = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(24, 0, 24, 60), Visibility = Visibility.Collapsed, Children = { _emptyTitle, _emptyHint } };
        _loadingLabel = new TextBlock
        {
            Text = L.T("Loading…"),
            FontSize = 12,
            Foreground = Ui.Brush("InspectText3Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = Visibility.Collapsed,
        };
        var listHost = new Grid { Children = { _listScroll, _empty, _loadingLabel } };

        var left = new Grid { Margin = new Thickness(16, 0, 16, 0) };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition());
        Grid.SetRow(tabRow, 1);
        Grid.SetRow(listHost, 2);
        left.Children.Add(searchBox);
        left.Children.Add(tabRow);
        left.Children.Add(listHost);
        Grid.SetRow(left, 1);

        var divider = new Border { Width = 1, Background = Ui.Brush("InspectLineBrush") };
        Grid.SetRow(divider, 1);
        Grid.SetColumn(divider, 1);

        // ── Detail column (insets 71 / 40 / 72) ──
        _detail.Margin = new Thickness(71, 40, 72, 40);
        _detailScroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _detail,
            Focusable = false,
        };
        Grid.SetRow(_detailScroll, 1);
        Grid.SetColumn(_detailScroll, 2);

        _root = new Grid();
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TitlebarHeight) });
        _root.RowDefinitions.Add(new RowDefinition());
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(420) });
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        _root.ColumnDefinitions.Add(new ColumnDefinition());
        foreach (var child in new UIElement[] { left, divider, _detailScroll, titlebar }) _root.Children.Add(child);
        var frame = new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(1, 0, 1, 1), Child = _root };
        Content = frame;

        StateChanged += (_, _) =>
        {
            _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
            _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
        };
        _services.WidgetsChanged += (_, _) => Render();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control)
            {
                _search.Focus();
                _search.SelectAll();
                e.Handled = true;
            }
            else if (e.Key == Key.W && Keyboard.Modifiers == ModifierKeys.Control)
            {
                Close();
                e.Handled = true;
            }
        };
        Render();
    }

    // ───────────────────────────── Public API ─────────────────────────────

    /// <summary>Shows (or brings forward) the Market beside <paramref name="owner"/>; refreshes the catalog.</summary>
    public void ShowFor(Window? owner)
    {
        var wasVisible = IsVisible;
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        if (!wasVisible)
        {
            Place(owner);
            Show();
            Place(owner);
        }
        Activate();
        _ = LoadCatalogAsync(silent: _loaded);
    }

    /// <summary>App exit: really close (otherwise closing only hides).</summary>
    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel || _quitting) return;
        e.Cancel = true;
        Hide();
        WindowState = WindowState.Normal;
    }

    // ───────────────────────────── Placement ─────────────────────────────

    /// <summary>Just right of the owner (2 pt gap, top-aligned) when it fits there, else centred on the cursor's monitor.</summary>
    private void Place(Window? owner)
    {
        if (WindowState != WindowState.Normal) return;
        var ownerHwnd = owner is { IsVisible: true, WindowState: WindowState.Normal } ? new WindowInteropHelper(owner).Handle : IntPtr.Zero;
        var monitor = ownerHwnd != IntPtr.Zero ? ScreenGeometry.MonitorOf(ownerHwnd) : ScreenGeometry.MonitorAtCursor();
        var work = monitor.WorkArea;
        var scale = monitor.Scale;
        var w = (int)Math.Round(Math.Max(MinWidth, Math.Min(DesignSize.Width, work.Width / scale * 0.96)) * scale);
        var h = (int)Math.Round(Math.Max(MinHeight, Math.Min(DesignSize.Height, work.Height / scale * 0.96)) * scale);
        if (ownerHwnd != IntPtr.Zero)
        {
            var from = ScreenGeometry.WindowRect(ownerHwnd);
            var gap = (int)Math.Round(2 * scale);
            var beside = new PixelRect(from.Right + gap, from.Y, w, h);
            if (beside.Right <= work.Right && beside.Bottom <= work.Bottom && beside.Y >= work.Y)
            {
                ScreenManager.Place(this, beside);
                return;
            }
        }
        ScreenManager.Place(this, ScreenManager.CenterFrame(new Size(w / scale, h / scale), monitor));
    }

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    // ───────────────────────────── Data ─────────────────────────────

    private async Task LoadCatalogAsync(bool silent)
    {
        if (_loading) return;
        _loading = true;
        if (!silent) Render();
        try
        {
            var catalog = await _services.Market.FetchCatalogAsync();
            _catalog = catalog.Widgets.ToList();
            _loaded = true;
            _loadError = null;
            Log.Info($"WidgetMarket: {_catalog.Count} Widget(s) in the catalog");
        }
        catch (ApiException ex)
        {
            Log.Warning($"WidgetMarket: catalog unavailable: {ex.Message}");
            if (!silent || _catalog.Count == 0) _loadError = L.T(ex.Message);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            Log.Warning($"WidgetMarket: catalog unavailable: {ex.Message}");
            if (!silent || _catalog.Count == 0) _loadError = L.T(WidgetMarketClient.UnavailableMessage);
        }
        finally
        {
            _loading = false;
        }
        Render();
    }

    /// <summary>Catalog order, then installed Widgets the catalog doesn't list (offline / delisted).</summary>
    private List<Entry> Entries()
    {
        var installed = _services.Registry.Installed.ToDictionary(w => w.Id);
        var entries = new List<Entry>();
        var seen = new HashSet<string>();
        foreach (var widget in _catalog)
        {
            if (!seen.Add(widget.Id)) continue;
            entries.Add(new Entry(widget.Id, widget, installed.GetValueOrDefault(widget.Id)));
        }
        foreach (var widget in installed.Values)
            if (seen.Add(widget.Id)) entries.Add(new Entry(widget.Id, null, widget));
        return entries;
    }

    private IEnumerable<Entry> InTab(IEnumerable<Entry> entries, Tab tab) => tab switch
    {
        Tab.Installed => entries.Where(e => e.IsInstalled),
        Tab.Updates => entries.Where(e => e.HasUpdate),
        _ => entries,
    };

    private List<Entry> Visible(List<Entry> all)
    {
        var query = _search.Text.Trim();
        var list = InTab(all, _tab);
        if (query.Length > 0) list = list.Where(e => e.Display.SearchableText.Contains(query, StringComparison.CurrentCultureIgnoreCase));
        if (_sortByName) list = list.OrderBy(e => e.Display.DisplayName(_services.Language), StringComparer.CurrentCultureIgnoreCase);
        return list.ToList();
    }

    // ───────────────────────────── Rendering ─────────────────────────────

    private void Render()
    {
        RenderList();
    }

    private void RenderList()
    {
        var all = Entries();
        RenderTabs(all);
        var visible = Visible(all);
        _searchPlaceholder.Text = _loading && _catalog.Count == 0 ? L.T("Search widgets") : L.F("Search %d widgets", all.Count);
        _searchPlaceholder.Visibility = _search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        _clearSearch.Visibility = _search.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        SetActive(_sortButton, _sortByName);

        if (_selectedId is null || visible.All(e => e.Id != _selectedId))
            _selectedId = visible.FirstOrDefault()?.Id ?? (_selectedId is not null && all.Any(e => e.Id == _selectedId) ? _selectedId : null);

        _list.Children.Clear();
        foreach (var entry in visible) _list.Children.Add(Row(entry));

        var showLoading = _loading && visible.Count == 0;
        _loadingLabel.Visibility = showLoading ? Visibility.Visible : Visibility.Collapsed;
        _empty.Visibility = !showLoading && visible.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (visible.Count == 0)
        {
            if (_loadError is not null && all.Count == 0)
            {
                _emptyTitle.Text = L.T("Could not load widgets");
                _emptyHint.Text = _loadError + "\n" + L.T("Refresh to load the catalog.");
            }
            else if (_search.Text.Trim().Length > 0)
            {
                _emptyTitle.Text = L.T("No matching widgets");
                _emptyHint.Text = L.T("Try a different search, or clear it to see every widget.");
            }
            else
            {
                _emptyTitle.Text = L.T("No widgets available");
                _emptyHint.Text = L.T("Refresh to load the catalog.");
            }
        }
        RenderDetail(all.FirstOrDefault(e => e.Id == _selectedId));
    }

    private void RenderTabs(List<Entry> all)
    {
        _tabs.Children.Clear();
        foreach (var (tab, title) in new[] { (Tab.Marketplace, "Marketplace"), (Tab.Installed, "Installed"), (Tab.Updates, "Updates") })
        {
            var selected = tab == _tab;
            var label = new TextBlock { Text = L.T(title), FontSize = 12, FontWeight = selected ? FontWeights.Medium : FontWeights.Normal, Foreground = Ui.Brush(selected ? "InspectText1Brush" : "InspectText2Brush"), VerticalAlignment = VerticalAlignment.Center };
            var count = new TextBlock { Text = InTab(all, tab).Count().ToString(System.Globalization.CultureInfo.InvariantCulture), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            var content = new StackPanel { Orientation = Orientation.Horizontal, Children = { label, count } };
            var underline = new Border { Height = 1, Background = Ui.Brush(selected ? "InspectText1Brush" : "InspectInk0Brush"), VerticalAlignment = VerticalAlignment.Bottom, Opacity = selected ? 1 : 0 };
            var body = new Grid { Height = 28, Children = { content, underline } };
            var button = new Button { Style = Ui.Style("InspectTextButton"), Content = body, Margin = new Thickness(0, 0, 18, 0), Padding = new Thickness(0) };
            button.Click += (_, _) =>
            {
                _tab = tab;
                _selectedId = null;
                RenderList();
            };
            _tabs.Children.Add(button);
        }
    }

    /// <summary>Figma <c>widget row</c>: 36 pt icon tile, name / summary, price + status or the hover Install / Update button.</summary>
    private FrameworkElement Row(Entry entry)
    {
        var widget = entry.Display;
        var language = _services.Language;
        var selected = entry.Id == _selectedId;

        var grid = new Grid { Height = RowHeight, Margin = new Thickness(8, 0, 8, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var tile = IconTile(widget, 36);
        tile.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(tile);

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = widget.DisplayName(language), FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextTrimming = TextTrimming.CharacterEllipsis });
        text.Children.Add(new TextBlock { Text = widget.DisplaySummary(language), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 2, 0, 0) });
        Grid.SetColumn(text, 2);
        grid.Children.Add(text);

        var status = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
        status.Children.Add(new TextBlock { Text = WidgetText.PriceTag(widget), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText2Brush"), HorizontalAlignment = HorizontalAlignment.Right });
        if (entry.HasUpdate || entry.IsInstalled)
            status.Children.Add(new TextBlock
            {
                Text = L.T(entry.HasUpdate ? "Update" : "Installed"),
                FontSize = 11,
                Foreground = Ui.Brush(entry.HasUpdate ? "InfoBrush" : "SuccessBrush"),
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(0, 2, 0, 0),
            });
        Grid.SetColumn(status, 3);
        grid.Children.Add(status);

        Button? hoverAction = null;
        if (entry.CanInstall)
        {
            var busy = _installing.Contains(entry.Id);
            hoverAction = new Button
            {
                Style = Ui.Style("InspectQuietButton"),
                Content = busy ? L.T("Installing…") : L.T(entry.HasUpdate ? "Update" : "Install"),
                Height = 26,
                Padding = new Thickness(10, 0, 10, 0),
                FontSize = 12,
                IsEnabled = !busy,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(12, 0, 0, 0),
                Visibility = Visibility.Collapsed,
            };
            hoverAction.Click += (_, e) =>
            {
                e.Handled = true;
                _ = InstallAsync(entry.Id);
            };
            Grid.SetColumn(hoverAction, 3);
            grid.Children.Add(hoverAction);
        }

        var row = new Border
        {
            Background = selected ? Ui.Brush("InspectInk2Brush") : Brushes.Transparent,
            CornerRadius = Ui.Corner("CornerControl"),
            Child = grid,
            Cursor = Cursors.Hand,
            ToolTip = widget.DisplayName(language),
        };
        row.MouseEnter += (_, _) =>
        {
            if (!selected) row.Background = Ui.Brush("InspectHoverBrush");
            if (hoverAction is not null)
            {
                hoverAction.Visibility = Visibility.Visible;
                status.Visibility = Visibility.Hidden;
            }
        };
        row.MouseLeave += (_, _) =>
        {
            if (!selected) row.Background = Brushes.Transparent;
            if (hoverAction is not null)
            {
                hoverAction.Visibility = Visibility.Collapsed;
                status.Visibility = Visibility.Visible;
            }
        };
        row.MouseLeftButtonUp += (_, _) =>
        {
            if (_selectedId == entry.Id) return;
            _selectedId = entry.Id;
            RenderList();
            _detailScroll.ScrollToTop();
        };
        return row;
    }

    /// <summary>Figma <c>detail</c>: eyebrow, title with actions, meta line, description and the spec rows.</summary>
    private void RenderDetail(Entry? entry)
    {
        _detail.Children.Clear();
        if (entry is null)
        {
            _detail.Children.Add(new TextBlock { Text = L.T("Select a Widget to see its details."), FontSize = 13, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 40, 0, 0) });
            return;
        }
        var widget = entry.Display;
        var language = _services.Language;
        var inputs = WidgetText.Kinds(widget.Commands.SelectMany(c => c.InputTypes).Where(k => k.Length > 0));
        var outputs = WidgetText.Kinds(widget.Commands.SelectMany(c => c.Outputs).Where(k => k.Length > 0));

        _detail.Children.Add(new TextBlock
        {
            Text = $"{L.T("Widget")}  ·  {inputs} → {outputs}".ToUpper(System.Globalization.CultureInfo.CurrentCulture),
            FontFamily = Ui.CodeFont,
            FontSize = 11,
            Foreground = Ui.Brush("InspectText3Brush"),
        });

        // Title row: title left, actions right (Remove, Install / Update, Run).
        var titleRow = new Grid { Margin = new Thickness(0, 12, 0, 0) };
        titleRow.ColumnDefinitions.Add(new ColumnDefinition());
        titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var titleLine = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var icon = IconTile(widget, 40);
        icon.Margin = new Thickness(0, 0, 14, 0);
        titleLine.Children.Add(icon);
        titleLine.Children.Add(new TextBlock { Text = widget.DisplayName(language), FontSize = 30, Foreground = Ui.Brush("InspectText1Brush"), TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
        titleRow.Children.Add(titleLine);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 0, 0) };
        var busy = _installing.Contains(entry.Id);
        if (entry.IsInstalled)
            actions.Children.Add(ActionButton(L.T("Remove"), "InspectQuietButton", !busy, () =>
            {
                _actionErrors.Remove(entry.Id);
                _services.Registry.Uninstall(entry.Id);
            }));
        if (entry.CanInstall)
            actions.Children.Add(ActionButton(busy ? L.T("Installing…") : L.T(entry.HasUpdate ? "Update" : "Install"), "InspectPrimaryButton", !busy, () => _ = InstallAsync(entry.Id)));
        if (entry.Installed is { } installed && _services.Registry.IsAvailable(entry.Id) && installed.Commands.FirstOrDefault(c => c.IsTextOnly) is { } textCommand)
            actions.Children.Add(ActionButton(L.T("Run"), entry.CanInstall ? "InspectQuietButton" : "InspectPrimaryButton", !busy, () => _host.RunText(installed, textCommand, this)));
        Grid.SetColumn(actions, 1);
        titleRow.Children.Add(actions);
        _detail.Children.Add(titleRow);

        // Meta line: author · v<version> · ✓ Installed / Not installed.
        var meta = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        void MetaText(string value, string brush = "InspectText3Brush") =>
            meta.Children.Add(new TextBlock { Text = value, FontSize = 12, Foreground = Ui.Brush(brush), VerticalAlignment = VerticalAlignment.Center });
        if (widget.Author.Length > 0)
        {
            MetaText(widget.Author);
            MetaText("  ·  ");
        }
        MetaText($"v{widget.Version}");
        MetaText("  ·  ");
        if (entry.IsInstalled)
        {
            var check = Ui.Glyph(((char)0xE73E).ToString(), 10, "SuccessBrush");
            check.Margin = new Thickness(0, 0, 4, 0);
            check.VerticalAlignment = VerticalAlignment.Center;
            meta.Children.Add(check);
            MetaText(L.T("Installed"), "SuccessBrush");
        }
        else
        {
            MetaText(L.T("Not installed"));
        }
        if (entry.Catalog is null) MetaText("  ·  " + L.T("No longer listed"), "InspectText3Brush");
        _detail.Children.Add(meta);

        if (_actionErrors.TryGetValue(entry.Id, out var error))
            _detail.Children.Add(new TextBlock { Text = error, FontSize = 12, Foreground = Ui.Brush("FailureBrush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0), MaxWidth = 700, HorizontalAlignment = HorizontalAlignment.Left });

        var description = new TextBlock
        {
            Text = widget.DisplaySummary(language),
            FontSize = 14,
            Foreground = Ui.Brush("InspectText2Brush"),
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 700,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 24, 0, 28),
        };
        TextBlock.SetLineHeight(description, 23);
        _detail.Children.Add(description);
        if (DemoView(widget) is { } demo) _detail.Children.Add(demo);

        _detail.Children.Add(SpecRow(L.T("Input"), Plain(inputs.Length > 0 ? inputs : "—")));
        _detail.Children.Add(SpecRow(L.T("Output"), Plain(outputs.Length > 0 ? outputs : "—")));
        _detail.Children.Add(SpecRow(L.T("Cost per task"), Plain(WidgetText.CostText(widget))));
        var commands = new StackPanel();
        foreach (var command in widget.Commands)
        {
            commands.Children.Add(new TextBlock { Text = widget.CommandName(command, language), FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, commands.Children.Count == 0 ? 0 : 10, 0, 0) });
            var commandDescription = widget.CommandDescription(command, language);
            if (commandDescription.Length > 0)
                commands.Children.Add(new TextBlock { Text = commandDescription, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) });
        }
        _detail.Children.Add(SpecRow(L.T("Commands"), commands));
        _detail.Children.Add(SpecRow(L.T("Privacy"), Plain(widget.PrivacyNotice.Length > 0 ? widget.PrivacyNotice : "—")));
    }

    /// <summary>
    /// Bundled walkthrough (macOS 4a19a60): <c>WidgetDemos\&lt;id&gt;-&lt;lang&gt;.gif</c>, then <c>&lt;id&gt;.gif</c>,
    /// then the MP4 for the language; 3:2, at most 700 wide. GIFs animate, MP4s loop muted.
    /// </summary>
    private FrameworkElement? DemoView(WidgetManifest widget)
    {
        if (!Guid.TryParse(widget.Id, out _)) return null;
        var folder = Path.Combine(AppContext.BaseDirectory, "WidgetDemos");
        var id = widget.Id.ToLowerInvariant();
        var tags = _services.Language == "en" ? new[] { "en" } : new[] { _services.Language, _services.Language.Split('-')[0], "en" };
        var gif = tags.Select(t => Path.Combine(folder, $"{id}-{t}.gif")).Append(Path.Combine(folder, $"{id}.gif")).FirstOrDefault(File.Exists);
        var mp4 = gif is null ? tags.Select(t => Path.Combine(folder, $"{id}-{t}.mp4")).FirstOrDefault(File.Exists) : null;
        if (gif is null && mp4 is null) return null;
        var frame = new Border
        {
            MaxWidth = 700,
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = Ui.Brush("InspectInk2Brush"),
            CornerRadius = Ui.Corner("CornerControl"),
            Margin = new Thickness(0, 0, 0, 28),
            ClipToBounds = true,
        };
        frame.SizeChanged += (_, e) =>
        {
            if (e.WidthChanged) frame.Height = Math.Round(frame.ActualWidth * 2 / 3);
        };
        void Fit() => frame.Width = Math.Max(120, Math.Min(700, _detail.ActualWidth > 0 ? _detail.ActualWidth : 700));
        Fit();
        _detail.SizeChanged += (_, _) => Fit();
        if (gif is not null)
        {
            var image = new Image { Stretch = Stretch.Uniform };
            frame.Child = image;
            var info = new Glance.Core.Detection.MediaInfo(gif, true, Glance.Core.Detection.MediaKind.Image);
            _ = LoadDemoGifAsync(info, image);
        }
        else
        {
            var player = new MediaElement { Source = new Uri(mp4!), LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Close, IsMuted = true, Stretch = Stretch.Uniform };
            player.MediaEnded += (_, _) =>
            {
                player.Position = TimeSpan.Zero;
                player.Play();
            };
            player.Loaded += (_, _) => player.Play();
            frame.Child = player;
        }
        System.Windows.Automation.AutomationProperties.SetName(frame, widget.DisplayName(_services.Language));
        return frame;
    }

    private static async Task LoadDemoGifAsync(Glance.Core.Detection.MediaInfo info, Image target)
    {
        var animation = await Glance.App.Media.GifAnimation.LoadAsync(info, 1400, CancellationToken.None);
        if (animation is null) return;
        target.Source = animation.Frames[0];
        target.BeginAnimation(Image.SourceProperty, animation.ToAnimation());
    }

    // ───────────────────────────── Actions ─────────────────────────────

    private async Task InstallAsync(string id)
    {
        if (!_installing.Add(id)) return;
        _actionErrors.Remove(id);
        RenderList();
        try
        {
            await _services.Market.InstallAsync(id);
        }
        catch (ApiException ex)
        {
            Log.Warning($"WidgetMarketPanel: install failed: {ex.Message}");
            _actionErrors[id] = L.T(ex.Message) + " " + L.T("Check your connection and try again.");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            Log.Warning($"WidgetMarketPanel: install failed: {ex.Message}");
            _actionErrors[id] = L.T(WidgetMarketClient.UnavailableMessage) + " " + L.T("Check your connection and try again.");
        }
        finally
        {
            _installing.Remove(id);
        }
        RenderList();
    }

    private void OnSearchKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        e.Handled = true;
        if (_search.Text.Length > 0) _search.Clear();
        else _listScroll.Focus();
    }

    // ───────────────────────────── Icons ─────────────────────────────

    /// <summary>Monogram tile, replaced by the Widget's https icon (aspect-fill) once it loads.</summary>
    private FrameworkElement IconTile(WidgetManifest widget, double size)
    {
        var tile = new Border
        {
            Width = size,
            Height = size,
            CornerRadius = Ui.Corner("CornerControl"),
            Background = Ui.Brush("InspectInk3Brush"),
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            ClipToBounds = true,
        };
        if (widget.IconUrl is { } url && _icons.TryGetValue(url, out var image))
        {
            tile.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill };
            return tile;
        }
        tile.Child = new TextBlock
        {
            Text = Monogram(widget),
            FontSize = size * 0.36,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.Brush("InspectText2Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (widget.IconUrl is { } iconUrl) _ = LoadIconAsync(iconUrl);
        return tile;
    }

    /// <summary>Two letters from the English name, else the first character of the display name.</summary>
    private string Monogram(WidgetManifest widget)
    {
        var english = widget.DisplayName("en");
        var words = english.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries).Where(w => char.IsAsciiLetterOrDigit(w[0])).ToList();
        if (words.Count >= 2) return $"{char.ToUpperInvariant(words[0][0])}{char.ToUpperInvariant(words[1][0])}";
        if (words.Count == 1 && words[0].Length >= 2 && char.IsAsciiLetter(words[0][1])) return $"{char.ToUpperInvariant(words[0][0])}{char.ToLowerInvariant(words[0][1])}";
        var name = widget.DisplayName(_services.Language);
        return name.Length > 0 ? char.ToUpper(name[0], System.Globalization.CultureInfo.CurrentCulture).ToString() : "?";
    }

    private async Task LoadIconAsync(string url)
    {
        if (!_loadingIcons.Add(url)) return;
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var bytes = await _services.Http.GetByteArrayAsync(url, timeout.Token);
            var image = await Task.Run(() =>
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.DecodePixelWidth = 96;
                bitmap.StreamSource = new MemoryStream(bytes);
                bitmap.EndInit();
                bitmap.Freeze();
                return (ImageSource)bitmap;
            });
            _icons[url] = image;
            RenderList();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or NotSupportedException or IOException or InvalidOperationException or ArgumentException or System.Runtime.InteropServices.COMException)
        {
            // Keep the monogram; don't retry this session.
            Log.Info($"WidgetMarket: icon '{Log.Redact(url)}' unavailable: {ex.GetType().Name}");
        }
    }

    // ───────────────────────────── Builders ─────────────────────────────

    /// <summary>Spec row: 120 pt label column, the value at +132, a hairline beneath.</summary>
    private static FrameworkElement SpecRow(string label, FrameworkElement value)
    {
        var grid = new Grid { Margin = new Thickness(0, 12, 0, 12), MaxWidth = 832, HorizontalAlignment = HorizontalAlignment.Left };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(132) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.Children.Add(new TextBlock { Text = label, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), Width = 120, HorizontalAlignment = HorizontalAlignment.Left, TextWrapping = TextWrapping.Wrap });
        Grid.SetColumn(value, 1);
        grid.Children.Add(value);
        return new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = grid,
        };
    }

    private static TextBlock Plain(string text) => new()
    {
        Text = text,
        FontSize = 13,
        Foreground = Ui.Brush("InspectText1Brush"),
        TextWrapping = TextWrapping.Wrap,
    };

    private static Button ActionButton(string title, string style, bool enabled, Action onClick)
    {
        var button = new Button { Style = Ui.Style(style), Content = title, Height = 32, Padding = new Thickness(14, 0, 14, 0), Margin = new Thickness(8, 0, 0, 0), IsEnabled = enabled };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static void SetActive(Button button, bool active)
    {
        button.Background = active ? Ui.Brush("InspectInk4Brush") : Brushes.Transparent;
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
