using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;

namespace Glance.Core.Logging;

public enum LogLevel { Debug, Info, Warning, Error }

/// <summary>
/// Port of the macOS <c>Logger</c>: appends to <c>app.log</c> on a background thread,
/// keeps one rotated generation (<c>app.log.1</c>) above 5 MB. Callers never block on I/O.
/// </summary>
public static class Log
{
    private const long MaxLogFileSize = 5 * 1024 * 1024;

    private static readonly BlockingCollection<string> Queue = new(new ConcurrentQueue<string>(), 4096);
    private static string? _logFile;
    private static Thread? _writer;

    public static string? LogFile => _logFile;

    /// <summary>Starts the background writer. Safe to call once at startup.</summary>
    public static void Initialize(string logFile)
    {
        if (_writer is not null) return;
        _logFile = logFile;
        Directory.CreateDirectory(Path.GetDirectoryName(logFile)!);
        _writer = new Thread(WriteLoop) { IsBackground = true, Name = "Glance log writer", Priority = ThreadPriority.BelowNormal };
        _writer.Start();
        Info("=== Logger initialized ===");
    }

    public static void Debug(string message, [CallerFilePath] string file = "", [CallerMemberName] string member = "", [CallerLineNumber] int line = 0)
        => Write(LogLevel.Debug, message, file, member, line);

    public static void Info(string message, [CallerFilePath] string file = "", [CallerMemberName] string member = "", [CallerLineNumber] int line = 0)
        => Write(LogLevel.Info, message, file, member, line);

    public static void Warning(string message, [CallerFilePath] string file = "", [CallerMemberName] string member = "", [CallerLineNumber] int line = 0)
        => Write(LogLevel.Warning, message, file, member, line);

    public static void Error(string message, Exception? ex = null, [CallerFilePath] string file = "", [CallerMemberName] string member = "", [CallerLineNumber] int line = 0)
        => Write(LogLevel.Error, ex is null ? message : $"{message}: {ex}", file, member, line);

    /// <summary>
    /// Selected text, clipboard contents, paths and URLs must pass through this.
    /// Release builds keep only the length; Debug builds keep the value.
    /// </summary>
    public static string Redact(string value)
    {
#if DEBUG
        return value;
#else
        return $"<redacted {value.Length} chars>";
#endif
    }

    /// <summary>Waits briefly for queued lines to reach disk (used on exit).</summary>
    public static void Flush(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (Queue.Count > 0 && DateTime.UtcNow < deadline) Thread.Sleep(10);
    }

    internal static string Format(DateTime time, LogLevel level, string message, string file, string member, int line)
    {
        var tag = level switch
        {
            LogLevel.Debug => "DEBUG",
            LogLevel.Info => "INFO",
            LogLevel.Warning => "WARN",
            _ => "ERROR",
        };
        return $"[{time:yyyy-MM-dd HH:mm:ss.fff}] [{tag}] [{Path.GetFileName(file)}:{line}] {member} - {message}";
    }

    private static void Write(LogLevel level, string message, string file, string member, int line)
    {
#if !DEBUG
        if (level == LogLevel.Debug) return;
#endif
        var formatted = Format(DateTime.Now, level, message, file, member, line);
        System.Diagnostics.Debug.WriteLine(formatted);
        // Drop rather than block when the writer falls behind: logging must never stall a caller.
        Queue.TryAdd(formatted);
    }

    private static void WriteLoop()
    {
        foreach (var line in Queue.GetConsumingEnumerable())
        {
            if (_logFile is null) continue;
            try
            {
                RotateIfNeeded(_logFile);
                File.AppendAllText(_logFile, line + Environment.NewLine, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"Glance: failed to write log: {ex.Message}");
            }
        }
    }

    private static void RotateIfNeeded(string logFile)
    {
        var info = new FileInfo(logFile);
        if (!info.Exists || info.Length <= MaxLogFileSize) return;
        File.Move(logFile, logFile + ".1", overwrite: true);
    }
}
