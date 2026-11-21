using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Platform;

namespace Glance.App.Inspect;

/// <summary>
/// Recognize Text results (port of macOS <c>OCRResultWindow</c> / Figma <c>22 · Recognize Text</c>):
/// a 360 pt panel docked beside the Inspect window with the text in reading order, the
/// character count and Copy All. The text is selectable, so this panel may take focus.
/// </summary>
internal sealed class OcrResultWindow : Window
{
    public const double PanelWidth = 360;
    private const double Inset = 28;
    private readonly Window _owner;
    private readonly TextBox _text;
    private readonly TextBlock _count;
    private readonly Button _copy;
    private readonly DispatcherTimer _revert = new() { Interval = TimeSpan.FromSeconds(1.2) };
    private string _recognized = "";

    public OcrResultWindow(Window owner)
    {
        _owner = owner;
        Owner = owner;
        Title = L.T("Recognize Text");
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        UseLayoutRounding = true;
        Width = PanelWidth + FloatingWindow.ShadowMargin * 2;

        var title = new TextBlock
        {
            Text = L.T("Recognize Text"),
            FontFamily = Ui.UiFont,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Foreground = Ui.Brush("InspectText1Brush"),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var close = new Button { Style = Ui.Style("InspectIconButton"), Content = Ui.LineIcon(Ui.IconClose, 16, "InspectText2Brush"), ToolTip = L.T("Close") };
        close.HorizontalAlignment = HorizontalAlignment.Right;
        close.VerticalAlignment = VerticalAlignment.Center;
        close.Margin = new Thickness(0, 0, 10, 0);
        close.Click += (_, _) => Dismiss();
        var titlebar = new Grid { Height = 44, Background = Brushes.Transparent, Children = { title, close } };
        titlebar.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 1) try { DragMove(); } catch (InvalidOperationException) { } };
        var divider = new Border { Height = 1, Background = Ui.Brush("InspectLineBrush") };

        _text = new TextBox
        {
            IsReadOnly = true,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            FontFamily = Ui.UiFont,
            FontSize = 14,
            Foreground = Ui.Brush("InspectText2Brush"),
            SelectionBrush = Ui.Brush("AccentBrush"),
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Margin = new Thickness(Inset - 2, 24, Inset - 2, 16),
            Padding = new Thickness(0),
        };
        TextBlock.SetLineHeight(_text, 24);

        _count = new TextBlock { FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center };
        _copy = new Button { Content = L.T("Copy All"), Style = Ui.Style("InspectQuietButton"), HorizontalAlignment = HorizontalAlignment.Right };
        _copy.Click += (_, _) => CopyAll();
        var footer = new Grid { Height = 56, Margin = new Thickness(Inset, 0, Inset, 0), Children = { _count, _copy } };
        var footerRule = new Border { Height = 1, Background = Ui.Brush("InspectLineBrush") };

        var layout = new DockPanel();
        DockPanel.SetDock(titlebar, Dock.Top);
        DockPanel.SetDock(divider, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        DockPanel.SetDock(footerRule, Dock.Bottom);
        layout.Children.Add(titlebar);
        layout.Children.Add(divider);
        layout.Children.Add(footer);
        layout.Children.Add(footerRule);
        layout.Children.Add(_text);

        Content = new Border
        {
            Margin = new Thickness(FloatingWindow.ShadowMargin),
            Background = Ui.Brush("InspectInk1Brush"),
            BorderBrush = Ui.Brush("InspectLineStrongBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerMedium"),
            Effect = Ui.Effect("PanelShadow"),
            Child = layout,
        };

        _revert.Tick += (_, _) =>
        {
            _revert.Stop();
            _copy.Content = L.T("Copy All");
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Dismiss();
                e.Handled = true;
            }
        };
        owner.LocationChanged += (_, _) => Reposition();
        owner.SizeChanged += (_, _) => Reposition();
        owner.StateChanged += (_, _) => Reposition();
    }

    public event Action? Dismissed;

    public void ShowLoading()
    {
        _recognized = "";
        _copy.IsEnabled = false;
        SetText(L.T("Recognizing…"), "InspectText3Brush", 0);
    }

    public void ShowResult(string text)
    {
        _recognized = text;
        _copy.IsEnabled = text.Length > 0;
        SetText(text.Length == 0 ? L.T("No text found") : text, text.Length == 0 ? "InspectText3Brush" : "InspectText2Brush", text.Length);
        _text.ScrollToHome();
    }

    public void ShowMessage(string message)
    {
        _recognized = "";
        _copy.IsEnabled = false;
        SetText(message, "InspectText3Brush", 0);
    }

    public void ShowBeside()
    {
        if (!IsVisible) Show();
        Reposition();
    }

    public void Dismiss()
    {
        if (!IsVisible) return;
        Hide();
        Dismissed?.Invoke();
    }

    private void SetText(string text, string brush, int count)
    {
        _text.Text = text;
        _text.Foreground = Ui.Brush(brush);
        _count.Text = L.F("%d characters", count);
    }

    private void CopyAll()
    {
        if (_recognized.Length == 0 || !InspectImages.CopyText(_recognized)) return;
        _copy.Content = L.T("Copied ✓");
        _revert.Stop();
        _revert.Start();
    }

    /// <summary>Beside the owner, full owner height; left of it when the right has no room.</summary>
    private void Reposition()
    {
        if (!IsVisible) return;
        if (_owner.WindowState == WindowState.Minimized)
        {
            Hide();
            Dismissed?.Invoke();
            return;
        }
        var ownerHwnd = new WindowInteropHelper(_owner).Handle;
        var hwnd = new WindowInteropHelper(this).EnsureHandle();
        if (ownerHwnd == IntPtr.Zero) return;
        var ownerRect = ScreenGeometry.WindowRect(ownerHwnd);
        var monitor = ScreenGeometry.MonitorOf(ownerHwnd);
        var scale = monitor.Scale;
        var margin = (int)Math.Round(FloatingWindow.ShadowMargin * scale);
        var width = (int)Math.Ceiling((PanelWidth + FloatingWindow.ShadowMargin * 2) * scale);
        var gap = (int)Math.Round(2 * scale);
        var work = monitor.WorkArea;
        var height = Math.Min(ownerRect.Height, work.Height) + margin * 2;

        var x = ownerRect.Right + gap - margin;
        if (x + width - margin > work.Right) x = ownerRect.X - gap - width + margin;
        x = Math.Clamp(x, work.X - margin, work.Right - width + margin);
        var y = Math.Clamp(ownerRect.Y - margin, work.Y - margin, Math.Max(work.Y - margin, work.Bottom - height + margin));
        ScreenGeometry.SetWindowRect(hwnd, new PixelRect(x, y, width, height));
    }
}
