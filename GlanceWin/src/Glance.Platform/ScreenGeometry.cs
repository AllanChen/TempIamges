using System.Runtime.InteropServices;
using Glance.Platform.Interop;

namespace Glance.Platform;

/// <summary>Rectangle in physical screen pixels (virtual-desktop coordinates, top-left origin).</summary>
public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public int CenterX => X + Width / 2;
    public int CenterY => Y + Height / 2;
}

/// <param name="Bounds">Whole monitor.</param>
/// <param name="WorkArea">Monitor minus the taskbar (macOS <c>visibleFrame</c>).</param>
/// <param name="Scale">DPI scale (1.0 = 96 DPI).</param>
public sealed record MonitorArea(PixelRect Bounds, PixelRect WorkArea, double Scale);

/// <summary>Monitor and window geometry in physical pixels (per-monitor DPI aware).</summary>
public static class ScreenGeometry
{
    public static (int X, int Y) CursorPosition() =>
        Native.GetCursorPos(out var p) ? (p.X, p.Y) : (0, 0);

    public static MonitorArea MonitorAt(int x, int y) =>
        Describe(Native.MonitorFromPoint(new Native.POINT { X = x, Y = y }, Native.MONITOR_DEFAULTTONEAREST));

    public static MonitorArea MonitorAtCursor()
    {
        var (x, y) = CursorPosition();
        return MonitorAt(x, y);
    }

    public static MonitorArea MonitorOf(IntPtr hwnd) =>
        Describe(Native.MonitorFromWindow(hwnd, Native.MONITOR_DEFAULTTONEAREST));

    public static PixelRect WindowRect(IntPtr hwnd) =>
        Native.GetWindowRect(hwnd, out var r) ? new PixelRect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top) : default;

    /// <summary>Moves/resizes without activating or changing z-order.</summary>
    public static void SetWindowRect(IntPtr hwnd, PixelRect rect) =>
        Native.SetWindowPos(hwnd, IntPtr.Zero, rect.X, rect.Y, rect.Width, rect.Height,
            Native.SWP_NOZORDER | Native.SWP_NOACTIVATE | Native.SWP_NOOWNERZORDER);

    private static MonitorArea Describe(IntPtr monitor)
    {
        var info = new Native.MONITORINFO { cbSize = Marshal.SizeOf<Native.MONITORINFO>() };
        if (monitor == IntPtr.Zero || !Native.GetMonitorInfo(monitor, ref info))
            return new MonitorArea(new PixelRect(0, 0, 1920, 1080), new PixelRect(0, 0, 1920, 1040), 1.0);

        var scale = Native.GetDpiForMonitor(monitor, 0 /* MDT_EFFECTIVE_DPI */, out var dpiX, out _) == 0 && dpiX > 0
            ? dpiX / 96.0
            : 1.0;
        return new MonitorArea(ToPixelRect(info.rcMonitor), ToPixelRect(info.rcWork), scale);
    }

    private static PixelRect ToPixelRect(Native.RECT r) => new(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
}
