using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Shell;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Platform;

namespace Glance.App.Shell;

/// <summary>
/// First-run guide (layout of macOS <c>OnboardingWindow</c>, Figma <c>12 · Onboarding / Permissions</c>,
/// 640 × 620). Windows needs no permissions, so the rows are the optional setup steps: the Peek
/// hotkey, "Open with Glance" in Explorer and starting with Windows. Continue, close and Esc all
/// mark the guide as shown.
/// </summary>
internal sealed class OnboardingWindow : Window
{
    private readonly IAppShell _shell;
    private readonly StackPanel _rows = new() { Margin = new Thickness(0, 32, 0, 0) };
    private string? _explorerError;
    private string? _startupError;

    public OnboardingWindow(IAppShell shell)
    {
        _shell = shell;
        Title = L.T("Welcome to Glance");
        Width = 640;
        Height = 620;
        ResizeMode = ResizeMode.NoResize;
        Background = Ui.Brush("InspectInk1Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 44,
            ResizeBorderThickness = new Thickness(0),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            UseAeroCaptionButtons = false,
        });

        var close = new Button
        {
            Content = new TextBlock { Text = Ui.GlyphChromeClose, FontFamily = Ui.IconFont, FontSize = 10 },
            ToolTip = L.T("Close"),
            Style = Ui.Style("CaptionCloseButton"),
            Height = 44,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
        };
        close.Click += (_, _) => Close();
        WindowChrome.SetIsHitTestVisibleInChrome(close, true);

        var column = new StackPanel { Width = 512, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 106, 0, 0) };
        column.Children.Add(new TextBlock { Text = L.T("Set up Glance"), FontSize = 30, Height = 38, Foreground = Ui.Brush("InspectText1Brush") });
        column.Children.Add(new TextBlock
        {
            Text = L.T("Peek works right away. These optional steps make Glance easier to reach. You can change them later in Preferences."),
            FontSize = 13,
            LineHeight = 21,
            Foreground = Ui.Brush("InspectText2Brush"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 10, 0, 0),
        });
        column.Children.Add(_rows);

        var footer = new Grid { Width = 512, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 40) };
        footer.Children.Add(new TextBlock { Text = L.T("You can change these anytime in Preferences."), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center });
        var proceed = new Button { Content = L.T("Continue"), Style = Ui.Style("InspectPrimaryButton"), Height = 32, MinWidth = 89, IsDefault = true, HorizontalAlignment = HorizontalAlignment.Right };
        proceed.Click += (_, _) => Close();
        footer.Children.Add(proceed);

        Content = new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            Child = new Grid { Children = { column, footer, close } },
        };

        _shell.HotkeyStateChanged += OnHotkeyStateChanged;
        _shell.Settings.Changed += OnSettingsChanged;
        Activated += (_, _) => RenderRows();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape)
            {
                Close();
                e.Handled = true;
            }
        };
        RenderRows();
    }

    public void Present()
    {
        if (!IsVisible)
        {
            var monitor = ScreenGeometry.MonitorAtCursor();
            ScreenManager.Place(this, ScreenManager.CenterFrame(new Size(Width, Height), monitor));
            Show();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel) return;
        _shell.HotkeyStateChanged -= OnHotkeyStateChanged;
        _shell.Settings.Changed -= OnSettingsChanged;
        _shell.Settings.Update(s => s with { OnboardingShown = true });
    }

    private void OnHotkeyStateChanged(object? sender, EventArgs e) => RenderRows();

    private void OnSettingsChanged(object? sender, Glance.Core.Settings.AppSettings settings) =>
        Dispatcher.BeginInvoke(new Action(RenderRows));

    private void RenderRows()
    {
        _rows.Children.Clear();
        var hotkey = _shell.Settings.Current.Hotkey.DisplayText;
        var registered = _shell.HotkeyRegistered;
        _rows.Children.Add(Step("01", L.T("Peek hotkey"), optional: false,
            registered ? L.F("Select a path, link or file name anywhere and press %@.", hotkey) : L.F("%@ is used by another app — choose another hotkey.", hotkey),
            registered ? "InspectText3Brush" : "FailureBrush",
            StepButton(L.T("Change"), primary: !registered, _shell.ShowPreferences)));

        FrameworkElement explorer = _shell.ExplorerIntegrationInstalled
            ? Done(L.T("Added"))
            : StepButton(L.T("Add"), primary: false, () =>
            {
                _explorerError = _shell.SetExplorerIntegration(true);
                RenderRows();
            });
        _rows.Children.Add(Step("02", L.T("Open with Glance"), optional: true,
            _explorerError ?? L.T("Add Glance to the right-click menu of images and videos in File Explorer."),
            _explorerError is null ? "InspectText3Brush" : "FailureBrush", explorer));

        FrameworkElement startup = _shell.Settings.Current.LaunchAtLogin
            ? Done(L.T("On"))
            : StepButton(L.T("Turn On"), primary: false, () =>
            {
                _startupError = _shell.SetLaunchAtLogin(true);
                RenderRows();
            });
        _rows.Children.Add(Step("03", L.T("Start with Windows"), optional: true,
            _startupError ?? L.T("Keep Glance ready in the notification area."),
            _startupError is null ? "InspectText3Brush" : "FailureBrush", startup));
    }

    private static FrameworkElement Step(string number, string heading, bool optional, string description, string descriptionBrush, FrameworkElement trailing)
    {
        var grid = new Grid { MinHeight = 69 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new TextBlock { Text = number, FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 17, 0, 0) });
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 12, 16, 12) };
        var line = new StackPanel { Orientation = Orientation.Horizontal };
        line.Children.Add(new TextBlock { Text = heading, FontSize = 14, Foreground = Ui.Brush("InspectText1Brush") });
        if (optional)
            line.Children.Add(new TextBlock { Text = L.T("Optional"), FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) });
        texts.Children.Add(line);
        texts.Children.Add(new TextBlock { Text = description, FontSize = 12, Foreground = Ui.Brush(descriptionBrush), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        trailing.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(trailing, 2);
        grid.Children.Add(trailing);
        return new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Child = grid };
    }

    private static FrameworkElement StepButton(string text, bool primary, Action onClick)
    {
        var button = new Button { Content = text, Style = Ui.Style(primary ? "InspectPrimaryButton" : "InspectQuietButton"), Height = 32, Padding = new Thickness(16, 0, 16, 0) };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static FrameworkElement Done(string text)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        panel.Children.Add(new TextBlock { Text = ((char)0xE73E).ToString(), FontFamily = Ui.IconFont, FontSize = 14, Foreground = Ui.Brush("SuccessBrush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        panel.Children.Add(new TextBlock { Text = text, FontSize = 12, Foreground = Ui.Brush("SuccessBrush"), VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }
}
