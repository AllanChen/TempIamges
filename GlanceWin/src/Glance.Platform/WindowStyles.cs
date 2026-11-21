using System.Windows;
using System.Windows.Interop;
using Glance.Platform.Interop;

namespace Glance.Platform;

public static class WindowStyles
{
    /// <summary>
    /// Floating panel that never takes focus from the app the user is working in
    /// (macOS <c>.nonactivatingPanel</c>): <c>WS_EX_NOACTIVATE</c>, and <c>WS_EX_TOOLWINDOW</c>
    /// to stay out of Alt+Tab and the taskbar. Call from <c>SourceInitialized</c> or after <c>EnsureHandle</c>.
    /// </summary>
    public static void MakeNonActivating(Window window)
    {
        var hwnd = new WindowInteropHelper(window).EnsureHandle();
        var style = Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64();
        style |= Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW;
        Native.SetWindowLongPtr(hwnd, Native.GWL_EXSTYLE, new IntPtr(style));
    }
}
