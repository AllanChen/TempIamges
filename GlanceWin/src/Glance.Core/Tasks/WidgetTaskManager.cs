using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Glance.Core.Account;
using Glance.Core.Billing;
using Glance.Core.Logging;
using Glance.Core.Widgets;

namespace Glance.Core.Tasks;

/// <summary>
/// Runs and remembers Widget tasks (port of macOS <c>WidgetTaskManager</c>): upload → create →
/// poll → download → settle, persisted to <c>widget-tasks.json</c>. Credits are protected the same
/// way as on macOS: the idempotency key is saved before upload, every failure / cancel is settled
/// with the service (<c>abandon</c>) and retried until the refund is confirmed, and a result only
/// counts once it is on disk and the service confirmed delivery (<c>settle</c>).
/// Thread-safe. <see cref="Changed"/> and <see cref="Completed"/> are posted to the
/// <see cref="SynchronizationContext"/> the manager was created on (the UI thread).
/// </summary>
public sealed class WidgetTaskManager
{
    private const int HistoryLimit = 200;
    private static readonly TimeSpan PollTimeout = TimeSpan.FromSeconds(1800);
    private static readonly TimeSpan StaleActive = TimeSpan.FromMinutes(30);
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly WidgetTaskClient _client;
    private readonly WidgetRegistry _registry;
    private readonly AuthService _auth;
    private readonly string _storeFile;
    private readonly string _downloads;
    private readonly SynchronizationContext? _ui;
    private readonly object _gate = new();
    private readonly SemaphoreSlim _saveLock = new(1, 1);
    private readonly HashSet<Guid> _cancelRequested = [];
    private readonly HashSet<Guid> _running = [];
    private readonly HashSet<Guid> _settling = [];
    private List<WidgetTaskRecord> _records = [];

    public WidgetTaskManager(WidgetTaskClient client, WidgetRegistry registry, AuthService auth, string storeFile, string downloadsFolder)
    {
        _client = client;
        _registry = registry;
        _auth = auth;
        _storeFile = storeFile;
        _downloads = downloadsFolder;
        _ui = SynchronizationContext.Current;
    }

    /// <summary>Any record changed (UI thread).</summary>
    public event EventHandler? Changed;

    /// <summary>A result is on disk and confirmed (UI thread). Drives "Widget completed" notifications.</summary>
    public event Action<WidgetTaskRecord>? Completed;

    /// <summary>
    /// The service refused to create the task because the price / balance / input changed
    /// (<c>insufficient_credits</c>, <c>price_changed</c>, <c>quote_expired</c>, <c>input_changed</c>).
    /// The app re-runs the quote / top-up flow and starts a new task (UI thread).
    /// </summary>
    public event Action<WidgetTaskRecord, string>? RequoteRequired;

    public string DownloadsFolder => _downloads;

    public IReadOnlyList<WidgetTaskRecord> Records
    {
        get
        {
            lock (_gate) return _records.ToList();
        }
    }

    public WidgetTaskRecord? Find(Guid id)
    {
        lock (_gate) return _records.FirstOrDefault(r => r.Id == id);
    }

    // ───────────────────────────── Queries ─────────────────────────────

    public IReadOnlyList<WidgetTaskRecord> ActiveRecords(string source)
    {
        var key = WidgetTaskRecord.MediaKey(source);
        lock (_gate) return _records.Where(r => r.IsActive && WidgetTaskRecord.MediaKey(r.SourceUrl) == key).ToList();
    }

    public WidgetTaskRecord? LatestRecord(string source)
    {
        var key = WidgetTaskRecord.MediaKey(source);
        lock (_gate) return _records.FirstOrDefault(r => WidgetTaskRecord.MediaKey(r.SourceUrl) == key);
    }

    /// <summary>The completed task that produced <paramref name="output"/>.</summary>
    public WidgetTaskRecord? CompletedRecord(string output)
    {
        var key = WidgetTaskRecord.MediaKey(output);
        lock (_gate) return _records.FirstOrDefault(r => r.Phase == WidgetTaskPhase.Completed && r.OutputPath is { } p && WidgetTaskRecord.MediaKey(p) == key);
    }

    public string? SourceOf(string output) => CompletedRecord(output) is { IsTextSource: false } r ? r.SourceUrl : null;

    public IReadOnlyList<string> CompletedOutputs(string source)
    {
        var key = WidgetTaskRecord.MediaKey(source);
        lock (_gate)
            return _records.Where(r => r.Phase == WidgetTaskPhase.Completed && r.OutputPath is not null && WidgetTaskRecord.MediaKey(r.SourceUrl) == key)
                .OrderByDescending(r => r.UpdatedAt).Select(r => r.OutputPath!).ToList();
    }

    /// <summary>A fresh signed link for a completed task's result (R2 links expire after an hour).</summary>
    public Task<string> FetchResultUrlAsync(string taskId, CancellationToken ct = default) => _client.FetchResultUrlAsync(taskId, ct);

    public static bool IsSameMedia(string a, string b) => WidgetTaskRecord.MediaKey(a) == WidgetTaskRecord.MediaKey(b);

    // ───────────────────────────── Start ─────────────────────────────

    /// <summary>
    /// Creates the record (saved with its idempotency key before anything is uploaded) and runs it in
    /// the background. Throws <see cref="WidgetTaskException"/> for a duplicate run or a failed save.
    /// </summary>
    public async Task<WidgetTaskRecord> StartAsync(WidgetManifest widget, WidgetCommand command, string language, string source, string sourceKind,
        WidgetTaskInput input, WidgetTaskQuote? quote)
    {
        WidgetTaskRecord record;
        lock (_gate)
        {
            var key = WidgetTaskRecord.MediaKey(source);
            var duplicate = _records.FirstOrDefault(r => r.IsActive && r.WidgetId == widget.Id && r.CommandId == command.Id && WidgetTaskRecord.MediaKey(r.SourceUrl) == key && !sourceKind.Equals("text"));
            if (duplicate is not null && DateTimeOffset.UtcNow - duplicate.UpdatedAt < StaleActive)
                throw new WidgetTaskException("This Widget is already running on this item.", "duplicate");
            if (duplicate is not null)
                Replace(duplicate with { Phase = WidgetTaskPhase.Interrupted, ErrorMessage = "Task was reset and can be submitted again.", UpdatedAt = DateTimeOffset.UtcNow });
            var id = Guid.NewGuid();
            record = new WidgetTaskRecord
            {
                Id = id,
                WidgetId = widget.Id,
                WidgetName = widget.DisplayName(language),
                CommandId = command.Id,
                CommandName = widget.Commands.Count == 1 ? widget.DisplayName(language) : widget.CommandName(command, language),
                OutputTypes = command.Outputs.ToList(),
                ShowResultUrl = command.ShowResultUrl,
                SourceUrl = source,
                SourceKind = sourceKind,
                Input = input,
                Quote = quote?.ToJson(),
                CreditCost = quote?.TotalCredits ?? widget.TaskCreditCost,
                RequestKey = id.ToString().ToUpperInvariant(),
                OwnerUserId = _auth.StoredUserId,
                Phase = WidgetTaskPhase.Uploading,
            };
            _records.Insert(0, record);
        }
        if (!await SaveAsync().ConfigureAwait(false))
        {
            lock (_gate) _records.RemoveAll(r => r.Id == record.Id);
            throw new WidgetTaskException("Could not save the task. Check available disk space and try again.", "save_failed");
        }
        Notify();
        Log.Info($"Tasks: started {record.WidgetId}/{record.CommandId} ({record.SourceKind})");
        _ = Task.Run(() => RunAsync(record.Id, quote));
        return record;
    }

    // ───────────────────────────── Pipeline ─────────────────────────────

    private async Task RunAsync(Guid id, WidgetTaskQuote? quote)
    {
        lock (_gate)
            if (!_running.Add(id)) return;
        try
        {
            if (Find(id) is not { } record) return;
            if (IsCancelRequested(id)) { await FinishCancelledAsync(id).ConfigureAwait(false); return; }
            Update(id, r => r with { Phase = WidgetTaskPhase.Uploading, Progress = 0 });

            var country = await _client.FetchCountryAsync(CancellationToken.None).ConfigureAwait(false);
            var input = record.Input ?? new WidgetTaskInput();
            var uploaded = new List<string>();
            if (!record.IsTextSource)
            {
                if (input.MediaUrls.Count is < 1 or > 4) throw new WidgetTaskException("A Widget task needs between one and four media inputs.", "bad_input");
                foreach (var media in input.MediaUrls)
                {
                    if (IsCancelRequested(id)) { await FinishCancelledAsync(id).ConfigureAwait(false); return; }
                    var local = await LocalCopyAsync(media).ConfigureAwait(false);
                    if (quote?.Evidence is { } evidence && record.SourceKind == "video") await CheckEvidenceAsync(local, evidence).ConfigureAwait(false);
                    uploaded.Add(await _client.UploadAsync(local, CancellationToken.None).ConfigureAwait(false));
                }
            }
            else if (string.IsNullOrWhiteSpace(input.Prompt))
            {
                throw new WidgetTaskException("Enter some text for the Widget.", "bad_input");
            }
            string? maskUrl = null;
            if (input.MaskUrl is { } mask) maskUrl = await _client.UploadAsync(await LocalCopyAsync(mask).ConfigureAwait(false), CancellationToken.None).ConfigureAwait(false);

            if (IsCancelRequested(id)) { await FinishCancelledAsync(id).ConfigureAwait(false); return; }
            Update(id, r => r with { Phase = WidgetTaskPhase.Submitting, Progress = 0 });
            var body = CreateBody(record, input, uploaded, maskUrl, country, quote);
            WidgetTaskResult created;
            try
            {
                created = await _client.CreateAsync(body, record.RequestKey!, record.WidgetId, CancellationToken.None).ConfigureAwait(false);
            }
            catch (WidgetTaskException ex) when (ex.RequiresRequote)
            {
                // Nothing was created: fail this record without settlement and let the app re-quote.
                var failed = Update(id, r => r with { Phase = WidgetTaskPhase.Failed, ErrorMessage = ex.Message, RequestKey = null, SettlementOutcome = null });
                if (failed is not null) Post(() => RequoteRequired?.Invoke(failed, ex.Code!));
                return;
            }
            if (created.TaskId is not { } remoteId) throw new WidgetTaskException("Could not read server response.", "bad_response");
            ApplyBilling(id, remoteId, created);
            if (IsCancelRequested(id))
            {
                await _client.CancelAsync(remoteId).ConfigureAwait(false);
                await FinishCancelledAsync(id).ConfigureAwait(false);
                return;
            }
            await PollAsync(id, remoteId).ConfigureAwait(false);
        }
        catch (WidgetTaskException ex)
        {
            await FailAsync(id, ex.Code == "expired" ? WidgetTaskPhase.Expired : WidgetTaskPhase.Failed, ex.Message).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or HttpRequestException or InvalidOperationException)
        {
            Log.Warning($"Tasks: {id} failed: {ex.GetType().Name}: {ex.Message}");
            await FailAsync(id, WidgetTaskPhase.Failed, ex is IOException or UnauthorizedAccessException
                ? "Could not read the input file. Check that it still exists and try again."
                : "The Widget task failed without reporting a reason.").ConfigureAwait(false);
        }
        finally
        {
            lock (_gate) _running.Remove(id);
        }
    }

    private static JsonObject CreateBody(WidgetTaskRecord record, WidgetTaskInput input, List<string> uploaded, string? maskUrl, string country, WidgetTaskQuote? quote)
    {
        var type = record.IsTextSource ? "text" : record.SourceKind;
        var inputNode = new JsonObject { ["type"] = type };
        var taskParams = new JsonObject
        {
            ["prompt"] = input.Prompt ?? "",
            ["mask"] = maskUrl,
            ["location"] = country,
        };
        if (record.IsTextSource)
        {
            inputNode["text"] = input.Prompt;
        }
        else
        {
            inputNode["url"] = uploaded[0];
            taskParams["url"] = uploaded[0];
            if (input.UsesMultipleVideos)
            {
                inputNode["videos"] = Array(uploaded);
                taskParams["videos"] = Array(uploaded);
            }
            else if (input.UsesMultipleImages || uploaded.Count > 1)
            {
                inputNode["images"] = Array(uploaded);
                taskParams["images"] = Array(uploaded);
            }
        }
        var body = new JsonObject
        {
            ["widgetID"] = record.WidgetId,
            ["commandID"] = record.CommandId,
            ["deliveryRequired"] = true,
            ["input"] = inputNode,
            ["taskParams"] = taskParams,
        };
        if (quote is not null)
        {
            body["quoteID"] = quote.QuoteId;
            body["expectedCreditCost"] = quote.TotalCredits;
        }
        return body;

        static JsonArray Array(List<string> urls) => new(urls.Select(u => (JsonNode?)u).ToArray());
    }

    /// <summary>Polls every <c>pollAfterMs</c> (1–10 s, default 5 s) for up to 30 minutes.</summary>
    private async Task PollAsync(Guid id, string remoteId)
    {
        Update(id, r => r with { Phase = WidgetTaskPhase.Processing, Progress = 0 });
        var started = DateTimeOffset.UtcNow;
        var delay = TimeSpan.FromSeconds(5);
        while (true)
        {
            await Task.Delay(delay).ConfigureAwait(false);
            if (IsCancelRequested(id) || Find(id) is not { IsActive: true }) return;
            if (DateTimeOffset.UtcNow - started > PollTimeout)
            {
                await _client.CancelAsync(remoteId).ConfigureAwait(false);
                throw new WidgetTaskException("The task timed out. Its credits will be refunded automatically. Please try again.", "expired");
            }
            WidgetTaskResult result;
            try
            {
                result = await _client.GetAsync(remoteId, CancellationToken.None).ConfigureAwait(false);
            }
            catch (WidgetTaskException ex) when (ex.Status is 401 or 404)
            {
                throw;
            }
            catch (WidgetTaskException ex)
            {
                Log.Info($"Tasks: poll retry for {id}: {ex.Message}");
                continue;
            }
            ApplyBilling(id, remoteId, result);
            delay = result.PollAfterMs is { } ms ? TimeSpan.FromSeconds(Math.Clamp(ms / 1000.0, 1, 10)) : TimeSpan.FromSeconds(5);
            if (result.IsSuccess)
            {
                await DeliverAsync(id, remoteId, result).ConfigureAwait(false);
                return;
            }
            switch (result.Status)
            {
                case "failed":
                    throw new WidgetTaskException(WidgetTaskException.ExecutionMessage(result.Error, result.ErrorReason), result.Error);
                case "cancelled":
                    await FinishCancelledAsync(id).ConfigureAwait(false);
                    return;
                case "expired":
                    throw new WidgetTaskException("The task timed out. Its credits will be refunded automatically. Please try again.", "expired");
            }
            var progress = result.Progress ?? result.ProcessCount ?? 0;
            var queued = result.Status == "queued" && result.QueuePosition is > 0;
            Update(id, r => r with
            {
                Phase = WidgetTaskPhase.Processing,
                Progress = Math.Clamp(progress, 0, 100),
                QueuePosition = queued ? result.QueuePosition : null,
                EstimatedWaitSeconds = queued ? result.EstimatedWaitSeconds : null,
                QueueWaitSeconds = queued ? result.QueueWaitSeconds : null,
            });
        }
    }

    /// <summary>Saves the result to Downloads\Glance, then confirms delivery with the service.</summary>
    private async Task DeliverAsync(Guid id, string remoteId, WidgetTaskResult result)
    {
        if (Find(id) is not { } record) return;
        string output;
        var media = result.Artifacts.Where(a => a.Type != "text" && a.Url is not null).ToList();
        if (result.Artifacts.Count == 1 && media.Count == 1 || result.Artifacts.Count == 0 && result.ResultUrl is not null)
        {
            var url = media.FirstOrDefault()?.Url ?? result.ResultUrl!;
            Update(id, r => r with { Phase = WidgetTaskPhase.Downloading, Progress = 100, OutputUrlString = url });
            var (path, mime) = await _client.DownloadAsync(url, _downloads, ResultBaseName(record), CancellationToken.None, authenticated: true).ConfigureAwait(false);
            ValidateDownload(path, mime, record.OutputTypes);
            output = path;
        }
        else if (result.Artifacts.Count > 0)
        {
            Update(id, r => r with { Phase = WidgetTaskPhase.Downloading, Progress = 100 });
            var folder = Path.Combine(_downloads, $"{remoteId}-{Guid.NewGuid():N}"[..Math.Min(64, remoteId.Length + 33)]);
            Directory.CreateDirectory(folder);
            var single = result.Artifacts.Count == 1;
            for (var i = 0; i < result.Artifacts.Count; i++)
            {
                var artifact = result.Artifacts[i];
                if (artifact.Type == "text" || artifact.Url is null)
                    await File.WriteAllTextAsync(Path.Combine(folder, single ? "result.txt" : $"result-{i + 1}.txt"), artifact.Text ?? "").ConfigureAwait(false);
                else
                    await _client.DownloadAsync(artifact.Url, folder, $"result-{i + 1}", CancellationToken.None, authenticated: true).ConfigureAwait(false);
            }
            output = single ? Path.Combine(folder, "result.txt") : folder;
        }
        else
        {
            throw new WidgetTaskException("The Widget task failed without reporting a reason.", "no_result");
        }

        Update(id, r => r with { OutputPath = output, SettlementOutcome = "delivered" });
        await SaveAsync().ConfigureAwait(false);
        await SettleAsync(id).ConfigureAwait(false);
    }

    private static void ValidateDownload(string path, string? mime, IReadOnlyList<string>? allowed)
    {
        var info = new FileInfo(path);
        var bad = !info.Exists || info.Length == 0
            || mime is not null && (mime.Contains("html", StringComparison.OrdinalIgnoreCase) || mime.Contains("json", StringComparison.OrdinalIgnoreCase));
        if (!bad && mime is not null && !mime.Equals("application/octet-stream", StringComparison.OrdinalIgnoreCase))
        {
            var kinds = allowed is { Count: > 0 } ? allowed : ["image", "video", "audio"];
            bad = !kinds.Any(k => mime.StartsWith(k + "/", StringComparison.OrdinalIgnoreCase));
        }
        if (!bad) return;
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        throw new WidgetTaskException("The result could not be downloaded. Please check your connection and try again.", "download_invalid");
    }

    private static string ResultBaseName(WidgetTaskRecord record)
    {
        var command = record.CommandName.Replace('/', '-').Replace(':', '-');
        if (record.IsTextSource) return command.Length > 0 ? command : "Widget Result";
        var stem = "";
        try
        {
            stem = Uri.TryCreate(record.SourceUrl, UriKind.Absolute, out var uri) && !uri.IsFile
                ? Path.GetFileNameWithoutExtension(uri.AbsolutePath)
                : Path.GetFileNameWithoutExtension(record.SourceUrl);
        }
        catch (ArgumentException)
        {
        }
        stem = stem.Replace('/', '-').Replace(':', '-');
        return stem.Length > 0 ? $"{stem}.{command}" : command.Length > 0 ? command : "Widget Result";
    }

    /// <summary>Copies clipboard temp files and remote media into Downloads\Glance before upload.</summary>
    private async Task<string> LocalCopyAsync(string media)
    {
        if (Uri.TryCreate(media, UriKind.Absolute, out var uri) && !uri.IsFile)
        {
            var (path, _) = await _client.DownloadAsync(media, _downloads, $"input-{Guid.NewGuid():N}", CancellationToken.None).ConfigureAwait(false);
            return path;
        }
        var local = uri?.IsFile == true ? uri.LocalPath : media;
        if (!File.Exists(local)) throw new WidgetTaskException("The input file no longer exists. Open it again and retry.", "missing_input");
        return local;
    }

    /// <summary>A duration-priced video must still match what was quoted (size and SHA-256).</summary>
    private static async Task CheckEvidenceAsync(string path, JsonObject evidence)
    {
        var info = new FileInfo(path);
        var expectedSize = ApiEnvelope.Double(evidence["byteSize"]);
        var expectedHash = ApiEnvelope.Text(evidence["sha256"]);
        var hash = expectedHash is null ? null : await Sha256Async(path).ConfigureAwait(false);
        if (expectedSize is { } size && size != info.Length || expectedHash is not null && !expectedHash.Equals(hash, StringComparison.OrdinalIgnoreCase))
            throw new WidgetTaskException("The video changed. Check its price again.", "input_changed", 409);
    }

    public static async Task<string> Sha256Async(string path)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20, useAsync: true);
        return Convert.ToHexStringLower(await SHA256.HashDataAsync(stream).ConfigureAwait(false));
    }

    // ───────────────────────────── Billing & settlement ─────────────────────────────

    private void ApplyBilling(Guid id, string remoteId, WidgetTaskResult result)
    {
        var before = Find(id);
        var after = Update(id, r =>
        {
            var refunded = Math.Max(result.RefundedCredits ?? 0, r.RefundedCredits ?? 0);
            return r with
            {
                RemoteTaskId = remoteId,
                CreditCost = result.CreditCost ?? r.CreditCost,
                RefundedCredits = refunded > 0 ? refunded : r.RefundedCredits,
            };
        }, save: false);
        if (result.Balance is { } balance && _auth.Session is { } session) _auth.UpdateCredits(balance, session.Token);
        if (before is null || after is null) return;
        // The remote id must survive a restart (polling resumes, settlement can't be lost).
        if (before.RemoteTaskId != after.RemoteTaskId || before.CreditCost != after.CreditCost || before.RefundedCredits != after.RefundedCredits)
            _ = SaveAsync();
        if (before.CreditCost != after.CreditCost || before.RefundedCredits != after.RefundedCredits)
            _ = _auth.RefreshAccountAsync();
    }

    private async Task FailAsync(Guid id, WidgetTaskPhase phase, string message)
    {
        if (Find(id) is not { } record || record.Phase == WidgetTaskPhase.Cancelled) return;
        var settle = record.RequestKey is not null || record.RemoteTaskId is not null;
        Update(id, r => r with { Phase = phase, ErrorMessage = message, SettlementOutcome = settle ? "failed" : null });
        Log.Info($"Tasks: {id} {phase}: {message}");
        if (settle) await SettleAsync(id).ConfigureAwait(false);
    }

    private async Task FinishCancelledAsync(Guid id)
    {
        if (Find(id) is not { } record) return;
        var settle = record.RequestKey is not null || record.RemoteTaskId is not null;
        Update(id, r => r with { Phase = WidgetTaskPhase.Cancelled, ErrorMessage = "You cancelled this task.", SettlementOutcome = settle ? "failed" : null });
        if (settle) await SettleAsync(id).ConfigureAwait(false);
    }

    /// <summary>
    /// Reports the outcome until the service confirms it: delivered (charged) or failed (refunded).
    /// Retries after 5, 10, 20, 40, 60, 60… seconds; survives restarts via the saved outcome.
    /// </summary>
    private async Task SettleAsync(Guid id)
    {
        lock (_gate)
            if (!_settling.Add(id)) return;
        try
        {
            for (var attempt = 1; ; attempt++)
            {
                if (Find(id) is not { SettlementOutcome: { } outcome } record) return;
                if (record.OwnerUserId is { } owner && _auth.StoredUserId is { } user && owner != user) return;
                if (!_auth.IsSignedIn)
                {
                    // Reconciled again when the user signs in (ReconcileAll on auth change).
                    return;
                }
                try
                {
                    WidgetTaskResult result;
                    if (outcome == "delivered" && record.RemoteTaskId is { } remote)
                        result = await _client.SettleAsync(remote, CancellationToken.None).ConfigureAwait(false);
                    else if (record.RequestKey is { } key)
                        result = await _client.AbandonAsync(key, CancellationToken.None).ConfigureAwait(false);
                    else if (record.RemoteTaskId is { } remoteId)
                        result = await _client.GetAsync(remoteId, CancellationToken.None).ConfigureAwait(false);
                    else
                    {
                        Update(id, r => r with { SettlementOutcome = null });
                        return;
                    }
                    if (result.Status.Length == 0 && record.RemoteTaskId is { } lookup)
                        result = await _client.GetAsync(lookup, CancellationToken.None).ConfigureAwait(false);
                    if (record.RemoteTaskId is { } rid) ApplyBilling(id, rid, result);
                    if (Resolve(id, outcome, result)) return;
                }
                catch (WidgetTaskException ex) when (ex.Status == 409 && record.RemoteTaskId is { } remoteId)
                {
                    try
                    {
                        var current = await _client.GetAsync(remoteId, CancellationToken.None).ConfigureAwait(false);
                        ApplyBilling(id, remoteId, current);
                        if (Resolve(id, outcome, current)) return;
                    }
                    catch (WidgetTaskException inner)
                    {
                        Log.Info($"Tasks: billing lookup for {id} failed: {inner.Message}");
                    }
                }
                catch (WidgetTaskException ex) when (ex.Status == 401)
                {
                    return;
                }
                catch (WidgetTaskException ex) when (ex.Status == 404 && outcome == "failed")
                {
                    // The service never created the task: nothing was charged.
                    Update(id, r => r with { SettlementOutcome = null });
                    return;
                }
                catch (WidgetTaskException ex)
                {
                    Log.Info($"Tasks: settlement retry {attempt} for {id}: {ex.Message}");
                }
                var delay = Math.Min(60, 5 * (1 << Math.Min(attempt - 1, 4)));
                await Task.Delay(TimeSpan.FromSeconds(delay)).ConfigureAwait(false);
            }
        }
        finally
        {
            lock (_gate) _settling.Remove(id);
        }
    }

    /// <summary>Applies a confirmed settlement. False while the service hasn't finalized it.</summary>
    private bool Resolve(Guid id, string outcome, WidgetTaskResult result)
    {
        if (outcome == "delivered")
        {
            if (result.Delivered == true && result.IsSuccess)
            {
                var record = Find(id);
                if (record?.OutputPath is not { } output || !File.Exists(output) && !Directory.Exists(output))
                {
                    Update(id, r => r with { Phase = WidgetTaskPhase.Failed, SettlementOutcome = null, ErrorMessage = "The result could not be downloaded. Please check your connection and try again." });
                    return true;
                }
                var done = Update(id, r => r with { Phase = WidgetTaskPhase.Completed, Progress = 100, SettlementOutcome = null, ErrorMessage = null });
                if (done is not null)
                {
                    Log.Info($"Tasks: {id} completed");
                    Post(() => Completed?.Invoke(done));
                }
                _ = _auth.RefreshAccountAsync();
                return true;
            }
            if (result.IsTerminalFailure && result.IsRefunded)
            {
                Update(id, r => r with { Phase = WidgetTaskPhase.Failed, SettlementOutcome = null, ErrorMessage = "Result confirmation timed out. Credits were refunded. Please run the task again." });
                _ = _auth.RefreshAccountAsync();
                return true;
            }
            return false;
        }
        if (result.SettlementResolved || result.IsTerminalFailure && result.IsRefunded)
        {
            Update(id, r => r with { SettlementOutcome = null });
            _ = _auth.RefreshAccountAsync();
            return true;
        }
        return false;
    }

    // ───────────────────────────── User actions ─────────────────────────────

    public void Cancel(Guid id)
    {
        if (Find(id) is not { CanCancel: true } record) return;
        lock (_gate) _cancelRequested.Add(id);
        Log.Info($"Tasks: cancel {id}");
        _ = Task.Run(async () =>
        {
            if (record.RemoteTaskId is { } remote) await _client.CancelAsync(remote).ConfigureAwait(false);
            bool running;
            lock (_gate) running = _running.Contains(id);
            if (!running || record.RemoteTaskId is not null) await FinishCancelledAsync(id).ConfigureAwait(false);
        });
    }

    /// <summary>
    /// Retry without a new charge when possible: a pending settlement is reconciled; a completed
    /// task whose result file went missing is downloaded again from the same remote task. Returns
    /// false when a new task (new quote, new charge) is needed — the app starts it.
    /// </summary>
    public bool TryResume(Guid id)
    {
        if (Find(id) is not { } record) return false;
        if (record.HasPendingSettlement)
        {
            _ = Task.Run(() => SettleAsync(id));
            return true;
        }
        if (record.Phase == WidgetTaskPhase.Completed && record.RemoteTaskId is { } remote && (record.RefundedCredits ?? 0) == 0
            && record.OutputPath is { } output && !File.Exists(output) && !Directory.Exists(output))
        {
            Update(id, r => r with { Phase = WidgetTaskPhase.Processing, Progress = 0, OutputPath = null });
            _ = Task.Run(async () =>
            {
                try
                {
                    await PollAsync(id, remote).ConfigureAwait(false);
                }
                catch (WidgetTaskException ex)
                {
                    await FailAsync(id, WidgetTaskPhase.Failed, ex.Message).ConfigureAwait(false);
                }
            });
            return true;
        }
        return false;
    }

    public bool Remove(Guid id)
    {
        lock (_gate)
        {
            if (_records.FirstOrDefault(r => r.Id == id) is not { IsActive: false, HasPendingSettlement: false } record) return false;
            _records.Remove(record);
        }
        _ = SaveAsync();
        Notify();
        return true;
    }

    /// <summary>Clears finished history; running and settling records stay.</summary>
    public void ClearFinished()
    {
        lock (_gate) _records.RemoveAll(r => !r.IsActive && !r.HasPendingSettlement);
        _ = SaveAsync();
        Notify();
    }

    /// <summary>Drops failure records for these sources (when their Inspect window closes).</summary>
    public void ClearFailed(IEnumerable<string> sources)
    {
        var keys = sources.Select(WidgetTaskRecord.MediaKey).ToHashSet();
        int removed;
        lock (_gate) removed = _records.RemoveAll(r => r.IsFailure && !r.HasPendingSettlement && keys.Contains(WidgetTaskRecord.MediaKey(r.SourceUrl)));
        if (removed == 0) return;
        _ = SaveAsync();
        Notify();
    }

    // ───────────────────────────── Startup ─────────────────────────────

    /// <summary>Loads history, resumes polling for submitted tasks and reconciles pending settlements.</summary>
    public async Task StartUpAsync()
    {
        try
        {
            if (File.Exists(_storeFile))
            {
                var json = await File.ReadAllTextAsync(_storeFile).ConfigureAwait(false);
                var loaded = JsonSerializer.Deserialize<List<WidgetTaskRecord>>(json, Json) ?? [];
                lock (_gate) _records = loaded.OrderByDescending(r => r.CreatedAt).ToList();
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            Log.Warning($"Tasks: could not read task history: {ex.Message}");
        }
        var user = _auth.StoredUserId;
        foreach (var record in Records.Where(r => r.IsActive && !r.HasPendingSettlement && (r.OwnerUserId is null || r.OwnerUserId == user)))
        {
            if (record.RemoteTaskId is not { } remote)
            {
                await FailAsync(record.Id, WidgetTaskPhase.Interrupted, "Glance closed before the task was submitted. Nothing was charged; run it again.").ConfigureAwait(false);
                continue;
            }
            var id = record.Id;
            _ = Task.Run(async () =>
            {
                try
                {
                    await PollAsync(id, remote).ConfigureAwait(false);
                }
                catch (WidgetTaskException ex)
                {
                    await FailAsync(id, ex.Code == "expired" ? WidgetTaskPhase.Expired : WidgetTaskPhase.Failed, ex.Message).ConfigureAwait(false);
                }
            });
        }
        ReconcileAll();
        Notify();
    }

    /// <summary>Re-runs pending settlements (startup and after sign-in).</summary>
    public void ReconcileAll()
    {
        foreach (var record in Records.Where(r => r.HasPendingSettlement))
        {
            var id = record.Id;
            _ = Task.Run(() => SettleAsync(id));
        }
    }

    // ───────────────────────────── State ─────────────────────────────

    private bool IsCancelRequested(Guid id)
    {
        lock (_gate) return _cancelRequested.Contains(id);
    }

    /// <summary>Replaces a record (cancelled records never change phase again) and saves.</summary>
    private WidgetTaskRecord? Update(Guid id, Func<WidgetTaskRecord, WidgetTaskRecord> change, bool save = true)
    {
        WidgetTaskRecord? updated;
        lock (_gate)
        {
            var index = _records.FindIndex(r => r.Id == id);
            if (index < 0) return null;
            var current = _records[index];
            updated = change(current) with { UpdatedAt = DateTimeOffset.UtcNow };
            if (current.Phase == WidgetTaskPhase.Cancelled && updated.Phase != WidgetTaskPhase.Cancelled) updated = updated with { Phase = WidgetTaskPhase.Cancelled };
            _records[index] = updated;
        }
        if (save) _ = SaveAsync();
        Notify();
        return updated;
    }

    private void Replace(WidgetTaskRecord record)
    {
        var index = _records.FindIndex(r => r.Id == record.Id);
        if (index >= 0) _records[index] = record;
    }

    /// <summary>Keeps every pending record plus the newest history, up to 200.</summary>
    private async Task<bool> SaveAsync()
    {
        List<WidgetTaskRecord> snapshot;
        lock (_gate)
        {
            var pending = _records.Where(r => r.IsActive || r.HasPendingSettlement).ToList();
            var history = _records.Where(r => !r.IsActive && !r.HasPendingSettlement).Take(Math.Max(0, HistoryLimit - pending.Count));
            snapshot = pending.Concat(history).OrderByDescending(r => r.CreatedAt).ToList();
            _records = snapshot.ToList();
        }
        await _saveLock.WaitAsync().ConfigureAwait(false);
        try
        {
            var json = JsonSerializer.Serialize(snapshot, Json);
            await Task.Run(() => AtomicFile.WriteAllText(_storeFile, json)).ConfigureAwait(false);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Warning($"Tasks: could not save task history: {ex.Message}");
            return false;
        }
        finally
        {
            _saveLock.Release();
        }
    }

    private void Notify() => Post(() => Changed?.Invoke(this, EventArgs.Empty));

    private void Post(Action action)
    {
        if (_ui is null) action();
        else _ui.Post(_ => action(), null);
    }
}
