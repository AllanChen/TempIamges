using System.Security.Cryptography;
using System.Text;
using Glance.Core.Account;
using Glance.Core.Logging;
using Microsoft.Win32;

namespace Glance.Platform;

/// <summary>
/// Per-user secrets encrypted with DPAPI (CurrentUser scope), one file per key under
/// <c>%APPDATA%\Glance\secure</c>. Port of the macOS secure store (UserDefaults / Keychain).
/// </summary>
public sealed class DpapiSecureStore(string folder) : ISecureStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Glance.SecureStore.v1");

    public string? Read(string key)
    {
        var path = PathFor(key);
        if (!File.Exists(path)) return null;
        var bytes = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
        return Encoding.UTF8.GetString(bytes);
    }

    public void Write(string key, string value)
    {
        Directory.CreateDirectory(folder);
        var protectedBytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), Entropy, DataProtectionScope.CurrentUser);
        var path = PathFor(key);
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, protectedBytes);
        File.Move(temp, path, overwrite: true);
    }

    public void Delete(string key)
    {
        var path = PathFor(key);
        if (File.Exists(path)) File.Delete(path);
    }

    private string PathFor(string key) =>
        Path.Combine(folder, string.Concat(key.Select(c => char.IsLetterOrDigit(c) || c is '.' or '-' or '_' ? c : '_')) + ".bin");
}

/// <summary>
/// Registers <c>glance://</c> for the current user (HKCU, no admin) so the browser can hand
/// sign-in and payment returns back to Glance: <c>"Glance.exe" "%1"</c>.
/// </summary>
public static class ProtocolRegistration
{
    private const string Scheme = "glance";

    public static void EnsureRegistered(string exePath)
    {
        try
        {
            var command = $"\"{exePath}\" \"%1\"";
            using var root = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{Scheme}");
            using var commandKey = root.CreateSubKey(@"shell\open\command");
            if (commandKey.GetValue(null) as string == command) return;
            root.SetValue(null, "URL:Glance");
            root.SetValue("URL Protocol", "");
            using (var icon = root.CreateSubKey("DefaultIcon")) icon.SetValue(null, $"\"{exePath}\",0");
            commandKey.SetValue(null, command);
            Log.Info("ProtocolRegistration: glance:// registered");
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            Log.Warning($"ProtocolRegistration: could not register glance://: {ex.Message}");
        }
    }
}
