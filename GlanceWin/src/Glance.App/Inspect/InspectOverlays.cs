using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Imaging;

namespace Glance.App.Inspect;

/// <summary>
/// The app's toast inside the Inspect window (Figma <c>15 · Toasts &amp; feedback</c>): an ink/3
/// capsule with an icon, a 13 pt message and a mono detail line (e.g. the saved path), centred
/// above the bottom bar. In-window instead of a child window so it can never take focus.
/// </summary>
internal sealed class InspectToast : Border
{
    private readonly TextBlock _icon;
    private readonly TextBlock _title;
    private readonly TextBlock _detail;
    private readonly DispatcherTimer _timer = new();

    public InspectToast()
    {
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Bottom;
        MaxWidth = 560;
        MinHeight = 38;
        Padding = new Thickness(14, 10, 16, 10);
        Background = Ui.Brush("InspectInk3Brush");
        BorderBrush = Ui.Brush("InspectLineStrongBrush");
        BorderThickness = new Thickness(1);
        CornerRadius = new CornerRadius(10);
        Effect = Ui.Effect("MenuShadow");
        IsHitTestVisible = false;
        Visibility = Visibility.Collapsed;

        _icon = Ui.Glyph(Ui.GlyphWarning, 14, "InspectText2Brush");
        _icon.VerticalAlignment = VerticalAlignment.Top;
        _icon.Margin = new Thickness(0, 1, 10, 0);
        _title = new TextBlock { FontFamily = Ui.UiFont, FontSize = 13, Foreground = Ui.Brush("InspectText1Brush"), TextWrapping = TextWrapping.Wrap };
        _detail = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
        var text = new StackPanel { Children = { _title, _detail } };
        var row = new DockPanel();
        DockPanel.SetDock(_icon, Dock.Left);
        row.Children.Add(_icon);
        row.Children.Add(text);
        Child = row;
        _timer.Tick += (_, _) => Hide();
    }

    /// <param name="message">First line is the message, an optional second line the detail (macOS "Saved ✓\npath").</param>
    public void Show(string message, bool error = false, double seconds = 3)
    {
        var split = message.IndexOf('\n');
        _title.Text = split < 0 ? message : message[..split];
        _detail.Text = split < 0 ? "" : message[(split + 1)..];
        _detail.Visibility = split < 0 ? Visibility.Collapsed : Visibility.Visible;
        _icon.Text = error ? Ui.GlyphWarning : CheckGlyph;
        _icon.Foreground = Ui.Brush(error ? "InspectShuBrush" : "InspectMossBrush");
        Visibility = Visibility.Visible;
        BeginAnimation(OpacityProperty, new DoubleAnimation(Opacity == 1 ? 1 : 0, 1, TimeSpan.FromMilliseconds(180)));
        _timer.Stop();
        _timer.Interval = TimeSpan.FromSeconds(seconds);
        _timer.Start();
    }

    public void Hide()
    {
        _timer.Stop();
        if (Visibility != Visibility.Visible) return;
        var fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(200));
        fade.Completed += (_, _) => { if (Opacity == 0) Visibility = Visibility.Collapsed; };
        BeginAnimation(OpacityProperty, fade);
    }

    private static readonly string CheckGlyph = ((char)0xE73E).ToString();
}

/// <summary>Figma <c>25 · Shortcuts</c>: title and rows of meaning with a key chip on the right.</summary>
internal sealed class ShortcutSheet : Border
{
    private static readonly (string Keys, string Meaning)[] Rows =
    [
        ("← →", "Previous / next"), ("0", "Fit to window"), ("1", "Actual size"), ("+  −", "Zoom"),
        ("Alt+click", "Compare with"), ("Esc", "Exit compare / close"), ("Ctrl+C", "Copy"), ("Ctrl+S", "Save"),
        ("Ctrl+L  Ctrl+R", "Rotate"), ("Ctrl+I", "Info"), ("Ctrl+Shift+X", "Capture"), ("Ctrl+V", "Paste image"),
    ];

    public ShortcutSheet()
    {
        Width = 520;
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
        Background = Ui.Brush("InspectInk1Brush");
        BorderBrush = Ui.Brush("InspectLineStrongBrush");
        BorderThickness = new Thickness(1);
        CornerRadius = Ui.Corner("CornerMedium");
        Effect = Ui.Effect("PanelShadow");
        Padding = new Thickness(32, 28, 32, 24);
        Visibility = Visibility.Collapsed;

        var stack = new StackPanel();
        stack.Children.Add(new TextBlock
        {
            Text = L.T("Keyboard Shortcuts"),
            FontFamily = Ui.UiFont,
            FontSize = 22,
            FontWeight = FontWeights.SemiBold,
            Foreground = Ui.Brush("InspectText1Brush"),
            Height = 30,
            Margin = new Thickness(0, 0, 0, 16),
        });
        foreach (var (keys, meaning) in Rows)
        {
            var label = new TextBlock { Text = L.T(meaning), FontFamily = Ui.UiFont, FontSize = 13, Foreground = Ui.Brush("InspectText2Brush"), VerticalAlignment = VerticalAlignment.Center };
            var chip = new Border
            {
                Background = Ui.Brush("InspectInk3Brush"),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(7, 2, 7, 2),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock { Text = keys, FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText1Brush") },
            };
            stack.Children.Add(new Border
            {
                Height = 33,
                BorderBrush = Ui.Brush("InspectLineBrush"),
                BorderThickness = new Thickness(0, 0, 0, 1),
                Child = new Grid { Children = { label, chip } },
            });
        }
        Child = stack;
    }
}

/// <summary>
/// Figma <c>26 · Image Inspect / Load error</c>: dashed frame over the stage, a vermilion dot,
/// the title, the explanation and recovery buttons.
/// </summary>
internal sealed class LoadErrorView : Grid
{
    private readonly TextBlock _title;
    private readonly TextBlock _body;
    private readonly Button _reveal;

    public LoadErrorView(Action reveal, Action retry)
    {
        Visibility = Visibility.Collapsed;
        var frame = new Rectangle
        {
            Stroke = Ui.Brush("InspectLineStrongBrush"),
            StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 3, 3 },
            RadiusX = 4,
            RadiusY = 4,
            IsHitTestVisible = false,
        };
        var dot = new Ellipse { Width = 6, Height = 6, Fill = Ui.Brush("InspectShuBrush"), HorizontalAlignment = HorizontalAlignment.Center };
        _title = new TextBlock
        {
            FontFamily = Ui.UiFont,
            FontSize = 24,
            FontWeight = FontWeights.SemiBold,
            Foreground = Ui.Brush("InspectText1Brush"),
            TextAlignment = TextAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(16, 16, 16, 8),
        };
        _body = new TextBlock
        {
            FontFamily = Ui.UiFont,
            FontSize = 13,
            Foreground = Ui.Brush("InspectText2Brush"),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 21,
            MaxWidth = 460,
            Margin = new Thickness(16, 0, 16, 22),
        };
        _reveal = new Button { Content = L.T("Reveal in File Explorer"), Style = Ui.Style("InspectQuietButton"), Margin = new Thickness(0, 0, 8, 0) };
        _reveal.Click += (_, _) => reveal();
        var tryAgain = new Button { Content = L.T("Try again"), Style = Ui.Style("InspectQuietButton") };
        tryAgain.Click += (_, _) => retry();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Children = { _reveal, tryAgain } };
        var block = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { dot, _title, _body, buttons } };
        Children.Add(frame);
        Children.Add(block);
    }

    public void Configure(string fileName, bool canReveal, bool canBrowse)
    {
        _title.Text = L.F("Couldn’t open %@", fileName);
        var text = L.T("Glance couldn’t read this image. The file may be damaged or in a format it can’t decode.");
        if (canBrowse) text += " " + L.T("Use ← → to keep browsing.");
        _body.Text = text;
        _reveal.Visibility = canReveal ? Visibility.Visible : Visibility.Collapsed;
    }
}

/// <summary>Figma compare <c>label</c>: ink/0 tag with the slot letter (mono 11) and the file name (11 pt, text/2).</summary>
internal sealed class CompareTag : Border
{
    private readonly TextBlock _letter;
    private readonly TextBlock _name;

    public CompareTag()
    {
        Background = Ui.Brush("InspectInk0Brush");
        CornerRadius = new CornerRadius(4);
        Padding = new Thickness(8, 3, 8, 4);
        IsHitTestVisible = false;
        Visibility = Visibility.Collapsed;
        _letter = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText1Brush"), Margin = new Thickness(0, 0, 6, 0) };
        _name = new TextBlock { FontFamily = Ui.UiFont, FontSize = 11, Foreground = Ui.Brush("InspectText2Brush"), MaxWidth = 180, TextTrimming = TextTrimming.CharacterEllipsis };
        Child = new StackPanel { Orientation = Orientation.Horizontal, Children = { _letter, _name } };
    }

    public void Configure(string letter, string name)
    {
        _letter.Text = letter;
        _name.Text = name;
    }
}

/// <summary>Minimal Figma slider: a 2 pt line/strong track, text/1 fill and a 14 pt thumb.</summary>
internal sealed class InspectSlider : Grid
{
    private readonly Border _fill;
    private readonly Ellipse _thumb;
    private double _value;

    public InspectSlider(double minimum, double maximum, double value)
    {
        Minimum = minimum;
        Maximum = maximum;
        Height = 14;
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        var track = new Border { Height = 2, CornerRadius = new CornerRadius(1), Background = Ui.Brush("InspectLineStrongBrush"), VerticalAlignment = VerticalAlignment.Center };
        _fill = new Border { Height = 2, CornerRadius = new CornerRadius(1), Background = Ui.Brush("InspectText1Brush"), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left };
        _thumb = new Ellipse { Width = 14, Height = 14, Fill = Ui.Brush("InspectInk1Brush"), Stroke = Ui.Brush("InspectText1Brush"), StrokeThickness = 1, HorizontalAlignment = HorizontalAlignment.Left };
        Children.Add(track);
        Children.Add(_fill);
        Children.Add(_thumb);
        _value = Math.Clamp(value, minimum, maximum);
        SizeChanged += (_, _) => Layout();
        Focusable = true;
    }

    public double Minimum { get; }
    public double Maximum { get; }
    public event Action<double>? ValueChanged;

    public double Value
    {
        get => _value;
        set
        {
            var v = Math.Clamp(value, Minimum, Maximum);
            if (Math.Abs(v - _value) < 1e-9) return;
            _value = v;
            Layout();
            ValueChanged?.Invoke(v);
        }
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        CaptureMouse();
        Track(e.GetPosition(this).X);
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (IsMouseCaptured) Track(e.GetPosition(this).X);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (IsMouseCaptured) ReleaseMouseCapture();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        var step = (Maximum - Minimum) / 100;
        if (e.Key is Key.Left or Key.Down) { Value -= step; e.Handled = true; }
        else if (e.Key is Key.Right or Key.Up) { Value += step; e.Handled = true; }
    }

    private void Track(double x)
    {
        var usable = Math.Max(1, ActualWidth - 14);
        Value = Minimum + (Maximum - Minimum) * Math.Clamp((x - 7) / usable, 0, 1);
    }

    private void Layout()
    {
        var usable = Math.Max(0, ActualWidth - 14);
        var fraction = Maximum > Minimum ? (_value - Minimum) / (Maximum - Minimum) : 0;
        _thumb.Margin = new Thickness(usable * fraction, 0, 0, 0);
        _fill.Width = usable * fraction + 7;
    }
}

/// <summary>
/// The Figma dialog card over a scrim (compress, resize, open URL, Base64): 440 pt ink/1 card,
/// 29 pt padding, Mincho-style title, caption, content, then right-aligned Quiet / Primary buttons.
/// Esc cancels; Enter confirms when the focus isn't in a multi-line field.
/// </summary>
internal sealed class InspectDialog : Grid
{
    private readonly Action _cancel;
    private readonly Func<bool>? _confirm;

    private InspectDialog(string title, string caption, UIElement content, string confirmTitle, Func<bool> confirm, Action cancel,
        out Button confirmButton, double width = 440)
    {
        _cancel = cancel;
        _confirm = confirm;
        Background = Ui.Brush("InspectScrimBrush");
        Focusable = true;

        var titleText = new TextBlock { Text = title, FontFamily = Ui.UiFont, FontSize = 22, FontWeight = FontWeights.SemiBold, Foreground = Ui.Brush("InspectText1Brush"), Height = 30 };
        var captionText = new TextBlock { Text = caption, FontFamily = Ui.UiFont, FontSize = 13, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 6, 0, 20), TextWrapping = TextWrapping.Wrap };
        var cancelButton = new Button { Content = L.T("Cancel"), Style = Ui.Style("InspectQuietButton"), Margin = new Thickness(0, 0, 8, 0) };
        cancelButton.Click += (_, _) => _cancel();
        confirmButton = new Button { Content = confirmTitle, Style = Ui.Style("InspectPrimaryButton") };
        confirmButton.Click += (_, _) => Confirm();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 22, 0, 0), Children = { cancelButton, confirmButton } };

        var card = new Border
        {
            Width = width,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Background = Ui.Brush("InspectInk1Brush"),
            BorderBrush = Ui.Brush("InspectLineStrongBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerMedium"),
            Effect = Ui.Effect("PanelShadow"),
            Padding = new Thickness(28),
            Child = new StackPanel { Children = { titleText, captionText, content, buttons } },
        };
        // Clicks on the card stay on it; clicks on the scrim do nothing (macOS dimmer swallows them).
        card.MouseLeftButtonDown += (_, e) => e.Handled = true;
        Children.Add(card);
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(this, true);
    }

    public void Cancel() => _cancel();

    /// <summary>The owner removes the dialog from inside the callback when it accepts.</summary>
    private void Confirm() => _confirm?.Invoke();

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        base.OnPreviewKeyDown(e);
        if (e.Key == Key.Escape)
        {
            _cancel();
            e.Handled = true;
        }
        else if (e.Key == Key.Enter && !(e.OriginalSource is TextBox { AcceptsReturn: true } && !Keyboard.Modifiers.HasFlag(ModifierKeys.Control)))
        {
            Confirm();
            e.Handled = true;
        }
    }

    /// <summary>Figma dialog key/value row: 13 pt text/3 key, mono 12 value on the right, a line rule (33 high).</summary>
    public static (Border Row, TextBlock Value) KeyValueRow(string key, string value, string valueBrush = "InspectText1Brush")
    {
        var keyText = new TextBlock { Text = key, FontFamily = Ui.UiFont, FontSize = 13, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center };
        var valueText = new TextBlock { Text = value, FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush(valueBrush), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        var row = new Border
        {
            Height = 33,
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = new Grid { Children = { keyText, valueText } },
        };
        return (row, valueText);
    }

    private static Grid LabelWithValue(string label, out TextBlock value)
    {
        var labelText = new TextBlock { Text = label, FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush") };
        value = new TextBlock { FontFamily = Ui.UiFont, FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Right };
        return new Grid { Margin = new Thickness(0, 0, 0, 12), Children = { labelText, value } };
    }

    /// <summary>Compress Image: quality slider, original / estimated size, Keep original dimensions.</summary>
    public static InspectDialog Compress(long sourceBytes, Action<double, long, bool> onConfirm, Action onCancel)
    {
        var header = LabelWithValue(L.T("Quality"), out var qualityValue);
        var slider = new InspectSlider(0.1, 1, 0.7) { Margin = new Thickness(0, 0, 0, 20) };
        var (originalRow, _) = KeyValueRow(L.T("Original"), Ui.FormatBytes(sourceBytes));
        var (resultRow, resultValue) = KeyValueRow(L.T("Compressed size"), "", "InspectMossBrush");
        var keep = new CheckBox
        {
            Content = L.T("Keep original dimensions"),
            IsChecked = true,
            FontFamily = Ui.UiFont,
            FontSize = 13,
            Foreground = Ui.Brush("InspectText1Brush"),
            Margin = new Thickness(0, 16, 0, 0),
            Focusable = false,
        };
        long target = 0;
        void Update(double quality)
        {
            qualityValue.Text = $"{Math.Round(quality * 100)}%";
            target = ImageTools.CompressedByteEstimate(sourceBytes, quality);
            var saving = (int)((1 - (double)target / Math.Max(1, sourceBytes)) * 100);
            resultValue.Text = saving > 0 ? $"{Ui.FormatBytes(target)}  ·  −{saving}%" : Ui.FormatBytes(target);
        }
        slider.ValueChanged += Update;
        Update(slider.Value);
        var content = new StackPanel { Children = { header, slider, originalRow, resultRow, keep } };
        var dialog = new InspectDialog(L.T("Compress Image"), L.T("Lower quality means a smaller file."), content, L.T("Compress"),
            () => { onConfirm(slider.Value, target, keep.IsChecked == true); return true; }, onCancel, out _);
        dialog.Loaded += (_, _) => slider.Focus();
        return dialog;
    }

    /// <summary>Resize Image: scale slider (1–99 %), original and new dimensions with the size estimate.</summary>
    public static InspectDialog Resize(int width, int height, long sourceBytes, Action<double> onConfirm, Action onCancel)
    {
        var header = LabelWithValue(L.T("Scale"), out var scaleValue);
        var slider = new InspectSlider(0.01, 0.99, 0.5) { Margin = new Thickness(0, 0, 0, 20) };
        var (originalRow, _) = KeyValueRow(L.T("Original"), $"{width} × {height}");
        var (resultRow, resultValue) = KeyValueRow(L.T("New size"), "", "InspectMossBrush");
        var selected = 0.5;
        Button? confirm = null;
        void Update(double scale)
        {
            var percent = Math.Clamp((int)Math.Round(scale * 100), 1, 99);
            selected = percent / 100.0;
            scaleValue.Text = $"{percent}%";
            var dims = ImageTools.ResizedDimensions(width, height, selected);
            resultValue.Text = dims is { } d ? $"{d.Width} × {d.Height}  ·  {Ui.FormatBytes(ImageTools.ResizedByteEstimate(sourceBytes, selected))}" : "—";
            if (confirm is not null) confirm.IsEnabled = dims is not null;
        }
        slider.ValueChanged += Update;
        var content = new StackPanel { Children = { header, slider, originalRow, resultRow } };
        var dialog = new InspectDialog(L.T("Resize Image"), L.T("Scale down proportionally."), content, L.T("Resize"),
            () =>
            {
                if (ImageTools.ResizedDimensions(width, height, selected) is null) return false;
                onConfirm(selected);
                return true;
            }, onCancel, out var button);
        confirm = button;
        Update(slider.Value);
        dialog.Loaded += (_, _) => slider.Focus();
        return dialog;
    }

    /// <summary>One text field (Open image URL, Base64 → Image).</summary>
    public static InspectDialog TextPrompt(string title, string caption, string confirmTitle, bool multiline, Func<string, bool> onConfirm, Action onCancel)
    {
        var field = new TextBox
        {
            Style = Ui.Style("FieldBox"),
            Height = multiline ? 180 : 88,
            AcceptsReturn = multiline,
            TextWrapping = TextWrapping.Wrap,
            VerticalContentAlignment = VerticalAlignment.Top,
            Padding = new Thickness(8, 8, 8, 8),
            FontFamily = multiline ? Ui.CodeFont : Ui.UiFont,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        var dialog = new InspectDialog(title, caption, field, confirmTitle,
            () => field.Text.Trim().Length > 0 && onConfirm(field.Text.Trim()), onCancel, out _, multiline ? 568 : 440);
        dialog.Loaded += (_, _) => Keyboard.Focus(field);
        return dialog;
    }
}
