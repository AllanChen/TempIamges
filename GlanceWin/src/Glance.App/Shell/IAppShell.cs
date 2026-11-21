using System.Windows;
using Glance.App.Account;
using Glance.App.Widgets;
using Glance.Core.Detection;
using Glance.Core.History;
using Glance.Core.Settings;

namespace Glance.App.Shell;

/// <summary>
/// What the shell windows (Home, Preferences, onboarding, tray popover) ask of the app.
/// Implemented by <see cref="AppShell"/>. All members are UI-thread only.
/// </summary>
internal interface IAppShell
{
    SettingsStore Settings { get; }
    HistoryStore History { get; }
    AccountServices Account { get; }
    WidgetRunner Widgets { get; }

    /// <summary>Full path of Glance.exe (autostart, Explorer integration).</summary>
    string ExePath { get; }

    /// <summary>False when another app holds the activation hotkey.</summary>
    bool HotkeyRegistered { get; }

    /// <summary>The hotkey registration result changed.</summary>
    event EventHandler? HotkeyStateChanged;

    /// <summary>Opens items like a Peek click: images in Image Inspect, videos in Video Inspect, the rest in their viewers.</summary>
    void OpenItems(IReadOnlyList<MediaInfo> items, bool hideHome = true);

    void ShowHome();
    void ShowPreferences();
    void ShowOnboarding();
    void ShowAbout(Window? owner);
    void PeekClipboard();
    void Quit();

    /// <summary>Saves the language, reloads strings and rebuilds the shell windows (Preferences reopens).</summary>
    void SetLanguage(AppLanguage language);

    /// <summary>Turns start-with-Windows on/off. Returns an error message to show, or null.</summary>
    string? SetLaunchAtLogin(bool enabled);

    /// <summary>Adds / removes "Open with Glance" in Explorer. Returns an error message to show, or null.</summary>
    string? SetExplorerIntegration(bool enabled);

    bool ExplorerIntegrationInstalled { get; }
}
