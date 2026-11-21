using System.Net.Http;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Glance.Core.Account;
using Glance.Core.Billing;
using Glance.Core.Tasks;
using Glance.Core.Widgets;
using Xunit;

namespace Glance.Tests;

internal sealed class MemoryStore : ISecureStore
{
    public Dictionary<string, string> Values { get; } = [];
    public string? Read(string key) => Values.TryGetValue(key, out var v) ? v : null;
    public void Write(string key, string value) => Values[key] = value;
    public void Delete(string key) => Values.Remove(key);
}

internal sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
{
    public List<HttpRequestMessage> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        Requests.Add(request);
        return Task.FromResult(respond(request));
    }

    public static HttpResponseMessage Json(HttpStatusCode status, string body) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
}

public class ApiEnvelopeTests
{
    [Fact]
    public void ReturnsResultOnSuccess()
    {
        var result = ApiEnvelope.Parse(200, """{"success":true,"result":{"email":"a@b.c"}}""");
        Assert.Equal("a@b.c", ApiEnvelope.Text(result?["email"]));
    }

    [Fact]
    public void ServerErrorCarriesCodeAndAttempts()
    {
        var ex = Assert.Throws<ApiException>(() => ApiEnvelope.Parse(400,
            """{"success":false,"error":{"code":"bad_code","message":"Wrong","details":{"attemptsRemaining":3}}}"""));
        Assert.Equal("bad_code", ex.Code);
        Assert.Equal("Wrong", ex.Message);
        Assert.Equal(3, ex.AttemptsRemaining);
    }

    [Fact]
    public void FallbackMessages()
    {
        Assert.Equal("Request failed with HTTP 502.", Assert.Throws<ApiException>(() => ApiEnvelope.Parse(502, "<html>")).Message);
        Assert.Equal("Empty server response.", Assert.Throws<ApiException>(() => ApiEnvelope.Parse(200, "")).Message);
        Assert.Equal("Request failed.", Assert.Throws<ApiException>(() => ApiEnvelope.Parse(200, """{"success":false}""")).Message);
        Assert.Equal("Could not read server response.", Assert.Throws<ApiException>(() => ApiEnvelope.Parse(200, "{oops")).Message);
        Assert.True(Assert.Throws<ApiException>(() => ApiEnvelope.Parse(401, """{"error":{"message":"no"}}""")).IsUnauthorized);
    }
}

public class AuthServiceTests
{
    private static AuthService Create(MemoryStore store, Func<HttpRequestMessage, HttpResponseMessage>? respond = null, StubHandler? handler = null)
    {
        handler ??= new StubHandler(respond ?? (_ => StubHandler.Json(HttpStatusCode.OK, """{"success":true,"result":{}}""")));
        return new AuthService(new HttpClient(handler), store);
    }

    [Fact]
    public void DeviceIdIsCreatedOnceUppercase()
    {
        var store = new MemoryStore();
        var first = Create(store).DeviceId;
        Assert.Equal(first.ToUpperInvariant(), first);
        Assert.True(Guid.TryParse(first, out _));
        Assert.Equal(first, Create(store).DeviceId);
    }

    [Fact]
    public void PkceChallengeIsBase64UrlSha256()
    {
        var (verifier, challenge, state) = AuthService.NewPkce();
        Assert.Equal(64, verifier.Length);
        Assert.Equal(32, state.Length);
        var expected = AuthService.Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        Assert.Equal(expected, challenge);
        Assert.DoesNotContain('=', challenge);
        Assert.DoesNotContain('+', challenge);
    }

    [Theory]
    [InlineData("a@b.co", true)]
    [InlineData(" a@b.co ", true)]
    [InlineData("ab.co", false)]
    [InlineData("a@bco", false)]
    [InlineData("a b@c.d", false)]
    public void EmailValidation(string email, bool valid) => Assert.Equal(valid, AuthService.IsValidEmail(email));

    [Fact]
    public async Task CallbackRejectsWrongStateAndMissingCode()
    {
        var auth = Create(new MemoryStore());
        var url = auth.BeginGoogleSignIn();
        var state = AuthService.ParseQuery(url.Query)["state"];
        Assert.Equal("glance", AuthService.ParseQuery(url.Query)["client"]);
        var wrong = await Assert.ThrowsAsync<ApiException>(() => auth.CompleteCallbackAsync("glance://auth/callback?state=nope&code=x"));
        Assert.Equal("This sign-in request expired. Please sign in again.", wrong.Message);
        var missing = await Assert.ThrowsAsync<ApiException>(() => auth.CompleteCallbackAsync($"glance://auth/callback?state={state}"));
        Assert.Equal("Callback URL did not include a code.", missing.Message);
        var path = await Assert.ThrowsAsync<ApiException>(() => auth.CompleteCallbackAsync($"glance://auth/other?state={state}&code=x"));
        Assert.Equal("Unsupported callback URL.", path.Message);
        Assert.True(AuthService.IsAuthCallback("glance://auth/callback?x=1"));
        Assert.False(AuthService.IsAuthCallback("glance://payment/return?order=order_1"));
    }

    [Fact]
    public async Task VerifyCodeSavesSessionAndExpiryRules()
    {
        var store = new MemoryStore();
        var future = DateTimeOffset.UtcNow.AddDays(30).ToString("O");
        var handler = new StubHandler(_ => StubHandler.Json(HttpStatusCode.OK,
            $$$"""{"success":true,"result":{"user":{"id":7,"email":"a@b.co","credits":100,"email_verified":true},"token":"tok","expires_at":"{{{future}}}"}}"""));
        var auth = Create(store, handler: handler);
        var changed = 0;
        auth.Changed += (_, _) => changed++;
        await auth.VerifyCodeAsync("a@b.co", "123456");
        Assert.True(auth.IsSignedIn);
        Assert.Equal(100, auth.Session!.User.Credits);
        Assert.Equal(1, changed);
        Assert.Equal(auth.DeviceId, handler.Requests[0].Headers.GetValues("X-Glance-Device").Single());
        // Reload from the store.
        Assert.True(Create(store).IsSignedIn);
        auth.InvalidateOnlineSession("tok");
        Assert.False(auth.IsSignedIn);
        Assert.Equal(7, auth.StoredUserId);
    }
}

public class WidgetManifestTests
{
    private const string Manifest = """
        {"schemaVersion":1,"id":"w1","version":"1.0","name":"图中文字","summary":"中文","author":"Glance","official":false,
         "execution":{"mode":"cloud"},"creditCost":30,
         "commands":[
           {"id":"run","name":"翻译","description":"d","inputTypes":["image"],"inputMimeTypes":["image/png"],"outputs":["image"],
            "taskType":"widget.w1.run","requiresUpload":true,
            "parameterSchema":{"type":"object","properties":{"prompt":{"type":"string","maxLength":2000,"description":"https://x/y"}},"required":["prompt"]}},
           {"id":"note","name":"Note","description":"t","inputTypes":["text"],"inputMimeTypes":[],"outputs":["text"],"taskType":"t","requiresUpload":false,
            "parameterSchema":{"properties":{"images":{"type":"array","maxItems":9,"minItems":2}}}}],
         "privacy":{"uploadsMedia":true,"notice":"n"},"minimumGlanceVersion":"2.0.0","updatedAt":"2026-01-01",
         "localizations":{"en":{"name":"Translate Text","commands":{"run":{"name":"Translate"}}}},
         "unknownField":123,
         "signature":{"algorithm":"Ed25519","keyID":"k","value":"AAAA"}}
        """;

    private static WidgetManifest Parse() => WidgetManifest.TryParse(JsonNode.Parse(Manifest))!;

    [Fact]
    public void CapabilitiesFromSchema()
    {
        var m = Parse();
        var run = m.Command("run")!.InputCapabilities;
        Assert.True(run.AcceptsPrompt);
        Assert.Equal(1, run.MaxImages);
        Assert.True(run.NeedsImageDialog);
        var note = m.Command("note")!;
        Assert.True(note.IsTextOnly);
        Assert.Equal(4, note.InputCapabilities.MaxImages);
        Assert.Equal(2, note.InputCapabilities.MinImages);
        Assert.True(m.HasTextOnlyCommand);
        Assert.True(m.IsCompatible("image"));
        Assert.False(m.IsCompatible("video"));
    }

    [Fact]
    public void CostAndLocalization()
    {
        var m = Parse();
        Assert.Equal(30, m.TaskCreditCost);
        Assert.False(m.UsesDurationBilling);
        Assert.Equal("Translate Text", m.DisplayName("en"));
        Assert.Equal("Translate", m.CommandName(m.Command("run")!, "en"));
        // The base name is already Chinese: zh shows it.
        Assert.Equal("图中文字", m.DisplayName("zh-Hans"));
        // Blank override falls back to the base summary.
        Assert.Equal("中文", m.DisplaySummary("en"));
        Assert.Contains("Translate Text", m.SearchableText);
    }

    [Fact]
    public void CanonicalJsonMatchesSwiftEncoder()
    {
        var canonical = WidgetSignature.Canonical(Parse().Raw);
        Assert.DoesNotContain("signature", canonical);
        Assert.DoesNotContain("unknownField", canonical);
        Assert.StartsWith("{\"author\":\"Glance\",\"commands\":[{\"description\":\"d\",\"id\":\"run\",", canonical);
        Assert.Contains("\"description\":\"https://x/y\"", canonical);
        Assert.Contains("\"name\":\"图中文字\"", canonical);
        Assert.Contains("\"localizations\":{\"en\":{\"commands\":{\"run\":{\"name\":\"Translate\"}},\"name\":\"Translate Text\"}}", canonical);
        Assert.DoesNotContain(" ", canonical.Replace("Translate Text", ""));
    }

    /// <summary>RFC 8032 §7.1 test vectors 1–3, plus tampered message / signature / key and S ≥ L.</summary>
    [Theory]
    [InlineData("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")]
    [InlineData("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
        "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")]
    [InlineData("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
        "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a")]
    public void Ed25519MatchesRfc8032(string publicKey, string message, string signature)
    {
        var key = Convert.FromHexString(publicKey);
        var msg = Convert.FromHexString(message);
        var sig = Convert.FromHexString(signature);
        Assert.True(Ed25519.Verify(key, msg, sig));

        Assert.False(Ed25519.Verify(key, [.. msg, 0x00], sig));
        var badSig = (byte[])sig.Clone();
        badSig[5] ^= 0x01;
        Assert.False(Ed25519.Verify(key, msg, badSig));
        var badKey = (byte[])key.Clone();
        badKey[0] ^= 0x01;
        Assert.False(Ed25519.Verify(badKey, msg, sig));

        // S + L encodes the same scalar mod L but must be rejected (malleability).
        var s = new System.Numerics.BigInteger(sig.AsSpan(32), isUnsigned: true) + (System.Numerics.BigInteger.Pow(2, 252) + System.Numerics.BigInteger.Parse("27742317777372353535851937790883648493"));
        var malleable = (byte[])sig.Clone();
        s.TryWriteBytes(malleable.AsSpan(32), out _, isUnsigned: true);
        Assert.False(Ed25519.Verify(key, msg, malleable));
        Assert.False(Ed25519.Verify(key[..31], msg, sig));
    }

    [Fact]
    public void UnverifiedSignatureIsRejectedUnlessOfficial()
    {
        var m = Parse();
        Assert.False(WidgetSignature.Verify(m.Raw));
        Assert.False(WidgetSignature.IsTrusted(m));
        var official = (JsonObject)m.Raw.DeepClone();
        official["official"] = true;
        Assert.True(WidgetSignature.IsTrusted(new WidgetManifest(official)));
        Assert.Equal(new byte[] { 0xfb, 0xff }, WidgetSignature.FromBase64Url("-_8"));
    }

    [Fact]
    public void RegistryInstallReconcileAndPersist()
    {
        var file = Path.Combine(Path.GetTempPath(), $"glance-widgets-{Guid.NewGuid():N}.json");
        try
        {
            var registry = new WidgetRegistry(file);
            registry.Install(Parse());
            Assert.True(registry.IsAvailable("w1"));
            Assert.Single(registry.Compatible("image"));
            registry.Reconcile(["other"]);
            Assert.False(registry.IsAvailable("w1"));
            Assert.True(registry.IsInstalled("w1"));
            var reloaded = new WidgetRegistry(file);
            Assert.True(reloaded.IsInstalled("w1"));
            Assert.False(reloaded.IsAvailable("w1"));
            reloaded.Install(Parse());
            Assert.True(reloaded.IsAvailable("w1"));
            reloaded.Uninstall("w1");
            Assert.Empty(new WidgetRegistry(file).Installed);
        }
        finally
        {
            File.Delete(file);
        }
    }

    [Fact]
    public void UpdateDetection()
    {
        var installed = Parse();
        var newer = (JsonObject)installed.Raw.DeepClone();
        Assert.False(installed.DiffersFrom(new WidgetManifest(newer)));
        newer["version"] = "1.1";
        Assert.True(installed.DiffersFrom(new WidgetManifest(newer)));
    }
}

public class WidgetTaskModelTests
{
    [Fact]
    public void BillingStatusPriority()
    {
        var r = new WidgetTaskRecord { CreditCost = 5, Phase = WidgetTaskPhase.Uploading };
        Assert.Equal<(string, int?)?>(("Estimated %d credits", (int?)5), r.BillingStatus);
        Assert.Equal<(string, int?)?>(("Not charged", (int?)null), (r with { Phase = WidgetTaskPhase.Failed }).BillingStatus);
        Assert.Equal<(string, int?)?>(("Charged %d credits", (int?)5), (r with { RemoteTaskId = "t" }).BillingStatus);
        Assert.Equal<(string, int?)?>(("Refunded %d credits", (int?)5), (r with { RemoteTaskId = "t", RefundedCredits = 5 }).BillingStatus);
        Assert.Equal<(string, int?)?>(("Refund confirmation pending", (int?)null), (r with { SettlementOutcome = "failed", RefundedCredits = 5 }).BillingStatus);
        Assert.Equal<(string, int?)?>(("Free of charge", (int?)null), new WidgetTaskRecord { CreditCost = 0 }.BillingStatus);
    }

    [Fact]
    public void QueueText()
    {
        var r = new WidgetTaskRecord { Phase = WidgetTaskPhase.Processing, QueuePosition = 3, EstimatedWaitSeconds = 170 };
        Assert.Equal("Queued · %d ahead · ~%@", r.QueueStatus!.Value.Format);
        Assert.Equal(new object[] { 2, "3 min" }, r.QueueStatus!.Value.Args);
        Assert.Equal("Waiting for a worker · Not started", (r with { QueueWaitSeconds = 130 }).QueueStatus!.Value.Format);
        Assert.Null((r with { Progress = 10 }).QueueStatus);
    }

    [Fact]
    public void SettlementResolution()
    {
        Assert.True(new WidgetTaskResult { Status = "completed", Delivered = true }.SettlementResolved);
        Assert.False(new WidgetTaskResult { Status = "completed", Delivered = false }.SettlementResolved);
        Assert.True(new WidgetTaskResult { Status = "failed", CreditCost = 5, RefundedCredits = 5 }.SettlementResolved);
        Assert.False(new WidgetTaskResult { Status = "failed", CreditCost = 5, RefundedCredits = 0 }.SettlementResolved);
        Assert.True(new WidgetTaskResult { Status = "cancelled", CreditCost = 0 }.SettlementResolved);
    }

    [Fact]
    public void ResultParsingAndUrls()
    {
        var result = WidgetTaskResult.From(JsonNode.Parse("""{"taskID":42,"status":"Completed","result":[{"type":"image","url":"https://r/x.png"}],"creditCost":3}"""));
        Assert.Equal("42", result.TaskId);
        Assert.True(result.IsSuccess);
        Assert.Equal("https://r/x.png", result.Artifacts.Single().Url);
        var record = new WidgetTaskRecord { Phase = WidgetTaskPhase.Completed, OutputUrlString = "https://r/x.png", OutputTypes = ["image"], ShowResultUrl = true };
        Assert.Equal("https://r/x.png", record.CopyableMediaResultUrl(null, null));
        Assert.Null((record with { ShowResultUrl = false }).CopyableMediaResultUrl(true, null));
        Assert.Contains("(possible sexual content)", WidgetTaskException.ExecutionMessage("content_rejected", "sexual"));
    }

    [Fact]
    public void MediaKeysAndFiles()
    {
        Assert.Equal(WidgetTaskRecord.MediaKey(@"C:\A\b.png"), WidgetTaskRecord.MediaKey(@"c:\a\B.PNG"));
        Assert.Equal("https://x/a.png", WidgetTaskRecord.MediaKey("https://x/a.png"));
        Assert.Equal("png", MimeTypes.Extension(null, "image/png", null));
        Assert.Equal("jpg", MimeTypes.Extension("result.jpg", "application/octet-stream", null));
        Assert.Equal("webp", MimeTypes.Extension(null, null, "https://x/y.webp?sig=1"));
        Assert.Equal("bin", MimeTypes.Extension(null, null, null));
        var folder = Path.Combine(Path.GetTempPath(), $"glance-unique-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        try
        {
            var first = WidgetTaskClient.UniqueFile(folder, "a:b", "png");
            Assert.Equal("a-b.png", Path.GetFileName(first));
            File.WriteAllText(first, "x");
            Assert.Equal("a-b 2.png", Path.GetFileName(WidgetTaskClient.UniqueFile(folder, "a:b", "png")));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void QuoteRoundTrip()
    {
        var quote = WidgetTaskQuote.From(JsonNode.Parse("""{"quoteID":"q1","mode":"duration","unitSeconds":10,"unitPrice":5,"units":3,"totalCredits":15,"balance":4,"shortfall":11}"""))!;
        Assert.Equal(15, quote.TotalCredits);
        Assert.Equal(11, quote.Shortfall);
        Assert.Equal("q1", WidgetTaskQuote.From(quote.ToJson())!.QuoteId);
        Assert.Equal("$12.00", BillingClient.FormatPrice(new BillingPrice(1200, null), "usd"));
        Assert.Equal("¥1200", BillingClient.FormatPrice(new BillingPrice(1200, null), "JPY"));
    }
}
