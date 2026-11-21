using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Glance.Platform;

namespace Glance.App.Windows;

/// <summary>
/// Base for Peek, toasts and other floating panels (CLAUDE.md rule 23): borderless, transparent
/// (rounded corners + soft shadow), topmost, never activates, not in taskbar/Alt+Tab.
/// Content is laid out in DIPs inside a <see cref="ShadowMargin"/> so the shadow has room.
/// </summary>
internal abstract class FloatingWindow : Window
{
    public const double ShadowMargin = 24;

    protected FloatingWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        SourceInitialized += (_, _) => WindowStyles.MakeNonActivating(this);
    }

    /// <summary>Content size + shadow margin, in DIPs.</summary>
    protected static Size WithMargin(Size content) =>
        new(content.Width + ShadowMargin * 2, content.Height + ShadowMargin * 2);

    /// <summary>Shows (if hidden) at <paramref name="frame"/>, fading in on first show.</summary>
    protected void ShowAt(PixelRect frame)
    {
        var firstShow = !IsVisible;
        if (firstShow)
        {
            Opacity = 0;
            Show();
        }
        else
        {
            // Cancel a fade-out in progress (its Completed handler won't run once replaced).
            BeginAnimation(OpacityProperty, null);
            Opacity = 1;
        }
        ScreenManager.Place(this, frame);
        if (firstShow) BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180)));
    }

    /// <summary>Fades out, then hides (or closes).</summary>
    protected void FadeOut(bool close, Action? completed = null)
    {
        if (!IsVisible)
        {
            completed?.Invoke();
            return;
        }
        var fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(160));
        fade.Completed += (_, _) =>
        {
            if (close) Close();
            else Hide();
            completed?.Invoke();
        };
        BeginAnimation(OpacityProperty, fade);
    }
}
