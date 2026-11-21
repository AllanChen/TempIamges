using System.Text;
using System.Text.RegularExpressions;
using Glance.Core.Logging;

namespace Glance.Core.Detection;

/// <summary>File-system access used by <see cref="PathDetector"/>; replaceable in tests.</summary>
public interface IFileProbe
{
    bool FileExists(string path);
    bool DirectoryExists(string path);
    string HomeDirectory { get; }
    string ExpandEnvironmentVariables(string value);
}

public sealed class RealFileProbe : IFileProbe
{
    public static RealFileProbe Instance { get; } = new();
    public bool FileExists(string path) => File.Exists(path);
    public bool DirectoryExists(string path) => Directory.Exists(path);
    public string HomeDirectory => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public string ExpandEnvironmentVariables(string value) => Environment.ExpandEnvironmentVariables(value);
}

/// <summary>
/// Extracts URLs, local paths, relative paths and bare filenames from selected text.
/// Port of macOS <c>PathDetector</c>: same priorities, lazy-match extension, dedup and
/// bare-filename fallbacks, plus Windows forms — <c>C:\…</c>, <c>\\server\share\…</c>,
/// <c>%VAR%\…</c>, <c>~\…</c>, <c>file:///C:/…</c> and WSL / Git-Bash <c>/mnt/c/…</c>, <c>/c/…</c>.
/// </summary>
public sealed class PathDetector
{
    private const int MaxTextLength = 20_000;
    private const int MaxBareCandidates = 16;
    private const int MaxNoExtCandidates = 3;
    private static readonly TimeSpan RegexTimeout = TimeSpan.FromMilliseconds(250);

    private const string TrailingPunctuation = ",.;!?\"'()[{]}\\，。；：！？、";
    private const string FolderTrailingPunctuation = ",.;!?\"')]}";
    private const string BoundaryPunctuation = "\"'<>()[]{},;!?";

    /// <summary>POSIX path character (macOS rules): no quotes, brackets, commas, tabs or newlines.</summary>
    private const string PosixChar = @"[^""'<>()\[\]{},\n\r\t\\]";
    /// <summary>
    /// Windows path character: everything except characters Windows forbids in names, plus
    /// comma (list separator) and line breaks. Parentheses and brackets are allowed because
    /// "photo (1).png" is the Windows duplicate-file convention; the lazy match still stops
    /// at the first known extension, and trailing ')' is trimmed afterwards.
    /// </summary>
    private const string WinChar = @"[^""'<>|*?,\n\r\t]";

    private static readonly HashSet<string> KnownTlds = new(StringComparer.OrdinalIgnoreCase)
    {
        "com", "net", "org", "io", "ai", "app", "dev", "co", "me", "info", "xyz", "page", "site", "store", "tech",
        "gov", "edu", "cn", "uk", "de", "jp", "fr", "ru", "us", "tv", "gg", "so", "to", "sh", "ly", "cc", "hk",
        "sg", "tw", "kr", "in", "br", "ca", "au", "nl", "eu", "ch", "se", "no", "es", "it", "pl",
    };

    private static readonly Regex[] QueryFormatPatterns =
    [
        new(@"(?:^|[&/])(?:format|fm|ext)[=/]([a-z0-9]+)", RegexOptions.CultureInvariant),
    ];

    private static readonly string[] BangTokens =
    [
        "jpeg", "webp", "heic", "heif", "tiff", "avif", "jxl",
        "svg", "jp2", "webm", "png", "jpg", "gif", "bmp",
        "mp4", "mov", "m4v", "mkv", "avi",
    ];

    private readonly IFileProbe _fs;
    private readonly Regex _http, _bareDomain, _fileUrl, _drive, _unc, _env, _home, _posix, _relative;
    private readonly Regex _bareFile, _bareNoExt, _extTail;
    private readonly Regex _driveFolder, _uncFolder, _homeFolder, _envFolder;

    public PathDetector(IFileProbe? probe = null)
    {
        _fs = probe ?? RealFileProbe.Instance;

        // Longest first so "markdown" wins over "md".
        var ext = string.Join("|", FileKinds.AllLocal.OrderByDescending(e => e.Length).Select(Regex.Escape));
        var tail = $@"+?\.(?i:{ext})";

        _http = Make(@"https?:?//[^\s""'<>]+");
        _bareDomain = Make(@"(?<![A-Za-z0-9._/@\\-])(?:www\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:com|net|org|io|ai|app|dev|co|me|info|xyz|page|site|store|tech|gov|edu))(?:/[^\s""'<>()\[\]{},\\]*)?(?![A-Za-z0-9])");
        _fileUrl = Make(@"file:/{2,3}" + WinChar + tail);
        _drive = Make(@"(?<![\p{L}\p{N}_])[A-Za-z]:[\\/]" + WinChar + tail);
        _unc = Make(@"(?<![\p{L}\p{N}_\\])\\\\[^\\/\s""'<>|*?,]+\\" + WinChar + tail);
        _env = Make(@"%[A-Za-z_][A-Za-z0-9_()]*%[\\/]" + WinChar + tail);
        _home = Make(@"(?<![\p{L}\p{N}_])~[\\/]" + WinChar + tail);
        _posix = Make(@"(?<![\p{L}\p{N}_.:~\\/%-])/" + PosixChar + tail);
        _relative = Make(@"(?<![\p{L}\p{N}_/\\~:%])(?:\.{1,2}[\\/])*[\p{L}\p{N}_.\-]+[\\/][\p{L}\p{N}_.\\/\- \t()]+?\.(?i:" + ext + @")(?![\p{L}\p{N}])");
        // Group 1 is the name; an optional "](" or " (" after it marks a link like "a.gif (dir/a.gif)".
        _bareFile = Make(@"(?<![\p{L}\p{N}_./\\~:%-])([\p{L}\p{N}_][\p{L}\p{N}_.\- ]+?\.(?i:" + ext + @")(?![\p{L}\p{N}]))(?:\]?[ \t]*\()?");
        _extTail = Make(@"\.(?i:" + ext + @")(?![\p{L}\p{N}])");
        _bareNoExt = Make(@"(?<![\p{L}\p{N}_./\\~:%-])[\p{L}\p{N}_][\p{L}\p{N}_\-]{2,29}(?![\p{L}\p{N}])");

        _driveFolder = Make(@"(?<![\p{L}\p{N}_])[A-Za-z]:\\[^""'<>|*?,\n\r\t]*");
        _uncFolder = Make(@"(?<![\p{L}\p{N}_\\])\\\\[^\\/\s""'<>|*?,]+\\[^""'<>|*?,\n\r\t]*");
        _homeFolder = Make(@"(?<![\p{L}\p{N}_])~[\\/][^""'<>|*?,\n\r\t]*");
        _envFolder = Make(@"%[A-Za-z_][A-Za-z0-9_()]*%(?:[\\/][^""'<>|*?,\n\r\t]*)?");
    }

    private static Regex Make(string pattern) => new(pattern, RegexOptions.CultureInvariant, RegexTimeout);

    public DetectedPath? Detect(string text) => DetectAll(text).FirstOrDefault();

    public IReadOnlyList<DetectedPath> DetectAll(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return [];
        if (trimmed.Length > MaxTextLength) trimmed = trimmed[..MaxTextLength];

        try
        {
            var results = CollectAll(trimmed);
            if (results.Count == 0)
            {
                // Soft-wrapped editors and OCR break long URLs/paths across lines.
                var unwrapped = UnwrapLines(trimmed);
                if (unwrapped != trimmed) results = CollectAll(unwrapped);
            }
            Log.Info($"PathDetector: detected {results.Count} candidate(s)");
            return results;
        }
        catch (RegexMatchTimeoutException)
        {
            Log.Warning("PathDetector: regex timed out; selection ignored");
            return [];
        }
    }

    /// <summary>Classifies an existing local path (used to rehydrate search results).</summary>
    public DetectedPath LocalKind(string path)
    {
        if (_fs.DirectoryExists(path)) return new DetectedPath(DetectedKind.LocalFolder, path);
        var kind = FileKinds.KindForExtension(FileKinds.ExtensionOf(path));
        return new DetectedPath(DetectedPath.LocalKindFor(kind), path);
    }

    private readonly record struct Hit(int Index, int Length, string Text, int Priority);

    /// <summary>Longer candidates ending at each later ".ext" (spaces allowed), the first that exists wins.</summary>
    private (DetectedPath Path, int End)? ExtendToLaterExtension(string text, int start, int end)
    {
        var from = end;
        for (var attempt = 0; attempt < 16 && from < text.Length; attempt++)
        {
            var m = _extTail.Match(text, from);
            if (!m.Success) return null;
            var stop = m.Index + m.Length;
            if (text.AsSpan(end, stop - end).IndexOfAny("\"'<>|\n\r\t") >= 0) return null;
            if (ResolveCandidate(text[start..stop]) is { } path) return (path, stop);
            from = m.Index + 1;
        }
        return null;
    }

    private List<DetectedPath> CollectAll(string text)
    {
        var hits = new List<Hit>();
        void AddHits(Regex regex, int priority)
        {
            foreach (Match m in regex.Matches(text)) hits.Add(new Hit(m.Index, m.Length, m.Value, priority));
        }

        AddHits(_http, 0);
        AddHits(_fileUrl, 1);
        AddHits(_drive, 2);
        AddHits(_unc, 2);
        AddHits(_env, 2);
        AddHits(_home, 2);
        AddHits(_posix, 3);
        AddHits(_relative, 4);
        AddHits(_bareDomain, 5);

        hits.Sort((a, b) =>
            a.Index != b.Index ? a.Index.CompareTo(b.Index)
            : a.Priority != b.Priority ? a.Priority.CompareTo(b.Priority)
            : b.Length.CompareTo(a.Length));

        var results = new List<DetectedPath>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var consumed = new List<(int Start, int End)>();
        var lastEnd = 0;
        var fileNameAt = new Dictionary<int, string>();

        foreach (var hit in hits)
        {
            if (hit.Index < lastEnd) continue;
            // Only consume the range when the candidate validates, so an over-extended
            // match that doesn't exist on disk can't block shorter strict matches after it.
            var path = ResolveCandidate(hit.Text);
            var end = hit.Index + hit.Length;

            // The lazy match under-matches paths with a dot before the real extension
            // ("C:\Users\me\.config\settings.json" -> "...\.c"). Retry up to the next boundary.
            if (path is null && IsRooted(hit.Text))
            {
                var i = end;
                while (i < text.Length && !IsBoundary(text[i])) i++;
                if (i > end && ResolveCandidate(hit.Text + text[end..i]) is { } extended)
                {
                    path = extended;
                    end = i;
                }
            }

            // A dot inside the name can look like an extension ("photo.Remove Objects.png" -> ".R",
            // an R script). Keep trying later extensions up to the end of the quote / line.
            if (path is null && IsRooted(hit.Text) && ExtendToLaterExtension(text, hit.Index, end) is { } later)
            {
                path = later.Path;
                end = later.End;
            }

            if (path is null) continue;
            lastEnd = end;
            consumed.Add((hit.Index, end));
            fileNameAt[hit.Index] = Path.GetFileName(path.Value.TrimEnd('/', Path.DirectorySeparatorChar));
            if (seen.Add(path.Key))
            {
                Log.Info($"PathDetector: matched '{Log.Redact(hit.Text)}' -> '{Log.Redact(path.Value)}'");
                results.Add(path);
            }
        }

        if (results.Count == 0)
        {
            foreach (var hit in FolderHits(text))
            {
                if (hit.Index < lastEnd) continue;
                if (ResolveFolderCandidate(hit.Text) is { } folder && seen.Add(folder.Key))
                {
                    results.Add(folder);
                    lastEnd = hit.Index + hit.Length;
                    consumed.Add((hit.Index, lastEnd));
                }
            }
        }

        var bareCount = 0;
        foreach (Match m in _bareFile.Matches(text))
        {
            if (bareCount >= MaxBareCandidates) break;
            var name = m.Groups[1];
            // A name inside an already-resolved path is not a new hit.
            if (consumed.Any(r => name.Index < r.End && name.Index + name.Length > r.Start)) continue;
            // A table can spell one link as "name.gif (folder/name.gif)" or "[name.gif](folder/name.gif)":
            // only the target counts (macOS 7f399a7).
            if (m.Length > name.Length && fileNameAt.TryGetValue(m.Index + m.Length, out var target)
                && target.Equals(name.Value, StringComparison.OrdinalIgnoreCase)) continue;
            foreach (var token in BareVariants(name.Value))
            {
                if (bareCount >= MaxBareCandidates || !seen.Add(token)) continue;
                results.Add(new DetectedPath(DetectedKind.UnresolvedFilename, token));
                bareCount++;
            }
        }

        if (results.Count == 0)
        {
            var noExtCount = 0;
            foreach (Match m in _bareNoExt.Matches(text))
            {
                if (noExtCount >= MaxNoExtCandidates) break;
                if (m.Length is < 3 or > 30 || !seen.Add(m.Value)) continue;
                results.Add(new DetectedPath(DetectedKind.UnresolvedFilename, m.Value));
                noExtCount++;
            }
        }

        return results;
    }

    /// <summary>
    /// The bare-filename regex allows spaces ("Project Access Guide.pdf"), so "see my photo.png"
    /// matches as a whole. Search both the whole phrase and its last word.
    /// </summary>
    private static IEnumerable<string> BareVariants(string token)
    {
        yield return token;
        var space = token.LastIndexOf(' ');
        if (space < 0) yield break;
        var last = token[(space + 1)..];
        if (last.LastIndexOf('.') >= 2) yield return last;
    }

    private IEnumerable<Hit> FolderHits(string text)
    {
        var hits = new List<Hit>();
        foreach (var regex in new[] { _driveFolder, _uncFolder, _homeFolder, _envFolder })
            foreach (Match m in regex.Matches(text))
                hits.Add(new Hit(m.Index, m.Length, m.Value, 0));
        return hits.OrderBy(h => h.Index);
    }

    private DetectedPath? ResolveCandidate(string raw)
    {
        var candidate = TrimTrailing(raw.Trim(), TrailingPunctuation);
        if (candidate.Length == 0) return null;
        var lower = candidate.ToLowerInvariant();
        var ext = MediaExtension(candidate);

        string? http = null;
        if (lower.StartsWith("http://") || lower.StartsWith("https://")) http = candidate;
        else if (lower.StartsWith("https//")) http = "https://" + candidate["https//".Length..];
        else if (lower.StartsWith("http//")) http = "http://" + candidate["http//".Length..];
        else if (!IsRooted(candidate) && !lower.Contains("://") && !candidate.Contains('\\'))
        {
            // Scheme-less domain ("github.com/x/readme.md"). Requires a known TLD.
            // Hosts are typed lowercase; "Glance.App/App.xaml" (".app" is a real TLD) is a folder.
            var slash = candidate.IndexOf('/');
            var host = slash >= 0 ? candidate[..slash] : candidate;
            var dot = host.LastIndexOf('.');
            if (dot > 0 && !host.Any(char.IsUpper) && KnownTlds.Contains(host[(dot + 1)..])) http = "https://" + candidate;
        }

        if (http is not null)
        {
            if (!TryParseWebUrl(http, out var uri)) return null;
            var kind = FileKinds.AllLocal.Contains(ext)
                ? DetectedPath.RemoteKindFor(FileKinds.KindForExtension(ext))
                : DetectedKind.WebPage;
            return new DetectedPath(kind, uri.AbsoluteUri);
        }

        if (lower.StartsWith("file:"))
        {
            if (Uri.TryCreate(candidate, UriKind.Absolute, out var fileUri) && fileUri.IsFile)
            {
                var local = fileUri.LocalPath;
                return IsValidLocal(local) ? LocalKind(local) : null;
            }
            return null;
        }

        if (IsRooted(candidate))
        {
            var local = ToLocalPath(candidate);
            return local is not null && IsValidLocal(local) ? LocalKind(local) : null;
        }

        if (candidate.Contains('/') || candidate.Contains('\\'))
        {
            // Users often drop the home prefix: "Desktop\work\Foo.pdf". Try under %USERPROFILE% first.
            var homeExpanded = Path.Combine(_fs.HomeDirectory, NormalizeSeparators(StripDotPrefix(candidate)));
            if (IsValidLocal(homeExpanded)) return LocalKind(homeExpanded);
            return new DetectedPath(DetectedKind.UnresolvedRelativePath, candidate);
        }

        return null;
    }

    private DetectedPath? ResolveFolderCandidate(string raw)
    {
        var candidate = TrimTrailing(raw.Trim(), FolderTrailingPunctuation);
        // Windows folder names often contain spaces ("Program Files"), so the folder regexes
        // run to the end of the line. Drop trailing words until an existing directory remains.
        while (candidate.Length > 0)
        {
            var local = ToLocalPath(candidate);
            if (local is not null && _fs.DirectoryExists(local))
            {
                var ext = FileKinds.ExtensionOf(local);
                if (ext.Length > 0 && FileKinds.AllLocal.Contains(ext)) return null;
                return new DetectedPath(DetectedKind.LocalFolder, TrimFolder(local));
            }
            var space = candidate.LastIndexOf(' ');
            if (space <= 0) return null;
            candidate = TrimTrailing(candidate[..space].TrimEnd(), FolderTrailingPunctuation);
        }
        return null;
    }

    /// <summary>Maps a rooted candidate to a Windows path, or null when it isn't one.</summary>
    private string? ToLocalPath(string candidate)
    {
        if (candidate.Length >= 2 && candidate[0] == '~' && candidate[1] is '\\' or '/')
            return Path.Combine(_fs.HomeDirectory, NormalizeSeparators(candidate[2..]));

        if (candidate[0] == '%')
        {
            var expanded = _fs.ExpandEnvironmentVariables(candidate);
            return expanded.StartsWith('%') ? null : NormalizeSeparators(expanded);
        }

        if (IsDrivePath(candidate)) return NormalizeSeparators(candidate);
        if (candidate.StartsWith(@"\\")) return @"\\" + NormalizeSeparators(candidate[2..]);

        if (candidate[0] == '/')
        {
            // WSL: /mnt/c/Users/... ; Git Bash / MSYS: /c/Users/...
            var m = Regex.Match(candidate, @"^/(?:mnt/)?([A-Za-z])(/.*)?$", RegexOptions.CultureInvariant);
            if (m.Success)
                return char.ToUpperInvariant(m.Groups[1].Value[0]) + @":\" + NormalizeSeparators(m.Groups[2].Value.TrimStart('/'));
            return NormalizeSeparators(candidate);
        }

        return null;
    }

    private bool IsValidLocal(string path)
    {
        if (path.Contains("..")) return false;
        var ext = FileKinds.ExtensionOf(path);
        if (_fs.FileExists(path) || _fs.DirectoryExists(path)) return FileKinds.AllLocal.Contains(ext);
        Log.Info($"PathDetector: file does not exist at '{Log.Redact(path)}'");
        return false;
    }

    private static bool IsRooted(string s) =>
        s.Length > 0 && (s[0] is '/' or '%' || s.StartsWith(@"\\") || IsDrivePath(s)
                         || (s.Length >= 2 && s[0] == '~' && s[1] is '\\' or '/')
                         || s.StartsWith("file:", StringComparison.OrdinalIgnoreCase));

    private static bool IsDrivePath(string s) =>
        s.Length >= 3 && char.IsAsciiLetter(s[0]) && s[1] == ':' && s[2] is '\\' or '/';

    private static bool IsBoundary(char c) => char.IsWhiteSpace(c) || BoundaryPunctuation.Contains(c);

    private static string TrimTrailing(string s, string chars)
    {
        var end = s.Length;
        while (end > 0 && chars.Contains(s[end - 1])) end--;
        return s[..end];
    }

    private static string TrimFolder(string path) =>
        path.Length > 3 ? path.TrimEnd('\\') : path;

    private static string StripDotPrefix(string s)
    {
        while (s.StartsWith("./") || s.StartsWith(@".\")) s = s[2..];
        return s;
    }

    private static string NormalizeSeparators(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s)
        {
            var ch = c == '/' ? '\\' : c;
            if (ch == '\\' && sb.Length > 0 && sb[^1] == '\\') continue;
            sb.Append(ch);
        }
        return sb.ToString();
    }

    private static string MediaExtension(string candidate)
    {
        var cut = candidate.IndexOfAny(['?', '#']);
        var withoutQuery = (cut >= 0 ? candidate[..cut] : candidate).TrimEnd('\\');
        var ext = FileKinds.ExtensionOf(withoutQuery);
        if (ext.Length > 0) return ext;

        // CDNs serve extensionless paths with the format in the query ("format=jpg", "/format/webp").
        var q = candidate.IndexOf('?');
        if (q >= 0)
        {
            var query = candidate[(q + 1)..].ToLowerInvariant();
            foreach (var pattern in QueryFormatPatterns)
            {
                var m = pattern.Match(query);
                if (m.Success) return m.Groups[1].Value;
            }
        }
        return ExtensionFromBangSuffix(withoutQuery);
    }

    /// <summary>
    /// Xiaohongshu-style CDN marker: the basename ends with a "!" section carrying the real
    /// format ("...!nc_n_webp_mw_1"). Only the "!" tail is scanned.
    /// </summary>
    internal static string ExtensionFromBangSuffix(string path)
    {
        var bang = path.LastIndexOf('!');
        if (bang < 0) return "";
        var tail = path[(bang + 1)..].ToLowerInvariant();
        return BangTokens.FirstOrDefault(tail.Contains) ?? "";
    }

    private static string UnwrapLines(string text) =>
        string.Concat(text.Split(["\r\n", "\n", "\r"], StringSplitOptions.None).Select(l => l.Trim(' ', '\t')));

    private static bool TryParseWebUrl(string s, out Uri uri)
    {
        if (TryWeb(s, out uri)) return true;
        // Percent-encode anything that isn't printable ASCII and retry.
        var sb = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(s))
        {
            if (b is > 0x20 and < 0x7F) sb.Append((char)b);
            else sb.Append('%').Append(b.ToString("X2"));
        }
        return TryWeb(sb.ToString(), out uri);

        static bool TryWeb(string value, out Uri result)
        {
            if (Uri.TryCreate(value, UriKind.Absolute, out var parsed) && parsed.Scheme is "http" or "https")
            {
                result = parsed;
                return true;
            }
            result = null!;
            return false;
        }
    }
}
