using System.Windows.Interop;
using System.Windows.Threading;
using Glance.Core.Logging;
using Glance.Core.Settings;
using Glance.Platform.Interop;

namespace Glance.Platform;

/// <summary>
/// System-wide hotkeys via <c>RegisterHotKey</c> on a message-only window owned by the UI thread.
/// Replaces the macOS <c>CGEventTap</c>: Windows delivers <c>WM_HOTKEY</c> as a posted message,
/// so there is no hook callback that could stall keyboard input system-wide.
/// </summary>
public sealed class HotkeyService : IDisposable
{
    public const int ActivationId = 1;
    public const int EscapeId = 2;

    private readonly HwndSource _source;
    private readonly HashSet<int> _registered = [];

    public HotkeyService()
    {
        var parameters = new HwndSourceParameters("GlanceHotkeys")
        {
            ParentWindow = Native.HWND_MESSAGE,
            WindowStyle = 0,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    /// <summary>Raised on the UI thread with the hotkey id.</summary>
    public event EventHandler<int>? Pressed;

    /// <summary>Message-only window handle; also used as the clipboard owner when restoring.</summary>
    public IntPtr Handle => _source.Handle;

    public bool Register(int id, Hotkey hotkey)
    {
        Unregister(id);
        var ok = Native.RegisterHotKey(_source.Handle, id, (uint)hotkey.Modifiers | Native.MOD_NOREPEAT, (uint)hotkey.VirtualKey);
        if (ok) _registered.Add(id);
        else Log.Warning($"RegisterHotKey failed for id {id} (mods {hotkey.Modifiers}, vk 0x{hotkey.VirtualKey:X2}); in use by another app?");
        return ok;
    }

    /// <summary>Esc closes floating panels; only registered while one is visible.</summary>
    public bool RegisterEscape()
    {
        if (_registered.Contains(EscapeId)) return true;
        var ok = Native.RegisterHotKey(_source.Handle, EscapeId, Native.MOD_NOREPEAT, Native.VK_ESCAPE);
        if (ok) _registered.Add(EscapeId);
        return ok;
    }

    public void Unregister(int id)
    {
        if (_registered.Remove(id)) Native.UnregisterHotKey(_source.Handle, id);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_HOTKEY)
        {
            handled = true;
            var id = wParam.ToInt32();
            // Return from the window procedure immediately; the Peek pipeline runs afterwards.
            Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Input, () => Pressed?.Invoke(this, id));
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        foreach (var id in _registered.ToList()) Unregister(id);
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
