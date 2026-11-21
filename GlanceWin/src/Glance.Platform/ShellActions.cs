using System.Diagnostics;
using Glance.Core.Logging;

namespace Glance.Platform;

/// <summary>Open files/URLs with their default handler and reveal files in Explorer.</summary>
public static class ShellActions
{
    public static void Open(string pathOrUrl)
    {
        try
        {
            Process.Start(new ProcessStartInfo(pathOrUrl) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or FileNotFoundException)
        {
            Log.Warning($"ShellActions.Open failed for '{Log.Redact(pathOrUrl)}': {ex.Message}");
        }
    }

    /// <summary>Opens Explorer with the item selected (folders open themselves).</summary>
    public static void RevealInExplorer(string path)
    {
        try
        {
            var args = Directory.Exists(path) && !File.Exists(path) ? $"\"{path}\"" : $"/select,\"{path}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", args) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Log.Warning($"ShellActions.RevealInExplorer failed: {ex.Message}");
        }
    }
}
