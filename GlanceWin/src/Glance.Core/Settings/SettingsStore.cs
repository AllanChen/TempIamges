using System.Text.Json;
using System.Text.Json.Serialization;
using Glance.Core.Logging;

namespace Glance.Core.Settings;

/// <summary>
/// Loads and saves <see cref="AppSettings"/> as JSON. Writes are atomic (temp file + replace)
/// so a crash mid-save never leaves a corrupt file. A corrupt or missing file falls back to defaults.
/// Thread-safe: <see cref="Current"/> may be read from any thread.
/// </summary>
public sealed class SettingsStore
{
    internal static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private readonly string _path;
    private readonly object _lock = new();
    private AppSettings _current;

    public SettingsStore(string path)
    {
        _path = path;
        IsFirstRun = !File.Exists(path);
        _current = IsFirstRun ? AppSettings.ForSystem(System.Globalization.CultureInfo.CurrentUICulture.Name) : Load(path);
    }

    /// <summary>Raised after a successful update, on the thread that called <see cref="Update"/>.</summary>
    public event EventHandler<AppSettings>? Changed;

    public AppSettings Current
    {
        get { lock (_lock) return _current; }
    }

    public void Update(Func<AppSettings, AppSettings> change)
    {
        AppSettings updated;
        lock (_lock)
        {
            updated = change(_current);
            if (updated == _current) return;
            _current = updated;
            Save(_path, updated);
        }
        Changed?.Invoke(this, updated);
    }

    /// <summary>Back to defaults (the language is re-detected; first-run flags and the Home size are kept).</summary>
    public void ResetToDefaults() => Update(current => AppSettings.ForSystem(System.Globalization.CultureInfo.CurrentUICulture.Name) with
    {
        OnboardingShown = current.OnboardingShown,
        HasOfferedDefaultViewer = current.HasOfferedDefaultViewer,
        HomeWidth = current.HomeWidth,
        HomeHeight = current.HomeHeight,
    });

    /// <summary>True when there was no settings file at start-up (a fresh install).</summary>
    public bool IsFirstRun { get; private set; }

    private static AppSettings Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new AppSettings();
            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), JsonOptions) ?? new AppSettings();
            return settings.Hotkey.IsValid ? settings : settings with { Hotkey = Hotkey.Default };
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            Log.Warning($"Settings unreadable, using defaults: {ex.Message}");
            return new AppSettings();
        }
    }

    private static void Save(string path, AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temp = path + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(settings, JsonOptions));
            File.Move(temp, path, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Error("Failed to save settings", ex);
        }
    }
}
