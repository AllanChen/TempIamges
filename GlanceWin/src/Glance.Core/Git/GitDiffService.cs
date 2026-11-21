using System.Text;
using Glance.Core.Content;

namespace Glance.Core.Git;

public sealed record GitResult(int ExitCode, byte[] Output)
{
    public string Text => Encoding.UTF8.GetString(Output);
}

/// <summary>Runs git. Returns null when git is missing, fails to start or times out.</summary>
public interface IGitRunner
{
    Task<GitResult?> RunAsync(IReadOnlyList<string> arguments, string workingDirectory, CancellationToken ct = default);
}

public sealed record GitContext(string Root, string FilePath, string RelativePath, string StatusLine,
    IReadOnlyList<string> History, bool IsTracked);

/// <summary>
/// Before/after texts for the diff window. Titles and summary are English UI keys (or contain a
/// short hash) so the app can pass them through its localization table.
/// </summary>
public sealed record GitSnapshot(string FilePath, string Root, string RelativePath, string BeforeTitle,
    string AfterTitle, string BeforeText, string AfterText, string Summary);

/// <summary>
/// Port of the macOS <c>GitDiffService</c>: finds the repository of a file and builds the
/// "what changed" snapshot. Working-tree changes are compared with HEAD; a clean file shows its
/// last committed change.
/// </summary>
public sealed class GitDiffService
{
    private readonly IGitRunner _git;

    public GitDiffService(IGitRunner git) => _git = git;

    public async Task<GitContext?> ContextAsync(string filePath, CancellationToken ct = default)
    {
        var fullPath = Path.GetFullPath(filePath);
        var directory = Path.GetDirectoryName(fullPath);
        if (directory is null || !Directory.Exists(directory)) return null;

        var top = await _git.RunAsync(["rev-parse", "--show-toplevel"], directory, ct);
        if (top is not { ExitCode: 0 }) return null;
        var rootText = top.Text.Trim();
        if (rootText.Length == 0) return null;
        var root = Path.GetFullPath(rootText.Replace('/', Path.DirectorySeparatorChar));

        var relative = RelativePath(root, fullPath);
        if (relative is null) return null;

        var status = (await _git.RunAsync(["--no-optional-locks", "status", "--porcelain", "--", relative], root, ct))?.Text.Trim() ?? "";
        var history = (await _git.RunAsync(["log", "--follow", "--format=%H", "-n", "2", "--", relative], root, ct))?.Text
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries) ?? [];
        var tracked = (await _git.RunAsync(["ls-files", "--error-unmatch", "--", relative], root, ct))?.ExitCode == 0;

        if (!tracked && status.Length == 0 && history.Length == 0) return null;
        return new GitContext(root, fullPath, relative, status, history, tracked);
    }

    public async Task<GitSnapshot> SnapshotAsync(GitContext context, CancellationToken ct = default)
    {
        var current = await ReadFileAsync(context.FilePath, ct) ?? "";

        if (context.StatusLine.Length > 0)
        {
            var hasBase = context.IsTracked || context.History.Count > 0;
            var before = hasBase ? await ShowAsync("HEAD", context, ct) ?? "" : "";
            return new GitSnapshot(context.FilePath, context.Root, context.RelativePath,
                hasBase ? "Before - HEAD" : "Before - New file", "After - Working Tree",
                before, current, context.StatusLine);
        }

        if (context.History.Count >= 2)
        {
            var afterRev = context.History[0];
            var beforeRev = context.History[1];
            var before = await ShowAsync(beforeRev, context, ct) ?? "";
            var after = await ShowAsync(afterRev, context, ct) ?? current;
            return new GitSnapshot(context.FilePath, context.Root, context.RelativePath,
                $"Before - {ShortHash(beforeRev)}", $"After - {ShortHash(afterRev)}",
                before, after, "Last committed change");
        }

        var head = await ShowAsync("HEAD", context, ct) ?? current;
        return new GitSnapshot(context.FilePath, context.Root, context.RelativePath,
            "Before - HEAD", "After - Working Tree", head, current, "No working-tree changes");
    }

    /// <summary>Repository-relative path with forward slashes, or null if outside the root.</summary>
    public static string? RelativePath(string root, string fullPath)
    {
        var relative = Path.GetRelativePath(root, fullPath);
        if (relative == "." || relative == ".." || Path.IsPathRooted(relative)
            || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)) return null;
        return relative.Replace('\\', '/');
    }

    public static string ShortHash(string hash) => hash.Length > 7 ? hash[..7] : hash;

    private async Task<string?> ShowAsync(string revision, GitContext context, CancellationToken ct)
    {
        var result = await _git.RunAsync(["show", "--textconv", $"{revision}:{context.RelativePath}"], context.Root, ct);
        return result is { ExitCode: 0 } ? TextFileCodec.Decode(result.Output).Text : null;
    }

    private static async Task<string?> ReadFileAsync(string path, CancellationToken ct)
    {
        try
        {
            return TextFileCodec.Decode(await File.ReadAllBytesAsync(path, ct)).Text;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
