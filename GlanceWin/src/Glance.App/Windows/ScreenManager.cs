using System.Windows;
using System.Windows.Interop;
using Glance.Platform;

namespace Glance.App.Windows;

/// <summary>
/// Window placement (port of macOS <c>ScreenManager</c>, CLAUDE.md rule 7): panels open centered
/// on the cursor's monitor, shrunk to fit and clamped to the work area (taskbar excluded).
/// Works in physical pixels so mixed-DPI multi-monitor setups place correctly.
/// </summary>
internal static class ScreenManager
{
    /// <summary>Centered, fully on-screen rect for a DIP size on <paramref name="monitor"/>.</summary>
    public static PixelRect CenterFrame(Size dipSize, MonitorArea monitor)
    {
        var work = monitor.WorkArea;
        var w = Math.Min((int)Math.Ceiling(dipSize.Width * monitor.Scale), work.Width);
        var h = Math.Min((int)Math.Ceiling(dipSize.Height * monitor.Scale), work.Height);
        var x = work.X + (work.Width - w) / 2;
        var y = work.Y + (work.Height - h) / 2;
        return Clamp(new PixelRect(x, y, w, h), work);
    }

    /// <summary>
    /// Beside the cursor (tooltips/toasts, macOS <c>adjustedFrame</c>): to the right of the cursor,
    /// vertically centered on it, flipped left near the right edge, clamped to the work area.
    /// </summary>
    public static PixelRect AdjustedFrame(Size dipSize, MonitorArea monitor, (int X, int Y) cursor, double offsetDip = 20)
    {
        var work = monitor.WorkArea;
        var w = Math.Min((int)Math.Ceiling(dipSize.Width * monitor.Scale), work.Width);
        var h = Math.Min((int)Math.Ceiling(dipSize.Height * monitor.Scale), work.Height);
        var offset = (int)Math.Round(offsetDip * monitor.Scale);
        var x = cursor.X + offset;
        if (x + w > work.Right) x = cursor.X - offset - w;
        var y = cursor.Y - h / 2;
        return Clamp(new PixelRect(x, y, w, h), work);
    }

    /// <summary>Keeps a rect fully inside the work area, shrinking it if larger.</summary>
    public static PixelRect Clamp(PixelRect rect, PixelRect work)
    {
        var w = Math.Min(rect.Width, work.Width);
        var h = Math.Min(rect.Height, work.Height);
        var x = Math.Max(work.X, Math.Min(rect.X, work.Right - w));
        var y = Math.Max(work.Y, Math.Min(rect.Y, work.Bottom - h));
        return new PixelRect(x, y, w, h);
    }

    /// <summary>
    /// Applies a physical rect. Moves onto the target monitor first so any per-monitor DPI change
    /// (and WPF's resize in response) happens before the final size is set.
    /// </summary>
    public static void Place(Window window, PixelRect target)
    {
        var hwnd = new WindowInteropHelper(window).EnsureHandle();
        var current = ScreenGeometry.WindowRect(hwnd);
        ScreenGeometry.SetWindowRect(hwnd, new PixelRect(target.X, target.Y, Math.Max(1, current.Width), Math.Max(1, current.Height)));
        ScreenGeometry.SetWindowRect(hwnd, target);
    }
}
