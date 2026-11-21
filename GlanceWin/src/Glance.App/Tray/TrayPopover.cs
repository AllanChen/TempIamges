using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Glance.App.Localization;
using Glance.App.Shell;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Platform;

namespace Glance.App.Tray;

/// <summary>
/// The tray popover (port of macOS <c>TrayPopoverPanel</c>, Figma <c>06 · Menu Bar Popover</c>):
/// 288 × 341, "Glance" with the Peek status and switch, then rows for Home, Tasks, Preferences, the
/// Peek hotkey (Windows stand-in for "Permissions"), Account, About and Quit. It activates so it can
/// close when it loses focus; every row closes it first.
/// </summary>
internal sealed class TrayPopover : Window
{
    private const double PanelWidth = 288;
    private const double PanelHeight = 341;
    private const double ShadowMargin = 12;

    private readonly IAppShell _shell;
    private readonly Border _panel;
    private DateTime _hiddenAt = DateTime.MinValue;

    public TrayPopover(IAppShell shell)
    {
        _shell = shell;
        Title = "Glance";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        Width = PanelWidth + ShadowMargin * 2;
        Height = PanelHeight + ShadowMargin * 2;
        WindowStartupLocation = WindowStartupLocation.Manual;
        _panel = new Border
        {
            Margin = new Thickness(ShadowMargin),
            Background = Ui.Brush("InspectInk2Brush"),
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Effect = Ui.Effect("PanelShadow"),
        };
        Content = _panel;
        Deactivated += (_, _) => HidePopover();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape)
            {
                HidePopover();
                e.Handled = true;
            }
        };
    }

    /// <summary>Opens near the cursor (the tray), or closes when it is open / was just closed by this click.</summary>
    public void Toggle()
    {
        if (IsVisible || (DateTime.UtcNow - _hiddenAt).TotalMilliseconds < 300)
        {
            HidePopover();
            return;
        }
        Build();
        var cursor = ScreenGeometry.CursorPosition();
        var monitor = ScreenGeometry.MonitorAt(cursor.X, cursor.Y);
        var scale = monitor.Scale;
        var w = (int)Math.Round(Width * scale);
        var h = (int)Math.Round(Height * scale);
        var gap = (int)Math.Round((6 - ShadowMargin) * scale);
        // Bottom-right at the cursor (the taskbar is usually at the bottom); clamped into the work area.
        var target = new PixelRect(cursor.X - w + (int)(ShadowMargin * scale), cursor.Y - h - gap, w, h);
        if (target.Y < monitor.WorkArea.Y) target = target with { Y = cursor.Y + (int)Math.Round(6 * scale) - (int)(ShadowMargin * scale) };
        ScreenManager.Place(this, ScreenManager.Clamp(target, monitor.WorkArea));
        Show();
        Activate();
        Focus();
    }

    private void HidePopover()
    {
        if (!IsVisible) return;
        _hiddenAt = DateTime.UtcNow;
        Hide();
    }

    private void Run(Action action)
    {
        HidePopover();
        Dispatcher.BeginInvoke(action);
    }

    /// <summary>Rebuilds the content with current state and strings (each time it opens).</summary>
    public void Build()
    {
        var settings = _shell.Settings.Current;
        var peekOn = settings.PeekEnabled;
        var root = new Canvas();

        root.Children.Add(At(new TextBlock { Text = "Glance", FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText1Brush") }, 17, 15));
        root.Children.Add(At(new System.Windows.Shapes.Ellipse { Width = 5, Height = 5, Fill = Ui.Brush(peekOn ? "SuccessBrush" : "InspectText4Brush") }, 17, 40));
        root.Children.Add(At(new TextBlock { Text = L.T(peekOn ? "Peek is on" : "Peek is off"), FontSize = 11, Foreground = Ui.Brush("InspectText3Brush") }, 28, 35));
        var toggle = Switch(peekOn, () => _shell.Settings.Update(s => s with { PeekEnabled = !s.PeekEnabled }));
        root.Children.Add(At(toggle, 241, 24));

        foreach (var y in new[] { 66.0, 197, 268 })
            root.Children.Add(At(new Border { Width = PanelWidth - 34, Height = 1, Background = Ui.Brush("InspectLineBrush") }, 17, y));

        var running = _shell.Account.Tasks.Records.Count(r => r.IsActive);
        root.Children.Add(At(Row(Ui.IconImage, L.T("Open Glance Home"), null, null, () => _shell.ShowHome()), 7, 72));
        root.Children.Add(At(Row(Ui.IconMore, L.T("Tasks"), running > 0 ? L.F("%d running", running) : null, "InfoBrush", () => _shell.Widgets.ShowTaskCenter()), 7, 102));
        root.Children.Add(At(Row(Ui.IconAdjust, L.T("Preferences..."), "Ctrl+,", "InspectText3Brush", () => _shell.ShowPreferences(), mono: true), 7, 132));
        var hotkey = settings.Hotkey.DisplayText;
        var hotkeyTrailing = !peekOn ? L.T("Off") : _shell.HotkeyRegistered ? hotkey : L.T("Action needed");
        var hotkeyBrush = !peekOn ? "InspectText3Brush" : _shell.HotkeyRegistered ? "SuccessBrush" : "FailureBrush";
        root.Children.Add(At(Row(Ui.IconText, L.T("Peek hotkey"), hotkeyTrailing, hotkeyBrush, () => _shell.ShowPreferences()), 7, 162));
        var credits = _shell.Account.Auth.IsSignedIn ? L.F("%d credits", _shell.Account.Credits ?? 0) : L.T("Sign in");
        root.Children.Add(At(Row(Ui.IconInfo, L.T("Account"), credits, "InspectText3Brush", () => _shell.Widgets.ShowAccount(null)), 7, 203));
        root.Children.Add(At(Row(null, L.T("About Glance"), null, null, () => _shell.ShowAbout(null), secondary: true), 7, 274));
        root.Children.Add(At(Row(null, L.T("Quit"), null, null, () => _shell.Quit(), secondary: true), 7, 304));
        _panel.Child = root;
    }

    private static UIElement At(UIElement element, double x, double y)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        return element;
    }

    /// <summary>A 274 × 30 row: icon at 10, label at 36 (10 without an icon), trailing text 10 from the edge.</summary>
    private Border Row(string? icon, string text, string? trailing, string? trailingBrush, Action action, bool mono = false, bool secondary = false)
    {
        var grid = new Grid();
        if (icon is not null)
        {
            var glyph = Ui.LineIcon(icon, 16, "InspectText2Brush");
            glyph.HorizontalAlignment = HorizontalAlignment.Left;
            glyph.VerticalAlignment = VerticalAlignment.Center;
            glyph.Margin = new Thickness(10, 0, 0, 0);
            grid.Children.Add(glyph);
        }
        grid.Children.Add(new TextBlock
        {
            Text = text,
            FontSize = 13,
            Foreground = Ui.Brush(secondary ? "InspectText2Brush" : "InspectText1Brush"),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(icon is null ? 10 : 36, 0, 0, 0),
        });
        if (trailing is not null)
        {
            var label = new TextBlock
            {
                Text = trailing,
                FontSize = mono ? 11 : 12,
                Foreground = Ui.Brush(trailingBrush ?? "InspectText3Brush"),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 10, 0),
            };
            if (mono) label.FontFamily = Ui.CodeFont;
            grid.Children.Add(label);
        }
        var row = new Border
        {
            Width = PanelWidth - 14,
            Height = 30,
            CornerRadius = Ui.Corner("CornerControl"),
            Background = Brushes.Transparent,
            Child = grid,
            Cursor = Cursors.Hand,
        };
        row.MouseEnter += (_, _) => row.Background = Ui.Brush("InspectHoverBrush");
        row.MouseLeave += (_, _) => row.Background = Brushes.Transparent;
        row.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            Run(action);
        };
        return row;
    }

    /// <summary>30 × 18 switch: accent track + ink knob when on, elevated track + tertiary knob when off.</summary>
    private Border Switch(bool on, Action toggle)
    {
        var knob = new System.Windows.Shapes.Ellipse
        {
            Width = 14,
            Height = 14,
            Fill = Ui.Brush(on ? "AccentInkBrush" : "InspectText3Brush"),
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(on ? 14 : 2, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        var track = new Border
        {
            Width = 30,
            Height = 18,
            CornerRadius = new CornerRadius(9),
            Background = Ui.Brush(on ? "AccentBrush" : "SurfaceElevatedBrush"),
            Child = new Grid { Children = { knob } },
            Cursor = Cursors.Hand,
            ToolTip = L.T(on ? "Peek is on" : "Peek is off"),
        };
        track.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            toggle();
            Build();
        };
        return track;
    }
}
