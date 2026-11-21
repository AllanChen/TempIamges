using System.Threading.Tasks;
using System.Windows;
using Glance.App.Account;
using Glance.App.Localization;
using Glance.App.Peek;
using Glance.App.Shell;
using Glance.App.Tray;
using Glance.App.Widgets;
using Glance.Core;
using Glance.Core.Account;
using Glance.Core.Detection;
using Glance.Core.History;
using Glance.Core.Logging;
using Glance.Core.Peek;
using Glance.Core.Search;
using Glance.Core.Settings;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App;

/// <summary>
/// Composition root (port of macOS <c>AppDelegate</c> startup). Tray-only app:
/// no main window, runs until "Quit Glance".
/// </summary>
public partial class App : Application
{
    private const string AppId = "Glance.App";

    private SingleInstance? _instance;
    private SettingsStore? _settings;
    private TrayIconHost? _tray;
    private HotkeyService? _hotkeys;
    private PeekController? _peek;
    private ItemRouter? _router;
    private AccountServices? _account;
    private AccountWindow? _accountWindow;
    private WidgetRunner? _widgets;
    private AppShell? _shell;
    private HistoryStore? _history;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _instance = SingleInstance.TryAcquire(AppId, e.Args);
        if (_instance is null)
        {
            // Another Glance is running and has received our arguments.
            Shutdown();
            return;
        }

        var paths = AppPaths.Default;
        paths.EnsureCreated();
        Log.Initialize(paths.LogFile);
        Log.Info($"Glance {typeof(App).Assembly.GetName().Version} starting on {Environment.OSVersion}");
        InstallCrashLogging();

        _settings = new SettingsStore(paths.SettingsFile);
        L.Apply(_settings.Current.Language);
        _settings.Changed += (_, _) => Dispatcher.BeginInvoke(OnSettingsChanged);

        _hotkeys = new HotkeyService();
        var environment = PlatformEnvironment.CreateResolverEnvironment();
        var resolver = new FileNameResolver(environment, new FilenameCache(paths.FilenameCacheFile), new WindowsSearchIndex());
        var pipeline = new PeekPipeline(new PathDetector(), resolver, environment.Home);
        _router = new ItemRouter(paths.WebViewDataDirectory, paths.VideoWebViewDataDirectory);
        var router = _router;
        _account = new AccountServices(paths, _settings);
        _accountWindow = new AccountWindow(_account);
        _widgets = new WidgetRunner(_account, _accountWindow, info => router.Open(info));
        _router.Widgets = _widgets;
        _history = new HistoryStore(paths.HistoryFile);
        _peek = new PeekController(_settings, _hotkeys, new SelectionReader(_hotkeys.Handle), pipeline,
            _history, _router);

        try
        {
            _tray = new TrayIconHost(_settings, paths);
        }
        catch (Exception ex)
        {
            // Without the tray icon Glance would run invisibly with no way to quit it.
            Log.Error("Tray icon could not be created", ex);
            MessageBox.Show($"Glance could not create its notification-area icon and will exit.\n\n{ex.GetBaseException().Message}\n\nLog: {paths.LogFile}",
                "Glance", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
            return;
        }
        _shell = new AppShell(_settings, _history, _account, _widgets, _router, QuitAsync, PeekClipboardAsync) { Tray = _tray };
        _tray.AttachShell(_shell);
        _shell.SyncAutostart();
        _tray.QuitRequested += async (_, _) => await QuitAsync();
        _tray.AccountRequested += (_, _) => _widgets?.ShowAccount(null);
        _tray.MarketRequested += (_, _) => _widgets?.ShowMarket(null);
        _tray.TaskCenterRequested += (_, _) => _widgets?.ShowTaskCenter();
        _account.Tasks.Completed += OnWidgetCompleted;
        // glance:// sign-in and payment returns (HKCU, no admin); registry writes stay off the UI thread.
        if (Environment.ProcessPath is { } exe) _ = Task.Run(() => ProtocolRegistration.EnsureRegistered(exe));
        _ = _account.StartAsync();
        _tray.PeekClipboardRequested += async (_, _) => await PeekClipboardAsync();

        SystemEvents.PowerModeChanged += OnPowerModeChanged;

        ApplyHotkey(announceFailure: true);

        _instance.ArgumentsReceived += (_, args) => Dispatcher.BeginInvoke(() =>
        {
            // Launching Glance again with nothing to open brings Home forward (macOS Dock reopen).
            if (args.Length == 0) _shell?.ShowHome();
            else HandleArguments(args);
        });
        _instance.StartListening();
        HandleArguments(e.Args);
        ShowStartupWindows(e.Args, _settings.IsFirstRun);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        _hotkeys?.Dispose();
        _shell?.Shutdown();
        _widgets?.Shutdown();
        _router?.Shutdown();
        _tray?.Dispose();
        if (_instance is not null)
        {
            Log.Info("Glance exiting");
            Log.Flush(TimeSpan.FromSeconds(1));
            _instance.Dispose();
        }
        base.OnExit(e);
    }

    private void OnSettingsChanged()
    {
        ApplyHotkey(announceFailure: true);
        _tray?.Refresh();
    }

    /// <summary>Registers the activation hotkey while Peek is enabled; reports conflicts.</summary>
    private void ApplyHotkey(bool announceFailure)
    {
        if (_settings is null || _hotkeys is null) return;
        var settings = _settings.Current;
        if (!settings.PeekEnabled)
        {
            _hotkeys.Unregister(HotkeyService.ActivationId);
            _peek?.ClosePeek();
            _tray?.SetHotkeyRegistered(true);
            _shell?.SetHotkeyRegistered(true);
            return;
        }

        var ok = _hotkeys.Register(HotkeyService.ActivationId, settings.Hotkey);
        _tray?.SetHotkeyRegistered(ok);
        _shell?.SetHotkeyRegistered(ok);
        if (ok)
        {
            Log.Info($"Activation hotkey registered: {settings.Hotkey.DisplayText}");
        }
        else if (announceFailure)
        {
            _peek?.ShowNotice(L.F("%@ is already used by another app. Choose another hotkey in Preferences.", settings.Hotkey.DisplayText));
        }
    }

    /// <summary>
    /// macOS <c>surfaceHomeIfIdle</c>: a plain launch shows Home shortly after start-up (not when
    /// started with files, a glance:// link, or by Windows at sign-in); a fresh install also shows the
    /// first-run guide on top of it.
    /// </summary>
    private void ShowStartupWindows(string[] args, bool firstRun)
    {
        if (_shell is null || _settings is null) return;
        var background = args.Any(a => a.Equals("--background", StringComparison.OrdinalIgnoreCase));
        var opensSomething = args.Any(a => !a.StartsWith("--", StringComparison.Ordinal));
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!background && !opensSomething && !Windows.Cast<Window>().Any(w => w.IsVisible && w is not Glance.App.Windows.FloatingWindow)) _shell.ShowHome();
            if (firstRun || !_settings.Current.OnboardingShown && !background) _shell.ShowOnboarding();
        };
        timer.Start();
    }

    /// <summary>Quit from the tray: the content viewer may ask to save edits first.</summary>
    private async Task QuitAsync()
    {
        if (_router is not null && !await _router.PrepareForQuitAsync()) return;
        Shutdown();
    }

    private async Task PeekClipboardAsync()
    {
        if (_peek is null || _hotkeys is null) return;
        var text = await new SelectionReader(_hotkeys.Handle).ReadClipboardAsync();
        if (text is null)
        {
            _peek.ShowNotice(L.T("The clipboard has no text"));
            return;
        }
        await _peek.PeekTextAsync(text.Text);
    }

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) Dispatcher.BeginInvoke(() => _peek?.OnSystemResumed());
    }

    /// <summary>
    /// Files from Explorer "Open with" (and forwarded from a second instance): images open in
    /// Image Inspect together, documents in the content viewer. <c>glance://</c> links are
    /// handled by the login flow in Phase 5; logged for now.
    /// </summary>
    private async void HandleArguments(string[] args)
    {
        if (args.Length == 0 || _router is null) return;
        Log.Info($"Received {args.Length} launch argument(s): {Log.Redact(string.Join(" | ", args))}");
        foreach (var url in args.Where(a => a.StartsWith("glance://", StringComparison.OrdinalIgnoreCase)))
            await HandleGlanceUrlAsync(url);
        // File checks can block on network paths: off the UI thread (CLAUDE.md rule 22).
        var infos = await Task.Run(() =>
        {
            var detector = new PathDetector();
            return args
                .Where(a => !a.StartsWith("glance://", StringComparison.OrdinalIgnoreCase) && (File.Exists(a) || Directory.Exists(a)))
                .Select(a => MediaInfo.From(detector.LocalKind(Path.GetFullPath(a))))
                .OfType<MediaInfo>()
                .ToList();
        });
        var images = infos.Where(i => i.Kind == MediaKind.Image).ToList();
        if (images.Count > 0) _router.OpenImages(images, 0);
        var videos = infos.Where(i => i.Kind == MediaKind.Video).ToList();
        if (videos.Count > 0) _router.OpenVideos(videos, 0);
        foreach (var other in infos.Where(i => i.Kind is not (MediaKind.Image or MediaKind.Video))) _router.Open(other);
    }

    /// <summary>
    /// <c>glance://auth/callback?…</c> finishes Google sign-in; <c>glance://payment/return?order=…</c>
    /// only prompts an order check (the balance always comes from the service).
    /// </summary>
    private async Task HandleGlanceUrlAsync(string url)
    {
        if (_account is null || _accountWindow is null) return;
        if (AuthService.IsAuthCallback(url))
        {
            try
            {
                await _account.Auth.CompleteCallbackAsync(url);
            }
            catch (ApiException ex)
            {
                Log.Info($"Sign-in callback failed: {ex.Code}: {ex.Message}");
                _accountWindow.ShowAuthenticationError(ex.Message);
            }
            return;
        }
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Host.Equals("payment", StringComparison.OrdinalIgnoreCase)
            && AuthService.ParseQuery(uri.Query).TryGetValue("order", out var order)
            && System.Text.RegularExpressions.Regex.IsMatch(order, "^order_[A-Za-z0-9-]{1,80}$"))
        {
            _accountWindow.HandlePaymentReturn(order);
            return;
        }
        Log.Info("Ignored an unsupported glance:// URL");
    }

    /// <summary>"Widget completed" with the file name; clicking opens the result (macOS user notification).</summary>
    private void OnWidgetCompleted(Glance.Core.Tasks.WidgetTaskRecord record)
    {
        var name = record.OutputPath is { } output ? Path.GetFileName(Path.TrimEndingDirectorySeparator(output)) : record.CommandName;
        var id = record.Id;
        _tray?.ShowNotification(L.T("Widget completed"), name, onClick: () =>
        {
            if (_account?.Tasks.Find(id) is { } current) _widgets?.OpenResult(current);
        });
    }

    private void InstallCrashLogging()
    {
        DispatcherUnhandledException += (_, ev) =>
        {
            Log.Error("Unhandled UI exception", ev.Exception);
            // Keep the tray app alive; a single failed panel must not kill Glance.
            ev.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, ev) =>
        {
            Log.Error("Unhandled exception (terminating)", ev.ExceptionObject as Exception);
            Log.Flush(TimeSpan.FromSeconds(1));
        };
        TaskScheduler.UnobservedTaskException += (_, ev) =>
        {
            Log.Error("Unobserved task exception", ev.Exception);
            ev.SetObserved();
        };
    }
}
