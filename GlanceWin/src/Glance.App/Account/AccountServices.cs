using System.Net.Http;
using System.Windows;
using Glance.App.Localization;
using Glance.Core;
using Glance.Core.Account;
using Glance.Core.Billing;
using Glance.Core.Settings;
using Glance.Core.Tasks;
using Glance.Core.Widgets;
using Glance.Platform;

namespace Glance.App.Account;

/// <summary>
/// The Phase 5 services in one place (macOS singletons: <c>AuthManager</c>, <c>BillingManager</c>,
/// <c>WidgetRegistry</c>, <c>WidgetTaskManager</c>). Created on the UI thread; <see cref="Changed"/>
/// (sign-in / credits) and the registry / task events are raised on the UI thread.
/// </summary>
internal sealed class AccountServices
{
    private readonly SettingsStore _settings;

    public AccountServices(AppPaths paths, SettingsStore settings)
    {
        _settings = settings;
        Http = new HttpClient(new SocketsHttpHandler { PooledConnectionLifetime = TimeSpan.FromMinutes(5), AutomaticDecompression = System.Net.DecompressionMethods.All })
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        Http.DefaultRequestHeaders.UserAgent.ParseAdd($"Glance-Windows/{typeof(AccountServices).Assembly.GetName().Version}");
        Auth = new AuthService(Http, new DpapiSecureStore(paths.SecureDirectory));
        Billing = new BillingClient(Http, Auth);
        Registry = new WidgetRegistry(paths.WidgetsFile);
        Market = new WidgetMarketClient(Http, Registry);
        Tasks = new WidgetTaskManager(new WidgetTaskClient(Http, Auth, Registry), Registry, Auth, paths.WidgetTasksFile, AppPaths.DownloadsGlanceDirectory);

        var dispatcher = Application.Current.Dispatcher;
        Auth.Changed += (_, _) => dispatcher.BeginInvoke(() =>
        {
            Changed?.Invoke(this, EventArgs.Empty);
            if (Auth.IsSignedIn) Tasks.ReconcileAll();
        });
        Registry.Changed += (_, _) => dispatcher.BeginInvoke(() => WidgetsChanged?.Invoke(this, EventArgs.Empty));
    }

    public HttpClient Http { get; }
    public AuthService Auth { get; }
    public BillingClient Billing { get; }
    public WidgetRegistry Registry { get; }
    public WidgetMarketClient Market { get; }
    public WidgetTaskManager Tasks { get; }

    /// <summary>Sign-in state or credits changed (UI thread).</summary>
    public event EventHandler? Changed;

    /// <summary>Widgets installed / removed / delisted (UI thread).</summary>
    public event EventHandler? WidgetsChanged;

    /// <summary>Widget manifest language tag for the app language.</summary>
    public string Language => _settings.Current.Language switch
    {
        AppLanguage.Chinese => "zh-Hans",
        _ => "en",
    };

    public int? Credits => Auth.Session?.User.Credits;

    public async Task StartAsync()
    {
        await Tasks.StartUpAsync();
        if (Auth.IsSignedIn) _ = Auth.RefreshAccountAsync();
        if (Registry.Installed.Count > 0)
        {
            try
            {
                await Market.FetchCatalogAsync();
            }
            catch (ApiException)
            {
                // Offline: keep the installed list as it is.
            }
        }
    }
}

/// <summary>Localized labels shared by the Market, menus, input panels and Task Center.</summary>
internal static class WidgetText
{
    /// <summary>"3 credits / task", "1 credit / task" or "N credits / 10 seconds".</summary>
    public static string CostLabel(WidgetManifest widget)
    {
        var cost = widget.TaskCreditCost;
        if (widget.UsesDurationBilling) return L.F("%d credits / 10 seconds", cost);
        return cost == 1 ? L.F("%d credit / task", cost) : L.F("%d credits / task", cost);
    }

    /// <summary>"Free of charge" or the cost label.</summary>
    public static string CostText(WidgetManifest widget) => widget.TaskCreditCost == 0 ? L.T("Free of charge") : CostLabel(widget);

    /// <summary>Market row price: "Free", the duration label, or "N credits".</summary>
    public static string PriceTag(WidgetManifest widget)
    {
        var cost = widget.TaskCreditCost;
        if (cost == 0) return L.T("Free");
        if (widget.UsesDurationBilling) return L.F("%d credits / 10 seconds", cost);
        return cost == 1 ? L.F("%d credit", cost) : L.F("%d credits", cost);
    }

    /// <summary>Menu badge: "Free of charge" or the bare number.</summary>
    public static string MenuBadge(WidgetManifest widget) =>
        widget.TaskCreditCost == 0 ? L.T("Free of charge") : widget.TaskCreditCost.ToString(System.Globalization.CultureInfo.InvariantCulture);

    public static string? BillingStatus(WidgetTaskRecord record) =>
        record.BillingStatus is { } status ? status.Value is { } v ? L.F(status.Format, v) : L.T(status.Format) : null;

    public static string? QueueStatus(WidgetTaskRecord record) =>
        record.QueueStatus is { } q ? L.F(q.Format, q.Args) : null;

    /// <summary>Task state for lists: queue text, or Running… / Preparing / Uploading / … / Done / Failed.</summary>
    public static string State(WidgetTaskRecord record) => QueueStatus(record) ?? record.Phase switch
    {
        WidgetTaskPhase.Uploading when record.IsPreparing => L.T("Preparing"),
        WidgetTaskPhase.Uploading => L.T("Uploading"),
        WidgetTaskPhase.Submitting => L.T("Submitting"),
        WidgetTaskPhase.Processing => L.T("Running…"),
        WidgetTaskPhase.Downloading => L.T("Downloading"),
        WidgetTaskPhase.Completed => L.T("Done"),
        WidgetTaskPhase.Failed => L.T("Failed"),
        WidgetTaskPhase.Interrupted => L.T("Interrupted"),
        WidgetTaskPhase.Cancelled => L.T("Cancelled"),
        WidgetTaskPhase.Expired => L.T("Expired"),
        _ => "",
    };

    /// <summary>Theme brush for a task state: info while active, failure, tertiary for cancelled, success.</summary>
    public static string StateBrush(WidgetTaskRecord record) => record.IsActive ? "InfoBrush"
        : record.IsFailure ? "FailureBrush"
        : record.Phase == WidgetTaskPhase.Cancelled ? "TextTertiaryBrush"
        : "SuccessBrush";

    /// <summary>"Image + Video" style input / output kinds.</summary>
    public static string Kinds(IEnumerable<string> kinds) =>
        string.Join(" + ", kinds.Distinct(StringComparer.OrdinalIgnoreCase).Select(k => L.T(char.ToUpperInvariant(k[0]) + k[1..])));
}
