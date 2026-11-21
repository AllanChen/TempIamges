using System.Text.Json;
using Glance.Core.Logging;

namespace Glance.Core.Search;

/// <summary>
/// Persistent token → absolute path cache (port of macOS <c>FilenameCache</c>): LRU, 500 entries.
/// Hits are re-validated against the file system. Saves run off the calling thread.
/// </summary>
public sealed class FilenameCache
{
    private const int MaxEntries = 500;

    private sealed record Entry(string Path, DateTime Timestamp);

    private readonly string _storePath;
    private readonly Func<string, bool> _fileExists;
    private readonly object _lock = new();
    private readonly SemaphoreSlim _saveGate = new(1, 1);
    private Dictionary<string, Entry> _entries = new(StringComparer.OrdinalIgnoreCase);

    public FilenameCache(string storePath, Func<string, bool>? fileExists = null)
    {
        _storePath = storePath;
        _fileExists = fileExists ?? File.Exists;
        Load();
    }

    public int Count
    {
        get { lock (_lock) return _entries.Count; }
    }

    public string? Lookup(string token)
    {
        lock (_lock)
        {
            if (!_entries.TryGetValue(token, out var entry)) return null;
            if (!_fileExists(entry.Path))
            {
                _entries.Remove(token);
                SaveAsync();
                return null;
            }
            _entries[token] = entry with { Timestamp = DateTime.UtcNow };
            return entry.Path;
        }
    }

    public void Store(string token, string path)
    {
        lock (_lock)
        {
            _entries[token] = new Entry(path, DateTime.UtcNow);
            if (_entries.Count > MaxEntries)
            {
                foreach (var key in _entries.OrderBy(e => e.Value.Timestamp).Take(_entries.Count - MaxEntries)
                             .Select(e => e.Key).ToList())
                    _entries.Remove(key);
            }
        }
        SaveAsync();
    }

    public void Clear()
    {
        lock (_lock) _entries.Clear();
        SaveAsync();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_storePath)) return;
            var loaded = JsonSerializer.Deserialize<Dictionary<string, Entry>>(File.ReadAllText(_storePath));
            if (loaded is not null) _entries = new Dictionary<string, Entry>(loaded, StringComparer.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            Log.Warning($"FilenameCache unreadable, starting empty: {ex.Message}");
        }
    }

    private void SaveAsync()
    {
        Dictionary<string, Entry> snapshot;
        lock (_lock) snapshot = new Dictionary<string, Entry>(_entries);
        _ = Task.Run(async () =>
        {
            await _saveGate.WaitAsync();
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_storePath)!);
                var temp = _storePath + ".tmp";
                await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(snapshot));
                File.Move(temp, _storePath, overwrite: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                Log.Warning($"FilenameCache save failed: {ex.Message}");
            }
            finally
            {
                _saveGate.Release();
            }
        });
    }
}
