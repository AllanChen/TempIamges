using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.Core.Logging;
using Glance.Platform.Interop;

namespace Glance.Platform;

/// <summary>
/// Explorer thumbnails and icons (QuickLook thumbnail role on macOS). Thumbnails come from
/// <c>IShellItemImageFactory</c> (video frames, PDFs, Office docs where a handler exists);
/// icons by extension come from the system "jumbo" image list, which also works for remote URLs.
/// All results are frozen, so they can cross threads.
/// </summary>
public static class ShellThumbnails
{
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, int flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE
    {
        public int cx, cy;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

    private const int SIIGBF_RESIZETOFIT = 0x0;
    private const int SIIGBF_BIGGERSIZEOK = 0x1;
    private const int SIIGBF_ICONONLY = 0x4;
    private const int SIIGBF_THUMBNAILONLY = 0x8;

    private static readonly Guid ShellItemImageFactoryId = new("bcc18b79-ba16-442f-80c4-8a59c30c463b");
    private static readonly Guid ImageListId = new("46EB5926-582E-4017-9FDF-E8998DAA0950");

    /// <summary>Thumbnail (or icon fallback) for an existing file/folder, on an STA worker thread.</summary>
    public static Task<BitmapSource?> GetAsync(string path, int sizePx, bool thumbnailOnly = false) =>
        RunSta(() => Get(path, sizePx, thumbnailOnly ? SIIGBF_THUMBNAILONLY : SIIGBF_RESIZETOFIT), TimeSpan.FromSeconds(4));

    /// <summary>The file-type icon for an extension (".png") or "folder"; works for files that don't exist.</summary>
    public static BitmapSource? IconForExtension(string extensionOrFolder)
    {
        var isFolder = extensionOrFolder == "folder";
        var info = new Native.SHFILEINFO();
        var name = isFolder ? "folder" : "file" + (extensionOrFolder.StartsWith('.') ? extensionOrFolder : "." + extensionOrFolder);
        var attributes = isFolder ? Native.FILE_ATTRIBUTE_DIRECTORY : Native.FILE_ATTRIBUTE_NORMAL;
        if (Native.SHGetFileInfo(name, attributes, ref info, (uint)Marshal.SizeOf<Native.SHFILEINFO>(),
                Native.SHGFI_SYSICONINDEX | Native.SHGFI_USEFILEATTRIBUTES) == IntPtr.Zero)
            return null;

        var riid = ImageListId;
        if (Native.SHGetImageList(Native.SHIL_JUMBO, ref riid, out var imageList) != 0 || imageList == IntPtr.Zero)
            return null;
        var hIcon = Native.ImageList_GetIcon(imageList, info.iIcon, Native.ILD_TRANSPARENT);
        if (hIcon == IntPtr.Zero) return null;
        try
        {
            var source = Imaging.CreateBitmapSourceFromHIcon(hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally
        {
            Native.DestroyIcon(hIcon);
        }
    }

    private static BitmapSource? Get(string path, int sizePx, int flags)
    {
        try
        {
            SHCreateItemFromParsingName(path, IntPtr.Zero, ShellItemImageFactoryId, out var factory);
            try
            {
                var hr = factory.GetImage(new SIZE { cx = sizePx, cy = sizePx }, flags | SIIGBF_BIGGERSIZEOK, out var hbitmap);
                if (hr != 0 || hbitmap == IntPtr.Zero) return null;
                try
                {
                    return FromHBitmap(hbitmap);
                }
                finally
                {
                    Native.DeleteObject(hbitmap);
                }
            }
            finally
            {
                Marshal.ReleaseComObject(factory);
            }
        }
        catch (Exception ex) when (ex is COMException or FileNotFoundException or UnauthorizedAccessException or ArgumentException)
        {
            Log.Info($"ShellThumbnails: no image for '{Log.Redact(path)}': {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Converts a shell HBITMAP keeping its alpha channel (CreateBitmapSourceFromHBitmap drops alpha
    /// and renders icon backgrounds black). The pixels are requested from GDI as a top-down 32-bpp
    /// DIB, so the result is upright however the shell stored them: reading <c>bmBits</c> directly
    /// and trusting <c>biHeight</c> flipped thumbnails upside down (verified by
    /// <c>ShellThumbnailOrientationTests</c>).
    /// </summary>
    private static BitmapSource? FromHBitmap(IntPtr hbitmap)
    {
        if (Native.GetObject(hbitmap, Marshal.SizeOf<Native.DIBSECTION>(), out var dib) == 0) return null;
        var width = dib.dsBm.bmWidth;
        var height = Math.Abs(dib.dsBm.bmHeight);
        if (width <= 0 || height <= 0) return null;

        var header = new BITMAPINFOHEADER
        {
            biSize = (uint)Marshal.SizeOf<BITMAPINFOHEADER>(),
            biWidth = width,
            biHeight = -height, // negative: top-down rows
            biPlanes = 1,
            biBitCount = 32,
            biCompression = 0, // BI_RGB
        };
        var stride = width * 4;
        var pixels = new byte[stride * height];
        var screen = GetDC(IntPtr.Zero);
        int lines;
        try
        {
            lines = GetDIBits(screen, hbitmap, 0, (uint)height, pixels, ref header, 0);
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screen);
        }
        BitmapSource result;
        if (lines == height)
        {
            // JPEG-style thumbnails often arrive with an all-zero alpha channel: treat as opaque.
            var hasAlpha = false;
            for (var i = 3; i < pixels.Length; i += 4)
            {
                if (pixels[i] != 0) { hasAlpha = true; break; }
            }
            result = BitmapSource.Create(width, height, 96, 96, hasAlpha ? PixelFormats.Pbgra32 : PixelFormats.Bgr32, null, pixels, stride);
        }
        else
        {
            result = Imaging.CreateBitmapSourceFromHBitmap(hbitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        }
        result.Freeze();
        return result;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth;
        public int biHeight;
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr hdc, IntPtr hbitmap, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFOHEADER info, uint usage);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    private static async Task<T?> RunSta<T>(Func<T?> work, TimeSpan timeout) where T : class
    {
        var tcs = new TaskCompletionSource<T?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { tcs.TrySetResult(work()); }
            catch (Exception ex) { tcs.TrySetException(ex); }
        })
        { IsBackground = true, Name = "Glance shell thumbnail" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        var finished = await Task.WhenAny(tcs.Task, Task.Delay(timeout));
        if (finished != tcs.Task) return null;
        try { return await tcs.Task; }
        catch (Exception ex)
        {
            Log.Info($"ShellThumbnails: failed: {ex.Message}");
            return null;
        }
    }
}
