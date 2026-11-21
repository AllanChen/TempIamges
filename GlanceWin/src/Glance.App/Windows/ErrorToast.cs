using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Glance.App.Theme;
using Glance.Platform;

namespace Glance.App.Windows;

/// <summary>
/// Notice for moments with no window to attach to — "No text selected", hotkey conflicts
/// (port of macOS <c>ErrorTooltip</c>). Placed beside the cursor, auto-hides after 3 s.
/// </summary>
internal sealed class ErrorToast : FloatingWindow
{
    private const double MaxTextWidth = 420;
    private readonly Border _card;
    private readonly TextBlock _icon;
    private readonly TextBlock _message;
    private readonly DispatcherTimer _hideTimer = new() { Interval = TimeSpan.FromSeconds(3) };

    public ErrorToast()
    {
        Title = "Glance";
        _icon = Ui.Glyph(Ui.GlyphWarning, 14, "FailureBrush");
        _icon.Margin = new Thickness(0, 1, 10, 0);
        _icon.VerticalAlignment = VerticalAlignment.Top;
        _message = Ui.Text("", "BodyText", TextTrimming.None);
        _message.TextWrapping = TextWrapping.Wrap;
        _message.MaxWidth = MaxTextWidth;

        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(_icon);
        row.Children.Add(_message);

        _card = new Border
        {
            Margin = new Thickness(ShadowMargin),
            Padding = new Thickness(14, 10, 16, 10),
            Background = Ui.Brush("SurfaceElevatedBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerMedium"),
            Effect = Ui.Effect("MenuShadow"),
            Child = row,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
        };
        Content = _card;
        _hideTimer.Tick += (_, _) => Dismiss();
    }

    public void ShowMessage(string message, bool isError = true)
    {
        _message.Text = message;
        _icon.Text = isError ? Ui.GlyphWarning : Ui.GlyphSearch;
        _icon.Foreground = Ui.Brush(isError ? "FailureBrush" : "TextSecondaryBrush");

        _card.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = new Size(_card.DesiredSize.Width, _card.DesiredSize.Height);
        // DesiredSize already includes the card margin (the shadow room).
        var cursor = ScreenGeometry.CursorPosition();
        var monitor = ScreenGeometry.MonitorAt(cursor.X, cursor.Y);
        ShowAt(ScreenManager.AdjustedFrame(size, monitor, cursor));

        _hideTimer.Stop();
        _hideTimer.Start();
    }

    public void Dismiss()
    {
        _hideTimer.Stop();
        FadeOut(close: false);
    }
}
