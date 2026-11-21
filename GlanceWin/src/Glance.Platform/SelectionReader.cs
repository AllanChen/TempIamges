using System.Diagnostics;
using System.Windows.Automation;
using Glance.Core.Logging;
using Glance.Platform.Interop;

namespace Glance.Platform;

public enum SelectionSource { UIAutomation, CopyCommand, Clipboard }

public sealed record SelectionResult(string Text, SelectionSource Source);

/// <summary>
/// Reads the text selected in the foreground app (port of macOS <c>SelectedTextExtractor</c>).
/// 1. UI Automation <c>TextPattern.GetSelection()</c> (the AX equivalent), bounded by a timeout.
/// 2. Fallback: snapshot the clipboard, inject Ctrl+C, wait for the clipboard to change,
///    read the text, restore the snapshot.
/// All work runs on worker threads; a hung target app can only cost the timeout.
/// Known limitation: apps running elevated cannot be read (UIPI).
/// </summary>
public sealed class SelectionReader
{
    private const int MaxChars = 20_000;
    private static readonly TimeSpan ModifierReleaseWait = TimeSpan.FromMilliseconds(300);
    private static readonly TimeSpan CopyWait = TimeSpan.FromMilliseconds(400);

    private readonly IntPtr _clipboardOwner;

    /// <param name="clipboardOwner">A window on a thread that pumps messages (the hotkey window).</param>
    public SelectionReader(IntPtr clipboardOwner) => _clipboardOwner = clipboardOwner;

    /// <summary>UI Automation only. <c>null</c> when nothing is selected, unsupported, or timed out.</summary>
    public Task<string?> ReadViaAutomationAsync(TimeSpan timeout) =>
        RunWithTimeout<string>(ReadViaAutomation, timeout, "UI Automation");

    /// <summary>Full read: UI Automation, then (when allowed) the Ctrl+C fallback.</summary>
    public async Task<SelectionResult?> ReadAsync(bool allowCopyFallback)
    {
        var uia = await ReadViaAutomationAsync(TimeSpan.FromSeconds(1.0));
        if (!string.IsNullOrWhiteSpace(uia)) return new SelectionResult(uia, SelectionSource.UIAutomation);
        if (!allowCopyFallback) return null;

        var copied = await RunWithTimeout<string>(ReadViaCopy, TimeSpan.FromSeconds(2), "Ctrl+C fallback");
        return string.IsNullOrWhiteSpace(copied) ? null : new SelectionResult(copied, SelectionSource.CopyCommand);
    }

    /// <summary>Current clipboard text, used as the last fallback when nothing is selected.</summary>
    public Task<SelectionResult?> ReadClipboardAsync() =>
        Task.Run(() =>
        {
            var text = ClipboardSnapshot.ReadText(_clipboardOwner);
            return string.IsNullOrWhiteSpace(text) ? null : new SelectionResult(text, SelectionSource.Clipboard);
        });

    private static string? ReadViaAutomation()
    {
        try
        {
            var focused = AutomationElement.FocusedElement;
            if (focused is null) return null;
            if (focused.Current.ProcessId == Environment.ProcessId) return null;
            if (!focused.TryGetCurrentPattern(TextPattern.Pattern, out var pattern) || pattern is not TextPattern text)
                return null;
            var ranges = text.GetSelection();
            var parts = ranges.Select(r => r.GetText(MaxChars)).Where(s => !string.IsNullOrEmpty(s));
            var joined = string.Join("\n", parts);
            return joined.Length > 0 ? joined : null;
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or InvalidOperationException
                                       or System.Runtime.InteropServices.COMException or ArgumentException)
        {
            Log.Info($"SelectionReader: UI Automation unavailable: {ex.GetType().Name}");
            return null;
        }
    }

    private string? ReadViaCopy()
    {
        ReleaseHeldModifiers();

        var snapshot = ClipboardSnapshot.Capture(_clipboardOwner);
        var before = Native.GetClipboardSequenceNumber();
        SendKeys(
            (Native.VK_CONTROL, false), (Native.VK_C, false),
            (Native.VK_C, true), (Native.VK_CONTROL, true));

        var clock = Stopwatch.StartNew();
        while (Native.GetClipboardSequenceNumber() == before && clock.Elapsed < CopyWait) Thread.Sleep(10);
        if (Native.GetClipboardSequenceNumber() == before)
        {
            Log.Info("SelectionReader: Ctrl+C did not change the clipboard (nothing selected?)");
            return null;
        }

        // Let the source app finish writing all of its formats.
        Thread.Sleep(30);
        var text = ClipboardSnapshot.ReadText(_clipboardOwner);
        snapshot?.Restore(_clipboardOwner);
        return text is { Length: > MaxChars } ? text[..MaxChars] : text;
    }

    /// <summary>
    /// The user is usually still holding the hotkey modifier (Alt of Alt+Q); Ctrl+C would arrive
    /// as Ctrl+Alt+C. Wait briefly for release; otherwise release it ourselves, injecting a
    /// masking key first so a lone Alt/Win release doesn't open the target app's menu or Start.
    /// </summary>
    private static void ReleaseHeldModifiers()
    {
        int[] modifiers = [Native.VK_MENU, Native.VK_CONTROL, Native.VK_SHIFT, Native.VK_LWIN, Native.VK_RWIN];
        var clock = Stopwatch.StartNew();
        while (modifiers.Any(IsDown) && clock.Elapsed < ModifierReleaseWait) Thread.Sleep(10);

        var held = modifiers.Where(IsDown).ToList();
        if (held.Count == 0) return;
        var keys = new List<(int, bool)> { (Native.VK_MASK, false), (Native.VK_MASK, true) };
        keys.AddRange(held.Select(vk => (vk, true)));
        SendKeys(keys.ToArray());
    }

    private static bool IsDown(int vk) => (Native.GetAsyncKeyState(vk) & 0x8000) != 0;

    private static void SendKeys(params (int Vk, bool Up)[] keys)
    {
        var inputs = keys.Select(k => new Native.INPUT
        {
            type = Native.INPUT_KEYBOARD,
            U = new Native.InputUnion
            {
                ki = new Native.KEYBDINPUT { wVk = (ushort)k.Vk, dwFlags = k.Up ? Native.KEYEVENTF_KEYUP : 0 },
            },
        }).ToArray();
        Native.SendInput((uint)inputs.Length, inputs, System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
    }

    /// <summary>Runs <paramref name="work"/> on its own background thread and gives up after the timeout.</summary>
    private static async Task<T?> RunWithTimeout<T>(Func<T?> work, TimeSpan timeout, string label) where T : class
    {
        var tcs = new TaskCompletionSource<T?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { tcs.TrySetResult(work()); }
            catch (Exception ex) { tcs.TrySetException(ex); }
        })
        { IsBackground = true, Name = $"Glance {label}" };
        thread.Start();

        var finished = await Task.WhenAny(tcs.Task, Task.Delay(timeout));
        if (finished != tcs.Task)
        {
            // The thread is abandoned (background, so it can't block exit).
            Log.Info($"SelectionReader: {label} timed out after {timeout.TotalSeconds:0.##}s");
            return null;
        }
        try
        {
            return await tcs.Task;
        }
        catch (Exception ex)
        {
            Log.Warning($"SelectionReader: {label} failed: {ex.Message}");
            return null;
        }
    }
}
