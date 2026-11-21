namespace Glance.Core;

/// <summary>
/// Where Glance keeps its data. Mirrors macOS <c>~/Library/Application Support/Glance</c>:
/// durable data (settings, history, log) roams in %APPDATA%, rebuildable caches stay in %LOCALAPPDATA%.
/// </summary>
public sealed class AppPaths
{
    public static AppPaths Default { get; } = new(
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Glance"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Glance"));

    public AppPaths(string dataDirectory, string cacheDirectory)
    {
        DataDirectory = dataDirectory;
        CacheDirectory = cacheDirectory;
    }

    public string DataDirectory { get; }
    public string CacheDirectory { get; }

    public string SettingsFile => Path.Combine(DataDirectory, "settings.json");
    public string HistoryFile => Path.Combine(DataDirectory, "history.json");
    public string LogFile => Path.Combine(DataDirectory, "app.log");
    public string FilenameCacheFile => Path.Combine(CacheDirectory, "filename-cache.json");

    /// <summary>DPAPI-encrypted account session and device id.</summary>
    public string SecureDirectory => Path.Combine(DataDirectory, "secure");

    /// <summary>Installed Widget manifests (macOS kept them in UserDefaults).</summary>
    public string WidgetsFile => Path.Combine(DataDirectory, "widgets.json");

    /// <summary>Widget task history and pending settlements (macOS <c>widget-tasks.json</c>).</summary>
    public string WidgetTasksFile => Path.Combine(DataDirectory, "widget-tasks.json");

    /// <summary>Widget results and remote inputs: <c>Downloads\Glance</c>, as on macOS.</summary>
    public static string DownloadsGlanceDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Glance");
    /// <summary>WebView2 profile (cookies, cache) for the content viewer.</summary>
    public string WebViewDataDirectory => Path.Combine(CacheDirectory, "WebView2");

    /// <summary>
    /// Separate WebView2 profile for the Video Inspect fallback player: it needs an autoplay switch,
    /// and one profile can't be shared by environments created with different browser arguments.
    /// </summary>
    public string VideoWebViewDataDirectory => Path.Combine(CacheDirectory, "WebView2Video");

    public void EnsureCreated()
    {
        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(CacheDirectory);
    }
}
