using System.Diagnostics;
using Glance.Core.Git;
using Glance.Core.Logging;

namespace Glance.Platform;

/// <summary>
/// Runs git.exe (PATH, then the usual Git for Windows install folders) without a console window,
/// with a timeout. Output is returned as raw bytes; callers decode.
/// </summary>
public sealed class GitRunner : IGitRunner
{
    private static readonly Lazy<string?> GitPath = new(FindGit);
    private readonly TimeSpan _timeout;

    public GitRunner(TimeSpan? timeout = null) => _timeout = timeout ?? TimeSpan.FromSeconds(5);

    public static bool IsAvailable => GitPath.Value is not null;

    public async Task<GitResult?> RunAsync(IReadOnlyList<string> arguments, string workingDirectory, CancellationToken ct = default)
    {
        var git = GitPath.Value;
        if (git is null) return null;

        var info = new ProcessStartInfo(git)
        {
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
        };
        // Unquoted UTF-8 paths, no pager, never prompt for credentials.
        info.ArgumentList.Add("-c");
        info.ArgumentList.Add("core.quotepath=off");
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        info.Environment["LC_ALL"] = "C";
        info.Environment["GIT_TERMINAL_PROMPT"] = "0";
        info.Environment["GIT_PAGER"] = "";

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(_timeout);
        Process? process = null;
        try
        {
            process = Process.Start(info);
            if (process is null) return null;
            process.StandardInput.Close();
            using var output = new MemoryStream();
            var copy = process.StandardOutput.BaseStream.CopyToAsync(output, timeout.Token);
            var drainError = process.StandardError.ReadToEndAsync(timeout.Token);
            await Task.WhenAll(copy, drainError, process.WaitForExitAsync(timeout.Token));
            return new GitResult(process.ExitCode, output.ToArray());
        }
        catch (OperationCanceledException)
        {
            if (!ct.IsCancellationRequested) Log.Warning($"GitRunner: git {arguments.FirstOrDefault()} timed out after {_timeout.TotalSeconds}s");
            Kill(process);
            return null;
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            Log.Warning($"GitRunner: git {arguments.FirstOrDefault()} failed: {ex.Message}");
            Kill(process);
            return null;
        }
        finally
        {
            process?.Dispose();
        }
    }

    private static void Kill(Process? process)
    {
        try { if (process is { HasExited: false }) process.Kill(entireProcessTree: true); }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception) { }
    }

    private static string? FindGit()
    {
        var candidates = (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(dir => Path.Combine(dir.Trim('"'), "git.exe"))
            .Concat(
            [
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "cmd", "git.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Git", "cmd", "git.exe"),
            ]);
        foreach (var candidate in candidates)
        {
            try
            {
                if (File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException)
            {
                // Malformed PATH entry.
            }
        }
        Log.Info("GitRunner: git.exe not found; Git diff is unavailable");
        return null;
    }
}
