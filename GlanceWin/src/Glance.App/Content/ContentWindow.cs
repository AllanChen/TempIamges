using System.ComponentModel;
using System.Net.Http;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Media;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Content;
using Glance.Core.Detection;
using Glance.Core.Git;
using Glance.Core.Logging;
using Glance.Platform;
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Search;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Glance.App.Content;

/// <summary>
/// The content viewer (port of macOS <c>ContentPanel</c>): one reusable window for Markdown
/// (rendered), plain text / code (editable, Ctrl+S), PDF and web pages.
/// <list type="bullet">
/// <item>Toolbar: file name over "folder · Modified date" (or an address bar for web pages),
/// then Find, Reveal in File Explorer, Git Diff and Save, then the window buttons.</item>
/// <item>WebView2 shows web pages, PDF and Markdown; AvalonEdit edits text. WebView2 is created on
/// first use; without the runtime Markdown falls back to the editor.</item>
/// <item>Esc closes (after closing an open find bar); unsaved edits are confirmed first.
/// Closing hides the window so the next document opens instantly.</item>
/// </list>
/// Unlike the floating panels this is a normal, activating window: it takes keyboard input.
/// </summary>
internal sealed class ContentWindow : Window
{
    private enum ViewKind { None, Web, Markdown, Pdf, Text }

    private const double ToolbarHeight = 52;
    private const double ResizeBorder = 5;
    private const int MaxHighlightedChars = 256 * 1024;
    private const long MaxServedFileBytes = 50L * 1024 * 1024;
    private const string ContentHost = "glance-content.local";
    private const string DocumentPath = "/__glance_document__.html";
    private const string WebView2Download = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";
    private static readonly Size WebSize = new(970, 990);
    private static readonly Size DocumentSize = new(720, 960);

    private readonly string _webDataFolder;
    private readonly GitDiffService _git = new(new GitRunner());
    private readonly string _home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    // Toolbar
    private readonly Grid _root;
    private readonly Grid _identity;
    private readonly TextBlock _fileName;
    private readonly TextBlock _subtitle;
    private readonly TextBox _address;
    private readonly Button _findButton;
    private readonly Button _revealButton;
    private readonly Button _diffButton;
    private readonly Button _saveButton;
    private readonly TextBlock _maximizeGlyph;
    private readonly LoadingSweep _loading;

    // Body
    private readonly Grid _content;
    private readonly TextEditor _editor;
    private readonly SearchPanel _search;
    private readonly Border _findBar;
    private readonly TextBox _findField;
    private readonly TextBlock _findCount;
    private readonly Border _failure;
    private readonly TextBlock _failureText;
    private readonly Button _failurePrimary;
    private readonly Button _failureSecondary;
    private WebView2? _web;
    private CoreWebView2Environment? _webEnvironment;
    private Task<bool>? _webReady;

    // State
    private MediaInfo? _info;
    private ViewKind _kind;
    private DecodedText? _decoded;
    private bool _dirty;
    private bool _suppressDirty;
    private long _editCount;
    private ulong _loadId;
    private ulong _findRequest;
    private int _findIndex = -1;
    private int _findTotal;
    private double _textZoom = 1;
    private bool _navigationArmed;
    private bool _quitting;
    private GitContext? _gitContext;
    private string? _documentHtml;
    private string? _documentFolder;
    private Action? _failurePrimaryAction;
    private Action? _failureSecondaryAction;
    private DispatcherTimer? _savedTimer;

    public ContentWindow(string webDataFolder)
    {
        _webDataFolder = webDataFolder;
        Title = "Glance";
        Width = DocumentSize.Width;
        Height = DocumentSize.Height;
        MinWidth = 560;
        MinHeight = 320;
        Background = Ui.Brush("SurfaceBrush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ResizeMode = ResizeMode.CanResize;
        // Own title bar so the toolbar sits in the caption like the macOS transparent titlebar.
        // A 1px bottom glass frame keeps the DWM shadow (and rounded corners on Windows 11).
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = ToolbarHeight - ResizeBorder,
            ResizeBorderThickness = new Thickness(ResizeBorder),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });

        // ── Toolbar: identity / address (left), actions, window buttons (right) ──
        _fileName = Ui.Text("", "HeadlineText", TextTrimming.CharacterEllipsis);
        _fileName.VerticalAlignment = VerticalAlignment.Top;
        _fileName.Margin = new Thickness(0, 11, 0, 0);
        _fileName.Height = 18;
        _subtitle = Ui.Text("", "CaptionText", TextTrimming.CharacterEllipsis);
        _subtitle.VerticalAlignment = VerticalAlignment.Top;
        _subtitle.Margin = new Thickness(0, 28, 0, 0);
        _subtitle.Height = 15;
        _identity = new Grid { Children = { _fileName, _subtitle } };

        _address = new TextBox { Style = Ui.Style("FieldBox"), Height = 26, VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
        _address.KeyDown += OnAddressKeyDown;
        WindowChrome.SetIsHitTestVisibleInChrome(_address, true);

        _findButton = ToolbarIcon(Ui.GlyphSearch, L.T("Find in page"), OnFindClicked);
        _revealButton = ToolbarIcon(Ui.GlyphFolder, L.T("Reveal in File Explorer"), () =>
        {
            if (_info is { IsLocal: true } info) ShellActions.RevealInExplorer(info.Location);
        });
        _diffButton = ToolbarText(L.T("Diff"), OnDiffClicked);
        _diffButton.ToolTip = L.T("Compare with Git");
        _saveButton = ToolbarText(L.T("Save"), () => _ = SaveAsync());

        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 16, 0) };
        foreach (var button in new[] { _findButton, _revealButton, _diffButton, _saveButton })
        {
            button.Margin = new Thickness(8, 0, 0, 0);
            actions.Children.Add(button);
        }

        _maximizeGlyph = CaptionGlyph(Ui.GlyphMaximize);
        var captions = new StackPanel { Orientation = Orientation.Horizontal };
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphMinimize), L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(_maximizeGlyph, L.T("Maximize"), "CaptionButton", ToggleMaximize));
        captions.Children.Add(CaptionButton(CaptionGlyph(Ui.GlyphChromeClose), L.T("Close"), "CaptionCloseButton", () => _ = RequestCloseAsync()));

        var toolbarGrid = new Grid();
        toolbarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        toolbarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        toolbarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new Grid { Margin = new Thickness(18, 0, 0, 0), Children = { _identity, _address } };
        toolbarGrid.Children.Add(left);
        Grid.SetColumn(actions, 1);
        toolbarGrid.Children.Add(actions);
        Grid.SetColumn(captions, 2);
        toolbarGrid.Children.Add(captions);

        _loading = new LoadingSweep { VerticalAlignment = VerticalAlignment.Bottom, Visibility = Visibility.Collapsed };
        var toolbar = new Border
        {
            Height = ToolbarHeight,
            Background = Ui.Brush("ChromeBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = new Grid { Children = { toolbarGrid, _loading } },
        };

        // ── Web find bar (its own row: nothing can overlay the WebView2 window) ──
        _findField = new TextBox { Style = Ui.Style("FieldBox"), Width = 240, Height = 24, Margin = new Thickness(12, 0, 0, 0) };
        _findField.TextChanged += (_, _) => _ = RunFindAsync();
        _findField.KeyDown += OnFindFieldKeyDown;
        _findCount = Ui.Text("", "CaptionText");
        _findCount.Margin = new Thickness(10, 0, 0, 0);
        _findCount.MinWidth = 70;
        var findLeft = new StackPanel { Orientation = Orientation.Horizontal, Children = { _findField, _findCount } };
        var findRight = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 10, 0) };
        findRight.Children.Add(FindBarButton(Ui.Glyph(Ui.GlyphUp, 11, "TextSecondaryBrush"), 32, L.T("Previous"), () => _ = StepFindAsync(false)));
        findRight.Children.Add(FindBarButton(Ui.Glyph(Ui.GlyphDown, 11, "TextSecondaryBrush"), 32, L.T("Next"), () => _ = StepFindAsync(true)));
        findRight.Children.Add(FindBarButton(L.T("Done"), 56, null, HideFindBar));
        _findBar = new Border
        {
            Height = 36,
            Background = Ui.Brush("ChromeBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Visibility = Visibility.Collapsed,
            Child = new Grid { Children = { findLeft, findRight } },
        };

        // ── Body ──
        _editor = new TextEditor
        {
            FontFamily = Ui.CodeFont,
            FontSize = Ui.Number("CodeSize"),
            Background = Ui.Brush("SurfaceBrush"),
            Foreground = Ui.Brush("TextPrimaryBrush"),
            LineNumbersForeground = Ui.Brush("TextTertiaryBrush"),
            ShowLineNumbers = true,
            WordWrap = true,
            Padding = new Thickness(8, 8, 8, 8),
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Visibility = Visibility.Collapsed,
        };
        _editor.Options.EnableHyperlinks = false;
        _editor.Options.EnableEmailHyperlinks = false;
        _editor.TextArea.SelectionBrush = Ui.Brush("AccentSubtleFillBrush");
        _editor.TextArea.SelectionBorder = null;
        _editor.TextArea.SelectionForeground = null;
        _editor.TextChanged += (_, _) =>
        {
            _editCount++;
            if (!_suppressDirty) SetDirty(true);
        };
        _editor.PreviewMouseWheel += (_, e) =>
        {
            if (Keyboard.Modifiers != ModifierKeys.Control) return;
            ZoomText(e.Delta > 0 ? 1.1 : 1 / 1.1);
            e.Handled = true;
        };
        _search = SearchPanel.Install(_editor);

        _failureText = Ui.Text("", "BodyText", TextTrimming.None);
        _failureText.TextWrapping = TextWrapping.Wrap;
        _failureText.TextAlignment = TextAlignment.Center;
        _failureText.MaxWidth = 380;
        _failureText.Margin = new Thickness(0, 12, 0, 16);
        _failurePrimary = new Button { Style = Ui.Style("PrimaryButton"), Margin = new Thickness(4, 0, 4, 0) };
        _failurePrimary.Click += (_, _) => _failurePrimaryAction?.Invoke();
        _failureSecondary = new Button { Style = Ui.Style("SecondaryButton"), Margin = new Thickness(4, 0, 4, 0) };
        _failureSecondary.Click += (_, _) => _failureSecondaryAction?.Invoke();
        _failure = new Border
        {
            Background = Ui.Brush("SurfaceBrush"),
            Visibility = Visibility.Collapsed,
            Child = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Children =
                {
                    Ui.Glyph(Ui.GlyphWarning, 28, "TextTertiaryBrush"),
                    _failureText,
                    new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Children = { _failureSecondary, _failurePrimary } },
                },
            },
        };

        _content = new Grid { Children = { _editor, _failure } };
        var body = new DockPanel();
        DockPanel.SetDock(_findBar, Dock.Top);
        body.Children.Add(_findBar);
        body.Children.Add(_content);

        _root = new Grid();
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _root.Children.Add(toolbar);
        Grid.SetRow(body, 1);
        _root.Children.Add(body);
        Content = _root;

        PreviewKeyDown += OnPreviewKeyDown;
        StateChanged += (_, _) => OnStateChanged();
    }

    // ───────────────────────────── Public API ─────────────────────────────

    public static bool CanShow(MediaInfo info) => info.Kind is MediaKind.Markdown or MediaKind.Text or MediaKind.Pdf or MediaKind.WebPage;

    /// <summary>Loads <paramref name="info"/> and brings the window to the front.</summary>
    public async void Open(MediaInfo info)
    {
        try
        {
            await OpenAsync(info);
        }
        catch (Exception ex)
        {
            Log.Error($"ContentWindow: opening '{Log.Redact(info.Location)}' failed", ex);
            ShowLoading(false);
            ShowFailure(ex.Message, L.T("Open with Default App"), () => ShellActions.Open(info.Location));
        }
    }

    /// <summary>Confirms unsaved edits before the app quits. False = the user cancelled.</summary>
    public async Task<bool> PrepareForQuitAsync()
    {
        if (!await ConfirmDiscardAsync()) return false;
        _quitting = true;
        return true;
    }

    public void DisposeViewer()
    {
        _quitting = true;
        _web?.Dispose();
        _web = null;
    }

    // ───────────────────────────── Loading ─────────────────────────────

    private async Task OpenAsync(MediaInfo info)
    {
        if (!await ConfirmDiscardAsync())
        {
            Activate();
            return;
        }

        var id = ++_loadId;
        _info = info;
        _kind = info.Kind switch
        {
            MediaKind.Markdown => ViewKind.Markdown,
            MediaKind.Pdf => ViewKind.Pdf,
            MediaKind.WebPage => ViewKind.Web,
            _ => ViewKind.Text,
        };
        _decoded = null;
        _gitContext = null;
        _documentHtml = null;
        _documentFolder = null;
        _textZoom = 1;
        _editor.FontSize = Ui.Number("CodeSize");
        HideFindBar();
        if (!_search.IsClosed) _search.Close();
        HideFailure();
        SetDirty(false);
        ApplyIdentity(info, id);
        PlaceAndShow(_kind == ViewKind.Web ? WebSize : DocumentSize);
        ShowLoading(true);
        Log.Info($"ContentWindow: {_kind} '{Log.Redact(info.Location)}'");

        switch (_kind)
        {
            case ViewKind.Text:
                await LoadTextAsync(info, id);
                break;
            case ViewKind.Markdown:
                await LoadMarkdownAsync(info, id);
                break;
            default:
                await LoadWebAsync(info, id);
                break;
        }

        if (info.IsLocal && _kind is ViewKind.Text or ViewKind.Markdown) _ = LookUpGitAsync(info.Location, id);
    }

    private async Task LoadTextAsync(MediaInfo info, ulong id)
    {
        ShowEditor();
        var (decoded, error) = await FetchTextAsync(info);
        if (id != _loadId) return;
        ShowLoading(false);
        if (decoded is null)
        {
            ShowFailure(error ?? L.T("Couldn't open this file."), L.T("Open with Default App"), () => ShellActions.Open(info.Location));
            return;
        }
        ShowTextInEditor(info, decoded);
    }

    private async Task LoadMarkdownAsync(MediaInfo info, ulong id)
    {
        ShowWeb();
        var fetch = FetchTextAsync(info);
        var webReady = await EnsureWebAsync();
        var (decoded, error) = await fetch;
        if (id != _loadId) return;
        if (decoded is null)
        {
            ShowLoading(false);
            ShowFailure(error ?? L.T("Couldn't open this file."), L.T("Open with Default App"), () => ShellActions.Open(info.Location));
            return;
        }
        if (!webReady)
        {
            // No WebView2: still useful as editable source.
            ShowLoading(false);
            ShowEditor();
            ShowTextInEditor(info, decoded);
            return;
        }

        var baseHref = info.IsLocal ? null : new Uri(new Uri(info.Location), ".").AbsoluteUri;
        var css = ContentHtml.MarkdownCss();
        var html = await Task.Run(() => ContentHtml.MarkdownPage(decoded.Text, info.FileName, baseHref, css));
        if (id != _loadId) return;
        _documentHtml = html;
        _documentFolder = info.IsLocal ? Path.GetDirectoryName(info.Location) : null;
        PrepareWeb(acceleratorKeys: false);
        Navigate($"https://{ContentHost}{DocumentPath}?v={id}");
    }

    private async Task LoadWebAsync(MediaInfo info, ulong id)
    {
        ShowWeb();
        var ready = await EnsureWebAsync();
        if (id != _loadId) return;
        if (!ready)
        {
            ShowLoading(false);
            ShowWebViewMissing(info);
            return;
        }
        // PDF: keep the built-in viewer's own shortcuts (Ctrl+F search, Ctrl+P print).
        PrepareWeb(acceleratorKeys: _kind == ViewKind.Pdf);
        Navigate(info.IsLocal ? new Uri(info.Location).AbsoluteUri : info.Location);
    }

    private void ShowTextInEditor(MediaInfo info, DecodedText decoded)
    {
        _decoded = decoded;
        var definition = decoded.Text.Length > MaxHighlightedChars ? null
            : CodeLanguage.AvalonEditDefinition(CodeLanguage.ForExtension(info.Extension));
        _suppressDirty = true;
        _editor.Document = new TextDocument(decoded.Text);
        _editor.SyntaxHighlighting = definition is null ? null : HighlightingManager.Instance.GetDefinition(definition);
        _suppressDirty = false;
        SetDirty(false);
        _editor.ScrollToHome();
        _editor.TextArea.Caret.Offset = 0;
        _editor.Focus();
        _editor.TextArea.Focus();
    }

    /// <summary>Reads a local file (shared read, size cap) or downloads a remote one, then decodes it.</summary>
    private static async Task<(DecodedText? Text, string? Error)> FetchTextAsync(MediaInfo info)
    {
        try
        {
            var bytes = info.IsLocal
                ? await Task.Run(() => ReadLocal(info.Location))
                : await ImageLoader.DownloadAsync(info.Location, CancellationToken.None, TextFileCodec.MaxEditableBytes);
            var decoded = await Task.Run(() => TextFileCodec.Decode(bytes));
            return (decoded, null);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or HttpRequestException
                                       or InvalidDataException or TaskCanceledException or UriFormatException)
        {
            Log.Warning($"ContentWindow: reading '{Log.Redact(info.Location)}' failed: {ex.Message}");
            return (null, ex is InvalidDataException ? L.T("This file is too large to open.") : ex.Message);
        }
    }

    private static byte[] ReadLocal(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > TextFileCodec.MaxEditableBytes) throw new InvalidDataException("too large");
        var buffer = new byte[stream.Length];
        stream.ReadExactly(buffer);
        return buffer;
    }

    // ───────────────────────────── WebView2 ─────────────────────────────

    /// <summary>Creates WebView2 on first use; retries after a failure (the runtime may get installed meanwhile).</summary>
    private Task<bool> EnsureWebAsync()
    {
        if (_webReady is null || (_webReady.IsCompletedSuccessfully && !_webReady.Result)) _webReady = CreateWebAsync();
        return _webReady;
    }

    private async Task<bool> CreateWebAsync()
    {
        WebView2? web = null;
        try
        {
            var version = CoreWebView2Environment.GetAvailableBrowserVersionString();
            var environment = await CoreWebView2Environment.CreateAsync(null, _webDataFolder);
            var surface = Ui.Color("SurfaceColor");
            web = new WebView2
            {
                DefaultBackgroundColor = System.Drawing.Color.FromArgb(surface.A, surface.R, surface.G, surface.B),
                // Leave the window's resize border uncovered: the WebView2 child window would swallow it.
                Margin = new Thickness(ResizeBorder, 0, ResizeBorder, ResizeBorder),
            };
            _webEnvironment = environment;
            _content.Children.Insert(0, web);
            await web.EnsureCoreWebView2Async(environment);

            var core = web.CoreWebView2;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = true;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
#if !DEBUG
            core.Settings.AreDevToolsEnabled = false;
#endif
            await core.AddScriptToExecuteOnDocumentCreatedAsync(ContentHtml.FindHelperScript());
            core.AddWebResourceRequestedFilter($"https://{ContentHost}/*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += OnWebResourceRequested;
            core.NavigationStarting += OnNavigationStarting;
            core.NavigationCompleted += OnNavigationCompleted;
            core.SourceChanged += (_, _) => OnSourceChanged();
            core.NewWindowRequested += OnNewWindowRequested;
            core.DocumentTitleChanged += (_, _) =>
            {
                if (_kind == ViewKind.Web && !string.IsNullOrWhiteSpace(core.DocumentTitle)) Title = core.DocumentTitle;
            };
            _web = web;
            Log.Info($"ContentWindow: WebView2 {version} ready");
            ApplyBodyVisibility();
            return true;
        }
        catch (Exception ex)
        {
            // Runtime missing (WebView2RuntimeNotFoundException), blocked by policy, profile folder not writable…
            Log.Warning($"ContentWindow: WebView2 unavailable: {ex.GetType().Name}: {ex.Message}");
            if (web is not null)
            {
                _content.Children.Remove(web);
                web.Dispose();
            }
            return false;
        }
    }

    private void PrepareWeb(bool acceleratorKeys)
    {
        if (_web?.CoreWebView2 is not { } core) return;
        core.Settings.AreBrowserAcceleratorKeysEnabled = acceleratorKeys;
        _web.ZoomFactor = 1;
    }

    private void Navigate(string uri)
    {
        if (_web?.CoreWebView2 is not { } core) return;
        _navigationArmed = true;
        core.Navigate(uri);
    }

    private void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        var uri = e.Uri;
        if (_kind == ViewKind.Web)
        {
            if (IsAllowedWebScheme(uri))
            {
                ShowLoading(uri != "about:blank");
                return;
            }
            e.Cancel = true;
            if (uri.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase)) ShellActions.Open(uri);
            return;
        }

        if (_navigationArmed || e.IsRedirected || uri == "about:blank")
        {
            ShowLoading(uri != "about:blank");
            return;
        }

        // A link clicked inside a Markdown document or PDF: never navigate the document away.
        e.Cancel = true;
        OpenLinkFromDocument(uri);
    }

    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        _navigationArmed = false;
        ShowLoading(false);
        if (!e.IsSuccess && e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
            Log.Info($"ContentWindow: navigation failed: {e.WebErrorStatus}");
    }

    private void OnSourceChanged()
    {
        if (_kind != ViewKind.Web || _web?.CoreWebView2 is not { } core || _address.IsKeyboardFocused) return;
        if (core.Source != "about:blank") _address.Text = core.Source;
    }

    private void OnNewWindowRequested(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        // target=_blank / window.open: stay in this window for web pages, hand documents' links to the browser.
        e.Handled = true;
        if (!IsHttp(e.Uri)) return;
        if (_kind == ViewKind.Web) _web?.CoreWebView2?.Navigate(e.Uri);
        else ShellActions.Open(e.Uri);
    }

    private void OpenLinkFromDocument(string uri)
    {
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var target)) return;
        if (target.Host.Equals(ContentHost, StringComparison.OrdinalIgnoreCase))
        {
            if (_documentFolder is null || ResolveServedPath(_documentFolder, target.AbsolutePath) is not { } local) return;
            var kind = FileKinds.KindForExtension(FileKinds.ExtensionOf(local));
            var info = kind switch
            {
                MediaKind.Markdown or MediaKind.Text or MediaKind.Pdf => new MediaInfo(local, true, kind),
                _ => null,
            };
            // Other files (images, executables…) are revealed, never launched from a document link.
            if (info is null) ShellActions.RevealInExplorer(local);
            else Dispatcher.BeginInvoke(() => Open(info));
            return;
        }
        if (IsHttp(uri)) ShellActions.Open(uri);
    }

    /// <summary>
    /// Serves the rendered Markdown page and files next to the document (relative images).
    /// Only paths inside the document's folder are served.
    /// </summary>
    private async void OnWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        if (_webEnvironment is not { } environment) return;
        if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri)) return;

        if (uri.AbsolutePath == DocumentPath)
        {
            e.Response = _documentHtml is null
                ? environment.CreateWebResourceResponse(null, 404, "Not Found", "")
                : environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(_documentHtml)), 200, "OK",
                    "Content-Type: text/html; charset=utf-8");
            return;
        }

        var folder = _documentFolder;
        if (folder is null)
        {
            e.Response = environment.CreateWebResourceResponse(null, 404, "Not Found", "");
            return;
        }

        var deferral = e.GetDeferral();
        try
        {
            var bytes = await Task.Run(() =>
            {
                var path = ResolveServedPath(folder, uri.AbsolutePath);
                if (path is null || new FileInfo(path).Length > MaxServedFileBytes) return null;
                return File.ReadAllBytes(path);
            });
            e.Response = bytes is null
                ? environment.CreateWebResourceResponse(null, 404, "Not Found", "")
                : environment.CreateWebResourceResponse(new MemoryStream(bytes), 200, "OK",
                    $"Content-Type: {ContentHtml.MimeType(uri.AbsolutePath)}");
        }
        catch (Exception ex)
        {
            Log.Warning($"ContentWindow: serving document resource failed: {ex.Message}");
        }
        finally
        {
            deferral.Complete();
        }
    }

    /// <summary>Maps a virtual-host URL path to an existing file inside <paramref name="folder"/>.</summary>
    private static string? ResolveServedPath(string folder, string urlPath)
    {
        try
        {
            var relative = Uri.UnescapeDataString(urlPath).TrimStart('/').Replace('/', '\\');
            if (relative.Length == 0) return null;
            var root = Path.GetFullPath(folder);
            if (!root.EndsWith('\\')) root += "\\";
            var full = Path.GetFullPath(Path.Combine(root, relative));
            return full.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(full) ? full : null;
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException or IOException)
        {
            return null;
        }
    }

    private bool IsAllowedWebScheme(string uri) =>
        IsHttp(uri) || uri.StartsWith("about:", StringComparison.OrdinalIgnoreCase)
        || uri.StartsWith("data:", StringComparison.OrdinalIgnoreCase) || uri.StartsWith("blob:", StringComparison.OrdinalIgnoreCase)
        || (uri.StartsWith("file:", StringComparison.OrdinalIgnoreCase) && _info is { IsLocal: true });

    private static bool IsHttp(string uri) =>
        uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase);

    // ───────────────────────────── Find ─────────────────────────────

    private void OnFindClicked()
    {
        switch (_kind)
        {
            case ViewKind.Text:
                OpenTextSearch();
                break;
            case ViewKind.Web or ViewKind.Markdown:
                ShowFindBar();
                break;
        }
    }

    private void OpenTextSearch()
    {
        if (_editor.Visibility != Visibility.Visible) return;
        _search.Open();
        _search.Reactivate();
    }

    private void ShowFindBar()
    {
        if (_web is null || _web.Visibility != Visibility.Visible) return;
        _findBar.Visibility = Visibility.Visible;
        _findField.Focus();
        _findField.SelectAll();
    }

    private void HideFindBar()
    {
        if (_findBar.Visibility != Visibility.Visible) return;
        _findBar.Visibility = Visibility.Collapsed;
        _findField.Text = ""; // clears the highlights
        _web?.Focus();
    }

    private async Task RunFindAsync()
    {
        if (_web?.CoreWebView2 is not { } core) return;
        var request = ++_findRequest;
        var query = _findField.Text;
        var result = await RunScriptAsync(core, $"window.__tdfind ? window.__tdfind.highlight({ContentHtml.JsString(query)}) : 0");
        if (request != _findRequest) return;
        _findTotal = int.TryParse(result, out var total) ? total : 0;
        _findIndex = _findTotal > 0 ? 0 : -1;
        UpdateFindCount();
    }

    private async Task StepFindAsync(bool forward)
    {
        if (_web?.CoreWebView2 is not { } core || _findTotal == 0) return;
        var request = ++_findRequest;
        var result = await RunScriptAsync(core, forward ? "window.__tdfind.next()" : "window.__tdfind.prev()");
        if (request != _findRequest) return;
        if (int.TryParse(result, out var index)) _findIndex = index;
        UpdateFindCount();
    }

    /// <summary>ExecuteScriptAsync that returns "null" instead of throwing while a page is (re)loading.</summary>
    private static async Task<string> RunScriptAsync(CoreWebView2 core, string script)
    {
        try
        {
            return await core.ExecuteScriptAsync(script);
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return "null";
        }
    }

    private void UpdateFindCount() =>
        _findCount.Text = _findField.Text.Length == 0 ? ""
            : _findTotal == 0 ? L.T("0 results")
            : $"{_findIndex + 1} / {_findTotal}";

    private void OnFindFieldKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        _ = StepFindAsync(!Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
        e.Handled = true;
    }

    // ───────────────────────────── Keyboard ─────────────────────────────

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var modifiers = Keyboard.Modifiers;
        var ctrl = modifiers == ModifierKeys.Control;
        var ctrlShift = modifiers == (ModifierKeys.Control | ModifierKeys.Shift);

        if (key == Key.Escape && modifiers == ModifierKeys.None)
        {
            if (_address.IsKeyboardFocused)
            {
                _address.Text = _web?.CoreWebView2?.Source ?? _info?.Location ?? "";
                _web?.Focus();
            }
            else if (_findBar.Visibility == Visibility.Visible) HideFindBar();
            else if (!_search.IsClosed) _search.Close();
            else _ = RequestCloseAsync();
            e.Handled = true;
            return;
        }

        if (ctrl && key == Key.F && _kind != ViewKind.Pdf)
        {
            OnFindClicked();
            e.Handled = true;
        }
        else if ((ctrl || ctrlShift) && key == Key.G || key == Key.F3 && _findBar.Visibility == Visibility.Visible)
        {
            var forward = !modifiers.HasFlag(ModifierKeys.Shift);
            if (_findBar.Visibility == Visibility.Visible) _ = StepFindAsync(forward);
            else if (_kind == ViewKind.Text && forward) _search.FindNext();
            else if (_kind == ViewKind.Text) _search.FindPrevious();
            e.Handled = true;
        }
        else if (ctrl && key == Key.S)
        {
            _ = SaveAsync();
            e.Handled = true;
        }
        else if (ctrl && key == Key.W)
        {
            _ = RequestCloseAsync();
            e.Handled = true;
        }
        else if (ctrl && key is Key.OemPlus or Key.Add)
        {
            Zoom(1.1);
            e.Handled = true;
        }
        else if (ctrl && key is Key.OemMinus or Key.Subtract)
        {
            Zoom(1 / 1.1);
            e.Handled = true;
        }
        else if (ctrl && key is Key.D0 or Key.NumPad0)
        {
            Zoom(0);
            e.Handled = true;
        }
    }

    private void OnAddressKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        var text = _address.Text.Trim();
        if (text.Length == 0) return;
        var url = IsHttp(text) ? text : "https://" + text;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) return;
        _web?.CoreWebView2?.Navigate(uri.AbsoluteUri);
        _web?.Focus();
    }

    /// <summary>factor 0 resets. Text scales the editor font; web content uses the WebView2 zoom.</summary>
    private void Zoom(double factor)
    {
        if (_kind == ViewKind.Text || _editor.Visibility == Visibility.Visible)
        {
            ZoomText(factor);
        }
        else if (_web is not null)
        {
            _web.ZoomFactor = factor == 0 ? 1 : Math.Clamp(_web.ZoomFactor * factor, 0.25, 5);
        }
    }

    private void ZoomText(double factor)
    {
        _textZoom = factor == 0 ? 1 : Math.Clamp(_textZoom * factor, 0.5, 5);
        _editor.FontSize = Ui.Number("CodeSize") * _textZoom;
    }

    // ───────────────────────────── Save / close ─────────────────────────────

    private bool CanSave => _kind != ViewKind.Pdf && _kind != ViewKind.Web && _decoded is not null
                            && _editor.Visibility == Visibility.Visible && _info is { IsLocal: true };

    private void SetDirty(bool dirty)
    {
        _dirty = dirty;
        _saveButton.IsEnabled = dirty && CanSave;
    }

    /// <summary>Writes the buffer back in its original encoding. Returns false if not saved.</summary>
    private async Task<bool> SaveAsync()
    {
        if (!CanSave || _info is not { } info || _decoded is not { } decoded) return false;
        if (!_dirty) return true;

        var id = _loadId;
        var editsAtStart = _editCount;
        var text = _editor.Text;
        var encoding = decoded.Encoding;
        byte[] bytes;
        try
        {
            bytes = await Task.Run(() => TextFileCodec.Encode(text, encoding));
        }
        catch (EncoderFallbackException)
        {
            var answer = MessageBox.Show(this,
                L.F("Some characters can't be saved as %@. Save the file as UTF-8 instead?", TextFileCodec.DisplayName(encoding)),
                "Glance", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes) return false;
            encoding = TextFileCodec.Utf8;
            bytes = await Task.Run(() => TextFileCodec.Encode(text, encoding));
        }

        try
        {
            await Task.Run(() => TextFileCodec.WriteAtomic(info.Location, bytes));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Warning($"ContentWindow: save failed for '{Log.Redact(info.Location)}': {ex.Message}");
            MessageBox.Show(this, $"{L.F("Couldn't save %@", info.FileName)}\n\n{ex.Message}", "Glance",
                MessageBoxButton.OK, MessageBoxImage.Error);
            return false;
        }

        Log.Info($"ContentWindow: saved '{Log.Redact(info.Location)}' ({TextFileCodec.DisplayName(encoding)})");
        if (id != _loadId) return true;
        _decoded = decoded with { Encoding = encoding };
        if (_editCount == editsAtStart) SetDirty(false);
        ShowSaved();
        return true;
    }

    private void ShowSaved()
    {
        _saveButton.Content = L.T("Saved ✓");
        _savedTimer?.Stop();
        _savedTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _savedTimer.Tick += (_, _) =>
        {
            _savedTimer?.Stop();
            _saveButton.Content = L.T("Save");
        };
        _savedTimer.Start();
    }

    /// <summary>Asks about unsaved edits. True = go ahead (saved or discarded).</summary>
    private async Task<bool> ConfirmDiscardAsync()
    {
        if (!_dirty || !CanSave || _info is not { } info) return true;
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        var answer = MessageBox.Show(this, L.F("Do you want to save the changes you made to %@?", info.FileName), "Glance",
            MessageBoxButton.YesNoCancel, MessageBoxImage.Warning);
        return answer switch
        {
            MessageBoxResult.Yes => await SaveAsync(),
            MessageBoxResult.No => true,
            _ => false,
        };
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (_quitting) return;
        // Alt+F4 / taskbar close: hide instead of destroying (WebView2 stays warm).
        e.Cancel = true;
        _ = RequestCloseAsync();
    }

    private async Task RequestCloseAsync()
    {
        if (!await ConfirmDiscardAsync()) return;
        _loadId++;
        HideFindBar();
        if (!_search.IsClosed) _search.Close();
        if (_web?.CoreWebView2 is { } core)
        {
            // Stops audio/video and frees the page.
            _navigationArmed = true;
            core.Navigate("about:blank");
        }
        _suppressDirty = true;
        _editor.Document = new TextDocument();
        _suppressDirty = false;
        _decoded = null;
        _info = null;
        _documentHtml = null;
        _documentFolder = null;
        _kind = ViewKind.None;
        SetDirty(false);
        ShowLoading(false);
        Hide();
    }

    // ───────────────────────────── Git ─────────────────────────────

    private async Task LookUpGitAsync(string path, ulong id)
    {
        _diffButton.Visibility = Visibility.Collapsed;
        try
        {
            var context = await Task.Run(() => _git.ContextAsync(path));
            if (id != _loadId || context is null) return;
            _gitContext = context;
            _diffButton.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            Log.Warning($"ContentWindow: git lookup failed: {ex.Message}");
        }
    }

    private async void OnDiffClicked()
    {
        if (_gitContext is not { } context) return;
        _diffButton.IsEnabled = false;
        _diffButton.Content = "…";
        try
        {
            var snapshot = await Task.Run(() => _git.SnapshotAsync(context));
            var rows = await Task.Run(() => LineDiff.Rows(snapshot.BeforeText, snapshot.AfterText));
            new GitDiffWindow(snapshot, rows).Show();
        }
        catch (Exception ex)
        {
            Log.Error("ContentWindow: Git diff failed", ex);
            MessageBox.Show(this, $"{L.T("Couldn't load Git diff")}\n\n{context.FilePath}", "Glance", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            _diffButton.IsEnabled = true;
            _diffButton.Content = L.T("Diff");
        }
    }

    // ───────────────────────────── Layout state ─────────────────────────────

    private void ApplyIdentity(MediaInfo info, ulong id)
    {
        var addressBar = _kind == ViewKind.Web && !info.IsLocal;
        _identity.Visibility = addressBar ? Visibility.Collapsed : Visibility.Visible;
        _address.Visibility = addressBar ? Visibility.Visible : Visibility.Collapsed;
        _address.Text = info.Location;
        _fileName.Text = info.FileName;
        _subtitle.Text = info.IsLocal ? FolderDisplay(info.Location) : info.Location;
        _subtitle.ToolTip = info.Location;
        _findButton.Visibility = _kind == ViewKind.Pdf ? Visibility.Collapsed : Visibility.Visible;
        _revealButton.Visibility = info.IsLocal ? Visibility.Visible : Visibility.Collapsed;
        _diffButton.Visibility = Visibility.Collapsed;
        _saveButton.Content = L.T("Save");
        Title = info.FileName;
        if (info.IsLocal) _ = AppendModifiedDateAsync(info.Location, id);
    }

    /// <summary>Folder of a file, home shortened to "~" (as in Peek).</summary>
    private string FolderDisplay(string path)
    {
        var folder = Path.GetDirectoryName(path) ?? path;
        var home = _home.TrimEnd('\\');
        if (folder.Equals(home, StringComparison.OrdinalIgnoreCase)) return "~";
        return folder.StartsWith(home + "\\", StringComparison.OrdinalIgnoreCase) ? "~" + folder[home.Length..] : folder;
    }

    private async Task AppendModifiedDateAsync(string path, ulong id)
    {
        var modified = await Task.Run(() =>
        {
            try { return File.Exists(path) ? File.GetLastWriteTime(path) : (DateTime?)null; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
        });
        if (id != _loadId || modified is not { } date) return;
        _subtitle.Text = $"{FolderDisplay(path)} · {L.T("Modified ")}{date:g}";
    }

    private void PlaceAndShow(Size size)
    {
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        var wasVisible = IsVisible;
        if (WindowState != WindowState.Maximized)
            ScreenManager.Place(this, ScreenManager.CenterFrame(size, ScreenGeometry.MonitorAtCursor()));
        if (!wasVisible)
        {
            Show();
            if (WindowState != WindowState.Maximized)
                ScreenManager.Place(this, ScreenManager.CenterFrame(size, ScreenGeometry.MonitorAtCursor()));
        }
        Activate();
    }

    private ViewKind _body = ViewKind.None; // which body surface is showing: Text (editor) or Web

    private void ShowEditor()
    {
        _body = ViewKind.Text;
        ApplyBodyVisibility();
    }

    private void ShowWeb()
    {
        _body = ViewKind.Web;
        ApplyBodyVisibility();
    }

    private void ApplyBodyVisibility()
    {
        var failed = _failure.Visibility == Visibility.Visible;
        _editor.Visibility = !failed && _body == ViewKind.Text ? Visibility.Visible : Visibility.Collapsed;
        if (_web is not null) _web.Visibility = !failed && _body == ViewKind.Web ? Visibility.Visible : Visibility.Collapsed;
        SetDirty(_dirty);
    }

    private void ShowLoading(bool loading) => _loading.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;

    private void ShowFailure(string message, string? primaryLabel, Action? primary, string? secondaryLabel = null, Action? secondary = null)
    {
        _failureText.Text = message;
        _failurePrimary.Content = primaryLabel;
        _failurePrimary.Visibility = primary is null ? Visibility.Collapsed : Visibility.Visible;
        _failurePrimaryAction = primary;
        _failureSecondary.Content = secondaryLabel;
        _failureSecondary.Visibility = secondary is null ? Visibility.Collapsed : Visibility.Visible;
        _failureSecondaryAction = secondary;
        _failure.Visibility = Visibility.Visible;
        ApplyBodyVisibility();
    }

    private void HideFailure()
    {
        _failure.Visibility = Visibility.Collapsed;
        ApplyBodyVisibility();
    }

    private void ShowWebViewMissing(MediaInfo info) =>
        ShowFailure(L.T("Showing this needs the Microsoft Edge WebView2 Runtime, which isn't installed."),
            L.T("Get WebView2"), () => ShellActions.Open(WebView2Download),
            L.T("Open with Default App"), () => ShellActions.Open(info.Location));

    private void OnStateChanged()
    {
        // A maximized custom-chrome window overhangs the screen by the resize border.
        _root.Margin = WindowState == WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
        _maximizeGlyph.Text = WindowState == WindowState.Maximized ? Ui.GlyphRestore : Ui.GlyphMaximize;
    }

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    // ───────────────────────────── Builders ─────────────────────────────

    private static Button ToolbarIcon(string glyph, string tooltip, Action onClick)
    {
        var button = Ui.IconButton(glyph, tooltip, onClick);
        button.Width = 30;
        button.Height = 26;
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }

    private static Button ToolbarText(string label, Action onClick)
    {
        var button = new Button { Content = label, Style = Ui.Style("SecondaryButton"), Width = 72, Height = 26, Padding = new Thickness(0), Focusable = false };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }

    private static Button FindBarButton(object content, double width, string? tooltip, Action onClick)
    {
        var button = new Button
        {
            Content = content,
            ToolTip = tooltip,
            Style = Ui.Style("SecondaryButton"),
            Width = width,
            Height = 24,
            Padding = new Thickness(0),
            Margin = new Thickness(6, 0, 0, 0),
            Focusable = false,
        };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static TextBlock CaptionGlyph(string glyph) => new()
    {
        Text = glyph,
        FontFamily = Ui.IconFont,
        FontSize = 10,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static Button CaptionButton(TextBlock glyph, string tooltip, string styleKey, Action onClick)
    {
        var button = new Button { Content = glyph, ToolTip = tooltip, Style = Ui.Style(styleKey), Height = ToolbarHeight - 1 };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }
}
