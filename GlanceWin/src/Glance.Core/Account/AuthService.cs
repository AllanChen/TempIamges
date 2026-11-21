using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Glance.Core.Logging;

namespace Glance.Core.Account;

/// <summary>Small secret store (DPAPI on Windows; macOS used UserDefaults / Keychain).</summary>
public interface ISecureStore
{
    string? Read(string key);
    void Write(string key, string value);
    void Delete(string key);
}

/// <summary>Signed-in user (snake_case JSON, macOS <c>AuthUser</c>).</summary>
public sealed record AuthUser
{
    [JsonPropertyName("id")] public long Id { get; init; }
    [JsonPropertyName("credits")] public int? Credits { get; init; }
    [JsonPropertyName("email")] public string Email { get; init; } = "";
    [JsonPropertyName("google_id")] public string? GoogleId { get; init; }
    [JsonPropertyName("name")] public string? Name { get; init; }
    [JsonPropertyName("avatar_url")] public string? AvatarUrl { get; init; }
    [JsonPropertyName("role")] public string? Role { get; init; }
    [JsonPropertyName("auth_provider")] public string? AuthProvider { get; init; }
    [JsonPropertyName("email_verified")] public bool EmailVerified { get; init; }
    [JsonPropertyName("status")] public string? Status { get; init; }
    [JsonPropertyName("created_at")] public string? CreatedAt { get; init; }
    [JsonPropertyName("updated_at")] public string? UpdatedAt { get; init; }
    [JsonPropertyName("last_login_at")] public string? LastLoginAt { get; init; }
}

/// <summary>One bearer token with its expiry; there is no refresh token (as on macOS).</summary>
public sealed record AuthSession
{
    [JsonPropertyName("user")] public AuthUser User { get; init; } = new();
    [JsonPropertyName("token")] public string Token { get; init; } = "";
    [JsonPropertyName("expires_at")] public string ExpiresAt { get; init; } = "";

    public DateTimeOffset? Expiry =>
        DateTimeOffset.TryParse(ExpiresAt, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var t) ? t : null;
}

/// <summary>
/// Sign-in and the account session (port of macOS <c>AuthManager</c>): email code, Google via the
/// browser with PKCE and the <c>glance://auth/callback</c> URL, <c>/auth/me</c> refresh, sign-out.
/// Thread-safe; <see cref="Changed"/> may fire on any thread.
/// </summary>
public sealed class AuthService
{
    private const string SessionKey = "auth.session";
    private const string DeviceKey = "device";
    private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    private readonly HttpClient _http;
    private readonly ISecureStore _store;
    private readonly Func<DateTimeOffset> _now;
    private readonly object _gate = new();
    private AuthSession? _session;
    private (string State, string Verifier)? _pendingOAuth;

    public AuthService(HttpClient http, ISecureStore store, Func<DateTimeOffset>? now = null)
    {
        _http = http;
        _store = store;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        DeviceId = LoadDeviceId(store);
        _session = LoadSession(store);
    }

    /// <summary>Uppercase UUID created once per install, sent as <c>X-Glance-Device</c>.</summary>
    public string DeviceId { get; }

    /// <summary>Lowercase hex SHA-256 of the device id.</summary>
    public string DeviceHash => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(DeviceId)));

    public event EventHandler? Changed;

    /// <summary>The session while it hasn't expired.</summary>
    public AuthSession? Session
    {
        get
        {
            lock (_gate)
            {
                return _session is { } s && s.Expiry is { } expiry && expiry > _now() && s.Token.Length > 0 ? s : null;
            }
        }
    }

    public bool IsSignedIn => Session is not null;

    /// <summary>The last known user id, kept after the session expires.</summary>
    public long? StoredUserId
    {
        get
        {
            lock (_gate) return _session?.User.Id;
        }
    }

    public static bool IsValidEmail(string email)
    {
        var trimmed = email.Trim();
        return trimmed.Contains('@') && trimmed.Contains('.') && !trimmed.Contains(' ');
    }

    // ───────────────────────────── Email code ─────────────────────────────

    public async Task SendCodeAsync(string email, CancellationToken ct = default)
    {
        await PostAsync("/auth/email/send-code", new JsonObject { ["email"] = email.Trim() }, ct).ConfigureAwait(false);
        Log.Info("Auth: email code sent");
    }

    public async Task VerifyCodeAsync(string email, string code, CancellationToken ct = default)
    {
        var result = await PostAsync("/auth/email/verify-code", new JsonObject
        {
            ["email"] = email.Trim(),
            ["code"] = code.Trim(),
            ["redirect_uri"] = GlanceApi.AuthCallback,
        }, ct).ConfigureAwait(false);
        if (TryReadSession(result) is { } session)
        {
            Save(session);
            Log.Info("Auth: signed in with an email code");
            return;
        }
        if (ApiEnvelope.Text(result?["code"]) is { } exchangeCode)
        {
            await ExchangeAsync(exchangeCode, ct).ConfigureAwait(false);
            return;
        }
        throw new ApiException("Sign-in response did not include a session code.", "bad_response");
    }

    // ───────────────────────────── Google (browser + PKCE) ─────────────────────────────

    /// <summary>Creates the pending PKCE request and returns the browser URL to open.</summary>
    public Uri BeginGoogleSignIn()
    {
        var (verifier, challenge, state) = NewPkce();
        lock (_gate) _pendingOAuth = (state, verifier);
        var query = $"client=glance&state={Uri.EscapeDataString(state)}&code_challenge={Uri.EscapeDataString(challenge)}&device_id={Uri.EscapeDataString(DeviceId)}";
        return new Uri($"{GlanceApi.BaseUrl}/auth/google?{query}");
    }

    /// <summary>True for <c>glance://auth/…</c> URLs.</summary>
    public static bool IsAuthCallback(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && uri.Scheme.Equals("glance", StringComparison.OrdinalIgnoreCase)
        && uri.Host.Equals("auth", StringComparison.OrdinalIgnoreCase);

    /// <summary>Finishes Google sign-in from <c>glance://auth/callback?state=…&amp;code=…</c>.</summary>
    public async Task CompleteCallbackAsync(string url, CancellationToken ct = default)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !uri.AbsolutePath.TrimEnd('/').Equals("/callback", StringComparison.OrdinalIgnoreCase))
            throw new ApiException("Unsupported callback URL.", "bad_callback");
        var query = ParseQuery(uri.Query);
        (string State, string Verifier)? pending;
        lock (_gate) pending = _pendingOAuth;
        if (pending is null || !query.TryGetValue("state", out var state) || state != pending.Value.State)
            throw new ApiException("This sign-in request expired. Please sign in again.", "expired_request");
        if (query.TryGetValue("error", out var error) && !string.IsNullOrWhiteSpace(error))
            throw new ApiException(error, "oauth_error");
        if (!query.TryGetValue("code", out var code) || string.IsNullOrWhiteSpace(code))
            throw new ApiException("Callback URL did not include a code.", "bad_callback");
        await ExchangeAsync(code, ct).ConfigureAwait(false);
        Log.Info("Auth: signed in with Google");
    }

    private async Task ExchangeAsync(string code, CancellationToken ct)
    {
        string verifier;
        lock (_gate)
        {
            if (_pendingOAuth is not { } pending) throw new ApiException("Please start sign-in again.", "expired_request");
            verifier = pending.Verifier;
        }
        var result = await PostAsync("/auth/native/exchange", new JsonObject { ["code"] = code, ["code_verifier"] = verifier }, ct).ConfigureAwait(false);
        var session = TryReadSession(result) ?? throw new ApiException("Could not read server response.", "bad_response");
        lock (_gate) _pendingOAuth = null;
        Save(session);
    }

    // ───────────────────────────── Account ─────────────────────────────

    /// <summary>GET /auth/me: refreshes the profile (credits); a 401 signs the user out but keeps their id.</summary>
    public async Task RefreshAccountAsync(CancellationToken ct = default)
    {
        if (Session is not { } session) return;
        using var request = new HttpRequestMessage(HttpMethod.Get, GlanceApi.BaseUrl + "/auth/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.Token);
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
        try
        {
            var result = await ApiEnvelope.SendAsync(_http, request, ct).ConfigureAwait(false);
            if (result?["user"]?.Deserialize<AuthUser>() is not { } user) return;
            lock (_gate)
            {
                if (_session?.Token != session.Token) return;
                _session = _session with { User = user };
                Persist(_session);
            }
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (ApiException ex) when (ex.IsUnauthorized)
        {
            InvalidateOnlineSession(session.Token);
        }
    }

    /// <summary>Patches the local credit balance after a task reports it.</summary>
    public void UpdateCredits(int credits, string forToken)
    {
        lock (_gate)
        {
            if (_session is not { } s || s.Token != forToken) return;
            _session = s with { User = s.User with { Credits = credits } };
            Persist(_session);
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>The server rejected the token: expire it locally (the user id stays for "sign in again").</summary>
    public void InvalidateOnlineSession(string? token = null)
    {
        lock (_gate)
        {
            if (_session is not { } s || (token is not null && s.Token != token)) return;
            _session = s with { ExpiresAt = "2000-01-01T00:00:00Z" };
            Persist(_session);
        }
        Log.Info("Auth: session rejected by the server");
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void SignOut()
    {
        string? token;
        lock (_gate)
        {
            token = Session?.Token;
            _session = null;
            _pendingOAuth = null;
            _store.Delete(SessionKey);
        }
        Log.Info("Auth: signed out");
        Changed?.Invoke(this, EventArgs.Empty);
        if (token is null) return;
        _ = Task.Run(async () =>
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, GlanceApi.BaseUrl + "/auth/logout");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                using var _ = await _http.SendAsync(request).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                Log.Info($"Auth: logout request failed: {ex.Message}");
            }
        });
    }

    // ───────────────────────────── Helpers ─────────────────────────────

    /// <summary>PKCE S256: verifier = two dash-less UUIDs, challenge = base64url(SHA-256(verifier)).</summary>
    public static (string Verifier, string Challenge, string State) NewPkce()
    {
        var verifier = (Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N")).ToUpperInvariant();
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        var state = Guid.NewGuid().ToString("N").ToUpperInvariant();
        return (verifier, challenge, state);
    }

    public static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private async Task<JsonNode?> PostAsync(string path, JsonObject body, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, GlanceApi.BaseUrl + path)
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("X-Glance-Device", DeviceId);
        return await ApiEnvelope.SendAsync(_http, request, ct).ConfigureAwait(false);
    }

    private static AuthSession? TryReadSession(JsonNode? result)
    {
        if (result is not JsonObject obj || ApiEnvelope.Text(obj["token"]) is null || obj["user"] is null) return null;
        try
        {
            return obj.Deserialize<AuthSession>();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private void Save(AuthSession session)
    {
        lock (_gate)
        {
            _session = session;
            Persist(session);
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void Persist(AuthSession session)
    {
        try
        {
            _store.Write(SessionKey, JsonSerializer.Serialize(session, Json));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException)
        {
            Log.Warning($"Auth: could not store the session: {ex.Message}");
        }
    }

    private static AuthSession? LoadSession(ISecureStore store)
    {
        try
        {
            return store.Read(SessionKey) is { } json ? JsonSerializer.Deserialize<AuthSession>(json) : null;
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException or CryptographicException)
        {
            Log.Warning($"Auth: stored session unreadable: {ex.Message}");
            return null;
        }
    }

    private static string LoadDeviceId(ISecureStore store)
    {
        try
        {
            if (store.Read(DeviceKey) is { Length: > 0 } existing) return existing;
            var id = Guid.NewGuid().ToString().ToUpperInvariant();
            store.Write(DeviceKey, id);
            return id;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException)
        {
            Log.Warning($"Auth: device id not persisted: {ex.Message}");
            return Guid.NewGuid().ToString().ToUpperInvariant();
        }
    }

    public static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = part.IndexOf('=');
            var key = Uri.UnescapeDataString((eq < 0 ? part : part[..eq]).Replace('+', ' '));
            var value = eq < 0 ? "" : Uri.UnescapeDataString(part[(eq + 1)..].Replace('+', ' '));
            result[key] = value;
        }
        return result;
    }
}
