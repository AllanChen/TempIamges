using Glance.App.Localization;
using Glance.App.Media;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.History;
using Glance.Core.Logging;
using Glance.Core.Peek;
using Glance.Core.Settings;
using Glance.Platform;

namespace Glance.App.Peek;

/// <summary>
/// The Peek flow (port of the macOS <c>AppDelegate</c> preview pipeline). All methods run on the
/// UI thread; blocking work (UI Automation, clipboard, file checks, search, decoding) is awaited
/// off-thread. Every request has an id; results from a superseded request are dropped.
/// </summary>
internal sealed class PeekController
{
    private readonly SettingsStore _settings;
    private readonly HotkeyService _hotkeys;
    private readonly SelectionReader _reader;
    private readonly PeekPipeline _pipeline;
    private readonly HistoryStore _history;
    private readonly ItemRouter _router;
    private readonly ImageLoader _loader = new();
    private readonly PeekWindow _window = new();
    private readonly ErrorToast _toast = new();

    private ulong _requestId;
    private CancellationTokenSource? _cts;
    private bool _isLoading;
    private bool _isTogglePending;
    private string? _activeSelection;
    private string? _lastSelectedText;
    private string? _sourceApp;

    public PeekController(SettingsStore settings, HotkeyService hotkeys, SelectionReader reader,
        PeekPipeline pipeline, HistoryStore history, ItemRouter router)
    {
        _router = router;
        _settings = settings;
        _hotkeys = hotkeys;
        _reader = reader;
        _pipeline = pipeline;
        _history = history;

        _window.OpenRequested += info =>
        {
            // The other images of this Peek fill the Image Inspect filmstrip.
            var context = _window.Items.ToList();
            ClosePeek();
            _router.Open(info, context);
        };
        _window.RevealRequested += _router.Reveal;
        _window.CloseRequested += ClosePeek;
        _hotkeys.Pressed += OnHotkey;
    }

    public bool IsPeekVisible => _window.IsVisible;

    public void ShowNotice(string message, bool isError = true) => _toast.ShowMessage(message, isError);

    /// <summary>Runs Peek on given text, skipping selection reading (debug / tests / "Peek clipboard").</summary>
    public Task PeekTextAsync(string text) => ActivateAsync(text);

    public void ClosePeek()
    {
        Invalidate();
        _isLoading = false;
        _activeSelection = null;
        _hotkeys.Unregister(HotkeyService.EscapeId);
        _window.Dismiss();
    }

    private void OnHotkey(object? sender, int id)
    {
        if (id == HotkeyService.EscapeId)
        {
            ClosePeek();
            _toast.Dismiss();
        }
        else if (id == HotkeyService.ActivationId)
        {
            _ = OnActivationAsync();
        }
    }

    /// <summary>
    /// Hotkey while Peek is open: close it if still loading, if nothing is selected, or if the
    /// selection is unchanged; otherwise peek at the new selection.
    /// </summary>
    private async Task OnActivationAsync()
    {
        if (!_settings.Current.PeekEnabled) return;
        if (_isTogglePending) return;

        if (_window.IsVisible)
        {
            if (_isLoading)
            {
                ClosePeek();
                return;
            }
            _isTogglePending = true;
            string? text;
            try
            {
                text = await _reader.ReadViaAutomationAsync(TimeSpan.FromMilliseconds(150));
            }
            finally
            {
                _isTogglePending = false;
            }
            if (!_window.IsVisible) return;
            if (string.IsNullOrWhiteSpace(text) || PeekPipeline.NormalizeSelection(text) == _activeSelection)
            {
                ClosePeek();
                return;
            }
            await ActivateAsync(text);
            return;
        }

        await ActivateAsync(null);
    }

    private async Task ActivateAsync(string? injectedText)
    {
        Invalidate();
        var id = _requestId;
        var ct = _cts!.Token;
        _isLoading = true;
        _sourceApp = PlatformEnvironment.ForegroundAppName();
        Log.Info("Peek: activated" + (injectedText is null ? "" : " (injected text)"));

        try
        {
            var text = injectedText;
            if (text is null)
            {
                // macOS 7f399a7: show "Searching…" at once while the selection is read. The Peek
                // window never activates, so focus stays in the source app for the Ctrl+C fallback.
                ShowWindow();
                _window.ShowLoading(null, L.T("Searching…"));
                var allowClipboard = _settings.Current.ReadClipboard;
                var result = await _reader.ReadAsync(allowClipboard);
                if (id != _requestId) return;

                text = result?.Text;
                if (!string.IsNullOrWhiteSpace(text))
                {
                    _lastSelectedText = text;
                }
                else if (!string.IsNullOrWhiteSpace(_lastSelectedText))
                {
                    Log.Info("Peek: no selection — using the last selection");
                    text = _lastSelectedText;
                }
                else if (allowClipboard)
                {
                    text = (await _reader.ReadClipboardAsync())?.Text;
                    if (id != _requestId) return;
                    if (!string.IsNullOrWhiteSpace(text)) Log.Info("Peek: no selection — using clipboard text");
                }
            }

            if (string.IsNullOrWhiteSpace(text))
            {
                ClosePeek();
                _toast.ShowMessage(L.T("No text selected"));
                return;
            }

            await ProceedAsync(text, id, ct);
        }
        catch (OperationCanceledException)
        {
            // Superseded or closed.
        }
        catch (Exception ex)
        {
            Log.Error("Peek: failed", ex);
            if (id == _requestId)
            {
                ClosePeek();
                _toast.ShowMessage(L.T("Something went wrong. See the log for details."));
            }
        }
    }

    private async Task ProceedAsync(string text, ulong id, CancellationToken ct)
    {
        _activeSelection = PeekPipeline.NormalizeSelection(text);
        // Detection checks the file system (network paths can be slow): keep it off the UI thread.
        var detection = await Task.Run(() => _pipeline.Detect(text), ct);
        if (id != _requestId) return;

        if (detection.IsEmpty)
        {
            ClosePeek();
            _toast.ShowMessage(L.T("No image or video found in selection"));
            return;
        }

        IReadOnlyList<PeekItem> items;
        if (!detection.NeedsSearch)
        {
            items = detection.Resolved.Select(p => new PeekItem(p, null)).ToList();
        }
        else
        {
            ShowWindow();
            _window.ShowLoading(detection.UnresolvedTokens[0]);
            items = await _pipeline.ResolveAsync(detection, ct);
            if (id != _requestId) return;
            if (items.Count == 0)
            {
                _isLoading = false;
                _window.ShowFailure(L.F("No file found matching '%@'", detection.UnresolvedTokens[0]));
                return;
            }
        }

        _history.Record(items.Select(i => i.Path));
        var infos = items
            .Select(i => MediaInfo.From(i.Path) is { } info ? info with { DisambiguationHint = i.Hint, SourceAppName = _sourceApp } : null)
            .OfType<MediaInfo>()
            .ToList();
        if (infos.Count == 0)
        {
            ClosePeek();
            _toast.ShowMessage(L.T("No media to preview"));
            return;
        }

        // Single document / web page: open straight away, like the macOS single-hit shortcut.
        if (infos.Count == 1 && infos[0].OpensInViewer)
        {
            ClosePeek();
            _router.Open(infos[0]);
            return;
        }

        ShowWindow();
        _window.ShowItems(infos);
        await LoadAllAsync(infos, id, ct);
        if (id == _requestId) _isLoading = false;
    }

    private async Task LoadAllAsync(IReadOnlyList<MediaInfo> infos, ulong id, CancellationToken ct)
    {
        var tasks = infos.Select(async (info, index) =>
        {
            var media = await _loader.LoadAsync(info, maxPixelSide: 1200, ct);
            if (id == _requestId) _window.UpdateItem(index, media);
        });
        await Task.WhenAll(tasks);
    }

    private void ShowWindow()
    {
        _toast.Dismiss();
        _hotkeys.RegisterEscape();
    }

    /// <summary>Cancels the active request and starts a new id.</summary>
    private void Invalidate()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = new CancellationTokenSource();
        _requestId++;
    }

    /// <summary>System resumed from sleep: drop any Peek (macOS <c>systemDidWake</c>).</summary>
    public void OnSystemResumed()
    {
        Log.Info("Peek: system resumed");
        ClosePeek();
    }
}
