using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Glance.App.Theme;

namespace Glance.App.Content;

/// <summary>
/// Indeterminate loading line (Windows stand-in for macOS <c>FocusSweepLoadingView</c>): an accent
/// segment sweeping along the bottom edge of the toolbar. It lives in the toolbar, not over the
/// body, because WPF can't draw on top of the WebView2 window (airspace). Animates only while visible.
/// </summary>
internal sealed class LoadingSweep : Canvas
{
    private readonly Border _segment;
    private readonly TranslateTransform _offset = new();

    public LoadingSweep()
    {
        Height = 2;
        IsHitTestVisible = false;
        ClipToBounds = true;
        _segment = new Border
        {
            Height = 2,
            Background = Ui.Brush("AccentBrush"),
            CornerRadius = new CornerRadius(1),
            RenderTransform = _offset,
        };
        Children.Add(_segment);
        IsVisibleChanged += (_, _) => Restart();
        SizeChanged += (_, _) => Restart();
    }

    private void Restart()
    {
        _offset.BeginAnimation(TranslateTransform.XProperty, null);
        if (!IsVisible || ActualWidth <= 0) return;
        var width = Math.Max(48, ActualWidth * 0.22);
        _segment.Width = width;
        var sweep = new DoubleAnimation(-width, ActualWidth, TimeSpan.FromMilliseconds(1200))
        {
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
        };
        _offset.BeginAnimation(TranslateTransform.XProperty, sweep);
    }
}
