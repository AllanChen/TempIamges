using System.Runtime.InteropServices;
using Glance.Platform.Interop;

namespace Glance.Platform;

/// <summary>
/// Byte copy of every HGLOBAL clipboard format, so the Ctrl+C selection fallback can put the
/// user's clipboard back afterwards (port of the macOS pasteboard snapshot/restore).
/// GDI-handle formats are skipped; Windows re-synthesizes bitmaps from CF_DIB.
/// </summary>
internal sealed class ClipboardSnapshot
{
    private const long MaxTotalBytes = 64L * 1024 * 1024;

    private static readonly HashSet<uint> HandleFormats =
    [
        2,    // CF_BITMAP
        3,    // CF_METAFILEPICT
        9,    // CF_PALETTE
        14,   // CF_ENHMETAFILE
        0x80, // CF_OWNERDISPLAY
        0x82, // CF_DSPBITMAP
        0x83, // CF_DSPMETAFILEPICT
        0x8E, // CF_DSPENHMETAFILE
    ];

    private static readonly uint ExcludeFromHistoryFormat =
        Native.RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");

    private readonly List<(uint Format, byte[] Data)> _items;

    private ClipboardSnapshot(List<(uint, byte[])> items) => _items = items;

    public static ClipboardSnapshot? Capture(IntPtr owner)
    {
        if (!TryOpen(owner)) return null;
        var items = new List<(uint, byte[])>();
        try
        {
            long total = 0;
            uint format = 0;
            while ((format = Native.EnumClipboardFormats(format)) != 0)
            {
                // Skip GDI handles and the private/GDI-object ranges, which are not HGLOBALs.
                if (HandleFormats.Contains(format) || format is >= 0x0200 and <= 0x03FF) continue;
                var handle = Native.GetClipboardData(format);
                if (handle == IntPtr.Zero) continue;
                var size = (long)(ulong)Native.GlobalSize(handle);
                if (size <= 0 || total + size > MaxTotalBytes) continue;
                var ptr = Native.GlobalLock(handle);
                if (ptr == IntPtr.Zero) continue;
                try
                {
                    var data = new byte[size];
                    Marshal.Copy(ptr, data, 0, (int)size);
                    items.Add((format, data));
                    total += size;
                }
                finally
                {
                    Native.GlobalUnlock(handle);
                }
            }
        }
        finally
        {
            Native.CloseClipboard();
        }
        return new ClipboardSnapshot(items);
    }

    /// <summary>Puts the snapshot back, marked so Windows clipboard history doesn't record it again.</summary>
    public void Restore(IntPtr owner)
    {
        if (!TryOpen(owner)) return;
        try
        {
            Native.EmptyClipboard();
            foreach (var (format, data) in _items) SetBytes(format, data);
            if (_items.Count > 0 && ExcludeFromHistoryFormat != 0) SetBytes(ExcludeFromHistoryFormat, [0, 0, 0, 0]);
        }
        finally
        {
            Native.CloseClipboard();
        }
    }

    public static string? ReadText(IntPtr owner)
    {
        if (!TryOpen(owner)) return null;
        try
        {
            var handle = Native.GetClipboardData(Native.CF_UNICODETEXT);
            if (handle == IntPtr.Zero) return null;
            var ptr = Native.GlobalLock(handle);
            if (ptr == IntPtr.Zero) return null;
            try
            {
                return Marshal.PtrToStringUni(ptr);
            }
            finally
            {
                Native.GlobalUnlock(handle);
            }
        }
        finally
        {
            Native.CloseClipboard();
        }
    }

    private static void SetBytes(uint format, byte[] data)
    {
        var handle = Native.GlobalAlloc(Native.GMEM_MOVEABLE, (UIntPtr)data.Length);
        if (handle == IntPtr.Zero) return;
        var ptr = Native.GlobalLock(handle);
        if (ptr == IntPtr.Zero)
        {
            Native.GlobalFree(handle);
            return;
        }
        Marshal.Copy(data, 0, ptr, data.Length);
        Native.GlobalUnlock(handle);
        // On success the system owns the memory; free it only on failure.
        if (Native.SetClipboardData(format, handle) == IntPtr.Zero) Native.GlobalFree(handle);
    }

    /// <summary>Another process may hold the clipboard briefly; retry for ~100 ms.</summary>
    private static bool TryOpen(IntPtr owner)
    {
        for (var i = 0; i < 10; i++)
        {
            if (Native.OpenClipboard(owner)) return true;
            Thread.Sleep(10);
        }
        return false;
    }
}
