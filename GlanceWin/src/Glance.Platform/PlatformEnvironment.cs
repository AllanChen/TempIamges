using System.Diagnostics;
using System.Runtime.InteropServices;
using Glance.Core.Search;
using Glance.Platform.Interop;

namespace Glance.Platform;

/// <summary>Windows locations and foreground-app facts.</summary>
public static class PlatformEnvironment
{
    private static readonly Guid DownloadsFolderId = new("374DE290-123F-4565-9164-39C4925E467B");

    /// <summary>Downloads honoring user relocation (not always %USERPROFILE%\Downloads).</summary>
    public static string DownloadsFolder()
    {
        if (Native.SHGetKnownFolderPath(DownloadsFolderId, 0, IntPtr.Zero, out var ptr) == 0 && ptr != IntPtr.Zero)
        {
            try
            {
                var path = Marshal.PtrToStringUni(ptr);
                if (!string.IsNullOrEmpty(path)) return path;
            }
            finally
            {
                Native.CoTaskMemFree(ptr);
            }
        }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }

    /// <summary>
    /// Search folders: home, (possibly OneDrive-redirected) Desktop/Documents, Downloads, and the
    /// roots of non-system fixed drives — Windows users often keep projects on D:\.
    /// </summary>
    public static ResolverEnvironment CreateResolverEnvironment()
    {
        var systemDrive = Path.GetPathRoot(Environment.SystemDirectory) ?? @"C:\";
        var extraRoots = DriveInfo.GetDrives()
            .Where(d => d.DriveType == DriveType.Fixed && SafeIsReady(d))
            .Select(d => d.RootDirectory.FullName)
            .Where(r => !string.Equals(r, systemDrive, StringComparison.OrdinalIgnoreCase))
            .ToList();

        return new ResolverEnvironment(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            DownloadsFolder(),
            extraRoots);
    }

    /// <summary>Display name of the app owning the foreground window, e.g. "Visual Studio Code".</summary>
    public static string? ForegroundAppName()
    {
        try
        {
            var hwnd = Native.GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return null;
            Native.GetWindowThreadProcessId(hwnd, out var pid);
            using var process = Process.GetProcessById((int)pid);
            try
            {
                var description = process.MainModule?.FileVersionInfo.FileDescription;
                if (!string.IsNullOrWhiteSpace(description)) return description;
            }
            catch (Exception)
            {
                // Elevated or protected process: module info is not readable.
            }
            return process.ProcessName;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static bool SafeIsReady(DriveInfo drive)
    {
        try { return drive.IsReady; }
        catch (IOException) { return false; }
    }
}
