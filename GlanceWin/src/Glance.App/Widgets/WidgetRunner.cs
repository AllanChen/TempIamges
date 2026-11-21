using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Glance.App.Account;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Account;
using Glance.Core.Billing;
using Glance.Core.Detection;
using Glance.Core.Logging;
using Glance.Core.Tasks;
using Glance.Core.Widgets;
using Glance.Platform;

namespace Glance.App.Widgets;

/// <summary>
/// Runs Widgets for the app (macOS <c>BillingCoordinator.requireWidgetSignIn</c> +
/// <c>confirmWidgetTask</c> + <c>WidgetTaskManager.start</c>): sign-in gate → input panel when the
/// command needs one → price quote → top-up when the balance is short → start. Nothing is uploaded
/// or charged before the user has signed in and the quote is covered. Also owns the Widget Market,
/// Task Center and text-Widget windows, and builds the Widgets menu used by Image / Video Inspect.
/// </summary>
internal sealed class WidgetRunner : IWidgetHost
{
    private const long MaxVideoBytes = 50L * 1024 * 1024;

    private readonly AccountServices _services;
    private readonly AccountWindow _account;
    private readonly Action<MediaInfo> _openMedia;
    private readonly Dictionary<string, TextWidgetWindow> _textWindows = [];
    private WidgetMarketWindow? _market;
    private TaskCenterWindow? _taskCenter;
    private Window? _lastOwner;

    public WidgetRunner(AccountServices services, AccountWindow account, Action<MediaInfo> openMedia)
    {
        _services = services;
        _account = account;
        _openMedia = openMedia;
        services.Tasks.RequoteRequired += OnRequoteRequired;
    }

    public AccountServices Services => _services;

    public void ShowMarket(Window? owner)
    {
        _market ??= new WidgetMarketWindow(_services, this);
        _market.ShowFor(owner);
    }

    public void ShowTaskCenter(Guid? id = null)
    {
        _taskCenter ??= new TaskCenterWindow(_services, this);
        _taskCenter.ShowTask(id);
    }

    public void ShowAccount(Window? owner) => _account.ShowAccount(owner);

    /// <summary>Language switch: discard the Market, Task Center and text windows so they rebuild with the new strings.</summary>
    public void ResetWindows()
    {
        _market?.Shutdown();
        _market = null;
        _taskCenter?.Shutdown();
        _taskCenter = null;
        foreach (var window in _textWindows.Values.ToList()) window.Close();
    }

    public void Shutdown()
    {
        _market?.Shutdown();
        _taskCenter?.Shutdown();
        foreach (var window in _textWindows.Values.ToList()) window.Close();
        _account.Shutdown();
    }

    // ───────────────────────────── Running ─────────────────────────────

    /// <summary>Runs <paramref name="command"/> on an image / video item from Inspect.</summary>
    public async Task RunAsync(WidgetManifest widget, WidgetCommand command, MediaInfo media, Window owner, Action<string> showError)
    {
        _lastOwner = owner;
        var video = media.Kind == MediaKind.Video;
        var caps = command.InputCapabilities;
        if (caps.AcceptsMask)
        {
            showError(L.T("This Widget needs a drawn mask, which Glance for Windows can't do yet. Nothing was charged."));
            return;
        }
        if (!await _account.RequireSignInAsync(owner, widget.TaskCreditCost == 0)) return;
        var input = new WidgetTaskInput { MediaUrls = [media.Location] };
        if (video ? caps.NeedsVideoDialog : caps.NeedsImageDialog)
        {
            var asked = WidgetInputWindow.Ask(owner, widget, command, _services.Language, [media.Location], video);
            if (asked is null) return;
            input = asked;
        }
        await StartFlowAsync(widget, command, media.Location, video ? "video" : "image", input, owner, showError);
    }

    /// <summary>Quote → (top-up) → start. Returns the new record, or null when it didn't start.</summary>
    private async Task<WidgetTaskRecord?> StartFlowAsync(WidgetManifest widget, WidgetCommand command, string source, string kind, WidgetTaskInput input, Window? owner, Action<string> showError)
    {
        if (!_services.Registry.IsAvailable(widget.Id))
        {
            showError(L.T("This Widget is no longer available."));
            return null;
        }
        if (!await _account.RequireSignInAsync(owner, widget.TaskCreditCost == 0)) return null;
        try
        {
            JsonObject? evidence = null;
            if (widget.UsesDurationBilling)
            {
                if (kind != "video" || input.MediaUrls.Count != 1) throw new WidgetTaskException("Select one video per task.");
                evidence = await VideoEvidenceAsync(input.MediaUrls[0]);
            }
            var quote = await _services.Billing.QuoteAsync(widget.Id, command.Id, evidence);
            if (quote.Shortfall > 0 || quote.Balance < quote.TotalCredits)
            {
                Log.Info($"Widgets: balance short for {widget.Id} ({quote.Balance}/{quote.TotalCredits})");
                if (!await _account.RequireCreditsAsync(owner, widget, quote)) return null;
                quote = await _services.Billing.QuoteAsync(widget.Id, command.Id, evidence);
                if (quote.Balance < quote.TotalCredits)
                {
                    showError(L.F("%d more credits needed", quote.TotalCredits - quote.Balance));
                    return null;
                }
            }
            return await _services.Tasks.StartAsync(widget, command, _services.Language, source, kind, input, quote);
        }
        catch (ApiException ex)
        {
            Log.Info($"Widgets: could not start {widget.Id}: {ex.Message}");
            showError(L.T(ex.Message) + " " + L.T("Nothing has been charged."));
        }
        catch (WidgetTaskException ex)
        {
            showError(L.T(ex.Message));
        }
        return null;
    }

    /// <summary>Duration-priced videos: size ≤ 50 MiB, duration (≤ 24 segments of ~8 s), SHA-256.</summary>
    private static async Task<JsonObject> VideoEvidenceAsync(string location)
    {
        if (Uri.TryCreate(location, UriKind.Absolute, out var uri) && !uri.IsFile)
            throw new WidgetTaskException("Save this video locally before checking its duration and price.");
        var info = new FileInfo(location);
        if (!info.Exists || info.Length == 0 || info.Length > MaxVideoBytes)
            throw new WidgetTaskException("Video must be nonempty and at most 50 MiB. Compress it and try again.");
        var metadata = await VideoMetadataReader.ReadAsync(location);
        if (metadata?.DurationSeconds is not { } seconds || seconds <= 0)
            throw new WidgetTaskException("Cannot read this video's duration. Save it as MP4 and try again.");
        var segments = Math.Ceiling(seconds / (seconds <= 8 ? 8 : 7.8));
        if (segments > 24)
            throw new WidgetTaskException("This video is too long. Trim it to 187.2 seconds or less before submitting. Nothing has been charged.");
        var hash = await WidgetTaskManager.Sha256Async(location);
        return new JsonObject { ["durationSeconds"] = seconds, ["byteSize"] = info.Length, ["sha256"] = hash };
    }

    private void OnRequoteRequired(WidgetTaskRecord record, string code)
    {
        if (_services.Registry.Find(record.WidgetId) is not { } widget || widget.Command(record.CommandId) is not { } command || record.Input is not { } input) return;
        Log.Info($"Widgets: re-quoting {record.WidgetId} after {code}");
        _ = StartFlowAsync(widget, command, record.SourceUrl, record.SourceKind, input, _lastOwner, message => ShowMessage(_lastOwner, message));
    }

    // ───────────────────────────── IWidgetHost ─────────────────────────────

    public void OpenResult(WidgetTaskRecord record)
    {
        if (record.OutputPath is not { } output) return;
        if (Directory.Exists(output))
        {
            ShellActions.Open(output);
            return;
        }
        if (!File.Exists(output))
        {
            ShowMessage(null, L.T("The result file is missing. Retry the task to download it again."));
            return;
        }
        if (Path.GetExtension(output).Equals(".txt", StringComparison.OrdinalIgnoreCase))
        {
            new TextResultWindow(record.WidgetName, TextWidgetWindow.ReadResult(output)).Present(_lastOwner);
            return;
        }
        var kind = MediaKindOf(output, record.OutputTypes);
        if (kind is MediaKind.Image or MediaKind.Video) _openMedia(new MediaInfo(output, true, kind));
        else ShellActions.Open(output);
    }

    public void OpenSource(WidgetTaskRecord record)
    {
        if (record.IsTextSource) return;
        var isLocal = !(Uri.TryCreate(record.SourceUrl, UriKind.Absolute, out var uri) && !uri.IsFile);
        if (isLocal && !File.Exists(record.SourceUrl)) return;
        _openMedia(new MediaInfo(record.SourceUrl, isLocal, record.SourceKind == "video" ? MediaKind.Video : MediaKind.Image));
    }

    public void Retry(WidgetTaskRecord record, Window? owner)
    {
        if (_services.Tasks.TryResume(record.Id)) return;
        if (_services.Registry.Find(record.WidgetId) is not { } widget || widget.Command(record.CommandId) is not { } command)
        {
            ShowMessage(owner, L.T("This Widget is no longer available."));
            return;
        }
        var input = record.Input ?? new WidgetTaskInput { MediaUrls = record.IsTextSource ? [] : [record.SourceUrl] };
        var source = record.IsTextSource ? $"glance-text:{Guid.NewGuid()}" : record.SourceUrl;
        _ = StartFlowAsync(widget, command, source, record.SourceKind, input, owner, message => ShowMessage(owner, message));
    }

    public void RunText(WidgetManifest widget, WidgetCommand command, Window? owner)
    {
        if (!_textWindows.TryGetValue(widget.Id, out var window))
        {
            window = new TextWidgetWindow(_services, widget, command, (input, w) =>
                StartFlowAsync(widget, command, $"glance-text:{Guid.NewGuid()}", "text", input, w, message => ShowMessage(w, message)));
            window.Closed += (_, _) => _textWindows.Remove(widget.Id);
            _textWindows[widget.Id] = window;
        }
        window.Present(owner);
    }

    private static MediaKind MediaKindOf(string path, IReadOnlyList<string>? outputs)
    {
        var detected = new PathDetector().LocalKind(path).MediaKind;
        if (detected is MediaKind.Image or MediaKind.Video) return detected.Value;
        if (outputs?.Contains("video") == true) return MediaKind.Video;
        if (outputs?.Contains("image") == true) return MediaKind.Image;
        return MediaKind.Other;
    }

    private static void ShowMessage(Window? owner, string message)
    {
        if (owner is { IsVisible: true }) MessageBox.Show(owner, message, "Glance", MessageBoxButton.OK, MessageBoxImage.Information);
        else MessageBox.Show(message, "Glance", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    // ───────────────────────────── Menu ─────────────────────────────

    /// <summary>
    /// Adds the Widgets entries to an Inspect menu (macOS <c>buildMoreEntries</c>): compatible
    /// Widgets with their credit cost, text Widgets, the Market, and Cancel for running tasks.
    /// </summary>
    public void AddMenuItems(ContextMenu menu, string inputType, MediaInfo? current, Window owner, Action<string> showError)
    {
        var language = _services.Language;
        var widgets = new MenuItem { Header = L.T("Widgets") };
        foreach (var widget in _services.Registry.Compatible(inputType))
        {
            var commands = widget.Commands.Where(c => c.Accepts(inputType)).ToList();
            if (commands.Count == 0) continue;
            MenuItem Entry(WidgetCommand command, string title)
            {
                var running = current is not null && _services.Tasks.ActiveRecords(current.Location).Any(r => r.WidgetId == widget.Id && r.CommandId == command.Id);
                var item = new MenuItem { Header = title, InputGestureText = WidgetText.MenuBadge(widget), IsEnabled = current is not null && !running, ToolTip = WidgetText.CostText(widget) };
                item.Click += (_, _) =>
                {
                    if (current is not null) _ = RunAsync(widget, command, current, owner, showError);
                };
                return item;
            }
            if (commands.Count == 1)
            {
                widgets.Items.Add(Entry(commands[0], widget.DisplayName(language)));
            }
            else
            {
                var parent = new MenuItem { Header = widget.DisplayName(language), InputGestureText = WidgetText.MenuBadge(widget) };
                foreach (var command in commands) parent.Items.Add(Entry(command, widget.CommandName(command, language)));
                widgets.Items.Add(parent);
            }
        }
        var text = _services.Registry.Available.Where(w => w.HasTextOnlyCommand).ToList();
        if (text.Count > 0)
        {
            if (widgets.Items.Count > 0) widgets.Items.Add(new Separator());
            widgets.Items.Add(new MenuItem { Header = L.T("Text input"), Style = Ui.Style("MenuSectionHeader") });
            foreach (var widget in text)
            {
                var command = widget.Commands.First(c => c.IsTextOnly);
                var item = new MenuItem { Header = widget.DisplayName(language), InputGestureText = WidgetText.MenuBadge(widget) };
                item.Click += (_, _) => RunText(widget, command, owner);
                widgets.Items.Add(item);
            }
        }
        var market = new MenuItem { Header = L.T("Widget Market…") };
        market.Click += (_, _) => ShowMarket(owner);
        menu.Items.Add(new Separator());
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
        var tasks = new MenuItem { Header = L.T("Task Center") };
        tasks.Click += (_, _) => ShowTaskCenter();
        menu.Items.Add(tasks);
        if (current is null) return;
        foreach (var record in _services.Tasks.ActiveRecords(current.Location).Where(r => r.CanCancel))
        {
            var id = record.Id;
            var cancel = new MenuItem { Header = L.F("Cancel %@", record.CommandName) };
            cancel.Click += (_, _) => _services.Tasks.Cancel(id);
            menu.Items.Add(cancel);
        }
    }

    /// <summary>Completed tasks whose source is one of <paramref name="sources"/> and that weren't handled yet.</summary>
    public IReadOnlyList<WidgetTaskRecord> NewResults(IEnumerable<string> sources, HashSet<Guid> handled)
    {
        var keys = sources.Select(WidgetTaskRecord.MediaKey).ToHashSet();
        var results = new List<WidgetTaskRecord>();
        foreach (var record in _services.Tasks.Records.Where(r => r.Phase == WidgetTaskPhase.Completed).OrderBy(r => r.UpdatedAt))
        {
            if (!handled.Add(record.Id)) continue;
            if (keys.Contains(WidgetTaskRecord.MediaKey(record.SourceUrl)) && record.OutputPath is not null) results.Add(record);
        }
        return results;
    }

    /// <summary>Ids of the tasks already completed (so a newly opened window doesn't re-insert old results).</summary>
    public HashSet<Guid> CompletedIds() =>
        _services.Tasks.Records.Where(r => r.Phase == WidgetTaskPhase.Completed).Select(r => r.Id).ToHashSet();

    public static MediaKind ResultKind(WidgetTaskRecord record) =>
        record.OutputPath is { } p ? MediaKindOf(p, record.OutputTypes) : MediaKind.Other;
}

/// <summary>
/// "Generating · Widget · 42 %" with Cancel (stand-in for macOS <c>TaskRunningChip</c> /
/// <c>InspectRunningPill</c>), shown over the stage while a task runs on the visible item.
/// </summary>
internal sealed class TaskRunningChip : Border
{
    private readonly TextBlock _text;
    private readonly Button _cancel;
    private Guid? _recordId;

    public TaskRunningChip(Action<Guid> cancel)
    {
        Height = 31;
        CornerRadius = new CornerRadius(15.5);
        Background = Ui.Brush("InspectInk1Brush");
        BorderBrush = Ui.Brush("InspectLineStrongBrush");
        BorderThickness = new Thickness(1);
        Padding = new Thickness(14, 0, 6, 0);
        Effect = Ui.Effect("MenuShadow");
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Top;
        Visibility = Visibility.Collapsed;
        var dot = new System.Windows.Shapes.Ellipse { Width = 6, Height = 6, Fill = Ui.Brush("InfoBrush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        _text = new TextBlock { FontSize = 12, Foreground = Ui.Brush("InspectText1Brush"), VerticalAlignment = VerticalAlignment.Center };
        _cancel = new Button { Content = L.T("Cancel"), Style = Ui.Style("InspectTextButton"), Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        _cancel.Click += (_, _) =>
        {
            if (_recordId is { } id) cancel(id);
        };
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(_cancel, true);
        Child = new StackPanel { Orientation = Orientation.Horizontal, Children = { dot, _text, _cancel } };
    }

    public void Show(WidgetTaskRecord? record)
    {
        _recordId = record?.Id;
        if (record is null)
        {
            Visibility = Visibility.Collapsed;
            return;
        }
        var percent = record.Progress > 0 ? $"  {Math.Min(99, (int)record.Progress)}%" : "";
        _text.Text = $"{L.T("Generating")} · {record.CommandName}{percent}  ·  {WidgetText.State(record)}";
        _cancel.Visibility = record.CanCancel ? Visibility.Visible : Visibility.Collapsed;
        Visibility = Visibility.Visible;
    }
}
