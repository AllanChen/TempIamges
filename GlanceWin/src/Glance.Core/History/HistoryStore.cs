using System.Text.Json;
using System.Text.Json.Serialization;
using Glance.Core.Detection;
using Glance.Core.Logging;

namespace Glance.Core.History;

/// <summary>
/// One hotkey-triggered preview. Only resolved items are stored — never the surrounding
/// selected text, which may contain unrelated terminal, code or chat content.
/// </summary>
public sealed record HistoryRecord(DateTime Timestamp, IReadOnlyList<HistoryItem> Items);

public sealed record HistoryItem(DetectedKind Kind, string Value)
{
    public DetectedPath ToDetectedPath() => new(Kind, Value);
    public static HistoryItem From(DetectedPath path) => new(path.Kind, path.Value);
}

/// <summary>Recent previews (port of macOS <c>HistoryManager</c>): newest first, 200 records, JSON.</summary>
public sealed class HistoryStore
{
    private const int MaxRecords = 200;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly string _path;
    private readonly object _lock = new();
    private readonly SemaphoreSlim _saveGate = new(1, 1);
    private List<HistoryRecord> _records = [];

    public HistoryStore(string path)
    {
        _path = path;
        Load();
    }

    /// <summary>Raised on the thread that changed history.</summary>
    public event EventHandler? Changed;

    public IReadOnlyList<HistoryRecord> Records
    {
        get { lock (_lock) return _records.ToList(); }
    }

    public void Record(IEnumerable<DetectedPath> paths)
    {
        var items = paths.Where(p => p.IsResolved).Select(HistoryItem.From).ToList();
        if (items.Count == 0) return;
        lock (_lock)
        {
            // Re-peeking the same thing moves it to the top instead of duplicating it.
            _records.RemoveAll(r => r.Items.SequenceEqual(items));
            _records.Insert(0, new HistoryRecord(DateTime.UtcNow, items));
            if (_records.Count > MaxRecords) _records.RemoveRange(MaxRecords, _records.Count - MaxRecords);
        }
        SaveAsync();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Remove(HistoryRecord record)
    {
        lock (_lock) _records.Remove(record);
        SaveAsync();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Clear()
    {
        lock (_lock) _records.Clear();
        SaveAsync();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path)) return;
            _records = JsonSerializer.Deserialize<List<HistoryRecord>>(File.ReadAllText(_path), JsonOptions) ?? [];
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException or NotSupportedException)
        {
            Log.Warning($"History unreadable, starting empty: {ex.Message}");
        }
    }

    private void SaveAsync()
    {
        List<HistoryRecord> snapshot;
        lock (_lock) snapshot = _records.ToList();
        _ = Task.Run(async () =>
        {
            await _saveGate.WaitAsync();
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                var temp = _path + ".tmp";
                await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(snapshot, JsonOptions));
                File.Move(temp, _path, overwrite: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                Log.Warning($"History save failed: {ex.Message}");
            }
            finally
            {
                _saveGate.Release();
            }
        });
    }
}
