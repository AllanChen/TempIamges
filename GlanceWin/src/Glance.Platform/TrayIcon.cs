using System.Runtime.InteropServices;
using System.Windows.Interop;
using Glance.Core.Logging;

namespace Glance.Platform;

/// <summary>
/// Notification-area icon via <c>Shell_NotifyIcon</c> directly (no System.Drawing / third-party
/// tray library). Re-adds itself when Explorer restarts (<c>TaskbarCreated</c>).
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4;
    private const uint NIF_MESSAGE = 0x01, NIF_ICON = 0x02, NIF_TIP = 0x04, NIF_INFO = 0x10, NIF_SHOWTIP = 0x80;
    private const uint NIIF_INFO = 0x01, NIIF_WARNING = 0x02, NIIF_RESPECT_QUIET_TIME = 0x80;
    private const int NIN_BALLOONUSERCLICK = 0x0405;
    private Action? _balloonClick;
    private const uint NOTIFYICON_VERSION_4 = 4;
    private const int WM_APP_TRAY = 0x8000 + 0x51;
    private const int WM_CONTEXTMENU = 0x007B;
    private const int NIN_SELECT = 0x0400, NIN_KEYSELECT = 0x0401;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpData);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint ExtractIconEx(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, uint nIcons);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string lpString);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    private readonly HwndSource _window;
    private readonly uint _taskbarCreated;
    private IntPtr _icon;
    private string _tooltip;
    private bool _added;

    /// <param name="iconFile">File whose first icon resource is shown (default: this exe).</param>
    public TrayIcon(string tooltip, string? iconFile = null)
    {
        _tooltip = tooltip;
        // A hidden top-level window (not message-only: those don't receive the TaskbarCreated broadcast).
        _window = new HwndSource(new HwndSourceParameters("GlanceTray")
        {
            WindowStyle = unchecked((int)0x80000000), // WS_POPUP, never shown
            ExtendedWindowStyle = 0x00000080,         // WS_EX_TOOLWINDOW
            Width = 0,
            Height = 0,
        });
        _window.AddHook(WndProc);
        _taskbarCreated = RegisterWindowMessage("TaskbarCreated");

        var source = iconFile ?? Environment.ProcessPath ?? "";
        ExtractIconEx(source, 0, out var large, out var small, 1);
        _icon = small != IntPtr.Zero ? small : large;
        if (small != IntPtr.Zero && large != IntPtr.Zero) DestroyIcon(large);
        if (_icon == IntPtr.Zero) Log.Warning($"TrayIcon: no icon resource found in '{source}'");
    }

    /// <summary>Left click, right click or keyboard selection. Raised on the UI thread.</summary>
    /// <summary>Left click or keyboard select (NIN_SELECT / NIN_KEYSELECT).</summary>
    public event EventHandler? LeftClicked;

    /// <summary>Right click / context-menu key (WM_CONTEXTMENU).</summary>
    public event EventHandler? RightClicked;

    /// <summary>
    /// Replaces the icon (e.g. the drawn character). The tray icon takes ownership of
    /// <paramref name="hIcon"/> and destroys the previous one.
    /// </summary>
    public void SetIcon(IntPtr hIcon)
    {
        if (hIcon == IntPtr.Zero) return;
        var previous = _icon;
        _icon = hIcon;
        if (_added)
        {
            var data = Data(NIF_ICON);
            Shell_NotifyIcon(NIM_MODIFY, ref data);
        }
        if (previous != IntPtr.Zero && previous != hIcon) DestroyIcon(previous);
    }

    /// <summary>
    /// An HICON from a square top-down BGRA (premultiplied) buffer, via <c>CreateIconIndirect</c>
    /// with a 32-bpp DIB section (alpha is honoured) and an all-zero mask. Zero on failure.
    /// </summary>
    public static IntPtr CreateIcon(int size, byte[] bgraPremultiplied)
    {
        if (size <= 0 || bgraPremultiplied.Length < size * size * 4) return IntPtr.Zero;
        var header = new BITMAPV5HEADER
        {
            bV5Size = (uint)Marshal.SizeOf<BITMAPV5HEADER>(),
            bV5Width = size,
            bV5Height = -size, // top-down
            bV5Planes = 1,
            bV5BitCount = 32,
            bV5Compression = 3, // BI_BITFIELDS
            bV5RedMask = 0x00FF0000,
            bV5GreenMask = 0x0000FF00,
            bV5BlueMask = 0x000000FF,
            bV5AlphaMask = 0xFF000000,
        };
        var screen = GetDC(IntPtr.Zero);
        var color = CreateDIBSection(screen, ref header, 0, out var bits, IntPtr.Zero, 0);
        ReleaseDC(IntPtr.Zero, screen);
        if (color == IntPtr.Zero) return IntPtr.Zero;
        Marshal.Copy(bgraPremultiplied, 0, bits, size * size * 4);
        var mask = CreateBitmap(size, size, 1, 1, new byte[((size + 15) / 16) * 2 * size]);
        var info = new ICONINFO { fIcon = true, hbmColor = color, hbmMask = mask };
        var icon = CreateIconIndirect(ref info);
        DeleteObject(color);
        DeleteObject(mask);
        return icon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ICONINFO
    {
        public bool fIcon;
        public int xHotspot;
        public int yHotspot;
        public IntPtr hbmMask;
        public IntPtr hbmColor;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPV5HEADER
    {
        public uint bV5Size;
        public int bV5Width;
        public int bV5Height;
        public ushort bV5Planes;
        public ushort bV5BitCount;
        public uint bV5Compression;
        public uint bV5SizeImage;
        public int bV5XPelsPerMeter;
        public int bV5YPelsPerMeter;
        public uint bV5ClrUsed;
        public uint bV5ClrImportant;
        public uint bV5RedMask;
        public uint bV5GreenMask;
        public uint bV5BlueMask;
        public uint bV5AlphaMask;
        public uint bV5CSType;
        public int ciexyzRedX, ciexyzRedY, ciexyzRedZ, ciexyzGreenX, ciexyzGreenY, ciexyzGreenZ, ciexyzBlueX, ciexyzBlueY, ciexyzBlueZ;
        public uint bV5GammaRed;
        public uint bV5GammaGreen;
        public uint bV5GammaBlue;
        public uint bV5Intent;
        public uint bV5ProfileData;
        public uint bV5ProfileSize;
        public uint bV5Reserved;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr CreateIconIndirect(ref ICONINFO info);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPV5HEADER header, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateBitmap(int width, int height, uint planes, uint bitCount, byte[] bits);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    public string ToolTip
    {
        get => _tooltip;
        set
        {
            _tooltip = value;
            if (_added)
            {
                var data = Data(NIF_TIP | NIF_SHOWTIP);
                Shell_NotifyIcon(NIM_MODIFY, ref data);
            }
        }
    }

    public bool Show()
    {
        var data = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        _added = Shell_NotifyIcon(NIM_ADD, ref data);
        if (_added)
        {
            data.uVersion = NOTIFYICON_VERSION_4;
            Shell_NotifyIcon(NIM_SETVERSION, ref data);
        }
        else
        {
            Log.Warning("TrayIcon: Shell_NotifyIcon(NIM_ADD) failed");
        }
        return _added;
    }

    /// <summary>
    /// A notification from the tray icon (shown as a Windows toast on Windows 10/11). Clicking it
    /// runs <paramref name="onClick"/>. Respects Focus Assist / quiet hours.
    /// </summary>
    public void ShowNotification(string title, string message, bool warning = false, Action? onClick = null)
    {
        if (!_added) return;
        _balloonClick = onClick;
        var data = Data(NIF_INFO);
        data.szInfoTitle = title.Length > 63 ? title[..63] : title;
        data.szInfo = message.Length > 255 ? message[..255] : message;
        data.dwInfoFlags = (warning ? NIIF_WARNING : NIIF_INFO) | NIIF_RESPECT_QUIET_TIME;
        if (!Shell_NotifyIcon(NIM_MODIFY, ref data)) Log.Info("TrayIcon: notification not shown");
    }

    /// <summary>
    /// Call right before opening a popup menu: the owner must be foreground, otherwise the
    /// menu doesn't close when the user clicks elsewhere.
    /// </summary>
    public void PrepareForMenu() => SetForegroundWindow(_window.Handle);

    private NOTIFYICONDATA Data(uint flags) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = _window.Handle,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = WM_APP_TRAY,
        hIcon = _icon,
        szTip = _tooltip.Length > 127 ? _tooltip[..127] : _tooltip,
        szInfo = "",
        szInfoTitle = "",
    };

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_APP_TRAY)
        {
            // NOTIFYICON_VERSION_4: the event is in LOWORD(lParam).
            var evt = (int)(lParam.ToInt64() & 0xFFFF);
            if (evt is NIN_SELECT or NIN_KEYSELECT)
            {
                handled = true;
                LeftClicked?.Invoke(this, EventArgs.Empty);
            }
            else if (evt == WM_CONTEXTMENU)
            {
                handled = true;
                RightClicked?.Invoke(this, EventArgs.Empty);
            }
            else if (evt == NIN_BALLOONUSERCLICK && _balloonClick is { } click)
            {
                handled = true;
                _balloonClick = null;
                click();
            }
        }
        else if (_taskbarCreated != 0 && msg == (int)_taskbarCreated)
        {
            // Explorer restarted: the icon is gone, add it again.
            _added = false;
            Show();
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_added)
        {
            var data = Data(0);
            Shell_NotifyIcon(NIM_DELETE, ref data);
            _added = false;
        }
        if (_icon != IntPtr.Zero) DestroyIcon(_icon);
        _window.RemoveHook(WndProc);
        _window.Dispose();
    }
}
