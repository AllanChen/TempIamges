using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Detection;
using Glance.Core.Imaging;
using Glance.Platform;

namespace Glance.App.Inspect;

/// <summary>One image's Image Information values.</summary>
internal sealed record InfoSnapshot(MediaInfo Info, ImageDetails? Details);

/// <summary>
/// Image Information (port of macOS <c>ImageInfoPanel</c> / Figma <c>20 · Image Inspect / Info</c>):
/// a 320 pt ink/1 panel attached to the right edge of the Inspect window, outside the image.
/// File name, folder, then Image / Color / File sections. While comparing it describes the
/// image under the pointer (or the active slot) and marks values that differ from the other
/// image. Never takes focus from the Inspect window (CLAUDE.md rule 23).
/// </summary>
internal sealed class InspectInfoWindow : Window
{
    private const double PanelWidth = 320;
    private const double Gap = 2;
    private const double PadX = 24;
    private readonly Window _owner;
    private readonly TextBlock _title;
    private readonly TextBlock _folder;
    private readonly StackPanel _sections = new();
    private readonly Border _card;

    public InspectInfoWindow(Window owner)
    {
        _owner = owner;
        Owner = owner;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = PanelWidth + FloatingWindow.ShadowMargin * 2;
        UseLayoutRounding = true;
        Title = L.T("Image information");
        SourceInitialized += (_, _) => WindowStyles.MakeNonActivating(this);

        _title = new TextBlock
        {
            FontFamily = Ui.UiFont,
            FontSize = 20,
            FontWeight = FontWeights.SemiBold,
            Foreground = Ui.Brush("InspectText1Brush"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            Height = 28,
            Margin = new Thickness(0, 0, 36, 0),
        };
        _folder = new TextBlock
        {
            FontFamily = Ui.CodeFont,
            FontSize = 11,
            Foreground = Ui.Brush("InspectText3Brush"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 4, 0, 24),
        };
        var close = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(Ui.IconClose, 16, "InspectText2Brush"), ToolTip = L.T("Close") };
        close.Click += (_, _) => CloseRequested?.Invoke();
        close.HorizontalAlignment = HorizontalAlignment.Right;
        close.VerticalAlignment = VerticalAlignment.Top;
        close.Margin = new Thickness(0, -2, -8, 0);

        var content = new Grid { Margin = new Thickness(PadX, 28, PadX, 4) };
        var stack = new StackPanel();
        stack.Children.Add(_title);
        stack.Children.Add(_folder);
        stack.Children.Add(_sections);
        content.Children.Add(stack);
        content.Children.Add(close);

        _card = new Border
        {
            Margin = new Thickness(FloatingWindow.ShadowMargin),
            Background = Ui.Brush("InspectInk1Brush"),
            BorderBrush = Ui.Brush("InspectLineStrongBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerMedium"),
            Effect = Ui.Effect("PanelShadow"),
            Child = content,
        };
        Content = _card;

        owner.LocationChanged += (_, _) => Reposition();
        owner.SizeChanged += (_, _) => Reposition();
        owner.StateChanged += (_, _) => Reposition();
        SizeChanged += (_, _) => Reposition();
    }

    public event Action? CloseRequested;

    /// <summary>Shows <paramref name="item"/>; values that differ from <paramref name="other"/> are marked.</summary>
    public void Display(InfoSnapshot item, InfoSnapshot? other)
    {
        var info = item.Info;
        _title.Text = info.FileName;
        _folder.Text = Folder(info);
        _sections.Children.Clear();
        foreach (var (caption, rows) in Sections(item))
        {
            var header = new TextBlock { Text = caption, FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), Height = 15, Margin = new Thickness(0, 0, 0, 4) };
            _sections.Children.Add(header);
            var otherRows = other is null ? null : Sections(other).FirstOrDefault(s => s.Caption == caption).Rows;
            foreach (var (key, value) in rows)
            {
                var differs = otherRows is not null && key != L.T("Path") && key != L.T("Created")
                              && otherRows.FirstOrDefault(r => r.Key == key).Value is { } otherValue && otherValue != value;
                _sections.Children.Add(Row(key, value, differs));
            }
            _sections.Children.Add(new Border { Height = 24 });
        }
    }

    public void ShowBeside()
    {
        if (!IsVisible) Show();
        Reposition();
    }

    private static List<(string Caption, List<(string Key, string Value)> Rows)> Sections(InfoSnapshot item)
    {
        const string dash = "—";
        var info = item.Info;
        var d = item.Details;
        var dims = info.PixelWidth is { } w && info.PixelHeight is { } h ? $"{w} × {h}" : dash;
        return
        [
            (L.T("Image"),
            [
                (L.T("Dimensions"), dims),
                (L.T("Aspect ratio"), ImageTools.AspectRatioText(info.PixelWidth, info.PixelHeight) ?? dash),
                (L.T("Format"), string.IsNullOrEmpty(info.FormatName) ? dash : info.FormatName),
                (L.T("File size"), info.FileSize is { } size ? Ui.FormatBytes(size) : dash),
            ]),
            (L.T("Color"),
            [
                (L.T("Color space"), d?.ColorSpace ?? dash),
                (L.T("Bit depth"), d?.BitDepth is { } depth ? $"{depth}-bit" : dash),
                (L.T("Alpha"), d?.HasAlpha is { } alpha ? L.T(alpha ? "Yes" : "No") : dash),
            ]),
            (L.T("File"),
            [
                (L.T("Created"), d?.Created is { } created ? created.ToString("g") : dash),
                (L.T("Path"), Folder(info)),
            ]),
        ];
    }

    private static string Folder(MediaInfo info)
    {
        if (!info.IsLocal) return Uri.TryCreate(info.Location, UriKind.Absolute, out var uri) ? uri.Host : info.Location;
        var folder = Path.GetDirectoryName(info.Location) ?? info.Location;
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return folder.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + folder[home.Length..] : folder;
    }

    /// <summary>Figma row: 12 pt text/3 key, mono 11 value right-aligned, a line rule at the foot (32 high).</summary>
    private static FrameworkElement Row(string key, string value, bool differs)
    {
        var keyText = new TextBlock { Text = key, FontFamily = Ui.UiFont, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center };
        var valueText = new TextBlock
        {
            Text = value,
            FontFamily = Ui.CodeFont,
            FontSize = 11,
            Foreground = Ui.Brush(differs ? "AccentTextBrush" : "InspectText1Brush"),
            FontWeight = differs ? FontWeights.SemiBold : FontWeights.Normal,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 0, 0),
            ToolTip = value,
        };
        var grid = new Grid { Height = 31 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.Children.Add(keyText);
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);
        return new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = grid,
        };
    }

    /// <summary>Right of the owner (2 pt gap), top-aligned; flips to the left when there is no room.</summary>
    private void Reposition()
    {
        if (!IsVisible) return;
        if (_owner.WindowState == WindowState.Minimized)
        {
            Hide();
            return;
        }
        var ownerHwnd = new WindowInteropHelper(_owner).Handle;
        var hwnd = new WindowInteropHelper(this).Handle;
        if (ownerHwnd == IntPtr.Zero || hwnd == IntPtr.Zero) return;
        var ownerRect = ScreenGeometry.WindowRect(ownerHwnd);
        var monitor = ScreenGeometry.MonitorOf(ownerHwnd);
        var scale = monitor.Scale;
        var margin = (int)Math.Round(FloatingWindow.ShadowMargin * scale);
        var width = (int)Math.Ceiling((PanelWidth + FloatingWindow.ShadowMargin * 2) * scale);
        var height = (int)Math.Ceiling(Math.Max(ActualHeight, 200) * scale);
        var gap = (int)Math.Round(Gap * scale);
        var work = monitor.WorkArea;

        var x = ownerRect.Right + gap - margin;
        if (x + width - margin > work.Right) x = ownerRect.X - gap - width + margin;
        x = Math.Clamp(x, work.X - margin, work.Right - width + margin);
        var y = Math.Clamp(ownerRect.Y - margin, work.Y - margin, Math.Max(work.Y - margin, work.Bottom - height + margin));
        ScreenGeometry.SetWindowRect(hwnd, new PixelRect(x, y, width, height));
    }
}
