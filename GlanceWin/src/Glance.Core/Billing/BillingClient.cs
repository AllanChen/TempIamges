using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Glance.Core.Account;

namespace Glance.Core.Billing;

/// <summary>A price in minor units (cents; JPY in whole yen) and optional points.</summary>
public sealed record BillingPrice(long Amount, int? Points);

/// <summary>A credit package (macOS <c>BillingPack</c>) with its price per currency.</summary>
public sealed record BillingPack(string Id, int Credits, int BonusCredits, IReadOnlyDictionary<string, BillingPrice> Prices, bool Recommended)
{
    public BillingPrice? PriceIn(string currency) => Prices.TryGetValue(currency.ToUpperInvariant(), out var p) ? p : null;
}

/// <summary>Public pricing (<c>GET /api/v2/pricing</c>), the parts the Windows client uses.</summary>
public sealed record BillingPricing(
    bool Enabled,
    int SignupCredits,
    IReadOnlyList<BillingPack> Packs,
    string? SupportEmail,
    string? TermsUrl,
    string? PrivacyUrl,
    string DefaultCurrency,
    bool PaymentsAvailable,
    bool MockCheckout);

public sealed record BillingTransaction(string Id, int Amount, string Reason, string? Note, DateTimeOffset? CreatedAt, string? WidgetName);

public sealed record BillingWallet(int Balance, IReadOnlyList<BillingTransaction> Transactions);

/// <summary>Price check before a task (<c>POST /api/v2/task-quotes</c>).</summary>
public sealed record WidgetTaskQuote(string QuoteId, string Mode, int UnitSeconds, int UnitPrice, int Units, int TotalCredits, DateTimeOffset? ExpiresAt, int Balance, int Shortfall, JsonObject? Evidence)
{
    public bool IsExpired(DateTimeOffset now) => ExpiresAt is { } e && e <= now;

    public JsonObject ToJson() => new()
    {
        ["quoteID"] = QuoteId,
        ["mode"] = Mode,
        ["unitSeconds"] = UnitSeconds,
        ["unitPrice"] = UnitPrice,
        ["units"] = Units,
        ["totalCredits"] = TotalCredits,
        ["expiresAt"] = ExpiresAt?.ToString("O", CultureInfo.InvariantCulture),
        ["balance"] = Balance,
        ["shortfall"] = Shortfall,
        ["evidence"] = Evidence?.DeepClone(),
    };

    public static WidgetTaskQuote? From(JsonNode? node)
    {
        if (node is not JsonObject o || ApiEnvelope.Text(o["quoteID"]) is not { } id) return null;
        return new WidgetTaskQuote(id, ApiEnvelope.Text(o["mode"]) ?? "task", ApiEnvelope.Int(o["unitSeconds"]) ?? 0,
            ApiEnvelope.Int(o["unitPrice"]) ?? 0, ApiEnvelope.Int(o["units"]) ?? 1, ApiEnvelope.Int(o["totalCredits"]) ?? 0,
            BillingClient.Date(o["expiresAt"]), ApiEnvelope.Int(o["balance"]) ?? 0, ApiEnvelope.Int(o["shortfall"]) ?? 0,
            o["evidence"]?.DeepClone() as JsonObject);
    }
}

public sealed record BillingOrder(string Id, string Product, string Currency, long Amount, int Credits, int BonusCredits, string Status, DateTimeOffset? CreatedAt, DateTimeOffset? ExpiresAt)
{
    public bool IsPaid => Status is "paid" or "refund_failed";
    public bool IsTerminal => Status is "paid" or "refund_failed" or "refunded" or "expired";
}

public sealed record BillingCheckout(BillingOrder Order, string? CheckoutUrl);

/// <summary>
/// Credits and quotes (port of the macOS <c>BillingManager</c> requests the Windows client needs).
/// Pro licences, devices, refunds and redeem codes are not ported yet.
/// </summary>
public sealed class BillingClient(HttpClient http, AuthService auth)
{
    public async Task<BillingPricing> FetchPricingAsync(CancellationToken ct = default)
    {
        var r = await SendAsync(HttpMethod.Get, "/api/v2/pricing", null, authenticated: false, ct).ConfigureAwait(false);
        var packs = (r?["packs"] as JsonArray ?? []).OfType<JsonObject>().Select(ParsePack).Where(p => p.Id.Length > 0).ToList();
        return new BillingPricing(
            ApiEnvelope.Bool(r?["enabled"]) == true,
            ApiEnvelope.Int(r?["signupCredits"]) ?? 100,
            packs,
            ApiEnvelope.Text(r?["supportEmail"]),
            HttpsOnly(ApiEnvelope.Text(r?["termsURL"])),
            HttpsOnly(ApiEnvelope.Text(r?["privacyURL"])),
            ApiEnvelope.Text(r?["defaultCurrency"]) ?? "USD",
            ApiEnvelope.Bool(r?["paymentsAvailable"]) == true,
            ApiEnvelope.Bool(r?["mockCheckout"]) == true);
    }

    public async Task<BillingWallet> FetchWalletAsync(CancellationToken ct = default)
    {
        var r = await SendAsync(HttpMethod.Get, "/api/v2/account/credits", null, authenticated: true, ct).ConfigureAwait(false);
        var transactions = (r?["transactions"] as JsonArray ?? []).OfType<JsonObject>().Select(t => new BillingTransaction(
            ApiEnvelope.Text(t["id"]) ?? ApiEnvelope.Int(t["id"])?.ToString(CultureInfo.InvariantCulture) ?? "",
            ApiEnvelope.Int(t["amount"]) ?? 0,
            ApiEnvelope.Text(t["reason"]) ?? "",
            ApiEnvelope.Text(t["note"]),
            Date(t["created_at"]),
            ApiEnvelope.Text(t["widget_name"]))).ToList();
        var balance = ApiEnvelope.Int(r?["balance"]) ?? auth.Session?.User.Credits ?? 0;
        if (auth.Session is { } session) auth.UpdateCredits(balance, session.Token);
        return new BillingWallet(balance, transactions);
    }

    public async Task<WidgetTaskQuote> QuoteAsync(string widgetId, string commandId, JsonObject? evidence, CancellationToken ct = default)
    {
        var body = new JsonObject { ["widgetID"] = widgetId, ["commandID"] = commandId };
        if (evidence is not null) body["evidence"] = evidence.DeepClone();
        var r = await SendAsync(HttpMethod.Post, "/api/v2/task-quotes", body, authenticated: true, ct).ConfigureAwait(false);
        return WidgetTaskQuote.From(r) ?? throw new ApiException("Could not read server response.", "bad_response");
    }

    /// <summary>Creates a credit top-up order; its <c>checkoutUrl</c> opens in the browser.</summary>
    public async Task<BillingCheckout> CreateCreditsOrderAsync(BillingPack pack, string currency, string language, string? intentId, CancellationToken ct = default)
    {
        var price = pack.PriceIn(currency) ?? throw new ApiException("This package isn't available in that currency.", "price_changed");
        var expected = new JsonObject { ["amount"] = price.Amount };
        if (price.Points is { } points) expected["points"] = points;
        var body = new JsonObject
        {
            ["product"] = "credits",
            ["currency"] = currency.ToUpperInvariant(),
            ["expectedPrice"] = expected,
            ["language"] = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh-Hans" : "en",
            ["packID"] = pack.Id,
        };
        if (intentId is not null) body["intentID"] = intentId;
        var r = await SendAsync(HttpMethod.Post, "/api/v2/orders", body, authenticated: true, ct, idempotencyKey: Guid.NewGuid().ToString()).ConfigureAwait(false);
        return ParseCheckout(r);
    }

    public async Task<(BillingOrder Order, int? Balance)> FetchOrderAsync(string orderId, CancellationToken ct = default)
    {
        var r = await SendAsync(HttpMethod.Get, $"/api/v2/orders/{Uri.EscapeDataString(orderId)}", null, authenticated: true, ct).ConfigureAwait(false);
        var order = ParseOrder(r?["order"] as JsonObject) ?? throw new ApiException("Could not read server response.", "bad_response");
        var balance = ApiEnvelope.Int(r?["balance"]);
        if (balance is { } b && auth.Session is { } session) auth.UpdateCredits(b, session.Token);
        return (order, balance);
    }

    public Task AbandonOrderAsync(string orderId, CancellationToken ct = default) =>
        SendAsync(HttpMethod.Post, $"/api/v2/orders/{Uri.EscapeDataString(orderId)}/abandon", new JsonObject(), authenticated: true, ct);

    // ───────────────────────────── Plumbing ─────────────────────────────

    private async Task<JsonNode?> SendAsync(HttpMethod method, string path, JsonObject? body, bool authenticated, CancellationToken ct, string? idempotencyKey = null)
    {
        var token = auth.Session?.Token;
        if (authenticated && token is null) throw new ApiException("Please sign in to continue.", "unauthorized", System.Net.HttpStatusCode.Unauthorized);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var request = new HttpRequestMessage(method, GlanceApi.BaseUrl + path);
        request.Headers.Add("X-Glance-Device", auth.DeviceId);
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (idempotencyKey is not null) request.Headers.Add("Idempotency-Key", idempotencyKey);
        if (body is not null) request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        try
        {
            var result = await ApiEnvelope.SendAsync(http, request, timeout.Token).ConfigureAwait(false);
            if (authenticated && auth.Session?.Token != token) throw new ApiException("The account changed. Please try again.", "account_changed");
            return result;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new ApiException("The request timed out.", "network");
        }
        catch (ApiException ex) when (ex.IsUnauthorized && token is not null)
        {
            auth.InvalidateOnlineSession(token);
            throw;
        }
    }

    private static BillingPack ParsePack(JsonObject p)
    {
        var prices = new Dictionary<string, BillingPrice>(StringComparer.OrdinalIgnoreCase);
        foreach (var currency in new[] { "CNY", "USD", "JPY", "EUR", "HKD" })
            if (p[currency] is JsonObject price && ApiEnvelope.Int(price["amount"]) is { } amount)
                prices[currency] = new BillingPrice(amount, ApiEnvelope.Int(price["points"]));
        return new BillingPack(ApiEnvelope.Text(p["id"]) ?? "", ApiEnvelope.Int(p["credits"]) ?? 0, ApiEnvelope.Int(p["bonusCredits"]) ?? 0,
            prices, ApiEnvelope.Bool(p["recommended"]) == true);
    }

    private static BillingCheckout ParseCheckout(JsonNode? r)
    {
        var order = ParseOrder(r?["order"] as JsonObject) ?? throw new ApiException("Could not read server response.", "bad_response");
        return new BillingCheckout(order, HttpsOnly(ApiEnvelope.Text(r?["checkoutUrl"])));
    }

    private static BillingOrder? ParseOrder(JsonObject? o)
    {
        if (o is null || ApiEnvelope.Text(o["id"]) is not { } id) return null;
        return new BillingOrder(id, ApiEnvelope.Text(o["product"]) ?? "", ApiEnvelope.Text(o["currency"]) ?? "", ApiEnvelope.Int(o["amount"]) ?? 0,
            ApiEnvelope.Int(o["credits"]) ?? 0, ApiEnvelope.Int(o["bonusCredits"]) ?? 0, ApiEnvelope.Text(o["status"]) ?? "",
            Date(o["createdAt"]), Date(o["expiresAt"]));
    }

    private static string? HttpsOnly(string? url) =>
        url is not null && url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ? url : null;

    public static DateTimeOffset? Date(JsonNode? node) =>
        ApiEnvelope.Text(node) is { } s && DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var d) ? d : null;

    /// <summary>"12.00 USD"-style price text (JPY has no minor unit).</summary>
    public static string FormatPrice(BillingPrice price, string currency)
    {
        var code = currency.ToUpperInvariant();
        var value = code == "JPY" ? price.Amount : price.Amount / 100.0;
        var symbol = code switch { "USD" => "$", "CNY" => "¥", "JPY" => "¥", "EUR" => "€", "HKD" => "HK$", _ => code + " " };
        return symbol + value.ToString(code == "JPY" ? "0" : "0.00", CultureInfo.InvariantCulture);
    }
}
