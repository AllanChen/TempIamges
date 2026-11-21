using System.Windows;
using Glance.App.Content;
using Glance.App.Inspect;
using Glance.App.Localization;
using Glance.App.Video;
using Glance.App.Widgets;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.Inspect;
using Glance.Core.Logging;
using Glance.Platform;

namespace Glance.App.Peek;

/// <summary>
/// What "open" means for an item (port of macOS <c>directOpen</c> / tile click routing).
/// Images open in Image Inspect (Phase 3) and videos in Video Inspect (Phase 4), each with the
/// other items of the same kind from that Peek in its filmstrip; Markdown, text/code, PDF and web
/// pages open in the content viewer (Phase 2).
/// </summary>
internal sealed class ItemRouter : IInspectHost
{
    private readonly Lazy<ContentWindow> _content;
    private InspectWindow? _inspect;
    private VideoWindow? _video;
    private readonly string _videoWebDataFolder;
    private readonly List<InspectWindow> _captureWindows = [];

    public ItemRouter(string webDataFolder, string videoWebDataFolder)
    {
        _content = new Lazy<ContentWindow>(() => new ContentWindow(webDataFolder));
        _videoWebDataFolder = videoWebDataFolder;
    }

    /// <param name="context">Everything the Peek showed; its images fill the Inspect filmstrip.</param>
    public void Open(MediaInfo info, IReadOnlyList<MediaInfo>? context = null)
    {
        Log.Info($"ItemRouter: open {info.Kind} '{Log.Redact(info.Location)}'");
        if (info.Kind is MediaKind.Image or MediaKind.Video)
        {
            var items = (context ?? new[] { info }).Where(i => i.Kind == info.Kind).ToList();
            var index = items.FindIndex(i => InspectSession.Identity(i) == InspectSession.Identity(info));
            if (index < 0)
            {
                items.Insert(0, info);
                index = 0;
            }
            if (info.Kind == MediaKind.Image) OpenImages(items, index);
            else OpenVideos(items, index);
            return;
        }
        if (ContentWindow.CanShow(info))
        {
            _content.Value.Open(info);
            return;
        }
        ShellActions.Open(info.Location);
    }

    /// <summary>Opens (or replaces) the reusable Image Inspect session.</summary>
    public void OpenImages(IReadOnlyList<MediaInfo> images, int focusedIndex, InspectMode mode = InspectMode.Focus)
    {
        if (images.Count == 0) return;
        _inspect ??= new InspectWindow(this, reusable: true);
        _inspect.Show(images, focusedIndex, mode);
    }

    /// <summary>Opens (or replaces) the reusable Video Inspect session.</summary>
    public void OpenVideos(IReadOnlyList<MediaInfo> videos, int focusedIndex, InspectMode mode = InspectMode.Focus)
    {
        if (videos.Count == 0) return;
        _video ??= new VideoWindow(this, reusable: true, _videoWebDataFolder);
        _video.Show(videos, focusedIndex, mode);
    }

    public void Reveal(MediaInfo info)
    {
        if (info.IsLocal) ShellActions.RevealInExplorer(info.Location);
        else ShellActions.Open(info.Location);
    }

    void IInspectHost.OpenOther(MediaInfo info) => Open(info);

    /// <summary>Set once the account services are up (Phase 5).</summary>
    public WidgetRunner? Widgets { get; set; }

    /// <summary>A saved capture opens in its own Inspect window, 28 pt down-right of its source, with a toast.</summary>
    void IInspectHost.OpenCapture(string path, Window source)
    {
        var window = new InspectWindow(this, reusable: false);
        _captureWindows.Add(window);
        window.Closed += (_, _) => _captureWindows.Remove(window);
        window.Show([new MediaInfo(path, true, MediaKind.Image)], 0);
        var sourceHwnd = new System.Windows.Interop.WindowInteropHelper(source).Handle;
        var hwnd = new System.Windows.Interop.WindowInteropHelper(window).Handle;
        if (sourceHwnd != IntPtr.Zero && hwnd != IntPtr.Zero && source.WindowState == WindowState.Normal)
        {
            var from = ScreenGeometry.WindowRect(sourceHwnd);
            var current = ScreenGeometry.WindowRect(hwnd);
            var offset = (int)Math.Round(28 * ScreenGeometry.MonitorOf(sourceHwnd).Scale);
            var work = ScreenGeometry.MonitorOf(sourceHwnd).WorkArea;
            ScreenGeometry.SetWindowRect(hwnd, ScreenManager.Clamp(new PixelRect(from.X + offset, from.Y + offset, current.Width, current.Height), work));
        }
        window.ShowToast(L.T("Capture saved ✓") + "\n" + path);
    }

    /// <summary>Lets the viewer ask about unsaved edits. False = the user cancelled quitting.</summary>
    public Task<bool> PrepareForQuitAsync() =>
        _content.IsValueCreated ? _content.Value.PrepareForQuitAsync() : Task.FromResult(true);

    public void Shutdown()
    {
        if (_content.IsValueCreated) _content.Value.DisposeViewer();
        _inspect?.Shutdown();
        _video?.Shutdown();
        foreach (var window in _captureWindows.ToList()) window.Shutdown();
    }
}
