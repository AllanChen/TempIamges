using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using Glance.App.Account;
using Glance.App.Inspect;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Account;
using Glance.Core.Tasks;
using Glance.Core.Widgets;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App.Widgets;

/// <summary>Shared look for the small Widget windows (Washi palette, 44 pt drag strip, close button).</summary>
internal abstract class WidgetDialogBase : Window
{
    protected readonly Grid Body = new();

    protected WidgetDialogBase(string title, double width, double height)
    {
        Title = title;
        Width = width;
        Height = height;
        MinWidth = Math.Min(width, 360);
        MinHeight = Math.Min(height, 420);
        Background = Ui.Brush("InspectInk1Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 40,
            ResizeBorderThickness = new Thickness(5),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            UseAeroCaptionButtons = false,
        });
        var close = new Button
        {
            Content = new TextBlock { Text = Ui.GlyphChromeClose, FontFamily = Ui.IconFont, FontSize = 10 },
            ToolTip = L.T("Close"),
            Style = Ui.Style("CaptionCloseButton"),
            Height = 40,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
        };
        close.Click += (_, _) => Close();
        WindowChrome.SetIsHitTestVisibleInChrome(close, true);
        var caption = new TextBlock { Text = title, FontSize = 12, Foreground = Ui.Brush("InspectText2Brush"), Margin = new Thickness(20, 12, 0, 0), IsHitTestVisible = false };
        Body.Margin = new Thickness(28, 52, 28, 24);
        Content = new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            Child = new Grid { Children = { caption, Body, close } },
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Close();
                e.Handled = true;
            }
        };
    }

    /// <summary>Centres over <paramref name="owner"/> (or the cursor's monitor), fully on screen.</summary>
    protected void PlaceOver(Window? owner)
    {
        var monitor = ScreenGeometry.MonitorAtCursor();
        var frame = ScreenManager.CenterFrame(new Size(Width, Height), monitor);
        if (owner is { IsVisible: true, WindowState: WindowState.Normal })
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(owner).Handle;
            if (hwnd != IntPtr.Zero)
            {
                monitor = ScreenGeometry.MonitorOf(hwnd);
                var o = ScreenGeometry.WindowRect(hwnd);
                var w = (int)Math.Round(Width * monitor.Scale);
                var h = (int)Math.Round(Height * monitor.Scale);
                frame = ScreenManager.Clamp(new PixelRect(o.CenterX - w / 2, o.CenterY - h / 2, w, h), monitor.WorkArea);
            }
        }
        ScreenManager.Place(this, frame);
    }

    protected static TextBlock Eyebrow(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        FontFamily = Ui.CodeFont,
        FontSize = 11,
        Foreground = Ui.Brush("InspectText3Brush"),
    };

    protected static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontSize = 22,
        Foreground = Ui.Brush("InspectText1Brush"),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 6, 0, 0),
    };

    protected static TextBlock Caption(string text, string brush = "InspectText3Brush") => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = Ui.Brush(brush),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 8, 0, 0),
    };

    protected static Button MakeButton(string text, bool primary, Action onClick)
    {
        var button = new Button { Content = text, Style = Ui.Style(primary ? "InspectPrimaryButton" : "InspectQuietButton"), Height = 32, MinWidth = 96 };
        button.Click += (_, _) => onClick();
        return button;
    }

    protected static TextBox PromptBox(string placeholder, int? maxLength) => new()
    {
        Style = Ui.Style("FieldBox"),
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        VerticalContentAlignment = VerticalAlignment.Top,
        MinHeight = 120,
        MaxLength = maxLength ?? 0,
        ToolTip = placeholder,
        Tag = placeholder,
    };
}

/// <summary>
/// Widget input panel (port of macOS <c>WidgetInputPanel</c> / <c>WidgetVideoInputPanel</c>, minus the
/// mask editor): ordered media (the first is the base), an optional prompt, the cost, Run Widget.
/// </summary>
internal sealed class WidgetInputWindow : WidgetDialogBase
{
    private readonly WidgetCommand _command;
    private readonly bool _video;
    private readonly WidgetInputCapabilities _caps;
    private readonly List<string> _media;
    private readonly StackPanel _mediaList = new() { Orientation = Orientation.Horizontal };
    private readonly TextBox? _prompt;
    private readonly TextBlock _hint;
    private readonly Button _run;
    private readonly Button _add;
    private readonly bool _promptRequired;

    private WidgetInputWindow(WidgetManifest widget, WidgetCommand command, string language, string costText, IReadOnlyList<string> media, bool video)
        : base(L.T("Widget"), 560, 640)
    {
        _command = command;
        _video = video;
        _caps = command.InputCapabilities;
        _media = media.Take(video ? _caps.MaxVideos : _caps.MaxImages).ToList();
        var kinds = new List<string> { video ? "video" : "image" };
        if (_caps.AcceptsPrompt) kinds.Add("text");

        var stack = new StackPanel();
        stack.Children.Add(Eyebrow(L.T("Widget") + "  ·  " + WidgetText.Kinds(kinds)));
        stack.Children.Add(Heading(widget.Commands.Count == 1 ? widget.DisplayName(language) : widget.CommandName(command, language)));
        stack.Children.Add(Caption(Description()));

        var mediaHeader = new TextBlock { Text = L.T(video ? "Video" : "Image(s)"), FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText2Brush"), Margin = new Thickness(0, 20, 0, 6) };
        stack.Children.Add(mediaHeader);
        stack.Children.Add(new ScrollViewer { Content = _mediaList, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled });
        _add = MakeButton(L.T(video ? "Add video" : "Add image"), primary: false, AddMedia);
        _add.HorizontalAlignment = HorizontalAlignment.Left;
        _add.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(_add);

        if (_caps.AcceptsPrompt)
        {
            var schema = command.PromptProperty;
            var description = ApiEnvelope.Text(schema?["description"]) ?? L.T("Describe what the Widget should do…");
            _promptRequired = ApiEnvelope.Int(schema?["minLength"]) is >= 1
                || (command.ParameterSchema?["required"] as System.Text.Json.Nodes.JsonArray)?.Any(n => ApiEnvelope.Text(n) == "prompt") == true;
            stack.Children.Add(new TextBlock { Text = L.T("Prompt") + (_promptRequired ? "" : "  ·  " + L.T("Optional")), FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText2Brush"), Margin = new Thickness(0, 20, 0, 6) });
            _prompt = PromptBox(description, ApiEnvelope.Int(schema?["maxLength"]));
            _prompt.TextChanged += (_, _) => Validate();
            stack.Children.Add(_prompt);
            stack.Children.Add(Caption(description));
        }

        var cost = new Grid { Margin = new Thickness(0, 20, 0, 0) };
        cost.Children.Add(new TextBlock { Text = L.T("Cost"), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush") });
        cost.Children.Add(new TextBlock { Text = costText, FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Right });
        stack.Children.Add(cost);
        _hint = Caption("", "FailureBrush");
        stack.Children.Add(_hint);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom };
        var cancel = MakeButton(L.T("Cancel"), primary: false, Close);
        _run = MakeButton(L.T("Run Widget"), primary: true, Submit);
        _run.Margin = new Thickness(10, 0, 0, 0);
        buttons.Children.Add(cancel);
        buttons.Children.Add(_run);
        Body.RowDefinitions.Add(new RowDefinition());
        Body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Body.Children.Add(new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Grid.SetRow(buttons, 1);
        Body.Children.Add(buttons);
        RenderMedia();
        Validate();
    }

    public WidgetTaskInput? Result { get; private set; }

    /// <summary>Shows the panel modally over <paramref name="owner"/>; null when cancelled.</summary>
    public static WidgetTaskInput? Ask(Window? owner, WidgetManifest widget, WidgetCommand command, string language, IReadOnlyList<string> media, bool video)
    {
        var window = new WidgetInputWindow(widget, command, language, WidgetText.CostText(widget), media, video);
        if (owner is { IsVisible: true }) window.Owner = owner;
        window.PlaceOver(owner);
        window.ShowDialog();
        return window.Result;
    }

    private int Max => _video ? _caps.MaxVideos : _caps.MaxImages;
    private int Min => _video ? 1 : _caps.MinImages;

    private string Description()
    {
        if (_video) return L.T(Max > 1 ? "Use up to four videos. The first video is the base." : "Select the video to process.");
        if (Max == 2 && Min == 2) return L.T("Use two images. The first image is the base.");
        if (Max > 1) return L.T("Use up to four images. The first image is the base.");
        return L.T("The prompt tells the Widget what to make or change.");
    }

    private void RenderMedia()
    {
        _mediaList.Children.Clear();
        for (var i = 0; i < _media.Count; i++)
        {
            var index = i;
            var path = _media[i];
            var tile = new Grid { Width = 96, Margin = new Thickness(0, 0, 8, 0) };
            tile.RowDefinitions.Add(new RowDefinition { Height = new GridLength(72) });
            tile.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var frame = new Border { Background = Ui.Brush("InspectInk3Brush"), CornerRadius = Ui.Corner("CornerThumb"), ClipToBounds = true };
            var image = new Image { Stretch = Stretch.UniformToFill };
            frame.Child = image;
            _ = LoadThumbAsync(path, image);
            tile.Children.Add(frame);
            var label = new TextBlock
            {
                Text = index == 0 ? L.T("Base") : Path.GetFileName(path),
                FontSize = 11,
                Foreground = Ui.Brush(index == 0 ? "InspectText1Brush" : "InspectText3Brush"),
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(0, 4, 0, 0),
                ToolTip = Path.GetFileName(path),
            };
            Grid.SetRow(label, 1);
            tile.Children.Add(label);
            if (index > 0)
            {
                var remove = new Button { Content = Ui.LineIcon(Ui.IconClose, 12, "InspectText2Brush"), Style = Ui.Style("InspectIconButton"), Width = 22, Height = 22, ToolTip = L.T("Remove"), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 4, 4, 0) };
                remove.Click += (_, _) =>
                {
                    _media.RemoveAt(index);
                    RenderMedia();
                    Validate();
                };
                tile.Children.Add(remove);
            }
            _mediaList.Children.Add(tile);
        }
        _add.Visibility = Max > 1 ? Visibility.Visible : Visibility.Collapsed;
        _add.IsEnabled = _media.Count < Max;
    }

    private static async Task LoadThumbAsync(string location, Image target)
    {
        if (!File.Exists(location)) return;
        var thumb = await ShellThumbnails.GetAsync(location, 192, thumbnailOnly: false);
        if (thumb is not null) target.Source = thumb;
    }

    private void AddMedia()
    {
        var dialog = new OpenFileDialog
        {
            Multiselect = true,
            Filter = _video
                ? L.T("Videos") + "|*.mp4;*.mov;*.m4v;*.webm;*.mkv;*.avi;*.wmv"
                : L.T("Images") + "|*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp;*.heic;*.heif;*.tif;*.tiff",
        };
        if (dialog.ShowDialog(this) != true) return;
        foreach (var file in dialog.FileNames)
        {
            if (_media.Count >= Max) break;
            if (!_media.Contains(file, StringComparer.OrdinalIgnoreCase)) _media.Add(file);
        }
        RenderMedia();
        Validate();
    }

    private void Validate()
    {
        string? issue = null;
        if (_media.Count < Min) issue = Max == 2 && Min == 2 ? L.T("This Widget requires exactly two images.") : L.T(_video ? "Select the video to process." : "Add image");
        else if (_promptRequired && string.IsNullOrWhiteSpace(_prompt?.Text)) issue = L.T("Describe what the Widget should do…");
        _run.IsEnabled = issue is null;
        _hint.Text = _media.Count >= Max && Max > 1 ? L.T(_video ? "Use up to four videos. The first video is the base." : "4 images maximum · remove one to add another") : "";
        _hint.Foreground = Ui.Brush("InspectText3Brush");
    }

    private void Submit()
    {
        if (!_run.IsEnabled) return;
        var prompt = _prompt?.Text.Trim();
        Result = new WidgetTaskInput
        {
            MediaUrls = _media.ToList(),
            Prompt = string.IsNullOrEmpty(prompt) ? null : prompt,
            UsesMultipleImages = !_video && Max > 1,
            UsesMultipleVideos = _video && Max > 1,
        };
        DialogResult = true;
    }
}

/// <summary>
/// A text-only Widget (macOS <c>TextWidgetPanel</c>, 560 × 640): one window per Widget; type or
/// paste text, Ctrl+Enter runs; progress, the credit status and the text result show in place.
/// </summary>
internal sealed class TextWidgetWindow : WidgetDialogBase
{
    private readonly AccountServices _services;
    private readonly WidgetManifest _widget;
    private readonly WidgetCommand _command;
    private readonly Func<WidgetTaskInput, Window, Task<WidgetTaskRecord?>> _start;
    private readonly TextBox _prompt;
    private readonly TextBlock _status;
    private readonly TextBox _result;
    private readonly Button _run;
    private readonly Button _copy;
    private readonly Button _reveal;
    private Guid? _recordId;

    public TextWidgetWindow(AccountServices services, WidgetManifest widget, WidgetCommand command, Func<WidgetTaskInput, Window, Task<WidgetTaskRecord?>> start)
        : base(widget.DisplayName(services.Language), 560, 640)
    {
        _services = services;
        _widget = widget;
        _command = command;
        _start = start;
        var language = services.Language;
        var schema = command.PromptProperty;
        var placeholder = ApiEnvelope.Text(schema?["description"]) ?? widget.CommandDescription(command, language);

        var stack = new StackPanel();
        stack.Children.Add(Eyebrow(L.T("Widget") + "  ·  " + L.T("Text")));
        stack.Children.Add(Heading(widget.Commands.Count == 1 ? widget.DisplayName(language) : widget.CommandName(command, language)));
        stack.Children.Add(Caption(WidgetText.CostText(widget)));
        stack.Children.Add(new TextBlock { Text = L.T("Input"), FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText2Brush"), Margin = new Thickness(0, 18, 0, 6) });
        _prompt = PromptBox(placeholder, ApiEnvelope.Int(schema?["maxLength"]));
        _prompt.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
            {
                _ = RunAsync();
                e.Handled = true;
            }
        };
        stack.Children.Add(_prompt);
        stack.Children.Add(Caption(placeholder));
        _status = Caption("");
        stack.Children.Add(_status);
        _result = new TextBox
        {
            Style = Ui.Style("FieldBox"),
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalContentAlignment = VerticalAlignment.Top,
            MinHeight = 120,
            FontSize = 14,
            Visibility = Visibility.Collapsed,
            Margin = new Thickness(0, 10, 0, 0),
        };
        stack.Children.Add(_result);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        _copy = MakeButton(L.T("Copy result"), primary: false, () =>
        {
            if (InspectImages.CopyText(_result.Text)) _status.Text = L.T("Copied");
        });
        _copy.Visibility = Visibility.Collapsed;
        _reveal = MakeButton(L.T("Reveal in File Explorer"), primary: false, () =>
        {
            if (_recordId is { } id && _services.Tasks.Find(id)?.OutputPath is { } output) ShellActions.RevealInExplorer(output);
        });
        _reveal.Visibility = Visibility.Collapsed;
        _reveal.Margin = new Thickness(10, 0, 0, 0);
        var paste = MakeButton(L.T("Paste"), primary: false, () =>
        {
            if (InspectImages.ClipboardText() is { } text) _prompt.SelectedText = text;
        });
        paste.Margin = new Thickness(10, 0, 0, 0);
        _run = MakeButton(L.T("Run"), primary: true, () => _ = RunAsync());
        _run.Margin = new Thickness(10, 0, 0, 0);
        foreach (var b in new[] { _copy, _reveal, paste, _run }) buttons.Children.Add(b);
        Body.RowDefinitions.Add(new RowDefinition());
        Body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Body.Children.Add(new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Grid.SetRow(buttons, 1);
        Body.Children.Add(buttons);
        services.Tasks.Changed += OnTasksChanged;
        Closed += (_, _) => services.Tasks.Changed -= OnTasksChanged;
    }

    public string WidgetId => _widget.Id;

    public void Present(Window? owner)
    {
        if (!IsVisible)
        {
            PlaceOver(owner);
            Show();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        _prompt.Focus();
    }

    private async Task RunAsync()
    {
        var text = _prompt.Text.Trim();
        if (text.Length == 0)
        {
            _status.Text = L.T("Enter some text for the Widget.");
            _status.Foreground = Ui.Brush("FailureBrush");
            return;
        }
        if (_recordId is { } running && _services.Tasks.Find(running) is { IsActive: true }) return;
        _run.IsEnabled = false;
        _status.Foreground = Ui.Brush("InspectText3Brush");
        _status.Text = L.T("Preparing…");
        var record = await _start(new WidgetTaskInput { Prompt = text }, this);
        _recordId = record?.Id;
        if (record is null)
        {
            _run.IsEnabled = true;
            _status.Text = "";
        }
        OnTasksChanged(null, EventArgs.Empty);
    }

    private void OnTasksChanged(object? sender, EventArgs e)
    {
        if (_recordId is not { } id || _services.Tasks.Find(id) is not { } r) return;
        _run.IsEnabled = !r.IsActive;
        _run.Content = L.T(r.IsFailure || r.Phase == WidgetTaskPhase.Cancelled ? "Try again" : "Run");
        var billing = WidgetText.BillingStatus(r);
        _status.Foreground = Ui.Brush(r.IsFailure ? "FailureBrush" : "InspectText3Brush");
        _status.Text = r.Phase switch
        {
            WidgetTaskPhase.Uploading or WidgetTaskPhase.Submitting => L.T("Submitting…"),
            WidgetTaskPhase.Processing => WidgetText.QueueStatus(r) ?? L.T("Running…"),
            WidgetTaskPhase.Downloading => L.T("Downloading result…"),
            WidgetTaskPhase.Completed => L.T("Widget completed"),
            WidgetTaskPhase.Cancelled => L.T("You cancelled this task."),
            _ => L.T(r.ErrorMessage ?? "The task stopped without reporting a reason."),
        } + (billing is null ? "" : "  ·  " + billing);
        if (r.Phase == WidgetTaskPhase.Completed && r.OutputPath is { } output)
        {
            _result.Text = ReadResult(output);
            _result.Visibility = Visibility.Visible;
            _copy.Visibility = Visibility.Visible;
            _reveal.Visibility = Visibility.Visible;
        }
    }

    internal static string ReadResult(string output)
    {
        try
        {
            if (File.Exists(output) && Path.GetExtension(output).Equals(".txt", StringComparison.OrdinalIgnoreCase)) return File.ReadAllText(output);
            if (Directory.Exists(output))
                return string.Join("\n\n", Directory.GetFiles(output, "*.txt").OrderBy(f => f, StringComparer.OrdinalIgnoreCase).Select(File.ReadAllText));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return L.T("The result could not be read.");
        }
        return L.F("Saved to %@", output);
    }
}

/// <summary>A text result (macOS <c>WidgetTextResultWindow</c>, 456 × 720): selectable text, character count, Copy result.</summary>
internal sealed class TextResultWindow : WidgetDialogBase
{
    public TextResultWindow(string widgetName, string text) : base(L.T("Widget Result"), 456, 720)
    {
        var stack = new DockPanel();
        var header = new StackPanel();
        header.Children.Add(Eyebrow(L.T("Result") + "  ·  " + L.T("Plain text")));
        header.Children.Add(Heading(widgetName));
        DockPanel.SetDock(header, Dock.Top);
        stack.Children.Add(header);
        var footer = new Grid { Margin = new Thickness(0, 12, 0, 0) };
        var count = new TextBlock { Text = L.F("%d characters", text.Length), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center };
        var copy = MakeButton(L.T("Copy result"), primary: true, () => { });
        copy.HorizontalAlignment = HorizontalAlignment.Right;
        copy.IsEnabled = text.Length > 0;
        copy.Click += (_, _) =>
        {
            if (InspectImages.CopyText(text)) copy.Content = L.T("Copied");
        };
        footer.Children.Add(count);
        footer.Children.Add(copy);
        DockPanel.SetDock(footer, Dock.Bottom);
        stack.Children.Add(footer);
        stack.Children.Add(new TextBox
        {
            Text = text.Length > 0 ? text : L.T("No text returned"),
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Foreground = Ui.Brush("InspectText1Brush"),
            FontSize = 15,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Margin = new Thickness(0, 16, 0, 0),
        });
        Body.Children.Add(stack);
    }

    public void Present(Window? owner)
    {
        PlaceOver(owner);
        Show();
        Activate();
    }
}
