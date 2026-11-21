using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Glance.App.Content;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Logging;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Glance.App.Video;

/// <summary>
/// One video surface of Video Inspect (port of macOS <c>VideoInspectViewport</c>). WPF's
/// <see cref="MediaPlayer"/> (Media Foundation) plays most files; WebM — and anything Media
/// Foundation can't open — falls back to a WebView2 <c>&lt;video&gt;</c> element, like the macOS
/// WebKit fallback. No system controls: Video Inspect drives play / pause / seek / mute.
/// </summary>
internal sealed class VideoPane : Grid, IDisposable
{
    private const string VideoHost = "video.glance.invalid";
    private static readonly string[] WebFirstExtensions = [".webm"];

    private readonly string _webDataFolder;
    private readonly VideoSurface _surface;
    private readonly Border _dim;
    private readonly LoadingSweep _loading;
    private readonly TextBlock _failed;
    private readonly ScaleTransform _zoom = new(1, 1);
    private MediaPlayer? _player;
    private WebView2? _web;
    private TaskCompletionSource<bool>? _seekWaiter;
    private bool _disposed;
    private bool _ready;
    private bool _muted;
    private double _webTime;
    private double _webDuration;
    private SizeD? _webSize;

    public VideoPane(MediaInfo info, string webDataFolder)
    {
        Info = info;
        _webDataFolder = webDataFolder;
        ClipToBounds = true;
        Background = Ui.Brush("InspectInk0Brush");
        _surface = new VideoSurface { RenderTransform = _zoom, RenderTransformOrigin = new Point(0.5, 0.5) };
        _dim = new Border { Background = Ui.Brush("InspectDimBrush"), Visibility = Visibility.Collapsed, IsHitTestVisible = false };
        _loading = new LoadingSweep { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(48, 0, 48, 0) };
        _failed = new TextBlock
        {
            Text = L.T("This video can’t be played."),
            FontSize = 13,
            Foreground = Ui.Brush("InspectText3Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(16),
            Visibility = Visibility.Collapsed,
        };
        Children.Add(_surface);
        Children.Add(_loading);
        Children.Add(_failed);
        Children.Add(_dim);

        if (WebFirstExtensions.Contains(info.Extension, StringComparer.OrdinalIgnoreCase)) _ = StartWebAsync();
        else StartNative();
    }

    public MediaInfo Info { get; private set; }
    public bool IsReady => _ready;
    public bool IsFailed { get; private set; }
    public bool UsesWeb => _web is not null;

    /// <summary>Size and duration are known; playback can start.</summary>
    public event Action<VideoPane>? Ready;
    public event Action<VideoPane>? Failed;
    public event Action<VideoPane>? Ended;
    public event Action<VideoPane>? Activated;
    public event Action<VideoPane>? MenuRequested;

    public SizeD? NaturalSize =>
        _player is { NaturalVideoWidth: > 0, NaturalVideoHeight: > 0 } p ? new SizeD(p.NaturalVideoWidth, p.NaturalVideoHeight) : _webSize;

    public double Duration =>
        _player is { NaturalDuration.HasTimeSpan: true } p ? p.NaturalDuration.TimeSpan.TotalSeconds : _webDuration;

    public double Position => _player?.Position.TotalSeconds ?? _webTime;

    public bool HasReachedEnd => Duration > 0 && Position >= Duration - 0.05;

    public bool IsMuted => _muted;

    public bool Dimmed
    {
        set => _dim.Visibility = value && _web is null ? Visibility.Visible : Visibility.Collapsed;
    }

    public void SetMuted(bool muted)
    {
        _muted = muted;
        if (_player is not null) _player.IsMuted = muted;
        else Script($"glance.mute({(muted ? "true" : "false")})");
    }

    public void Play()
    {
        if (_player is not null) _player.Play();
        else Script("glance.play()");
    }

    public void Pause()
    {
        if (_player is not null) _player.Pause();
        else Script("glance.pause()");
    }

    /// <summary>Seeks to <paramref name="seconds"/>; completes when the frame there is shown (or after a timeout).</summary>
    public async Task SeekAsync(double seconds)
    {
        seconds = Math.Max(0, seconds);
        if (_player is not null)
        {
            _player.Position = TimeSpan.FromSeconds(seconds);
            // MediaPlayer has no seek callback; give the scrubbed frame a moment to present.
            await Task.Delay(60);
            return;
        }
        if (_web?.CoreWebView2 is null) return;
        _seekWaiter?.TrySetResult(false);
        var waiter = new TaskCompletionSource<bool>();
        _seekWaiter = waiter;
        _webTime = seconds;
        Script($"glance.seek({seconds.ToString(System.Globalization.CultureInfo.InvariantCulture)})");
        await Task.WhenAny(waiter.Task, Task.Delay(1500));
    }

    /// <summary>Hides the WebView2 window (it would cover WPF overlays such as the capture editor).</summary>
    public void SetWebVisible(bool visible)
    {
        if (_web is not null) _web.Visibility = visible ? Visibility.Visible : Visibility.Hidden;
    }

    /// <summary>The frame on screen at native size (WebView2: at its display size).</summary>
    public async Task<BitmapSource?> CaptureFrameAsync()
    {
        try
        {
            if (_player is { NaturalVideoWidth: > 0, NaturalVideoHeight: > 0 } player)
            {
                var w = player.NaturalVideoWidth;
                var h = player.NaturalVideoHeight;
                var visual = new DrawingVisual();
                using (var dc = visual.RenderOpen()) dc.DrawVideo(player, new Rect(0, 0, w, h));
                var target = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
                target.Render(visual);
                target.Freeze();
                return target;
            }
            if (_web?.CoreWebView2 is { } core && _web.Visibility == Visibility.Visible)
            {
                using var stream = new MemoryStream();
                await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
                stream.Position = 0;
                var decoder = new PngBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                var frame = decoder.Frames[0];
                frame.Freeze();
                return frame;
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException or OutOfMemoryException or System.Runtime.InteropServices.COMException or NotSupportedException)
        {
            Log.Warning($"VideoPane: frame capture failed: {ex.Message}");
        }
        return null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_player is not null)
        {
            _player.MediaOpened -= OnMediaOpened;
            _player.MediaFailed -= OnMediaFailed;
            _player.MediaEnded -= OnMediaEnded;
            _player.Stop();
            _player.Close();
            _player = null;
        }
        if (_web is not null)
        {
            Children.Remove(_web);
            _web.Dispose();
            _web = null;
        }
        _seekWaiter?.TrySetResult(false);
    }

    // ───────────────────────────── Native (Media Foundation) ─────────────────────────────

    private void StartNative()
    {
        _loading.Visibility = Visibility.Visible;
        var player = new MediaPlayer { ScrubbingEnabled = true, Volume = 1, IsMuted = _muted };
        player.MediaOpened += OnMediaOpened;
        player.MediaFailed += OnMediaFailed;
        player.MediaEnded += OnMediaEnded;
        _player = player;
        _surface.Player = player;
        player.Open(SourceUri(Info));
    }

    private void OnMediaOpened(object? sender, EventArgs e)
    {
        if (_player is not { } player) return;
        // Audio-only or zero-size streams: let the web fallback try (it shows a clean error if it can't).
        if (player.NaturalVideoWidth <= 0 || player.NaturalVideoHeight <= 0)
        {
            Log.Info($"VideoPane: no video stream in '{Log.Redact(Info.Location)}' via Media Foundation");
        }
        _loading.Visibility = Visibility.Collapsed;
        _failed.Visibility = Visibility.Collapsed;
        _ready = true;
        _surface.InvalidateVisual();
        Ready?.Invoke(this);
    }

    private void OnMediaFailed(object? sender, ExceptionEventArgs e)
    {
        Log.Info($"VideoPane: Media Foundation can't play '{Log.Redact(Info.Location)}' ({e.ErrorException?.GetType().Name}); trying WebView2");
        if (_player is { } player)
        {
            player.MediaOpened -= OnMediaOpened;
            player.MediaFailed -= OnMediaFailed;
            player.MediaEnded -= OnMediaEnded;
            player.Close();
        }
        _player = null;
        _surface.Player = null;
        _ = StartWebAsync();
    }

    private void OnMediaEnded(object? sender, EventArgs e) => Ended?.Invoke(this);

    private static Uri SourceUri(MediaInfo info) =>
        info.IsLocal ? new Uri(Path.GetFullPath(info.Location)) : new Uri(info.Location);

    // ───────────────────────────── WebView2 fallback ─────────────────────────────

    private async Task StartWebAsync()
    {
        _loading.Visibility = Visibility.Visible;
        try
        {
            var options = new CoreWebView2EnvironmentOptions("--autoplay-policy=no-user-gesture-required");
            var environment = await CoreWebView2Environment.CreateAsync(null, _webDataFolder, options);
            if (_disposed) return;
            var web = new WebView2 { DefaultBackgroundColor = System.Drawing.Color.FromArgb(unchecked((int)Ui.Argb("InspectInk0Color"))) };
            _web = web;
            Children.Insert(1, web);
            await web.EnsureCoreWebView2Async(environment);
            if (_disposed) return;
            var core = web.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.WebMessageReceived += OnWebMessage;
            string source;
            if (Info.IsLocal)
            {
                var folder = Path.GetDirectoryName(Path.GetFullPath(Info.Location)) ?? "";
                core.SetVirtualHostNameToFolderMapping(VideoHost, folder, CoreWebView2HostResourceAccessKind.Allow);
                source = $"https://{VideoHost}/{Uri.EscapeDataString(Path.GetFileName(Info.Location))}";
            }
            else
            {
                source = Info.Location;
            }
            core.NavigateToString(PlayerHtml(source, Ui.CssHex("InspectInk0Color"), _muted));
        }
        catch (Exception ex)
        {
            Log.Warning($"VideoPane: WebView2 player unavailable: {ex.GetType().Name}: {ex.Message}");
            ShowFailed(L.T("This video can’t be played. Install the Microsoft Edge WebView2 Runtime or open it with the default app."));
        }
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var root = doc.RootElement;
            switch (root.GetProperty("type").GetString())
            {
                case "ready":
                    _webDuration = Number(root, "duration");
                    var w = Number(root, "width");
                    var h = Number(root, "height");
                    _webSize = w > 0 && h > 0 ? new SizeD(w, h) : null;
                    _loading.Visibility = Visibility.Collapsed;
                    _ready = true;
                    Ready?.Invoke(this);
                    break;
                case "time":
                    _webTime = Number(root, "time");
                    break;
                case "seeked":
                    _webTime = Number(root, "time");
                    _seekWaiter?.TrySetResult(true);
                    break;
                case "ended":
                    Ended?.Invoke(this);
                    break;
                case "error":
                    Log.Info($"VideoPane: WebView2 can't play '{Log.Redact(Info.Location)}' (code {Number(root, "code")})");
                    ShowFailed(L.T("This video can’t be played."));
                    break;
                case "click":
                    Activated?.Invoke(this);
                    break;
                case "menu":
                    Activated?.Invoke(this);
                    MenuRequested?.Invoke(this);
                    break;
            }
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            Log.Warning($"VideoPane: bad player message: {ex.Message}");
        }
    }

    private static double Number(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var d) && double.IsFinite(d) ? d : 0;

    private void ShowFailed(string message)
    {
        _loading.Visibility = Visibility.Collapsed;
        _failed.Text = message;
        _failed.Visibility = Visibility.Visible;
        if (_web is not null) _web.Visibility = Visibility.Hidden;
        IsFailed = true;
        Failed?.Invoke(this);
    }

    private void Script(string script)
    {
        if (_web?.CoreWebView2 is not { } core || !_ready) return;
        _ = core.ExecuteScriptAsync(script);
    }

    /// <summary>A bare player page. Time is reported every animation frame while playing.</summary>
    private static string PlayerHtml(string source, string background, bool muted) => $$"""
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;height:100%;background:{{background}};overflow:hidden}
        video{width:100%;height:100%;object-fit:contain;display:block;background:{{background}} }</style></head>
        <body><video id="v" preload="auto" playsinline {{(muted ? "muted" : "")}}></video>
        <script>
        const v=document.getElementById('v');const post=m=>window.chrome.webview.postMessage(m);
        v.addEventListener('loadedmetadata',()=>post({type:'ready',duration:isFinite(v.duration)?v.duration:0,width:v.videoWidth,height:v.videoHeight}));
        v.addEventListener('seeked',()=>post({type:'seeked',time:v.currentTime}));
        v.addEventListener('ended',()=>post({type:'ended'}));
        v.addEventListener('error',()=>post({type:'error',code:v.error?v.error.code:0}));
        let last=0;const tick=t=>{if(v.paused)return;if(t-last>30){last=t;post({type:'time',time:v.currentTime});}requestAnimationFrame(tick);};
        v.addEventListener('play',()=>requestAnimationFrame(tick));
        v.addEventListener('pause',()=>post({type:'time',time:v.currentTime}));
        document.addEventListener('mousedown',e=>{if(e.button===0)post({type:'click'});});
        document.addEventListener('contextmenu',e=>{e.preventDefault();post({type:'menu'});});
        window.glance={play:()=>v.play().catch(()=>{}),pause:()=>v.pause(),seek:t=>{v.currentTime=t;},mute:m=>{v.muted=m;} };
        v.src={{JsonSerializer.Serialize(source)}};
        </script></body></html>
        """;

    // ───────────────────────────── Input ─────────────────────────────

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Activated?.Invoke(this);
        // Double-click toggles between aspect fit and 2× (macOS mirrors Image Inspect's gesture).
        if (e.ClickCount == 2)
        {
            var scale = _zoom.ScaleX > 1.01 ? 1 : 2;
            _zoom.ScaleX = scale;
            _zoom.ScaleY = scale;
            e.Handled = true;
        }
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonUp(e);
        Activated?.Invoke(this);
        MenuRequested?.Invoke(this);
        e.Handled = true;
    }

    public void ResetZoom()
    {
        _zoom.ScaleX = 1;
        _zoom.ScaleY = 1;
    }

    /// <summary>Draws the MediaPlayer's frames aspect-fitted into the pane.</summary>
    private sealed class VideoSurface : FrameworkElement
    {
        private MediaPlayer? _player;

        public MediaPlayer? Player
        {
            get => _player;
            set
            {
                _player = value;
                InvalidateVisual();
            }
        }

        protected override void OnRender(DrawingContext dc)
        {
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(RenderSize));
            if (_player is not { NaturalVideoWidth: > 0, NaturalVideoHeight: > 0 } player) return;
            var fit = Math.Min(RenderSize.Width / player.NaturalVideoWidth, RenderSize.Height / player.NaturalVideoHeight);
            var w = player.NaturalVideoWidth * fit;
            var h = player.NaturalVideoHeight * fit;
            dc.DrawVideo(player, new Rect((RenderSize.Width - w) / 2, (RenderSize.Height - h) / 2, w, h));
        }

        protected override void OnRenderSizeChanged(SizeChangedInfo sizeInfo)
        {
            base.OnRenderSizeChanged(sizeInfo);
            InvalidateVisual();
        }
    }
}
