using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.Core.Inspect;

namespace Glance.App.Inspect;

/// <summary>
/// The Shizuka bottom bar (port of macOS <c>InspectBottomBar</c>, Figma <c>bottom bar</c>, 92 pt):
/// file name and metadata on the left, and on the right the zoom state with the position — or,
/// while comparing, the A / B pair and the Slider / Side by side switch. The filmstrip is a
/// sibling centred over it; <see cref="InfoMaxWidth"/> keeps the left text out from under it.
/// </summary>
internal sealed class InspectBottomBar : Grid
{
    private const double SideInset = 28;
    private readonly TextBlock _name;
    private readonly TextBlock _meta;
    private readonly TextBlock _pairA;
    private readonly TextBlock _pairB;
    private readonly StackPanel _single;
    private readonly StackPanel _pair;
    private readonly Button _zoom;
    private readonly TextBlock _position;
    private readonly Button _slider;
    private readonly Button _sideBySide;
    private readonly StackPanel _right;

    public InspectBottomBar()
    {
        Height = 92;
        Background = Brushes.Transparent;

        _name = Label(13, FontWeights.Medium, "InspectText1Brush", Ui.UiFont);
        _name.TextTrimming = TextTrimming.CharacterEllipsis;
        _name.Height = 17;
        _meta = Label(11, FontWeights.Normal, "InspectText3Brush", Ui.CodeFont);
        _meta.Margin = new Thickness(0, 4, 0, 0);
        _single = new StackPanel { Margin = new Thickness(SideInset, 28, 0, 0), VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Left };
        _single.Children.Add(_name);
        _single.Children.Add(_meta);

        _pairA = Label(13, FontWeights.Medium, "InspectText1Brush", Ui.UiFont);
        _pairB = Label(13, FontWeights.Normal, "InspectText2Brush", Ui.UiFont);
        _pair = new StackPanel { Margin = new Thickness(SideInset, 26, 0, 0), VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Left, Visibility = Visibility.Collapsed };
        _pair.Children.Add(PairRow("A", _pairA));
        var rowB = PairRow("B", _pairB);
        rowB.Margin = new Thickness(0, 5, 0, 0);
        _pair.Children.Add(rowB);

        _zoom = TextButton(L.T("Fit"), () => FitRequested?.Invoke());
        _zoom.ToolTip = L.T("Fit to window");
        _position = Label(11, FontWeights.Normal, "InspectText3Brush", Ui.CodeFont);
        _position.Margin = new Thickness(20, 0, 0, 0);
        _position.VerticalAlignment = VerticalAlignment.Center;
        _slider = TextButton(L.T("Slider"), () => StyleRequested?.Invoke(CompareStyle.Slider));
        _sideBySide = TextButton(L.T("Side by side"), () => StyleRequested?.Invoke(CompareStyle.SideBySide));
        _sideBySide.Margin = new Thickness(18, 0, 0, 0);
        _right = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 44, SideInset, 0),
            Height = 17,
        };
        foreach (var child in new UIElement[] { _zoom, _position, _slider, _sideBySide }) _right.Children.Add(child);

        Children.Add(_single);
        Children.Add(_pair);
        Children.Add(_right);
    }

    public event Action? FitRequested;
    public event Action<CompareStyle>? StyleRequested;

    /// <summary>The left text may not run under the filmstrip (or the right-hand controls).</summary>
    public double InfoMaxWidth
    {
        set
        {
            var width = Math.Max(0, value - SideInset);
            _single.MaxWidth = width;
            _pair.MaxWidth = width;
        }
    }

    public void ShowSingle(string name, string meta, string zoom, string? position)
    {
        _single.Visibility = Visibility.Visible;
        _pair.Visibility = Visibility.Collapsed;
        _name.Text = name;
        _meta.Text = meta;
        _zoom.Content = zoom;
        _zoom.Visibility = string.IsNullOrEmpty(zoom) ? Visibility.Collapsed : Visibility.Visible;
        _position.Text = position ?? "";
        _position.Visibility = position is null ? Visibility.Collapsed : Visibility.Visible;
        _position.Margin = new Thickness(_zoom.Visibility == Visibility.Visible ? 20 : 0, 0, 0, 0);
        _slider.Visibility = Visibility.Collapsed;
        _sideBySide.Visibility = Visibility.Collapsed;
    }

    public void ShowPair(string a, string b, CompareStyle style)
    {
        _single.Visibility = Visibility.Collapsed;
        _pair.Visibility = Visibility.Visible;
        _pairA.Text = a;
        _pairB.Text = b;
        _zoom.Visibility = Visibility.Collapsed;
        _position.Visibility = Visibility.Collapsed;
        _slider.Visibility = Visibility.Visible;
        _sideBySide.Visibility = Visibility.Visible;
        Emphasize(_slider, style == CompareStyle.Slider);
        Emphasize(_sideBySide, style == CompareStyle.SideBySide);
    }

    private static void Emphasize(Button button, bool active)
    {
        button.FontWeight = active ? FontWeights.Medium : FontWeights.Normal;
        button.Foreground = Ui.Brush(active ? "InspectText1Brush" : "InspectText3Brush");
    }

    private static TextBlock Label(double size, FontWeight weight, string brush, FontFamily font) => new()
    {
        FontFamily = font,
        FontSize = size,
        FontWeight = weight,
        Foreground = Ui.Brush(brush),
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private static DockPanel PairRow(string letter, TextBlock name)
    {
        var tag = Label(11, FontWeights.Normal, "InspectText3Brush", Ui.CodeFont);
        tag.Text = letter;
        tag.Margin = new Thickness(0, 2, 8, 0);
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        var row = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(tag, Dock.Left);
        row.Children.Add(tag);
        row.Children.Add(name);
        return row;
    }

    private static Button TextButton(string text, Action onClick)
    {
        var button = new Button { Content = text, Style = Ui.Style("InspectTextButton") };
        button.Click += (_, _) => onClick();
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }
}
