using System.Net.Http;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Account;
using Glance.App.Inspect;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Account;
using Glance.Core.Logging;
using Glance.Core.Tasks;
using Glance.Platform;

namespace Glance.App.Widgets;

/// <summary>
/// Task Center (port of macOS <c>WidgetTaskCenterWindow</c>, Figma Shizuka "04 · Task Center",
/// "13 · Task Center / Failed", "47 · Empty states"): the history and live state of cloud Widget
/// tasks. A list column (filters, search, rows) and a detail pane with the credit / refund status,
/// the failure reason and the actions (cancel, open, copy URL, reveal, retry, remove).
/// </summary>
internal sealed class TaskCenterWindow : Window
{
    private enum Filter { All, Running, Done, Failed }

    private const double TitlebarHeight = 44;
    private const double ResizeBorder = 5;
    private const double ListWidth = 360;
    private static readonly Size DesignSize = new(1554, 1012);
    private const string IconRefresh = "M21,12 A9,9 0 1 1 18.36,5.64 M21,4 V10 H15";
    private const string IconTrash = "M3,6 H21 M8,6 V4 H16 V6 M6,6 L7,20 H17 L18,6 M10,10 V16 M14,10 V16";

    private readonly AccountServices _services;
    private readonly IWidgetHost _host;
    private readonly Grid _root;
    private readonly Button[] _tabs = new Button[4];
    private readonly TextBox _search;
    private readonly TextBlock _searchPlaceholder;
    private readonly TextBlock _countLine;
    private readonly StackPanel _rows = new();
    private readonly StackPanel _listEmpty;
    private readonly TextBlock _listEmptyTitle;
    private readonly TextBlock _listEmptyHint;
    private readonly ScrollViewer _detailScroll;
    private readonly StackPanel _detail = new() { Margin = new Thickness(56, 40, 56, 40), MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };
    private readonly TextBlock _detailEmpty;
    private readonly Grid _confirm;
    private readonly InspectToast _toast = new();
    private readonly TextBlock _maximizeGlyph;
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly Dictionary<string, ImageSource?> _thumbs = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _loadingThumbs = new(StringComparer.OrdinalIgnoreCase);

    private Filter _filter = Filter.All;
    private Guid? _selected;
    private bool _quitting;

    public TaskCenterWindow(AccountServices services, IWidgetHost host)
    {
        _services = services;
        _host = host;
        Title = L.T("Tasks");
        Width = 1200;
        Height = 780;
        MinWidth = 900;
        MinHeight = 586;
        Background = Ui.Brush("InspectInk0Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = TitlebarHeight - ResizeBorder,
            ResizeBorderThickness = new Thickness(ResizeBorder),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Titlebar: "Tasks" centred, window buttons right ──
        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var captions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized));
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", Close));
        var title = new TextBlock { Text = L.T("Tasks"), FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var titlebar = new Grid { Height = TitlebarHeight, Children = { title, captions } };
        Grid.SetColumnSpan(titlebar, 3);

        // ── List column ──
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 12, 16, 0) };
        string[] tabTitles = ["All", "Running", "Done", "Failed"];
        for (var i = 0; i < 4; i++)
        {
            var filter = (Filter)i;
            var tab = new Button { Style = Ui.Style("InspectTextButton"), Margin = new Thickness(i == 0 ? 0 : 14, 0, 0, 0), Tag = tabTitles[i] };
            tab.Click += (_, _) =>
            {
                _filter = filter;
                Render();
            };
            _tabs[i] = tab;
            tabs.Children.Add(tab);
        }

        _search = new TextBox { Style = Ui.Style("FieldBox"), Height = 32, VerticalContentAlignment = VerticalAlignment.Center };
        _search.TextChanged += (_, _) =>
        {
            _searchPlaceholder!.Visibility = _search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            Render();
        };
        _search.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape && _search.Text.Length > 0)
            {
                _search.Text = "";
                e.Handled = true;
            }
        };
        _searchPlaceholder = new TextBlock { Text = L.T("Search tasks"), FontSize = 13, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(11, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
        var searchBox = new Grid { Children = { _search, _searchPlaceholder } };
        var refresh = IconButton(IconRefresh, L.T("Refresh"), () =>
        {
            _services.Tasks.ReconcileAll();
            _thumbs.Clear();
            Render();
        });
        var clear = IconButton(IconTrash, L.T("Clear Finished"), ShowClearConfirmation);
        var searchRow = new DockPanel { Margin = new Thickness(16, 12, 16, 0), LastChildFill = true };
        clear.Margin = new Thickness(4, 0, 0, 0);
        refresh.Margin = new Thickness(8, 0, 0, 0);
        DockPanel.SetDock(clear, Dock.Right);
        DockPanel.SetDock(refresh, Dock.Right);
        searchRow.Children.Add(clear);
        searchRow.Children.Add(refresh);
        searchRow.Children.Add(searchBox);

        _countLine = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(16, 12, 16, 8) };
        var listScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = _rows, Padding = new Thickness(8, 0, 8, 8) };
        _listEmptyTitle = new TextBlock { FontSize = 14, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center };
        _listEmptyHint = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        _listEmpty = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(32), Children = { _listEmptyTitle, _listEmptyHint }, Visibility = Visibility.Collapsed };
        var listBody = new Grid { Children = { listScroll, _listEmpty } };
        var listColumn = new DockPanel { Background = Ui.Brush("InspectInk1Brush") };
        foreach (var top in new FrameworkElement[] { tabs, searchRow, _countLine })
        {
            DockPanel.SetDock(top, Dock.Top);
            listColumn.Children.Add(top);
        }
        listColumn.Children.Add(listBody);
        Grid.SetRow(listColumn, 1);

        var divider = new Border { Width = 1, Background = Ui.Brush("InspectLineBrush") };
        Grid.SetRow(divider, 1);
        Grid.SetColumn(divider, 1);

        // ── Detail pane ──
        _detailScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = _detail };
        _detailEmpty = new TextBlock { Text = L.T("Select a task"), FontSize = 14, Foreground = Ui.Brush("InspectText3Brush"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var detailPane = new Grid { Children = { _detailScroll, _detailEmpty } };
        Grid.SetRow(detailPane, 1);
        Grid.SetColumn(detailPane, 2);

        // ── Overlays: clear confirmation, toast ──
        _confirm = BuildConfirmation();
        foreach (var overlay in new FrameworkElement[] { _confirm, _toast })
        {
            Grid.SetRowSpan(overlay, 2);
            Grid.SetColumnSpan(overlay, 3);
        }
        _toast.Margin = new Thickness(0, 0, 0, 28);

        _root = new Grid();
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TitlebarHeight) });
        _root.RowDefinitions.Add(new RowDefinition());
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ListWidth) });
        _root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _root.ColumnDefinitions.Add(new ColumnDefinition());
        foreach (var child in new UIElement[] { listColumn, divider, detailPane, titlebar, _confirm, _toast })
            _root.Children.Add(child);
        Content = _root;

        _services.Tasks.Changed += (_, _) => { if (IsVisible) Render(); };
        _clock.Tick += (_, _) => Render();
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible) _clock.Start();
            else _clock.Stop();
        };
        StateChanged += (_, _) =>
        {
            _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
            _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape || e.Handled) return;
            if (_search.IsKeyboardFocused && _search.Text.Length > 0)
            {
                _search.Text = "";
                e.Handled = true;
                return;
            }
            if (_confirm.Visibility == Visibility.Visible) _confirm.Visibility = Visibility.Collapsed;
            else Close();
            e.Handled = true;
        };
    }

    // ───────────────────────────── Public API ─────────────────────────────

    /// <summary>Shows (or brings forward) the Task Center and selects <paramref name="id"/> when given.</summary>
    public void ShowTask(Guid? id = null)
    {
        if (id is not null) _selected = id;
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        if (!IsVisible)
        {
            PlaceDesignFrame();
            Show();
            PlaceDesignFrame();
        }
        Activate();
        Render();
    }

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
        _confirm.Visibility = Visibility.Collapsed;
        Hide();
    }

    // ───────────────────────────── Rendering ─────────────────────────────

    private void Render()
    {
        var all = _services.Tasks.Records;
        int Count(Filter f) => all.Count(r => Matches(r, f));
        string[] titles = ["All", "Running", "Done", "Failed"];
        for (var i = 0; i < 4; i++)
        {
            var active = (int)_filter == i;
            _tabs[i].Content = TabContent(L.T(titles[i]), Count((Filter)i), active);
            _tabs[i].BorderBrush = active ? Ui.Brush("InspectText1Brush") : Brushes.Transparent;
            _tabs[i].BorderThickness = new Thickness(0, 0, 0, active ? 1 : 0);
        }

        var query = _search.Text.Trim();
        var shown = all.Where(r => Matches(r, _filter) && (query.Length == 0 || SearchText(r).Contains(query, StringComparison.CurrentCultureIgnoreCase))).ToList();
        _countLine.Text = L.F("%d tasks  •  %d running", all.Count, all.Count(r => r.IsActive));

        _rows.Children.Clear();
        foreach (var record in shown) _rows.Children.Add(Row(record));
        if (shown.Count == 0)
        {
            var filtered = all.Count > 0;
            _listEmptyTitle.Text = L.T(filtered ? "No matching tasks" : "No tasks yet");
            _listEmptyHint.Text = L.T(filtered ? "Try a different search or filter." : "Run a Widget on an image and it will show up here.");
            _listEmpty.Visibility = Visibility.Visible;
        }
        else
        {
            _listEmpty.Visibility = Visibility.Collapsed;
        }

        var selected = _selected is { } id ? all.FirstOrDefault(r => r.Id == id) : null;
        if (selected is null && _selected is not null) _selected = null;
        RenderDetail(selected);
    }

    private static bool Matches(WidgetTaskRecord r, Filter filter) => filter switch
    {
        Filter.Running => r.IsActive,
        Filter.Done => r.Phase == WidgetTaskPhase.Completed,
        Filter.Failed => r.IsFailure,
        _ => true,
    };

    private static string SearchText(WidgetTaskRecord r) => $"{r.WidgetName} {r.CommandName} {InputSummary(r)}";

    private static string? InputSummary(WidgetTaskRecord r)
    {
        if (r.Input?.Prompt is { } prompt && !string.IsNullOrWhiteSpace(prompt))
        {
            var line = prompt.Trim().ReplaceLineEndings(" ");
            return line.Length > 60 ? line[..60] + "…" : line;
        }
        if (r.IsTextSource || r.SourceUrl.Length == 0) return null;
        return FileName(r.SourceUrl);
    }

    private static string FileName(string location)
    {
        if (Uri.TryCreate(location, UriKind.Absolute, out var uri) && !uri.IsFile)
        {
            var segment = Uri.UnescapeDataString(uri.Segments.LastOrDefault()?.Trim('/') ?? "");
            return segment.Length > 0 ? segment : uri.Host;
        }
        try
        {
            var name = Path.GetFileName(location.TrimEnd('\\', '/'));
            return name.Length > 0 ? name : location;
        }
        catch (ArgumentException)
        {
            return location;
        }
    }

    private static object TabContent(string title, int count, bool active)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 13, FontWeight = active ? FontWeights.Medium : FontWeights.Normal, Foreground = Ui.Brush(active ? "InspectText1Brush" : "InspectText2Brush") });
        panel.Children.Add(new TextBlock { Text = count.ToString(System.Globalization.CultureInfo.InvariantCulture), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(6, 1, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }

    /// <summary>A 56 pt row: thumbnail, command name, credits / input · date, state.</summary>
    private Border Row(WidgetTaskRecord r)
    {
        var selected = r.Id == _selected;
        var thumb = Thumbnail(r, 40);
        var title = new TextBlock { Text = r.CommandName, FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextTrimming = TextTrimming.CharacterEllipsis };
        var detailText = $"{WidgetText.BillingStatus(r) ?? InputSummary(r) ?? L.T("Media")} · {RelativeDate(r.UpdatedAt)}";
        var detail = new TextBlock { Text = detailText, FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 3, 0, 0) };
        var state = new TextBlock { Text = WidgetText.State(r), FontSize = 11, Foreground = Ui.Brush(WidgetText.StateBrush(r)), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0), MaxWidth = 120, TextTrimming = TextTrimming.CharacterEllipsis };
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0), Children = { title, detail } };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(text, 1);
        Grid.SetColumn(state, 2);
        grid.Children.Add(thumb);
        grid.Children.Add(text);
        grid.Children.Add(state);
        var row = new Border
        {
            Height = 56,
            Padding = new Thickness(8, 8, 10, 8),
            CornerRadius = Ui.Corner("CornerControl"),
            Background = selected ? Ui.Brush("InspectInk3Brush") : Brushes.Transparent,
            Child = grid,
            Cursor = Cursors.Hand,
            ToolTip = SearchText(r),
        };
        row.MouseEnter += (_, _) => { if (r.Id != _selected) row.Background = Ui.Brush("InspectHoverBrush"); };
        row.MouseLeave += (_, _) => { if (r.Id != _selected) row.Background = Brushes.Transparent; };
        row.MouseLeftButtonUp += (_, _) =>
        {
            _selected = r.Id;
            Render();
        };
        return row;
    }

    private static string RelativeDate(DateTimeOffset when)
    {
        var age = DateTimeOffset.UtcNow - when;
        if (age < TimeSpan.FromMinutes(1)) return L.T("Just now");
        if (age < TimeSpan.FromHours(1)) return L.F("%d min ago", (int)age.TotalMinutes);
        if (age < TimeSpan.FromDays(1)) return L.F("%d h ago", (int)age.TotalHours);
        return when.ToLocalTime().ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
    }

    // ───────────────────────────── Detail ─────────────────────────────

    private void RenderDetail(WidgetTaskRecord? r)
    {
        _detail.Children.Clear();
        _detailEmpty.Visibility = r is null ? Visibility.Visible : Visibility.Collapsed;
        _detailScroll.Visibility = r is null ? Visibility.Collapsed : Visibility.Visible;
        if (r is null) return;

        _detail.Children.Add(new TextBlock
        {
            Text = "TASK  " + r.Id.ToString("N")[..4].ToUpperInvariant(),
            FontFamily = Ui.CodeFont,
            FontSize = 11,
            Foreground = Ui.Brush("InspectText3Brush"),
        });
        _detail.Children.Add(new TextBlock
        {
            Text = r.CommandName,
            FontSize = 28,
            Foreground = Ui.Brush("InspectText1Brush"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 8, 0, 0),
        });

        var stateLine = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        stateLine.Children.Add(new Border { Width = 7, Height = 7, CornerRadius = new CornerRadius(3.5), Background = Ui.Brush(WidgetText.StateBrush(r)), VerticalAlignment = VerticalAlignment.Center });
        stateLine.Children.Add(new TextBlock { Text = WidgetText.State(r), FontSize = 13, Foreground = Ui.Brush(WidgetText.StateBrush(r)), Margin = new Thickness(8, 0, 0, 0) });
        stateLine.Children.Add(new TextBlock { Text = "  ·  " + r.WidgetName, FontSize = 13, Foreground = Ui.Brush("InspectText2Brush") });
        if (r.IsActive)
            stateLine.Children.Add(new TextBlock { Text = $"   {(int)Math.Round(Math.Clamp(r.Progress, 0, 100))}%", FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush("InspectText2Brush"), VerticalAlignment = VerticalAlignment.Center });
        _detail.Children.Add(stateLine);

        if (r.IsActive) _detail.Children.Add(ProgressBar(r.Progress));
        if (r.Phase == WidgetTaskPhase.Processing && r.QueueWaitSeconds is >= 120)
            _detail.Children.Add(Note(L.T("No worker has claimed this task yet. You can cancel; any deducted credits will be refunded."), "InspectText2Brush"));

        // Previews: source and result.
        var previews = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 24, 0, 0) };
        if (!r.IsTextSource && r.SourceUrl.Length > 0) previews.Children.Add(Preview(r.SourceUrl, L.F("Source · %@", FileName(r.SourceUrl))));
        if (r.OutputPath is { } output && File.Exists(output))
        {
            var preview = Preview(output, L.T("Result") + " · " + FileName(output));
            preview.Margin = new Thickness(previews.Children.Count > 0 ? 16 : 0, 0, 0, 0);
            previews.Children.Add(preview);
        }
        if (previews.Children.Count > 0) _detail.Children.Add(previews);

        // Outcome for stopped tasks: what happened, why, and the credits.
        if (r.IsFailure || r.Phase == WidgetTaskPhase.Cancelled)
        {
            var cancelled = r.Phase == WidgetTaskPhase.Cancelled;
            var stoppedAt = (int)Math.Round(Math.Clamp(r.Progress, 0, 100));
            var outcome = new StackPanel { Margin = new Thickness(0, 24, 0, 0) };
            outcome.Children.Add(InfoRow(L.T(cancelled ? "What happened" : "What failed"),
                L.F(cancelled ? "Task cancelled · Stopped at %d%%" : "Task failed · Stopped at %d%%", stoppedAt).Replace("%%", "%"),
                cancelled ? "InspectText1Brush" : "FailureBrush"));
            var reason = cancelled
                ? L.T(string.IsNullOrWhiteSpace(r.ErrorMessage) ? "You cancelled this task." : r.ErrorMessage)
                : L.T(string.IsNullOrWhiteSpace(r.ErrorMessage) ? "The task stopped without reporting a reason." : r.ErrorMessage);
            outcome.Children.Add(InfoRow(L.T("Reason"), reason));
            outcome.Children.Add(InfoRow(L.T("Credits"), WidgetText.BillingStatus(r) ?? "—", CreditsBrush(r)));
            _detail.Children.Add(outcome);
        }

        // Details.
        var rows = new StackPanel { Margin = new Thickness(0, 24, 0, 0) };
        rows.Children.Add(InfoRow(L.T("Widget"), r.WidgetName));
        rows.Children.Add(InfoRow(L.T("Input"), InputSummary(r) ?? "—"));
        if (!r.IsFailure && r.Phase != WidgetTaskPhase.Cancelled)
            rows.Children.Add(InfoRow(L.T("Credits"), WidgetText.BillingStatus(r) ?? "—", CreditsBrush(r)));
        if (r.IsActive)
        {
            rows.Children.Add(InfoRow(L.T("Progress"), $"{(int)Math.Round(Math.Clamp(r.Progress, 0, 100))}%"));
        }
        else
        {
            rows.Children.Add(InfoRow(L.T("Duration"), FormatDuration(r.UpdatedAt - r.CreatedAt)));
            if (r.OutputPath is { } path) rows.Children.Add(InfoRow(L.T("Result"), path));
        }
        _detail.Children.Add(rows);

        _detail.Children.Add(Actions(r));
    }

    private static string CreditsBrush(WidgetTaskRecord r) =>
        r.HasPendingSettlement ? "InfoBrush" : r.RefundedCredits is > 0 ? "SuccessBrush" : "InspectText1Brush";

    private static string FormatDuration(TimeSpan span)
    {
        if (span < TimeSpan.Zero) span = TimeSpan.Zero;
        if (span.TotalSeconds < 60) return L.F("%d s", (int)span.TotalSeconds);
        if (span.TotalMinutes < 60) return L.F("%d min %d s", (int)span.TotalMinutes, span.Seconds);
        return L.F("%d h %d min", (int)span.TotalHours, span.Minutes);
    }

    private static Grid ProgressBar(double progress)
    {
        var fraction = Math.Clamp(progress, 0, 100);
        var bar = new Grid { Height = 2, Margin = new Thickness(0, 14, 0, 0), Background = Ui.Brush("InspectLineBrush"), MaxWidth = 520, HorizontalAlignment = HorizontalAlignment.Stretch };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, fraction), GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, 100 - fraction), GridUnitType.Star) });
        bar.Children.Add(new Border { Background = Ui.Brush("InfoBrush") });
        return bar;
    }

    private static TextBlock Note(string text, string brush) => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = Ui.Brush(brush),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 12, 0, 0),
        MaxWidth = 560,
        HorizontalAlignment = HorizontalAlignment.Left,
    };

    /// <summary>Key (120 pt, 12 pt text/3) / value (13 pt) with a hairline below.</summary>
    private static Border InfoRow(string key, string value, string valueBrush = "InspectText1Brush")
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(132) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.Children.Add(new TextBlock { Text = key, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 1, 0, 0) });
        var valueText = new TextBlock { Text = value, FontSize = 13, Foreground = Ui.Brush(valueBrush), TextWrapping = TextWrapping.Wrap };
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);
        return new Border
        {
            Padding = new Thickness(0, 9, 0, 9),
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = grid,
        };
    }

    private FrameworkElement Preview(string location, string caption)
    {
        var image = Thumbnail(location, 180, 120);
        var label = new TextBlock { Text = caption, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 180, Margin = new Thickness(0, 6, 0, 0) };
        return new StackPanel { Children = { image, label } };
    }

    // ───────────────────────────── Actions ─────────────────────────────

    private FrameworkElement Actions(WidgetTaskRecord r)
    {
        var panel = new WrapPanel { Margin = new Thickness(0, 28, 0, 0) };
        void Add(Button button)
        {
            button.Margin = new Thickness(0, 0, 8, 8);
            panel.Children.Add(button);
        }

        if (r.IsActive)
        {
            var sourceExists = !r.IsTextSource && SourceAvailable(r.SourceUrl);
            if (sourceExists) Add(TextAction(L.T("Show Source"), () => _host.OpenSource(r)));
            var cancel = TextAction(L.T("Cancel"), () => _services.Tasks.Cancel(r.Id));
            cancel.IsEnabled = r.CanCancel;
            Add(cancel);
            return panel;
        }

        var outputExists = r.OutputPath is { } output && (File.Exists(output) || Directory.Exists(output));
        if (r.Phase == WidgetTaskPhase.Completed && outputExists)
        {
            var output2 = r.OutputPath!;
            var isMedia = File.Exists(output2) && !output2.EndsWith(".txt", StringComparison.OrdinalIgnoreCase);
            Add(TextAction(L.T(isMedia ? "Show in Image Inspect" : "Open Result"), () => _host.OpenResult(r), primary: true));
            var command = _services.Registry.Find(r.WidgetId)?.Command(r.CommandId);
            if (r.CopyableMediaResultUrl(command?.ShowResultUrl, command?.Outputs) is { } url)
                Add(TextAction(L.T("Copy URL"), () => _ = CopyUrlAsync(r, url)));
            Add(TextAction(L.T("Reveal in File Explorer"), () => ShellActions.RevealInExplorer(output2)));
        }
        else
        {
            Add(TextAction(L.T("Retry"), () => _host.Retry(r, this), primary: true));
        }
        var remove = TextAction(L.T("Remove Record"), () =>
        {
            if (_services.Tasks.Remove(r.Id) && _selected == r.Id) _selected = null;
        });
        remove.IsEnabled = !r.IsActive && !r.HasPendingSettlement;
        if (r.HasPendingSettlement) remove.ToolTip = L.T("Confirming the credits for this task. You can remove it once that finishes.");
        Add(remove);
        return panel;
    }

    private static bool SourceAvailable(string source)
    {
        if (Uri.TryCreate(source, UriKind.Absolute, out var uri) && !uri.IsFile) return true;
        try
        {
            return File.Exists(uri?.IsFile == true ? uri.LocalPath : source);
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    /// <summary>First-party result links are signed for an hour: fetch a fresh one before copying.</summary>
    private async Task CopyUrlAsync(WidgetTaskRecord r, string stored)
    {
        var url = stored;
        if (GlanceApi.IsFirstParty(stored) && r.RemoteTaskId is { } remote)
        {
            try
            {
                url = await _services.Tasks.FetchResultUrlAsync(remote);
            }
            catch (Exception ex) when (ex is WidgetTaskException or HttpRequestException or OperationCanceledException)
            {
                Log.Info($"TaskCenter: result URL refresh failed: {ex.Message}");
                _toast.Show(L.T("Could not refresh result URL"), error: true);
                return;
            }
        }
        if (InspectImages.CopyText(url)) _toast.Show(L.T("Result URL copied"));
        else _toast.Show(L.T("Could not refresh result URL"), error: true);
    }

    // ───────────────────────────── Clear confirmation ─────────────────────────────

    private void ShowClearConfirmation()
    {
        _confirm.Visibility = Visibility.Visible;
    }

    private Grid BuildConfirmation()
    {
        var title = new TextBlock { Text = L.T("Clear finished task history?"), FontSize = 15, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), TextWrapping = TextWrapping.Wrap };
        var body = new TextBlock { Text = L.T("Downloaded files will not be deleted."), FontSize = 13, Foreground = Ui.Brush("InspectText2Brush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
        var cancel = new Button { Style = Ui.Style("InspectQuietButton"), Content = L.T("Cancel"), Height = 32, MinWidth = 88, Margin = new Thickness(0, 0, 8, 0), IsCancel = true };
        var clear = new Button { Style = Ui.Style("InspectPrimaryButton"), Content = L.T("Clear"), Height = 32, MinWidth = 88 };
        var overlay = new Grid { Background = Ui.Brush("InspectScrimBrush"), Visibility = Visibility.Collapsed };
        cancel.Click += (_, _) => overlay.Visibility = Visibility.Collapsed;
        clear.Click += (_, _) =>
        {
            overlay.Visibility = Visibility.Collapsed;
            _services.Tasks.ClearFinished();
            if (_selected is { } id && _services.Tasks.Find(id) is null) _selected = null;
            Render();
        };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 24, 0, 0), Children = { cancel, clear } };
        var card = new Border
        {
            Width = 400,
            Padding = new Thickness(24),
            CornerRadius = new CornerRadius(12),
            Background = Ui.Brush("InspectInk1Brush"),
            BorderBrush = Ui.Brush("InspectLineStrongBrush"),
            BorderThickness = new Thickness(1),
            Effect = Ui.Effect("PanelShadow"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Child = new StackPanel { Children = { title, body, buttons } },
        };
        overlay.Children.Add(card);
        overlay.MouseLeftButtonDown += (_, e) =>
        {
            if (e.OriginalSource == overlay) overlay.Visibility = Visibility.Collapsed;
        };
        WindowChrome.SetIsHitTestVisibleInChrome(overlay, true);
        return overlay;
    }

    // ───────────────────────────── Thumbnails ─────────────────────────────

    /// <summary>Result thumbnail when the result is a file on disk, otherwise the source.</summary>
    private FrameworkElement Thumbnail(WidgetTaskRecord r, double size)
    {
        var location = r.OutputPath is { } output && File.Exists(output) && !output.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)
            ? output
            : r.IsTextSource ? null : r.SourceUrl;
        return Thumbnail(location, size, size);
    }

    private FrameworkElement Thumbnail(string? location, double width, double height)
    {
        var image = new Image { Stretch = Stretch.UniformToFill, Width = width, Height = height };
        var frame = new Border
        {
            Width = width,
            Height = height,
            CornerRadius = Ui.Corner("CornerThumb"),
            Background = Ui.Brush("InspectInk2Brush"),
            Child = image,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        Ui.RoundClip(frame, 4);
        if (location is null || !IsLocalFile(location, out var path)) return frame;
        if (_thumbs.TryGetValue(path, out var cached))
        {
            image.Source = cached;
            return frame;
        }
        if (_loadingThumbs.Add(path)) _ = LoadThumbnailAsync(path);
        return frame;
    }

    private static bool IsLocalFile(string location, out string path)
    {
        path = location;
        if (Uri.TryCreate(location, UriKind.Absolute, out var uri))
        {
            if (!uri.IsFile) return false;
            path = uri.LocalPath;
        }
        return true;
    }

    /// <summary>Shell thumbnails off the UI thread (rule 22); re-renders once loaded.</summary>
    private async Task LoadThumbnailAsync(string path)
    {
        ImageSource? thumb = null;
        try
        {
            var exists = await Task.Run(() => File.Exists(path));
            if (exists) thumb = await ShellThumbnails.GetAsync(path, 80, thumbnailOnly: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            Log.Info($"TaskCenter: no thumbnail for '{Log.Redact(path)}': {ex.Message}");
        }
        finally
        {
            _loadingThumbs.Remove(path);
        }
        _thumbs[path] = thumb;
        if (thumb is not null && IsVisible) Render();
    }

    // ───────────────────────────── Window frame & builders ─────────────────────────────

    /// <summary>Figma design size (1554 × 1012) shrunk to the cursor's monitor, centred.</summary>
    private void PlaceDesignFrame()
    {
        if (WindowState != WindowState.Normal) return;
        var monitor = ScreenGeometry.MonitorAtCursor();
        var workDip = new Size(monitor.WorkArea.Width / monitor.Scale, monitor.WorkArea.Height / monitor.Scale);
        var scale = Math.Min(1, Math.Min(workDip.Width / DesignSize.Width, workDip.Height / DesignSize.Height));
        var size = new Size(Math.Max(Math.Min(MinWidth, workDip.Width), DesignSize.Width * scale), Math.Max(Math.Min(MinHeight, workDip.Height), DesignSize.Height * scale));
        ScreenManager.Place(this, ScreenManager.CenterFrame(size, monitor));
    }

    private static Button IconButton(string icon, string tooltip, Action onClick)
    {
        var button = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(icon, 16, "InspectText2Brush"), ToolTip = tooltip };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static Button TextAction(string title, Action onClick, bool primary = false)
    {
        var button = new Button { Style = Ui.Style(primary ? "InspectPrimaryButton" : "InspectQuietButton"), Content = title, Height = 32, MinWidth = 88 };
        button.Click += (_, _) => onClick();
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
}
