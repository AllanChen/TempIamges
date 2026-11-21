using System.Windows;
using System.Windows.Threading;
using Glance.App.Account;
using Glance.App.Localization;
using Glance.App.Peek;
using Glance.App.Tray;
using Glance.App.Widgets;
using Glance.Core.Detection;
using Glance.Core.History;
using Glance.Core.Logging;
using Glance.Core.Settings;
using Glance.Platform;

namespace Glance.App.Shell;

/// <summary>
/// The app's shell (macOS <c>AppDelegate</c> window management): owns Home, Preferences and the
/// first-run guide, routes opened items, and applies language / startup / Explorer settings.
/// </summary>
internal sealed class AppShell : IAppShell
{
    private readonly ItemRouter _router;
    private readonly Func<Task> _quit;
    private readonly Func<Task> _peekClipboard;
    private HomeWindow? _home;
    private PreferencesWindow? _preferences;
    private OnboardingWindow? _onboarding;
    private bool _hotkeyRegistered = true;

    public AppShell(SettingsStore settings, HistoryStore history, AccountServices account, WidgetRunner widgets, ItemRouter router,
        Func<Task> quit, Func<Task> peekClipboard)
    {
        Settings = settings;
        History = history;
        Account = account;
        Widgets = widgets;
        _router = router;
        _quit = quit;
        _peekClipboard = peekClipboard;
        ExePath = Environment.ProcessPath ?? "";
    }

    public SettingsStore Settings { get; }
    public HistoryStore History { get; }
    public AccountServices Account { get; }
    public WidgetRunner Widgets { get; }
    public string ExePath { get; }
    public TrayIconHost? Tray { get; set; }

    public bool HotkeyRegistered => _hotkeyRegistered;
    public event EventHandler? HotkeyStateChanged;

    public void SetHotkeyRegistered(bool registered)
    {
        if (_hotkeyRegistered == registered) return;
        _hotkeyRegistered = registered;
        HotkeyStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void OpenItems(IReadOnlyList<MediaInfo> items, bool hideHome = true)
    {
        if (items.Count == 0) return;
        var images = items.Where(i => i.Kind == MediaKind.Image).ToList();
        var videos = items.Where(i => i.Kind == MediaKind.Video).ToList();
        if (images.Count > 0) _router.OpenImages(images, 0);
        if (videos.Count > 0) _router.OpenVideos(videos, 0);
        foreach (var other in items.Where(i => i.Kind is not (MediaKind.Image or MediaKind.Video))) _router.Open(other);
        // Home steps aside once media is handed to an inspector (macOS orderOut).
        if (hideHome && (images.Count > 0 || videos.Count > 0)) _home?.Hide();
    }

    public void ShowHome()
    {
        _home ??= new HomeWindow(this);
        _home.Present();
    }

    public void ShowPreferences()
    {
        if (_preferences is null)
        {
            _preferences = new PreferencesWindow(this);
        }
        _preferences.Present();
    }

    public void ShowOnboarding()
    {
        if (_onboarding is null)
        {
            var window = new OnboardingWindow(this);
            window.Closed += (_, _) =>
            {
                if (_onboarding == window) _onboarding = null;
            };
            _onboarding = window;
        }
        _onboarding.Present();
    }

    public void ShowAbout(Window? owner)
    {
        var version = typeof(AppShell).Assembly.GetName().Version?.ToString(3) ?? "";
        var text = L.F("Version %@\n\nThe Preview for the AI era: view images and videos, fix them with AI in place, and compare the result.", version);
        if (owner is { IsVisible: true }) MessageBox.Show(owner, text, "Glance", MessageBoxButton.OK, MessageBoxImage.Information);
        else MessageBox.Show(text, "Glance", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    public void PeekClipboard() => _ = _peekClipboard();

    public void Quit() => _ = _quit();

    /// <summary>
    /// macOS language switch: save, reload strings, discard the shell windows (they read strings when
    /// built), rebuild the tray, then reopen Preferences. Inspect windows switch when reopened.
    /// </summary>
    public void SetLanguage(AppLanguage language)
    {
        if (Settings.Current.Language == language && L.Current == language) return;
        Settings.Update(s => s with { Language = language });
        L.Apply(language);
        Log.Info($"Shell: language switched to {language}");
        _preferences?.Shutdown();
        _preferences = null;
        _onboarding?.Close();
        _onboarding = null;
        var homeWasVisible = _home?.IsVisible == true;
        _home?.Shutdown();
        _home = null;
        Widgets.ResetWindows();
        Tray?.RebuildForLanguage();
        Application.Current.Dispatcher.BeginInvoke(new Action(() =>
        {
            if (homeWasVisible) ShowHome();
            ShowPreferences();
        }), DispatcherPriority.Background);
    }

    public string? SetLaunchAtLogin(bool enabled)
    {
        try
        {
            Autostart.Set(ExePath, enabled);
            Settings.Update(s => s with { LaunchAtLogin = enabled });
            return null;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            Log.Warning($"Shell: autostart change failed: {ex.Message}");
            return L.T("Windows didn’t allow Glance to change its startup setting. Check Settings ▸ Apps ▸ Startup, then try again.");
        }
    }

    public bool ExplorerIntegrationInstalled => ExplorerIntegration.IsInstalled(ExePath);

    public string? SetExplorerIntegration(bool enabled)
    {
        try
        {
            if (enabled) ExplorerIntegration.Install(ExePath, L.T("Open with Glance"));
            else ExplorerIntegration.Uninstall();
            return null;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            Log.Warning($"Shell: Explorer integration change failed: {ex.Message}");
            return L.T("Windows didn’t allow Glance to change File Explorer’s menu. Try again, or sign in with your usual account.");
        }
    }

    /// <summary>Keeps the stored autostart flag in line with the registry (Task Manager can change it).</summary>
    public void SyncAutostart()
    {
        if (ExePath.Length == 0) return;
        var enabled = Autostart.IsEnabled(ExePath);
        if (Settings.Current.LaunchAtLogin != enabled) Settings.Update(s => s with { LaunchAtLogin = enabled });
    }

    public void Shutdown()
    {
        _preferences?.Shutdown();
        _onboarding?.Close();
        _home?.Shutdown();
    }
}
