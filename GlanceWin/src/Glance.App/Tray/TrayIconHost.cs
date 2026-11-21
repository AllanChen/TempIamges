using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Shell;
using Glance.Core;
using Glance.Core.Logging;
using Glance.Core.Settings;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App.Tray;

/// <summary>
/// Notification-area icon (port of macOS <c>StatusBarController</c>): the drawn character icon,
/// left click toggles the <see cref="TrayPopover"/>, right click opens the fallback menu. The
/// character covers its eyes while Peek is off and looks around while Widget tasks run.
/// </summary>
internal sealed class TrayIconHost : IDisposable
{
    private static readonly TimeSpan FrameInterval = TimeSpan.FromMilliseconds(280);

    /// <summary>macOS sequence: [left, centre, right, centre] × 3, then a blink.</summary>
    private static readonly CharacterState[] RunningFrames = BuildFrames();

    private readonly SettingsStore _settings;
    private readonly AppPaths _paths;
    private readonly TrayIcon _icon;
    private readonly DispatcherTimer _animation = new() { Interval = FrameInterval };
    private ContextMenu _menu;
    private IAppShell? _shell;
    private TrayPopover? _popover;
    private bool _hotkeyRegistered = true;
    private CharacterState? _shownState;
    private int _frame;

    public TrayIconHost(SettingsStore settings, AppPaths paths)
    {
        _settings = settings;
        _paths = paths;
        _menu = BuildMenu();
        _icon = new TrayIcon("Glance");
        _icon.LeftClicked += (_, _) => OnLeftClick();
        _icon.RightClicked += (_, _) => OpenMenu();
        _animation.Tick += (_, _) => NextFrame();
        Refresh();
        if (!_icon.Show()) throw new InvalidOperationException("Shell_NotifyIcon could not add the icon.");
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
    }

    public event EventHandler? QuitRequested;
    public event EventHandler? PeekClipboardRequested;
    public event EventHandler? AccountRequested;
    public event EventHandler? MarketRequested;
    public event EventHandler? TaskCenterRequested;

    /// <summary>Connects the popover, menu actions and task-driven animation. Call once on the UI thread.</summary>
    public void AttachShell(IAppShell shell)
    {
        _shell = shell;
        shell.Account.Tasks.Changed += (_, _) => Refresh();
        shell.HotkeyStateChanged += (_, _) => Refresh();
        _menu = BuildMenu();
        Refresh();
    }

    /// <summary>Rebuilds the menu and popover with the current <see cref="L"/> strings.</summary>
    public void RebuildForLanguage()
    {
        if (_menu.IsOpen) _menu.IsOpen = false;
        _menu = BuildMenu();
        if (_popover is not null)
        {
            _popover.Close();
            _popover = null;
        }
        Refresh();
    }

    /// <summary>A Windows notification from the tray icon; clicking it runs <paramref name="onClick"/>.</summary>
    public void ShowNotification(string title, string message, Action? onClick = null) =>
        _icon.ShowNotification(title, message, onClick: onClick);

    /// <summary>Shows whether the activation hotkey could be registered.</summary>
    public void SetHotkeyRegistered(bool registered)
    {
        _hotkeyRegistered = registered;
        Refresh();
    }

    /// <summary>Re-reads settings into the icon and tooltip. Call on the UI thread.</summary>
    public void Refresh()
    {
        var current = _settings.Current;
        var hotkey = current.Hotkey.DisplayText;
        _icon.ToolTip = !current.PeekEnabled ? L.T("Glance, Peek off")
            : !_hotkeyRegistered ? L.F("Hotkey %@ is used by another app", hotkey)
            : IsTaskRunning ? L.T("Glance, Widget task running")
            : $"Glance — {hotkey}";
        UpdateIcon();
    }

    private bool IsTaskRunning => _shell?.Account.Tasks.Records.Any(r => r.IsActive) == true;

    // ───────────────────────────── Clicks ─────────────────────────────

    private void OnLeftClick()
    {
        if (_shell is null)
        {
            OpenMenu();
            return;
        }
        _popover ??= new TrayPopover(_shell);
        _icon.PrepareForMenu();
        _popover.Toggle();
    }

    private void OpenMenu()
    {
        Refresh();
        _icon.PrepareForMenu();
        _menu.IsOpen = true;
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu { Placement = PlacementMode.MousePoint };
        MenuItem Item(string title, Action action)
        {
            var item = new MenuItem { Header = title };
            item.Click += (_, _) => action();
            return item;
        }
        if (_shell is { } shell)
        {
            menu.Items.Add(Item(L.T("Open Home"), shell.ShowHome));
            menu.Items.Add(Item(L.T("Preferences..."), shell.ShowPreferences));
        }
        else
        {
            menu.Items.Add(Item(L.T("Peek Clipboard Text"), () => PeekClipboardRequested?.Invoke(this, EventArgs.Empty)));
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("Widget Market…"), () => MarketRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(Item(L.T("Task Center"), () => TaskCenterRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(Item(L.T("Account and Credits…"), () => AccountRequested?.Invoke(this, EventArgs.Empty)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("Show Log File"), RevealLogFile));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("Quit Glance"), () => QuitRequested?.Invoke(this, EventArgs.Empty)));
        return menu;
    }

    // ───────────────────────────── Character ─────────────────────────────

    /// <summary>Peek off → hands over the eyes; tasks running → look around (unless animations are off); else default.</summary>
    private void UpdateIcon()
    {
        if (!_settings.Current.PeekEnabled)
        {
            _animation.Stop();
            ShowState(CharacterState.PeekOff);
            return;
        }
        if (IsTaskRunning && SystemParameters.ClientAreaAnimation)
        {
            if (!_animation.IsEnabled)
            {
                _frame = 0;
                _animation.Start();
                ShowState(RunningFrames[0]);
            }
            return;
        }
        _animation.Stop();
        ShowState(CharacterState.Default);
    }

    private void NextFrame()
    {
        _frame = (_frame + 1) % RunningFrames.Length;
        ShowState(RunningFrames[_frame]);
    }

    private void ShowState(CharacterState state, bool force = false)
    {
        if (!force && _shownState == state) return;
        try
        {
            var handle = CharacterIcon.Render(state);
            if (handle == IntPtr.Zero) return;
            _icon.SetIcon(handle);
            _shownState = state;
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException or System.Runtime.InteropServices.COMException)
        {
            Log.Warning($"Tray: character icon failed: {ex.Message}");
        }
    }

    private void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        // Light / dark taskbar switches arrive as General.
        if (e.Category == UserPreferenceCategory.General)
            Application.Current?.Dispatcher.BeginInvoke(new Action(RerenderIcon));
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) =>
        Application.Current?.Dispatcher.BeginInvoke(new Action(RerenderIcon));

    private void RerenderIcon()
    {
        if (_shownState is { } state) ShowState(state, force: true);
    }

    private static CharacterState[] BuildFrames()
    {
        var frames = new List<CharacterState>();
        for (var i = 0; i < 3; i++)
            frames.AddRange([CharacterState.LookLeft, CharacterState.Default, CharacterState.LookRight, CharacterState.Default]);
        frames.Add(CharacterState.Blink);
        return frames.ToArray();
    }

    private void RevealLogFile()
    {
        var target = File.Exists(_paths.LogFile) ? $"/select,\"{_paths.LogFile}\"" : $"\"{_paths.DataDirectory}\"";
        Process.Start(new ProcessStartInfo("explorer.exe", target) { UseShellExecute = true });
    }

    public void Dispose()
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        _animation.Stop();
        _popover?.Close();
        _icon.Dispose();
    }
}
