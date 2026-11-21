using System.Collections.Concurrent;
using System.Diagnostics;
using Glance.Core.Logging;

namespace Glance.Core.Search;

public sealed record FileMatch(string Path, DateTime? LastModified, bool IsInUserHome);

/// <summary>Folders the resolver searches. Built by the platform layer from Windows known folders.</summary>
public sealed record ResolverEnvironment(
    string Home,
    string Desktop,
    string Documents,
    string Downloads,
    IReadOnlyList<string> ExtraDeepRoots)
{
    public static ResolverEnvironment FromSpecialFolders()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return new ResolverEnvironment(
            home,
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            Path.Combine(home, "Downloads"),
            []);
    }
}

/// <summary>Indexed filename search (Windows Search on Windows; Spotlight's role on macOS).</summary>
public interface IIndexSearch
{
    IReadOnlyList<string> FindByFileName(string fileName, int limit, CancellationToken cancellationToken);
}

/// <summary>
/// Resolves bare filenames / relative paths to files (port of macOS <c>FileNameResolver</c>).
/// Cascade: cache → quick bounded walk of likely folders (0.5 s) → in parallel, the search
/// index and a deep bounded walk (1.0 s), cut off at the overall timeout (1.5 s).
/// Everything runs off the calling thread.
/// </summary>
public sealed class FileNameResolver
{
    private const int QuickMaxDirectories = 20_000;
    private static readonly TimeSpan QuickBudget = TimeSpan.FromMilliseconds(500);
    private const int QuickMaxDepth = 10;

    private const int DeepMaxDirectories = 50_000;
    private static readonly TimeSpan DeepBudget = TimeSpan.FromSeconds(1.0);
    private const int DeepMaxDepth = 12;

    private static readonly string[] BlocklistSubstrings =
    [
        @"\$Recycle.Bin\", @"\AppData\Local\Temp\", @"\AppData\Local\Microsoft\Windows\INetCache\",
        @"\.git\", @"\node_modules\", @"\System Volume Information\",
    ];

    private static readonly HashSet<string> SkippedDirectoryNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ".git", ".svn", ".hg", "node_modules", "DerivedData", "build", "dist", ".build", ".dart_tool",
        ".next", ".nuxt", ".cache", "Pods", "bin", "obj", ".vs", ".idea", "packages",
        "AppData", "$Recycle.Bin", "System Volume Information", "Windows", "Program Files",
        "Program Files (x86)", "ProgramData", "Music", "Videos",
    };

    private static readonly string[] ProjectDirectoryNames =
        ["Projects", "Workspace", "Code", "Dev", "work", "src", "repos", @"source\repos"];

    private static readonly EnumerationOptions Enumeration = new()
    {
        IgnoreInaccessible = true,
        RecurseSubdirectories = false,
        // Profile junctions ("My Documents", "Application Data") are Hidden|System: skipping
        // them also prevents junction loops. OneDrive placeholders are reparse points but
        // not hidden, so they stay searchable.
        AttributesToSkip = FileAttributes.Hidden | FileAttributes.System,
    };

    private readonly ResolverEnvironment _env;
    private readonly FilenameCache _cache;
    private readonly IIndexSearch? _index;

    public FileNameResolver(ResolverEnvironment env, FilenameCache cache, IIndexSearch? index)
    {
        _env = env;
        _cache = cache;
        _index = index;
    }

    public async Task<IReadOnlyList<FileMatch>> ResolveAsync(string token, int limit = 24,
        TimeSpan? timeout = null, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeToken(token);
        if (normalized.Length == 0) return [];

        if (_cache.Lookup(normalized) is { } cached)
        {
            Log.Info($"FileNameResolver: cache hit for '{Log.Redact(token)}'");
            return [new FileMatch(cached, null, IsUnder(cached, _env.Home))];
        }

        var basename = Path.GetFileName(normalized);
        if (basename.Length == 0) return [];
        var suffix = normalized.Contains('\\') ? "\\" + normalized : null;

        var quick = await Task.Run(() => QuickMatches(normalized, basename, suffix, limit, cancellationToken), cancellationToken);
        if (quick.Count > 0)
        {
            _cache.Store(normalized, quick[0].Path);
            Log.Info($"FileNameResolver: quick hit for '{Log.Redact(token)}' -> {quick.Count}");
            return quick;
        }

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var found = new ConcurrentDictionary<string, FileMatch>(StringComparer.OrdinalIgnoreCase);
        void Add(IEnumerable<FileMatch> matches)
        {
            foreach (var m in matches) found.TryAdd(m.Path, m);
        }

        var tasks = new List<Task>
        {
            Task.Run(() => Add(DeepMatches(basename, suffix, limit, cts.Token)), cts.Token),
        };
        if (_index is not null)
        {
            tasks.Add(Task.Run(() => Add(IndexMatches(basename, suffix, limit, cts.Token)), cts.Token));
        }

        var all = Task.WhenAll(tasks);
        // Searches abandoned at the timeout may still fault later; observe them so they don't surface as unobserved.
        _ = all.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);
        var finished = await Task.WhenAny(all, Task.Delay(timeout ?? TimeSpan.FromSeconds(1.5), cancellationToken));
        cts.Cancel();
        if (finished == all && all.IsFaulted) Log.Warning($"FileNameResolver: search failed: {all.Exception?.GetBaseException().Message}");
        cancellationToken.ThrowIfCancellationRequested();

        var sorted = Sort(found.Values, limit);
        Log.Info($"FileNameResolver: '{Log.Redact(token)}' -> {sorted.Count} [{(finished == all ? "completed" : "timeout")}]");
        if (sorted.Count > 0) _cache.Store(normalized, sorted[0].Path);
        return sorted;
    }

    /// <summary>Trims quotes/whitespace/trailing punctuation, unifies separators, drops leading ".\".</summary>
    internal static string NormalizeToken(string token)
    {
        // Repeat until stable: "\"shot.png\"," needs comma, then quote, removed in turn.
        var t = token;
        string previous;
        do
        {
            previous = t;
            t = t.Trim().Trim('"', '\'', '`', '“', '”', '‘', '’')
                 .TrimEnd(',', '.', ';', ':', '!', '?', ')', ']', '}', '，', '。', '；', '：');
        } while (t != previous);
        t = t.Replace('/', '\\');
        while (t.StartsWith(@".\") || t.StartsWith(@"..\")) t = t[(t.IndexOf('\\') + 1)..];
        return t.Trim('\\');
    }

    // ---- quick / deep walks -------------------------------------------------------------

    private List<FileMatch> QuickMatches(string token, string basename, string? suffix, int limit, CancellationToken ct)
    {
        var matches = new List<FileMatch>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var candidate in DirectCandidates(token))
        {
            if (matches.Count >= limit) break;
            if (MakeMatch(candidate) is { } m && MatchesSuffix(m.Path, suffix) && seen.Add(m.Path)) matches.Add(m);
        }
        if (matches.Count > 0) return Sort(matches, limit);

        var clock = Stopwatch.StartNew();
        var visited = 0;
        foreach (var root in QuickRoots())
        {
            if (clock.Elapsed >= QuickBudget || ct.IsCancellationRequested) break;
            Walk(root, basename, suffix, QuickMaxDepth, limit, clock, QuickBudget, QuickMaxDirectories, ref visited, seen, matches, ct);
            if (matches.Count >= limit || visited >= QuickMaxDirectories) break;
        }
        return Sort(matches, limit);
    }

    private List<FileMatch> DeepMatches(string basename, string? suffix, int limit, CancellationToken ct)
    {
        var matches = new List<FileMatch>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var clock = Stopwatch.StartNew();
        var visited = 0;
        foreach (var root in DeepRoots())
        {
            if (clock.Elapsed >= DeepBudget || ct.IsCancellationRequested) break;
            Walk(root, basename, suffix, DeepMaxDepth, limit, clock, DeepBudget, DeepMaxDirectories, ref visited, seen, matches, ct);
            if (matches.Count >= limit || visited >= DeepMaxDirectories) break;
        }
        return matches;
    }

    private IEnumerable<FileMatch> IndexMatches(string basename, string? suffix, int limit, CancellationToken ct)
    {
        var paths = _index!.FindByFileName(basename, limit, ct);
        foreach (var path in paths)
            if (MakeMatch(path) is { } m && MatchesSuffix(m.Path, suffix))
                yield return m;
    }

    /// <summary>Breadth-first, newest directories first, bounded by depth, count and time.</summary>
    private static void Walk(string root, string basename, string? suffix, int maxDepth, int limit,
        Stopwatch clock, TimeSpan budget, int maxDirectories, ref int visited,
        HashSet<string> seen, List<FileMatch> matches, CancellationToken ct)
    {
        var queue = new Queue<(string Dir, int Depth)>();
        queue.Enqueue((root, 0));
        while (queue.Count > 0 && matches.Count < limit && visited < maxDirectories
               && clock.Elapsed < budget && !ct.IsCancellationRequested)
        {
            var (dir, depth) = queue.Dequeue();
            visited++;
            var childDirs = new List<(string Path, DateTime Modified)>();
            try
            {
                foreach (var entry in new DirectoryInfo(dir).EnumerateFileSystemInfos("*", Enumeration))
                {
                    if (entry is DirectoryInfo sub)
                    {
                        if (depth < maxDepth && !SkippedDirectoryNames.Contains(sub.Name))
                            childDirs.Add((sub.FullName, sub.LastWriteTimeUtc));
                    }
                    else if (string.Equals(entry.Name, basename, StringComparison.OrdinalIgnoreCase)
                             && MatchesSuffix(entry.FullName, suffix)
                             && !IsBlocked(entry.FullName)
                             && seen.Add(entry.FullName))
                    {
                        matches.Add(new FileMatch(entry.FullName, entry.LastWriteTimeUtc, false));
                        if (matches.Count >= limit) break;
                    }
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            {
                continue;
            }
            foreach (var child in childDirs.OrderByDescending(c => c.Modified)) queue.Enqueue((child.Path, depth + 1));
        }
    }

    // ---- roots ----------------------------------------------------------------------------

    private IEnumerable<string> CommonRoots() =>
        Unique([_env.Home, _env.Desktop, _env.Documents, _env.Downloads]).Where(Directory.Exists);

    private IEnumerable<string> PreferredRoots() => Unique([_env.Desktop, _env.Downloads, _env.Documents]);

    private IEnumerable<string> QuickRoots()
    {
        var roots = new List<string>();
        roots.AddRange(CommonRoots().Where(r => !SamePath(r, _env.Home)));
        foreach (var root in PreferredRoots().Where(Directory.Exists))
            roots.AddRange(ShallowDirectories(root, maxDepth: 1, limit: 200));
        roots.Add(_env.Home);
        return Unique(roots);
    }

    private IEnumerable<string> DeepRoots()
    {
        var roots = new List<string>();
        foreach (var name in ProjectDirectoryNames)
        {
            var dir = Path.Combine(_env.Home, name);
            if (Directory.Exists(dir)) roots.Add(dir);
        }
        roots.AddRange(CommonRoots());
        roots.AddRange(_env.ExtraDeepRoots.Where(Directory.Exists));
        return Unique(roots);
    }

    /// <summary>For a relative token, try it under the common roots and their recent subfolders.</summary>
    private IEnumerable<string> DirectCandidates(string token)
    {
        if (!token.Contains('\\')) yield break;
        var roots = CommonRoots().ToList();
        foreach (var root in PreferredRoots().Where(Directory.Exists))
            roots.AddRange(ShallowDirectories(root, maxDepth: 2, limit: 500));
        foreach (var root in Unique(roots))
            yield return Path.Combine(root, token);
    }

    private static List<string> ShallowDirectories(string root, int maxDepth, int limit)
    {
        var result = new List<string>();
        var queue = new Queue<(string Dir, int Depth)>();
        queue.Enqueue((root, 0));
        var clock = Stopwatch.StartNew();
        while (queue.Count > 0 && result.Count < limit && clock.Elapsed < QuickBudget)
        {
            var (dir, depth) = queue.Dequeue();
            if (depth >= maxDepth) continue;
            List<DirectoryInfo> children;
            try
            {
                children = new DirectoryInfo(dir).EnumerateDirectories("*", Enumeration)
                    .Where(d => !SkippedDirectoryNames.Contains(d.Name))
                    .OrderByDescending(d => d.LastWriteTimeUtc)
                    .ToList();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            foreach (var child in children)
            {
                result.Add(child.FullName);
                if (depth + 1 < maxDepth) queue.Enqueue((child.FullName, depth + 1));
                if (result.Count >= limit) break;
            }
        }
        return result;
    }

    // ---- matching / ranking -----------------------------------------------------------------

    private FileMatch? MakeMatch(string path)
    {
        try
        {
            var full = Path.GetFullPath(path);
            if (IsBlocked(full)) return null;
            var info = new FileInfo(full);
            if (!info.Exists) return null;
            return new FileMatch(info.FullName, info.LastWriteTimeUtc, IsUnder(info.FullName, _env.Home));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return null;
        }
    }

    private List<FileMatch> Sort(IEnumerable<FileMatch> matches, int limit)
    {
        var preferred = PreferredRoots().ToList();
        return matches
            .Select(m => m with { IsInUserHome = IsUnder(m.Path, _env.Home) })
            .OrderByDescending(m => preferred.Any(p => IsUnder(m.Path, p)))
            .ThenByDescending(m => m.IsInUserHome)
            .ThenByDescending(m => m.LastModified.HasValue)
            .ThenByDescending(m => m.LastModified ?? DateTime.MinValue)
            .ThenBy(m => m.Path.Length)
            .Take(limit)
            .ToList();
    }

    private static bool MatchesSuffix(string path, string? suffix) =>
        suffix is null || path.EndsWith(suffix, StringComparison.OrdinalIgnoreCase);

    private static bool IsBlocked(string path) =>
        BlocklistSubstrings.Any(b => path.Contains(b, StringComparison.OrdinalIgnoreCase));

    internal static bool IsUnder(string path, string root)
    {
        if (string.IsNullOrEmpty(root)) return false;
        var r = root.TrimEnd('\\');
        return path.Equals(r, StringComparison.OrdinalIgnoreCase)
               || path.StartsWith(r + "\\", StringComparison.OrdinalIgnoreCase);
    }

    private static bool SamePath(string a, string b) =>
        string.Equals(a.TrimEnd('\\'), b.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    private static IEnumerable<string> Unique(IEnumerable<string> paths) =>
        paths.Where(p => !string.IsNullOrEmpty(p)).Distinct(StringComparer.OrdinalIgnoreCase);
}
