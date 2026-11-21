using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Core.Inspect;
using Glance.Core.Logging;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App.Inspect;

internal sealed partial class InspectWindow
{
    private readonly Dictionary<string, OcrOutput> _ocr = [];
    private string? _ocrShownKey;

    // ───────────────────────────── Modes & navigation ─────────────────────────────

    private void EnterCompare(CompareStyle style)
    {
        if (_session is not { } s) return;
        if (!s.EnterCompare(style))
        {
            _toast.Show(L.T("Add another image to compare."), error: true);
            return;
        }
        Render();
        LoadActive();
    }

    private void ExitCompare()
    {
        if (_session is not { IsComparing: true } s) return;
        s.ExitCompare();
        _fittedFor = null;
        Render();
        LoadActive();
    }

    private void SelectSlot(int slot)
    {
        if (_session?.SelectSlot(slot) != true) return;
        _primary.Dimmed = slot != 0;
        _secondary.Dimmed = slot != 1;
        UpdateInfo();
        RefreshOcrPanel();
    }

    private void OnTileClicked(int index, bool alt)
    {
        if (_session is not { } s) return;
        var changed = alt ? s.CompareWith(index) : s.Select(index);
        if (!changed) return;
        Render();
        LoadActive();
    }

    private void Navigate(int delta)
    {
        if (_session?.Navigate(delta) != true) return;
        Render();
        LoadActive();
    }

    private IEnumerable<ImageViewport> ActiveViewports =>
        _session is { IsComparing: true, Style: CompareStyle.SideBySide } ? new[] { _primary, _secondary } : new[] { _primary };

    /// <summary>The pane actions apply to: the active compare slot side by side, otherwise the main pane.</summary>
    private ImageViewport ActiveViewport =>
        _session is { IsComparing: true, Style: CompareStyle.SideBySide, ActiveSlot: 1 } ? _secondary : _primary;

    private void FitAll()
    {
        foreach (var viewport in ActiveViewports) viewport.FitToView();
        UpdateBottomBar();
    }

    private void ActualSizeAll()
    {
        foreach (var viewport in ActiveViewports) viewport.ActualSize();
        UpdateBottomBar();
    }

    private void ZoomAll(double factor)
    {
        foreach (var viewport in ActiveViewports) viewport.ZoomBy(factor);
        UpdateBottomBar();
    }

    private void Rotate(int quarters)
    {
        if (ActiveBitmap() is null) return;
        ActiveViewport.Rotate(quarters);
    }

    private void Flip(bool horizontal)
    {
        if (ActiveBitmap() is null) return;
        ActiveViewport.Flip(horizontal);
    }

    private void RevealActive()
    {
        if (_session is not { } s) return;
        var info = s[s.ActiveIndex];
        if (info.IsLocal) ShellActions.RevealInExplorer(info.Location);
    }

    private void RetryActive()
    {
        if (_session is not { } s) return;
        var key = ItemKey(s.ActiveIndex);
        _failed.Remove(key);
        _thumbs.Remove(key);
        Render();
        LoadActive();
    }

    // ───────────────────────────── Image information ─────────────────────────────

    private void ToggleInfo()
    {
        if (_infoVisible)
        {
            CloseInfo();
            return;
        }
        if (_session is null) return;
        _infoWindow ??= CreateInfoWindow();
        _infoVisible = true;
        SetActive(_infoButton, true);
        UpdateInfo();
        _infoWindow.ShowBeside();
    }

    private InspectInfoWindow CreateInfoWindow()
    {
        var window = new InspectInfoWindow(this);
        window.CloseRequested += CloseInfo;
        return window;
    }

    private void CloseInfo()
    {
        _infoVisible = false;
        SetActive(_infoButton, false);
        _infoWindow?.Hide();
    }

    /// <summary>The image under the pointer (slider: A), else the active slot; the other compare image for the diff.</summary>
    private void UpdateInfo()
    {
        if (!_infoVisible || _infoWindow is null || _session is not { } s) return;
        int index;
        int? other = null;
        if (s.IsComparing)
        {
            var (a, b) = s.Pair!.Value;
            index = s.Style == CompareStyle.SideBySide && _hovered is not null
                ? (_hovered == _primary ? a : b)
                : s.Style == CompareStyle.Slider && _hovered is not null ? a : s.ActiveIndex;
            other = index == a ? b : a;
        }
        else
        {
            index = s.FocusedIndex;
        }
        _infoWindow.Display(Snapshot(index), other is { } o ? Snapshot(o) : null);

        InfoSnapshot Snapshot(int i)
        {
            _ = LoadDetailsAsync(i);
            return new InfoSnapshot(s[i], _details.GetValueOrDefault(ItemKey(i)));
        }
    }

    // ───────────────────────────── Recognize Text ─────────────────────────────

    private async Task RecognizeTextAsync()
    {
        if (_session is not { } s || ActiveBitmap() is not { } bitmap) return;
        var key = ItemKey(s.ActiveIndex);
        _ocrWindow ??= CreateOcrWindow();
        _ocrWindow.ShowBeside();
        _ocrShownKey = key;
        if (_ocr.TryGetValue(key, out var cached))
        {
            _ocrWindow.ShowResult(cached.Text);
            return;
        }
        if (!OcrService.IsAvailable)
        {
            _ocrWindow.ShowMessage(L.T("Windows has no text recognition language installed. Add a language with OCR in Settings ▸ Time & language ▸ Language & region."));
            return;
        }
        _ocrWindow.ShowLoading();
        var session = _session;
        try
        {
            var pixels = await Task.Run(() => InspectImages.ToPixels(bitmap));
            var result = await OcrService.RecognizeAsync(pixels, _cts.Token);
            if (session != _session) return;
            if (result is null)
            {
                if (_ocrShownKey == key) _ocrWindow.ShowMessage(L.T("Text recognition isn't available. Add a language with OCR in Windows Settings."));
                return;
            }
            _ocr[key] = result;
            if (_ocrShownKey == key) _ocrWindow.ShowResult(result.Text);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex)
        {
            Log.Warning($"Inspect: OCR failed: {ex.Message}");
            if (_ocrShownKey == key) _ocrWindow.ShowMessage(L.T("Text recognition failed. Try again."));
        }
    }

    private OcrResultWindow CreateOcrWindow()
    {
        var window = new OcrResultWindow(this);
        window.Dismissed += () => _ocrShownKey = null;
        return window;
    }

    /// <summary>While the panel is open it follows the active image.</summary>
    private void RefreshOcrPanel()
    {
        if (_ocrWindow is not { IsVisible: true } || _session is not { } s) return;
        if (ItemKey(s.ActiveIndex) == _ocrShownKey) return;
        _ = RecognizeTextAsync();
    }

    // ───────────────────────────── Menus ─────────────────────────────

    private void ShowMoreMenu()
    {
        ShowChrome();
        var menu = BuildMenu(includeWindowSettings: true);
        menu.PlacementTarget = _moreButton;
        menu.Placement = PlacementMode.Custom;
        // Figma `21 · More menu`: 6 pt below the ⋯ button, right-aligned with it (the template adds a 12 pt shadow margin).
        menu.CustomPopupPlacementCallback = (popup, target, _) =>
            [new CustomPopupPlacement(new Point(target.Width - popup.Width + 12, target.Height + 6 - 12), PopupPrimaryAxis.Horizontal)];
        Open(menu);
    }

    private void ShowContextMenu(object? _)
    {
        var menu = BuildMenu(includeWindowSettings: false);
        menu.Placement = PlacementMode.MousePoint;
        Open(menu);
    }

    private void Open(ContextMenu menu)
    {
        if (_menu is { IsOpen: true }) _menu.IsOpen = false;
        _menu = menu;
        menu.Closed += (_, _) => { if (!IsMouseOver && _autoHide) _hideTimer.Start(); };
        menu.IsOpen = true;
    }

    /// <summary>macOS <c>buildActionEntries</c>: Actions, Export, Tools, Widgets, window settings (no Pro locks).</summary>
    private ContextMenu BuildMenu(bool includeWindowSettings)
    {
        var s = _session;
        var hasImage = ActiveBitmap() is not null;
        var info = s is null ? null : s[s.ActiveIndex];
        var menu = new ContextMenu();

        void Header(string title) => menu.Items.Add(new MenuItem { Header = title, Style = Ui.Style("MenuSectionHeader") });
        MenuItem Item(string title, Action action, bool enabled = true, string? gesture = null)
        {
            var item = new MenuItem { Header = title, IsEnabled = enabled, InputGestureText = gesture ?? "" };
            item.Click += (_, _) => action();
            return item;
        }
        MenuItem Sub(string title, bool enabled, params MenuItem[] children)
        {
            var item = new MenuItem { Header = title, IsEnabled = enabled };
            foreach (var child in children) item.Items.Add(child);
            return item;
        }
        void Separator() => menu.Items.Add(new Separator());

        Header(L.T("Actions"));
        menu.Items.Add(Item(L.T("Copy Image"), () => _ = CopyImageAsync(), hasImage, "Ctrl+C"));
        menu.Items.Add(Item(L.T("Save to Documents"), () => _ = QuickSaveAsync(), hasImage || s?.IsComparing == true, "Ctrl+S"));
        menu.Items.Add(Item(L.T("Recognize Text"), () => _ = RecognizeTextAsync(), hasImage));
        Separator();
        menu.Items.Add(Item(L.T("Rotate Left"), () => Rotate(-1), hasImage, "Ctrl+L"));
        menu.Items.Add(Item(L.T("Rotate Right"), () => Rotate(1), hasImage, "Ctrl+R"));
        menu.Items.Add(Sub(L.T("Flip"), hasImage,
            Item(L.T("Flip Horizontally"), () => Flip(true)),
            Item(L.T("Flip Vertically"), () => Flip(false))));
        Separator();
        Header(L.T("Export"));
        menu.Items.Add(Sub(L.T("Save as…"), hasImage,
            Item("PNG", () => _ = ExportAsync(ImageExportFormat.Png)),
            Item("JPG", () => _ = ExportAsync(ImageExportFormat.Jpeg)),
            Item("WebP", () => _ = ExportAsync(ImageExportFormat.WebP)),
            Item(L.T("Icon (.ico)"), () => _ = ExportAsync(ImageExportFormat.Ico))));
        menu.Items.Add(Item(L.T("Compress…"), ShowCompress, hasImage));
        menu.Items.Add(Item(L.T("Resize…"), ShowResize, hasImage));
        menu.Items.Add(Item(L.T("Copy as Base64"), () => _ = CopyBase64Async(), hasImage));
        Separator();
        Header(L.T("Tools"));
        menu.Items.Add(Item(L.T("Capture…"), () => _ = BeginCaptureAsync(), hasImage || s?.IsComparing == true, "Ctrl+Shift+X"));
        menu.Items.Add(Item(L.T("Base64 → Image…"), ShowBase64Input));
        menu.Items.Add(Item(L.T("Open image URL") + "…", ShowUrlInput));
        menu.Items.Add(Item(L.T("Add Images…"), AddImages));
        Separator();
        menu.Items.Add(Item(L.T("Reveal in File Explorer"), RevealActive, info?.IsLocal == true));
        menu.Items.Add(Item(L.T("Image information"), ToggleInfo, info is not null, "Ctrl+I"));
        _host.Widgets?.AddMenuItems(menu, "image", hasImage ? info : null, this, message => _toast.Show(message, error: true));
        if (includeWindowSettings)
        {
            Separator();
            menu.Items.Add(Item(L.T(_pinned ? "Unpin" : "Pin on Top"), TogglePin));
            var autoHide = Item(L.T("Automatic hide"), () => { _autoHide = !_autoHide; if (!_autoHide) ShowChrome(); });
            autoHide.IsChecked = _autoHide;
            menu.Items.Add(autoHide);
            menu.Items.Add(Item(L.T("Keyboard Shortcuts"), ShowShortcuts, gesture: "?"));
        }
        return menu;
    }

    private void TogglePin()
    {
        _pinned = !_pinned;
        Topmost = _pinned;
    }

    private void ShowShortcuts()
    {
        _shortcuts.Visibility = Visibility.Visible;
        _shortcuts.Focus();
    }

    // ───────────────────────────── Copy / save / export ─────────────────────────────

    private uint StageArgb => Ui.Argb("InspectInk0Color");

    /// <summary>The item at original resolution with the pane's rotation and flips (WYSIWYG; the file is untouched).</summary>
    private async Task<PixelImage?> PixelsAsync(int index, ImageViewport viewport)
    {
        if (_session is not { } s) return null;
        var pixels = await InspectImages.OriginalPixelsAsync(_loader, s[index], Bitmap(index), _cts.Token);
        if (pixels is null) return null;
        int quarters = viewport.Quarters;
        bool flipX = viewport.FlipX, flipY = viewport.FlipY;
        return await Task.Run(() => ImageCodec.Orient(pixels, quarters, flipX, flipY));
    }

    private Task<PixelImage?> ActivePixelsAsync() =>
        _session is { } s ? PixelsAsync(s.ActiveIndex, ActiveViewport) : Task.FromResult<PixelImage?>(null);

    private async Task CopyImageAsync()
    {
        try
        {
            var pixels = await ActivePixelsAsync();
            if (pixels is null) return;
            var (png, bitmap) = await Task.Run(() => (ImageCodec.Encode(pixels, ImageExportFormat.Png), InspectImages.ToBitmap(pixels)));
            if (png is null || !InspectImages.CopyToClipboard(bitmap, png))
            {
                _toast.Show(L.T("Couldn’t copy the image. The clipboard may be busy; try again."), error: true);
                return;
            }
            _toast.Show(L.T("Copied ✓"));
        }
        catch (OperationCanceledException) { }
    }

    private async Task CopyBase64Async()
    {
        try
        {
            var pixels = await ActivePixelsAsync();
            if (pixels is null) return;
            var base64 = await Task.Run(() => ImageCodec.Encode(pixels, ImageExportFormat.Png) is { } png ? Convert.ToBase64String(png) : null);
            if (base64 is null || !InspectImages.CopyText(base64))
            {
                _toast.Show(L.T("Couldn’t copy the image. The clipboard may be busy; try again."), error: true);
                return;
            }
            _toast.Show(L.T("Base64 copied ✓"));
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>
    /// Ctrl+S: the current view as PNG in Documents\Glance. Compare saves both images as the
    /// visible side-by-side or slider comparison.
    /// </summary>
    private async Task QuickSaveAsync()
    {
        if (_session is not { } s) return;
        try
        {
            PixelImage? output;
            if (s.IsComparing)
            {
                var (a, b) = s.Pair!.Value;
                var sideBySide = s.Style == CompareStyle.SideBySide;
                var pa = await PixelsAsync(a, _primary);
                var pb = await PixelsAsync(b, sideBySide ? _secondary : _primary);
                if (pa is null || pb is null) return;
                var fraction = _primary.RevealFraction;
                var background = StageArgb;
                var divider = Ui.Argb("InspectText1Color", 0.82);
                output = await Task.Run(() => sideBySide
                    ? ImageCodec.SideBySide(pa, pb, background)
                    : ImageCodec.Slider(pa, pb, fraction, background, divider));
            }
            else
            {
                output = await ActivePixelsAsync();
            }
            if (output is null) return;
            var path = Path.Combine(InspectImages.QuickSaveFolder, Guid.NewGuid().ToString("N")[..8].ToUpperInvariant() + ".png");
            var ok = await Task.Run(() => Write(path, ImageCodec.Encode(output, ImageExportFormat.Png)));
            _toast.Show(ok ? L.T("Saved ✓") + "\n" + path : L.T("Export failed"), error: !ok);
        }
        catch (OperationCanceledException) { }
    }

    private async Task ExportAsync(ImageExportFormat format)
    {
        if (_session is not { } s) return;
        var index = s.ActiveIndex;
        var source = s[index];
        var dialog = new SaveFileDialog
        {
            FileName = $"{Path.GetFileNameWithoutExtension(source.FileName)}.{format.Extension()}",
            Filter = $"{format.DisplayName()} (*.{format.Extension()})|*.{format.Extension()}",
            DefaultExt = format.Extension(),
            AddExtension = true,
            OverwritePrompt = true,
            InitialDirectory = source.IsLocal ? Path.GetDirectoryName(source.Location) : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
        };
        if (dialog.ShowDialog(this) != true) return;
        var path = dialog.FileName;
        try
        {
            var pixels = await ActivePixelsAsync();
            if (pixels is null) return;
            var ok = await Task.Run(() => Write(path, ImageCodec.Encode(pixels, format)));
            if (!ok)
            {
                _toast.Show(L.T("Export failed"), error: true);
                return;
            }
            if (format != ImageExportFormat.Ico && _session == s)
            {
                var result = new MediaInfo(path, true, MediaKind.Image);
                Forget(InspectSession.Identity(result));
                s.InsertDerived(result, Math.Max(0, s.IndexOf(source)), compare: false);
                Render();
                LoadActive();
            }
            _toast.Show(L.T("Exported ✓") + "\n" + path);
        }
        catch (OperationCanceledException) { }
    }

    private static bool Write(string path, byte[]? bytes)
    {
        if (bytes is null) return false;
        try
        {
            InspectImages.WriteFile(path, bytes);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Warning($"Inspect: write failed for '{Log.Redact(path)}': {ex.Message}");
            return false;
        }
    }

    // ───────────────────────────── Compress / resize ─────────────────────────────

    private void ShowCompress()
    {
        if (_session is not { } s || ActiveBitmap() is not { } bitmap) return;
        var index = s.ActiveIndex;
        var source = s[index];
        if (ImageExportFormats.ForSource(source.Location) is not { } format)
        {
            _toast.Show(L.F("Glance can’t write %@ files. Use Save as… to convert it first.", source.FormatName), error: true);
            return;
        }
        var bytes = source.FileSize ?? ImageTools.FallbackByteCount(source.PixelWidth ?? bitmap.PixelWidth, source.PixelHeight ?? bitmap.PixelHeight);
        OpenDialog(InspectDialog.Compress(bytes, (quality, target, keep) =>
        {
            CloseDialog();
            _ = ProcessAsync(source, format, ".compressed", L.T("Compressed ✓"), L.T("Compression failed"),
                pixels => ImageCodec.Compress(pixels, format, quality, target, allowResizing: !keep));
        }, CloseDialog));
    }

    private void ShowResize()
    {
        if (_session is not { } s || ActiveBitmap() is not { } bitmap) return;
        var source = s[s.ActiveIndex];
        if (ImageExportFormats.ForSource(source.Location) is not { } format)
        {
            _toast.Show(L.F("Glance can’t write %@ files. Use Save as… to convert it first.", source.FormatName), error: true);
            return;
        }
        var width = source.PixelWidth ?? bitmap.PixelWidth;
        var height = source.PixelHeight ?? bitmap.PixelHeight;
        var bytes = source.FileSize ?? ImageTools.FallbackByteCount(width, height);
        OpenDialog(InspectDialog.Resize(width, height, bytes, scale =>
        {
            CloseDialog();
            var percent = (int)Math.Round(scale * 100);
            _ = ProcessAsync(source, format, $".resized-{percent}", L.T("Resized ✓"), L.T("Resize failed"), pixels =>
                ImageTools.ResizedDimensions(pixels.Width, pixels.Height, scale) is { } d
                    ? ImageCodec.Encode(ImageCodec.Resize(pixels, d.Width, d.Height), format, 0.92)
                    : null);
        }, CloseDialog));
    }

    /// <summary>
    /// Writes a processed copy of <paramref name="source"/> (original pixels, no view rotation)
    /// next to it — or in Downloads for remote images — and compares it side by side with the source.
    /// </summary>
    private async Task ProcessAsync(MediaInfo source, ImageExportFormat format, string suffix, string success, string failure, Func<PixelImage, byte[]?> encode)
    {
        if (_session is not { } s) return;
        try
        {
            var index = s.IndexOf(source);
            if (index < 0) return;
            var pixels = await InspectImages.OriginalPixelsAsync(_loader, source, Bitmap(index), _cts.Token);
            if (pixels is null)
            {
                _toast.Show(failure, error: true);
                return;
            }
            var extension = source.Extension.Length > 0 ? source.Extension.ToLowerInvariant() : format.Extension();
            var baseName = Path.GetFileNameWithoutExtension(source.FileName) + suffix;
            var folder = InspectImages.OutputFolder(source);
            var path = ImageTools.UniquePath(folder, baseName, extension);
            var ok = await Task.Run(() => Write(path, encode(pixels)));
            if (!ok)
            {
                _toast.Show(failure, error: true);
                return;
            }
            if (_session != s) return;
            var result = new MediaInfo(path, true, MediaKind.Image);
            Forget(InspectSession.Identity(result));
            s.InsertDerived(result, Math.Max(0, s.IndexOf(source)));
            _fittedFor = null;
            Render();
            LoadActive();
            _toast.Show(success + "\n" + path);
        }
        catch (OperationCanceledException) { }
    }

    // ───────────────────────────── Dialogs ─────────────────────────────

    private void OpenDialog(InspectDialog dialog)
    {
        CloseDialog();
        ShowChrome();
        _dialog = dialog;
        _overlayHost.Children.Add(dialog);
    }

    private void CloseDialog()
    {
        if (_dialog is null) return;
        _overlayHost.Children.Remove(_dialog);
        _dialog = null;
        Focus();
    }

    private void ShowUrlInput() => OpenDialog(InspectDialog.TextPrompt(L.T("Open image URL"), L.T("Paste an image URL or local path"), L.T("Open"), multiline: false,
        text =>
        {
            if (ImageInfoFromText(text) is not { } info)
            {
                _toast.Show(L.T("No image URL found"), error: true);
                return false;
            }
            CloseDialog();
            AppendOrFocus(info);
            return true;
        }, CloseDialog));

    private void ShowBase64Input() => OpenDialog(InspectDialog.TextPrompt(L.T("Base64 to Image"), L.T("Paste a Base64 image string below"), L.T("Convert"), multiline: true,
        text =>
        {
            CloseDialog();
            _ = DecodeBase64Async(text);
            return true;
        }, CloseDialog));

    private async Task DecodeBase64Async(string text)
    {
        var image = await Task.Run(() => ImageTools.DecodeBase64Payload(text) is { } bytes ? ImageCodec.Decode(bytes) : null);
        if (image is null)
        {
            _toast.Show(L.T("Invalid Base64 image"), error: true);
            return;
        }
        if (await InspectImages.SaveTempPngAsync(image, "base64") is { } path) AppendOrFocus(new MediaInfo(path, true, MediaKind.Image));
        else _toast.Show(L.T("Couldn’t save the image."), error: true);
    }

    private void AddImages()
    {
        var dialog = new OpenFileDialog
        {
            Multiselect = true,
            Title = L.T("Add Images"),
            Filter = L.T("Images") + "|" + string.Join(';', FileKinds.Image.Select(e => "*." + e)) + "|" + L.T("All files") + "|*.*",
        };
        if (dialog.ShowDialog(this) != true) return;
        foreach (var path in dialog.FileNames) HandleDropped(MediaInfo.From(_detector.LocalKind(path)), dropSlot: 1);
    }

    private void CloseOverlays()
    {
        CloseDialog();
        EndCapture();
        _shortcuts.Visibility = Visibility.Collapsed;
        if (_menu is { IsOpen: true }) _menu.IsOpen = false;
    }

    // ───────────────────────────── Capture ─────────────────────────────

    /// <summary>Freezes what the panes show (zoom, pan, rotation, compare layout) and opens the capture editor over the window.</summary>
    private async Task BeginCaptureAsync()
    {
        if (_capture is not null || _session is not { } s) return;
        var sideBySide = s.IsComparing && s.Style == CompareStyle.SideBySide;
        var slider = s.IsComparing && !sideBySide;
        var a = Pane(_primary, _primary.Image);
        var b = sideBySide ? Pane(_secondary, _secondary.Image) : slider ? Pane(_primary, _primary.Overlay) : null;
        if (a is null || (s.IsComparing && b is null)) return;
        var fraction = _primary.RevealFraction;
        var background = StageArgb;
        var divider = Ui.Argb("InspectText1Color", 0.82);

        PixelImage frozen;
        try
        {
            frozen = await Task.Run(() =>
            {
                var (cropA, shownA) = VisibleCrop(a);
                if (b is null) return cropA;
                var (cropB, _) = VisibleCrop(b);
                return sideBySide
                    ? ImageCodec.SideBySideCapture(cropA, cropB, background)
                    : ImageCodec.SliderCapture(cropA, shownA, a.PaneSize.Width, cropB, fraction, background, divider);
            });
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException or OutOfMemoryException)
        {
            Log.Warning($"Inspect: capture freeze failed: {ex.Message}");
            _toast.Show(L.T("Couldn’t start a capture."), error: true);
            return;
        }
        if (_session != s) return;

        Rect? display = DisplayRectInRoot(_primary);
        if (sideBySide && DisplayRectInRoot(_secondary) is { } right && display is { } left) display = Rect.Union(left, right);
        var frozenBitmap = InspectImages.ToBitmap(frozen);
        var sourceName = s[s.ActiveIndex].FileName;
        _capture = new CaptureEditor(frozenBitmap, display, EndCapture, crop => _ = FinishCaptureAsync(frozen, crop, sourceName));
        Grid.SetRowSpan(_capture, 3);
        _overlayHost.Children.Add(_capture);
        ShowChrome();
    }

    private sealed record CapturePane(BitmapSource Image, int Quarters, bool FlipX, bool FlipY, SizeD PaneSize, ViewportState State);

    private static CapturePane? Pane(ImageViewport viewport, BitmapSource? image) =>
        image is null || viewport.ActualWidth <= 0 ? null
            : new CapturePane(image, viewport.Quarters, viewport.FlipX, viewport.FlipY, viewport.Pane, viewport.State);

    /// <summary>The oriented image cropped to what the pane shows, plus where it sits in the pane.</summary>
    private static (PixelImage Crop, RectD Displayed) VisibleCrop(CapturePane pane)
    {
        var oriented = ImageCodec.Orient(InspectImages.ToPixels(pane.Image), pane.Quarters, pane.FlipX, pane.FlipY);
        var visible = ViewportMath.VisibleRect(oriented.Size, pane.PaneSize, pane.State.Zoom, new PointD(pane.State.CenterX, pane.State.CenterY));
        var displayed = ViewportMath.DisplayedRect(oriented.Size, pane.PaneSize, pane.State.Zoom);
        return (ImageCodec.LimitSide(ImageCodec.Crop(oriented, visible), ImageCodec.MaxCompositeSide), displayed);
    }

    private Rect? DisplayRectInRoot(ImageViewport viewport)
    {
        if (viewport.Visibility != Visibility.Visible || viewport.DisplayedImageRect() is not { } r) return null;
        return new Rect(viewport.TranslatePoint(r.TopLeft, _root), r.Size);
    }

    private void EndCapture()
    {
        if (_capture is null) return;
        _overlayHost.Children.Remove(_capture);
        _capture = null;
        Focus();
    }

    private async Task FinishCaptureAsync(PixelImage frozen, RectD crop, string sourceName)
    {
        EndCapture();
        var path = await Task.Run(() =>
        {
            var cropped = ImageCodec.Crop(frozen, crop);
            var target = ImageTools.UniquePath(InspectImages.CaptureFolder, ImageTools.CaptureStem(sourceName, cropped.Width, cropped.Height), "png");
            return Write(target, ImageCodec.Encode(cropped, ImageExportFormat.Png)) ? target : null;
        });
        if (path is null)
        {
            _toast.Show(L.T("Could not save capture"), error: true);
            return;
        }
        Log.Info($"Inspect: capture saved to '{Log.Redact(path)}'");
        _host.OpenCapture(path, this);
    }

    // ───────────────────────────── Keyboard ─────────────────────────────

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_capture is not null)
        {
            if (e.Key == Key.Escape || (e.Key == Key.X && Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift))) { EndCapture(); e.Handled = true; }
            else if (e.Key == Key.Enter) { _capture.Commit(); e.Handled = true; }
            return;
        }
        if (_dialog is not null) return; // the dialog handles Esc / Enter itself
        if (_shortcuts.Visibility == Visibility.Visible)
        {
            _shortcuts.Visibility = Visibility.Collapsed;
            if (e.Key == Key.Escape) { e.Handled = true; return; }
        }
        if (e.OriginalSource is TextBox) return;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers;
        var ctrl = mods.HasFlag(ModifierKeys.Control);
        var shift = mods.HasFlag(ModifierKeys.Shift);
        var alt = mods.HasFlag(ModifierKeys.Alt);
        var hasImage = ActiveBitmap() is not null;
        var handled = true;

        if (ctrl && shift && key == Key.X) _ = BeginCaptureAsync();
        else if (ctrl && key == Key.W) Close();
        else if (ctrl && key == Key.I) ToggleInfo();
        else if (ctrl && key == Key.L && hasImage) Rotate(-1);
        else if (ctrl && key == Key.R && hasImage) Rotate(1);
        else if (ctrl && key == Key.C && hasImage) _ = CopyImageAsync();
        else if (ctrl && key == Key.S && (hasImage || _session?.IsComparing == true)) _ = QuickSaveAsync();
        else if (ctrl && key == Key.V) _ = PasteAsync();
        else if (!alt && key is Key.D0 or Key.NumPad0 && !shift) FitAll();
        else if (!alt && key is Key.D1 or Key.NumPad1 && !shift) ActualSizeAll();
        else if (!alt && key is Key.OemPlus or Key.Add) ZoomAll(1.25);
        else if (!alt && key is Key.OemMinus or Key.Subtract) ZoomAll(0.8);
        else if ((shift && key == Key.OemQuestion) || key == Key.F1) ShowShortcuts();
        else if (!ctrl && key == Key.Left) Navigate(-1);
        else if (!ctrl && key == Key.Right) Navigate(1);
        else if (key == Key.Escape) HandleEscape();
        else handled = false;
        e.Handled = handled;
    }

    /// <summary>Esc steps back one level: leave Compare, then close the info panel, then the window.</summary>
    private void HandleEscape()
    {
        if (_session is { IsComparing: true })
        {
            ExitCompare();
            return;
        }
        if (_infoVisible)
        {
            CloseInfo();
            return;
        }
        if (_ocrWindow is { IsVisible: true })
        {
            _ocrWindow.Dismiss();
            return;
        }
        Close();
    }

    // ───────────────────────────── Paste, drop, URL input ─────────────────────────────

    /// <summary>
    /// A detected image in text (path or URL). Image-specific entry points also try an
    /// extensionless web URL as an image, like macOS <c>imageInfo(from:allowExtensionlessRemoteURL:)</c>.
    /// </summary>
    private MediaInfo? ImageInfoFromText(string text)
    {
        foreach (var path in _detector.DetectAll(text))
        {
            if (MediaInfo.From(path) is not { } info) continue;
            if (info.Kind == MediaKind.Image) return info;
            if (info.Kind == MediaKind.WebPage && !info.IsLocal) return new MediaInfo(info.Location, false, MediaKind.Image);
        }
        return null;
    }

    private void AppendOrFocus(MediaInfo info)
    {
        if (_session is not { } s)
        {
            Show([info], 0);
            return;
        }
        s.AppendOrFocus(info);
        _fittedFor = null;
        Render();
        LoadActive();
    }

    /// <summary>Ctrl+V: an image path / URL in the clipboard text, else image data (screenshot, "Copy image").</summary>
    private async Task PasteAsync()
    {
        var text = InspectImages.ClipboardText();
        if (text is not null && ImageInfoFromText(text) is { } info)
        {
            AppendOrFocus(info);
            return;
        }
        var image = InspectImages.ClipboardImage();
        if (image is null)
        {
            _toast.Show(L.T("No image on the clipboard"), error: true);
            return;
        }
        if (await InspectImages.SaveTempPngAsync(image, "pasted") is { } path) AppendOrFocus(new MediaInfo(path, true, MediaKind.Image));
        else _toast.Show(L.T("Couldn’t save the image."), error: true);
    }

    private static bool HasDroppable(IDataObject data) =>
        data.GetDataPresent(DataFormats.FileDrop) || data.GetDataPresent(DataFormats.UnicodeText) || data.GetDataPresent(DataFormats.Text);

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = _capture is null && _dialog is null && HasDroppable(e.Data) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (_capture is not null || _dialog is not null) return;
        // Side by side: the drop replaces the pane it landed on.
        var slot = _secondary.Visibility == Visibility.Visible && IsOver(_secondary, e) ? 1 : IsOver(_primary, e) ? 0 : 1;
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            foreach (var file in files) HandleDropped(MediaInfo.From(_detector.LocalKind(file)), slot);
            return;
        }
        var text = e.Data.GetData(DataFormats.UnicodeText) as string ?? e.Data.GetData(DataFormats.Text) as string;
        if (string.IsNullOrWhiteSpace(text)) return;
        var detected = _detector.DetectAll(text).Select(MediaInfo.From).FirstOrDefault(i => i is not null);
        if (detected is null)
        {
            _toast.Show(L.T("Nothing Glance can open was dropped."), error: true);
            return;
        }
        HandleDropped(detected, slot);
    }

    private static bool IsOver(FrameworkElement element, DragEventArgs e)
    {
        var p = e.GetPosition(element);
        return p.X >= 0 && p.Y >= 0 && p.X <= element.ActualWidth && p.Y <= element.ActualHeight;
    }

    /// <summary>Images join the session; documents, videos and pages go to their viewers; folders are revealed.</summary>
    private void HandleDropped(MediaInfo? info, int dropSlot)
    {
        if (info is null) return;
        switch (info.Kind)
        {
            case MediaKind.Image:
                if (_session is not { } s)
                {
                    Show([info], 0);
                    return;
                }
                s.AddDropped(info, dropSlot);
                _fittedFor = null;
                Render();
                LoadActive();
                break;
            case MediaKind.Video or MediaKind.Markdown or MediaKind.Text or MediaKind.Pdf or MediaKind.WebPage:
                _host.OpenOther(info);
                break;
            default:
                if (info.IsLocal) ShellActions.RevealInExplorer(info.Location);
                else ShellActions.Open(info.Location);
                break;
        }
    }
}
