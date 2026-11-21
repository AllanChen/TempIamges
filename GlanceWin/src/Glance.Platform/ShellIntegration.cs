using Glance.Core.Detection;
using Glance.Core.Logging;
using Microsoft.Win32;

namespace Glance.Platform;

/// <summary>
/// Start with Windows: the per-user <c>Run</c> key (no admin; Task Manager ▸ Startup can disable it,
/// which Windows records under <c>StartupApproved</c>). Port of macOS <c>SMAppService.mainApp</c>.
/// </summary>
public static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string ValueName = "Glance";

    public static bool IsEnabled(string exePath)
    {
        using var run = Registry.CurrentUser.OpenSubKey(RunKey);
        if (run?.GetValue(ValueName) is not string command || !command.Contains(exePath, StringComparison.OrdinalIgnoreCase)) return false;
        // StartupApproved: first byte 0x02/0x06 = enabled, 0x03/0x07 = disabled in Task Manager.
        using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
        return approved?.GetValue(ValueName) is not byte[] { Length: > 0 } state || (state[0] & 0x01) == 0;
    }

    /// <summary>Turns autostart on/off. Throws on registry errors so the caller can tell the user.</summary>
    public static void Set(string exePath, bool enabled)
    {
        using var run = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled)
        {
            run.SetValue(ValueName, $"\"{exePath}\" --background");
            // Re-enable if the user had disabled it in Task Manager.
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey, writable: true);
            if (approved?.GetValue(ValueName) is not null) approved.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        else
        {
            run.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        Log.Info($"Autostart: {(enabled ? "enabled" : "disabled")}");
    }
}

/// <summary>
/// Explorer integration (Windows counterpart of the macOS "Open With" / Services entries):
/// "Open with Glance" on image and video files, and Glance in the "Open with" list. Per user (HKCU).
/// </summary>
public static class ExplorerIntegration
{
    private const string AppKey = @"Software\Classes\Applications\Glance.exe";
    private static readonly string[] Perceived = ["image", "video"];

    public static bool IsInstalled(string exePath)
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Classes\SystemFileAssociations\image\shell\Glance\command");
        return key?.GetValue(null) is string command && command.Contains(exePath, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Adds the context-menu verb and the "Open with" entry. Throws on registry errors.</summary>
    public static void Install(string exePath, string verbTitle)
    {
        var command = $"\"{exePath}\" \"%1\"";
        foreach (var kind in Perceived)
        {
            using var verb = Registry.CurrentUser.CreateSubKey($@"Software\Classes\SystemFileAssociations\{kind}\shell\Glance");
            verb.SetValue(null, verbTitle);
            verb.SetValue("Icon", $"\"{exePath}\",0");
            // Several selected files arrive in one launch (single-instance forwarding).
            verb.SetValue("MultiSelectModel", "Player");
            using var cmd = verb.CreateSubKey("command");
            cmd.SetValue(null, command);
        }
        using (var app = Registry.CurrentUser.CreateSubKey(AppKey))
        {
            app.SetValue("FriendlyAppName", "Glance");
            using (var cmd = app.CreateSubKey(@"shell\open\command")) cmd.SetValue(null, command);
            using var types = app.CreateSubKey("SupportedTypes");
            foreach (var ext in FileKinds.Image.Concat(FileKinds.Video))
                types.SetValue("." + ext.TrimStart('.'), "");
        }
        NotifyAssociationsChanged();
        Log.Info("ExplorerIntegration: installed");
    }

    public static void Uninstall()
    {
        foreach (var kind in Perceived)
            Registry.CurrentUser.DeleteSubKeyTree($@"Software\Classes\SystemFileAssociations\{kind}\shell\Glance", throwOnMissingSubKey: false);
        Registry.CurrentUser.DeleteSubKeyTree(AppKey, throwOnMissingSubKey: false);
        NotifyAssociationsChanged();
        Log.Info("ExplorerIntegration: removed");
    }

    /// <summary>Opens Settings ▸ Default apps so the user can pick Glance (Windows doesn't allow apps to set it).</summary>
    public static void OpenDefaultAppsSettings() => ShellActions.Open("ms-settings:defaultapps");

    private static void NotifyAssociationsChanged() => SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);

    [System.Runtime.InteropServices.DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
