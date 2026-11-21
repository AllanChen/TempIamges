using System.IO;
using System.Reflection;
using Glance.Core.Localization;
using Glance.Core.Logging;
using Glance.Core.Settings;

namespace Glance.App.Localization;

/// <summary>
/// UI strings. Keys are the English source strings used by the macOS app (<c>"…".localized</c>);
/// Chinese comes from the macOS <c>zh-Hans.lproj/Localizable.strings</c>, embedded as-is. Missing
/// keys fall back to English. Windows read strings when they're built, so a language switch
/// applies to windows opened afterwards (the app rebuilds its long-lived windows).
/// </summary>
public static class L
{
    internal const string ChineseResource = "Glance.Localization.zh-Hans.strings";
    internal const string WindowsChineseResource = "Glance.Localization.zh-Hans.windows.strings";
    private static IReadOnlyDictionary<string, string>? _table;

    public static AppLanguage Current { get; private set; } = AppLanguage.English;

    /// <summary>Culture for dates and weekday names in the app language (not the Windows display language).</summary>
    public static System.Globalization.CultureInfo Culture =>
        System.Globalization.CultureInfo.GetCultureInfo(Current == AppLanguage.English ? "en-US" : "zh-CN");

    /// <summary>Installs a translation table. Pass null for English.</summary>
    public static void Use(IReadOnlyDictionary<string, string>? table) => _table = table;

    /// <summary>Switches the UI language (English needs no table).</summary>
    public static void Apply(AppLanguage language)
    {
        Current = language;
        if (language == AppLanguage.English)
        {
            _table = null;
            return;
        }
        var macos = ReadResource(ChineseResource);
        var windows = ReadResource(WindowsChineseResource);
        if (macos is null && windows is null)
        {
            _table = null;
            return;
        }
        var merged = new Dictionary<string, string>(macos ?? new Dictionary<string, string>(), StringComparer.Ordinal);
        foreach (var (key, value) in windows ?? new Dictionary<string, string>()) merged[key] = value;
        _table = merged;
        Log.Info($"Localization: zh-Hans ({macos?.Count ?? 0} macOS + {windows?.Count ?? 0} Windows strings)");
    }

    /// <summary>Parses an embedded <c>.strings</c> resource; null (logged) when missing or unreadable.</summary>
    internal static IReadOnlyDictionary<string, string>? ReadResource(string name)
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
            if (stream is null)
            {
                Log.Warning($"Localization: {name} is missing from the build");
                return null;
            }
            using var reader = new StreamReader(stream);
            return StringsFile.Parse(reader.ReadToEnd());
        }
        catch (IOException ex)
        {
            Log.Warning($"Localization: could not read {name}: {ex.Message}");
            return null;
        }
    }

    public static string T(string english) =>
        _table is not null && _table.TryGetValue(english, out var translated) ? translated : english;

    /// <summary>Formats a macOS-style key (<c>%@</c>, <c>%d</c>, positional <c>%1$@</c>).</summary>
    public static string F(string englishFormat, params object[] args) => StringsFile.Format(T(englishFormat), args);
}
