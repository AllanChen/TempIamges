using Glance.Core.Settings;
using Xunit;

namespace Glance.Tests;

public sealed class SettingsStoreTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "GlanceTests", Guid.NewGuid().ToString("N"));
    private string SettingsPath => Path.Combine(_dir, "settings.json");

    [Fact]
    public void MissingFileUsesWindowsDefaults()
    {
        var store = new SettingsStore(SettingsPath);

        Assert.True(store.Current.PeekEnabled);
        Assert.True(store.Current.ReadClipboard);
        Assert.Equal(Hotkey.Default, store.Current.Hotkey);
        Assert.Equal(HotkeyModifiers.Alt, store.Current.Hotkey.Modifiers);
        Assert.Equal(Hotkey.VkQ, store.Current.Hotkey.VirtualKey);
    }

    [Fact]
    public void UpdatePersistsAndReloads()
    {
        var store = new SettingsStore(SettingsPath);
        store.Update(s => s with
        {
            PeekEnabled = false,
            Language = AppLanguage.Chinese,
            Hotkey = new Hotkey(HotkeyModifiers.Control | HotkeyModifiers.Shift, 0x47),
        });

        var reloaded = new SettingsStore(SettingsPath).Current;
        Assert.False(reloaded.PeekEnabled);
        Assert.Equal(AppLanguage.Chinese, reloaded.Language);
        Assert.Equal(new Hotkey(HotkeyModifiers.Control | HotkeyModifiers.Shift, 0x47), reloaded.Hotkey);
        Assert.Contains("\"zh-Hans\"", File.ReadAllText(SettingsPath));
    }

    [Fact]
    public void ChangedFiresOnlyForRealChanges()
    {
        var store = new SettingsStore(SettingsPath);
        var count = 0;
        store.Changed += (_, _) => count++;

        store.Update(s => s);
        store.Update(s => s with { PeekEnabled = true });
        Assert.Equal(0, count);

        store.Update(s => s with { PeekEnabled = false });
        Assert.Equal(1, count);
    }

    [Fact]
    public void CorruptFileFallsBackToDefaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(SettingsPath, "{ not json");

        Assert.Equal(new AppSettings(), new SettingsStore(SettingsPath).Current);
    }

    [Fact]
    public void InvalidHotkeyFallsBackToDefaultHotkey()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(SettingsPath, """{ "peekEnabled": false, "hotkey": { "modifiers": "none", "virtualKey": 81 } }""");

        var settings = new SettingsStore(SettingsPath).Current;
        Assert.False(settings.PeekEnabled);
        Assert.Equal(Hotkey.Default, settings.Hotkey);
    }

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }
}
