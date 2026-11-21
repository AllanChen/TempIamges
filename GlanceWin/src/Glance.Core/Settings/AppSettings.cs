using System.Text.Json.Serialization;

namespace Glance.Core.Settings;

/// <summary>Hotkey modifiers, values match Win32 <c>MOD_*</c> flags used by <c>RegisterHotKey</c>.</summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Win = 0x0008,
}

/// <param name="Modifiers">Required modifier keys.</param>
/// <param name="VirtualKey">Win32 virtual-key code of the non-modifier key (e.g. 0x51 = Q).</param>
public sealed record Hotkey(HotkeyModifiers Modifiers, int VirtualKey)
{
    public const int VkQ = 0x51;

    /// <summary>Windows default. macOS uses Option+Space, but Alt+Space is the window system menu.</summary>
    public static Hotkey Default { get; } = new(HotkeyModifiers.Alt, VkQ);

    [JsonIgnore]
    public bool IsValid => Modifiers != HotkeyModifiers.None && VirtualKey is > 0 and < 0xFF;

    /// <summary>Human-readable form, e.g. "Ctrl+Alt+Q".</summary>
    [JsonIgnore]
    public string DisplayText
    {
        get
        {
            var parts = new List<string>();
            if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
            if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
            parts.Add(KeyName(VirtualKey));
            return string.Join("+", parts);
        }
    }

    public static string KeyName(int vk) => vk switch
    {
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x70 and <= 0x87 => $"F{vk - 0x6F}",
        0x20 => "Space",
        0x0D => "Enter",
        0x09 => "Tab",
        0xC0 => "`",
        0xBA => ";",
        0xBC => ",",
        0xBE => ".",
        0xBF => "/",
        _ => $"0x{vk:X2}",
    };
}

public enum AppLanguage
{
    [JsonStringEnumMemberName("en")] English,
    [JsonStringEnumMemberName("zh-Hans")] Chinese,
}

/// <summary>
/// User preferences (port of macOS <c>Preferences</c>). Immutable; change with <c>with</c>
/// and save through <see cref="SettingsStore.Update"/>. There is no theme setting:
/// the Windows client is light-only.
/// </summary>
public sealed record AppSettings
{
    /// <summary>
    /// Peek (select text anywhere, press the hotkey). Opt-in on macOS only because it needs
    /// TCC permissions; Windows needs none, so it is on by default.
    /// </summary>
    public bool PeekEnabled { get; init; } = true;

    public Hotkey Hotkey { get; init; } = Hotkey.Default;

    /// <summary>Allow the Ctrl+C clipboard fallback when UI Automation finds no selection.</summary>
    public bool ReadClipboard { get; init; } = true;

    public bool LaunchAtLogin { get; init; }

    public AppLanguage Language { get; init; } = AppLanguage.English;

    /// <summary>One-time "make Glance the default image viewer?" offer was shown.</summary>
    public bool HasOfferedDefaultViewer { get; init; }

    public string? LoginUrl { get; init; }

    /// <summary>The first-run guide was shown and closed (macOS <c>permissionSetupDismissed</c>).</summary>
    public bool OnboardingShown { get; init; }

    /// <summary>Home window size the user chose (DIPs); restored when at least 900 × 580.</summary>
    public double? HomeWidth { get; init; }
    public double? HomeHeight { get; init; }

    /// <summary>The folder last opened from Home (its strip shows under the drop zone).</summary>
    public string? HomeLastFolder { get; init; }

    /// <summary>
    /// Defaults for a new install: the UI language follows the primary system language (macOS
    /// <c>SystemLanguage</c>: Simplified Chinese for zh / zh-Hans / zh-CN / zh-SG, English otherwise,
    /// including Traditional Chinese, which has no translation yet).
    /// </summary>
    public static AppSettings ForSystem(string uiCultureName) => new() { Language = LanguageFor(uiCultureName) };

    public static AppLanguage LanguageFor(string cultureName)
    {
        var name = cultureName.Replace('_', '-').ToLowerInvariant();
        if (!name.StartsWith("zh", StringComparison.Ordinal)) return AppLanguage.English;
        if (name.Contains("hant") || name.EndsWith("-tw") || name.EndsWith("-hk") || name.EndsWith("-mo")) return AppLanguage.English;
        return AppLanguage.Chinese;
    }
}
