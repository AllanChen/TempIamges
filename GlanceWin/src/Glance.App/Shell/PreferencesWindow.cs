using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Shell;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Settings;
using Glance.Platform;

namespace Glance.App.Shell;

/// <summary>
/// Preferences (port of macOS <c>PreferencesWindow</c>, Figma <c>05 · Preferences</c>): a 212 pt
/// sidebar (General, Peek, Language pages; Account, First-run guide and About open their own
/// windows) and a scrolling content column of 64 pt rows with a trailing control. Every change is
/// saved immediately; the footer resets everything.
/// </summary>
internal sealed class PreferencesWindow : Window
{
    private enum Page { General, Peek, Language }

    private const string IconUser = "M20,21 V19 A4,4 0 0 0 16,15 H8 A4,4 0 0 0 4,19 V21 M8,7 A4,4 0 1 0 16,7 A4,4 0 1 0 8,7 Z";
    private const string IconShield = "M12,22 C12,22 20,18 20,12 V5 L12,2 L4,5 V12 C4,18 12,22 12,22 Z";
    private const string IconGlobe = "M2,12 A10,10 0 1 0 22,12 A10,10 0 1 0 2,12 Z M2,12 H22 M12,2 A15,15 0 0 1 12,22 A15,15 0 0 1 12,2 Z";

    private readonly IAppShell _shell;
    private readonly StackPanel _sidebar = new() { Margin = new Thickness(12, 16, 12, 0) };
    private readonly StackPanel _content = new() { Margin = new Thickness(64, 40, 64, 32) };
    private readonly ScrollViewer _scroll;
    private Page _page = Page.General;
    private bool _quitting;
    private bool _recording;
    private bool _customSelected;
    private string? _generalError;
    private string? _explorerError;
    private string? _hotkeyError;

    public PreferencesWindow(IAppShell shell)
    {
        _shell = shell;
        Title = L.T("Preferences");
        Width = 960;
        Height = 720;
        MinWidth = 860;
        MinHeight = 560;
        Background = Ui.Brush("InspectInk1Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 39,
            ResizeBorderThickness = new Thickness(5),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            UseAeroCaptionButtons = false,
        });
        _customSelected = shell.Settings.Current.Hotkey != Hotkey.Default && shell.Settings.Current.Hotkey != CtrlAltQ;

        var title = new TextBlock { Text = L.T("Preferences"), FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Ui.Brush("InspectText2Brush"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 14, 0, 0), IsHitTestVisible = false };
        var captions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
        captions.Children.Add(CaptionButton(Ui.GlyphMinimize, L.T("Minimize"), "CaptionButton", () => WindowState = WindowState.Minimized));
        captions.Children.Add(CaptionButton(Ui.GlyphMaximize, L.T("Maximize"), "CaptionButton", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized));
        captions.Children.Add(CaptionButton(Ui.GlyphChromeClose, L.T("Close"), "CaptionCloseButton", Close));

        var body = new Grid { Margin = new Thickness(0, 44, 0, 0) };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(212) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        body.ColumnDefinitions.Add(new ColumnDefinition());
        body.RowDefinitions.Add(new RowDefinition());
        body.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
        body.Children.Add(_sidebar);
        Grid.SetRowSpan(_sidebar, 2);
        var divider = new Border { Background = Ui.Brush("InspectLineBrush") };
        Grid.SetColumn(divider, 1);
        Grid.SetRowSpan(divider, 2);
        body.Children.Add(divider);
        _scroll = new ScrollViewer { Content = _content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(_scroll, 2);
        body.Children.Add(_scroll);

        var footer = new Grid { Margin = new Thickness(64, 0, 64, 0) };
        footer.Children.Add(new TextBlock { Text = L.T("Changes are saved automatically"), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center });
        var reset = new Button { Content = L.T("Reset to Defaults"), Style = Ui.Style("InspectTextButton"), FontSize = 12, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        reset.Click += (_, _) =>
        {
            _customSelected = false;
            _generalError = _explorerError = _hotkeyError = null;
            _shell.Settings.ResetToDefaults();
            Render();
        };
        footer.Children.Add(reset);
        Grid.SetColumn(footer, 2);
        Grid.SetRow(footer, 1);
        body.Children.Add(footer);

        Content = new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            Child = new Grid { Children = { body, title, captions } },
        };

        _shell.Settings.Changed += OnSettingsChanged;
        _shell.HotkeyStateChanged += OnHotkeyStateChanged;
        Closed += (_, _) =>
        {
            _shell.Settings.Changed -= OnSettingsChanged;
            _shell.HotkeyStateChanged -= OnHotkeyStateChanged;
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape && !_recording)
            {
                Close();
                e.Handled = true;
            }
        };
        Render();
    }

    private static Hotkey CtrlAltQ { get; } = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, Hotkey.VkQ);

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

    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel || _quitting) return;
        e.Cancel = true;
        _recording = false;
        Hide();
    }

    private void OnSettingsChanged(object? sender, AppSettings settings) =>
        Dispatcher.BeginInvoke(new Action(() =>
        {
            if (!_recording) Render();
        }));

    private void OnHotkeyStateChanged(object? sender, EventArgs e)
    {
        if (!_recording) Render();
    }

    // ───────────────────────────── Rendering ─────────────────────────────

    private void Render()
    {
        RenderSidebar();
        _content.Children.Clear();
        switch (_page)
        {
            case Page.General: RenderGeneral(); break;
            case Page.Peek: RenderPeek(); break;
            case Page.Language: RenderLanguage(); break;
        }
    }

    private void RenderSidebar()
    {
        _sidebar.Children.Clear();
        _sidebar.Children.Add(SidebarItem(Ui.IconAdjust, L.T("General"), _page == Page.General, () => Navigate(Page.General)));
        _sidebar.Children.Add(SidebarItem(Ui.IconImage, L.T("Peek"), _page == Page.Peek, () => Navigate(Page.Peek)));
        _sidebar.Children.Add(SidebarItem(IconGlobe, L.T("Language"), _page == Page.Language, () => Navigate(Page.Language)));
        _sidebar.Children.Add(SidebarItem(IconUser, L.T("Account"), false, () => _shell.Widgets.ShowAccount(this)));
        _sidebar.Children.Add(SidebarItem(IconShield, L.T("First-run guide"), false, _shell.ShowOnboarding));
        _sidebar.Children.Add(SidebarItem(Ui.IconInfo, L.T("About Glance"), false, () => _shell.ShowAbout(this)));
    }

    private void Navigate(Page page)
    {
        _page = page;
        _recording = false;
        Render();
        _scroll.ScrollToTop();
    }

    private void RenderGeneral()
    {
        Heading(L.T("General"), L.T("Control startup and how Glance works with File Explorer."));
        var startup = Group(L.T("Startup"));
        startup.Children.Add(Row(L.T("Start Glance with Windows"), L.T("Keep Glance ready in the notification area when you sign in."),
            new Switch(_shell.Settings.Current.LaunchAtLogin, value =>
            {
                _generalError = _shell.SetLaunchAtLogin(value);
                Render();
            }), _generalError));
        var explorer = Group(L.T("Explorer"));
        explorer.Children.Add(Row(L.T("Open with Glance in File Explorer"), L.T("Adds “Open with Glance” to the right-click menu of images and videos."),
            new Switch(_shell.ExplorerIntegrationInstalled, value =>
            {
                _explorerError = _shell.SetExplorerIntegration(value);
                Render();
            }), _explorerError));
        var defaults = new Button { Content = L.T("Open Default Apps"), Style = Ui.Style("InspectQuietButton"), Height = 32 };
        defaults.Click += (_, _) => ExplorerIntegration.OpenDefaultAppsSettings();
        explorer.Children.Add(Row(L.T("Default image viewer"), L.T("Windows lets you choose the default app in Settings."), defaults));
    }

    private void RenderPeek()
    {
        var settings = _shell.Settings.Current;
        Heading(L.T("Peek"), L.T("Preview the selected text with the activation hotkey."));
        var peek = Group(L.T("Peek"));
        peek.Children.Add(Row(L.T("Enable Peek"), L.T("Show Peek when you press the activation hotkey."),
            new Switch(settings.PeekEnabled, value => _shell.Settings.Update(s => s with { PeekEnabled = value }))));

        var hotkey = settings.Hotkey;
        var selected = _customSelected ? 2 : hotkey == Hotkey.Default ? 0 : hotkey == CtrlAltQ ? 1 : 2;
        string help;
        var helpBrush = "InspectText3Brush";
        if (!settings.PeekEnabled)
        {
            help = L.T("No hotkey while Peek is disabled.");
        }
        else if (!_shell.HotkeyRegistered)
        {
            help = L.F("%@ is used by another app. Choose another hotkey.", hotkey.DisplayText);
            helpBrush = "FailureBrush";
        }
        else
        {
            help = L.F("Press %@ to show or hide Peek.", hotkey.DisplayText);
        }
        var segments = Segments([L.T("Alt + Q"), L.T("Ctrl + Alt + Q"), L.T("Custom")], selected, index =>
        {
            _hotkeyError = null;
            _customSelected = index == 2;
            if (index == 0) _shell.Settings.Update(s => s with { Hotkey = Hotkey.Default });
            else if (index == 1) _shell.Settings.Update(s => s with { Hotkey = CtrlAltQ });
            Render();
        });
        peek.Children.Add(Row(L.T("Activation hotkey"), help, segments, helpBrush: helpBrush));
        if (selected == 2)
            peek.Children.Add(Row(L.T("Custom shortcut"), L.T("Click the field, then press a key with Ctrl, Alt, Shift or Win."), Recorder(hotkey), _hotkeyError));

        var clipboard = Group(L.T("Clipboard"));
        clipboard.Children.Add(Row(L.T("Read clipboard when nothing is selected"), L.T("Peek copies the selection with Ctrl+C when it can't read it directly."),
            new Switch(settings.ReadClipboard, value => _shell.Settings.Update(s => s with { ReadClipboard = value }))));
    }

    private void RenderLanguage()
    {
        Heading(L.T("Language"), L.T("Choose the language Glance uses."));
        var group = Group(L.T("Language"));
        var chinese = string.Concat((char)0x7B80, (char)0x4F53, (char)0x4E2D, (char)0x6587);
        var options = new (string Name, AppLanguage Value)[] { ("English", AppLanguage.English), (chinese, AppLanguage.Chinese) };
        var current = _shell.Settings.Current.Language;
        group.Children.Add(Row(L.T("Interface language"), L.T("Open windows switch when you reopen them."),
            Selection(options.Select(o => o.Name).ToList(), Array.FindIndex(options, o => o.Value == current), index =>
            {
                if (options[index].Value != current) _shell.SetLanguage(options[index].Value);
            })));
    }

    // ───────────────────────────── Hotkey recorder ─────────────────────────────

    private FrameworkElement Recorder(Hotkey current)
    {
        var text = new TextBlock
        {
            Text = current.DisplayText,
            FontFamily = Ui.CodeFont,
            FontSize = 12,
            Foreground = Ui.Brush("InspectText1Brush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var box = new Border
        {
            Width = 160,
            Height = 35,
            Background = Ui.Brush("InspectInk2Brush"),
            BorderBrush = Ui.Brush("InspectText3Brush"),
            BorderThickness = new Thickness(1),
            CornerRadius = Ui.Corner("CornerControl"),
            Child = text,
            Focusable = true,
            Cursor = Cursors.Hand,
            ToolTip = L.T("Click to record shortcut"),
        };
        void Stop(bool restore)
        {
            _recording = false;
            if (restore) text.Text = _shell.Settings.Current.Hotkey.DisplayText;
            text.Foreground = Ui.Brush("InspectText1Brush");
        }
        box.MouseLeftButtonDown += (_, e) =>
        {
            _recording = true;
            text.Text = L.T("Press shortcut...");
            text.Foreground = Ui.Brush("InspectText3Brush");
            box.Focus();
            Keyboard.Focus(box);
            e.Handled = true;
        };
        box.LostKeyboardFocus += (_, _) =>
        {
            if (_recording) Stop(restore: true);
        };
        box.PreviewKeyDown += (_, e) =>
        {
            if (!_recording) return;
            e.Handled = true;
            var key = e.Key == System.Windows.Input.Key.System ? e.SystemKey : e.Key;
            if (key == System.Windows.Input.Key.Escape && Keyboard.Modifiers == ModifierKeys.None)
            {
                Stop(restore: true);
                return;
            }
            var modifiers = HotkeyModifiers.None;
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= HotkeyModifiers.Control;
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= HotkeyModifiers.Alt;
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= HotkeyModifiers.Shift;
            if (Keyboard.IsKeyDown(System.Windows.Input.Key.LWin) || Keyboard.IsKeyDown(System.Windows.Input.Key.RWin)) modifiers |= HotkeyModifiers.Win;
            if (IsModifierKey(key))
            {
                text.Text = modifiers == HotkeyModifiers.None ? L.T("Press shortcut...") : new Hotkey(modifiers, 0).DisplayText.Replace("+0x00", "+…");
                return;
            }
            if (modifiers == HotkeyModifiers.None) return;
            var candidate = new Hotkey(modifiers, KeyInterop.VirtualKeyFromKey(key));
            if (!candidate.IsValid) return;
            Stop(restore: false);
            if (IsReserved(candidate))
            {
                _hotkeyError = L.F("%@ is reserved by Windows.", candidate.DisplayText);
                Render();
                return;
            }
            _hotkeyError = null;
            _customSelected = true;
            _shell.Settings.Update(s => s with { Hotkey = candidate });
            Render();
        };
        return box;
    }

    private static bool IsModifierKey(System.Windows.Input.Key key) => key is System.Windows.Input.Key.LeftCtrl or System.Windows.Input.Key.RightCtrl
        or System.Windows.Input.Key.LeftAlt or System.Windows.Input.Key.RightAlt or System.Windows.Input.Key.LeftShift
        or System.Windows.Input.Key.RightShift or System.Windows.Input.Key.LWin or System.Windows.Input.Key.RWin;

    /// <summary>Shortcuts Windows keeps for itself (window menu, switcher, close, lock).</summary>
    private static bool IsReserved(Hotkey hotkey)
    {
        const int space = 0x20, tab = 0x09, f4 = 0x73, l = 0x4C;
        if (hotkey.Modifiers == HotkeyModifiers.Alt && hotkey.VirtualKey is space or tab or f4) return true;
        return hotkey.Modifiers == HotkeyModifiers.Win && hotkey.VirtualKey == l;
    }

    // ───────────────────────────── Builders ─────────────────────────────

    private void Heading(string text, string summary)
    {
        _content.Children.Add(new TextBlock { Text = text, FontSize = 28, Height = 36, Foreground = Ui.Brush("InspectText1Brush") });
        _content.Children.Add(new TextBlock { Text = summary, FontSize = 13, Foreground = Ui.Brush("InspectText2Brush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) });
    }

    private StackPanel Group(string label)
    {
        var group = new StackPanel { Margin = new Thickness(0, _content.Children.Count <= 2 ? 36 : 32, 0, 0) };
        group.Children.Add(new TextBlock { Text = label, FontSize = 12, Height = 15, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(0, 0, 0, 6) });
        _content.Children.Add(group);
        return group;
    }

    private static FrameworkElement Row(string title, string help, FrameworkElement control, string? error = null, string helpBrush = "InspectText3Brush")
    {
        var grid = new Grid { MinHeight = 64 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 16, 10) };
        texts.Children.Add(new TextBlock { Text = title, FontSize = 13, Foreground = Ui.Brush("InspectText1Brush"), TextWrapping = TextWrapping.Wrap });
        texts.Children.Add(new TextBlock { Text = help, FontSize = 12, Foreground = Ui.Brush(helpBrush), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
        if (!string.IsNullOrEmpty(error))
            texts.Children.Add(new TextBlock { Text = error, FontSize = 12, Foreground = Ui.Brush("FailureBrush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
        grid.Children.Add(texts);
        control.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(control, 1);
        grid.Children.Add(control);
        return new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Child = grid };
    }

    private static FrameworkElement SidebarItem(string icon, string text, bool selected, Action onClick)
    {
        var content = new Grid { Width = 188, Height = 30 };
        var glyph = Ui.LineIcon(icon, 16, selected ? "InspectText1Brush" : "InspectText3Brush");
        glyph.HorizontalAlignment = HorizontalAlignment.Left;
        glyph.Margin = new Thickness(10, 0, 0, 0);
        content.Children.Add(glyph);
        content.Children.Add(new TextBlock { Text = text, FontSize = 13, Foreground = Ui.Brush(selected ? "InspectText1Brush" : "InspectText2Brush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(36, 0, 0, 0) });
        var item = new Border
        {
            Width = 188,
            Height = 30,
            CornerRadius = Ui.Corner("CornerControl"),
            Background = selected ? Ui.Brush("InspectInk3Brush") : Brushes.Transparent,
            Child = content,
            Cursor = Cursors.Hand,
            Margin = new Thickness(0, 0, 0, 2),
        };
        item.MouseEnter += (_, _) =>
        {
            if (!selected) item.Background = Ui.Brush("InspectHoverBrush");
        };
        item.MouseLeave += (_, _) =>
        {
            if (!selected) item.Background = Brushes.Transparent;
        };
        item.MouseLeftButtonUp += (_, _) => onClick();
        return item;
    }

    private static FrameworkElement Segments(IReadOnlyList<string> labels, int selected, Action<int> onSelect)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2) };
        for (var i = 0; i < labels.Count; i++)
        {
            var index = i;
            var on = i == selected;
            var segment = new Border
            {
                Height = 23,
                Padding = new Thickness(10, 0, 10, 0),
                CornerRadius = new CornerRadius(5),
                Background = on ? Ui.Brush("InspectInk1Brush") : Brushes.Transparent,
                Margin = new Thickness(i == 0 ? 0 : 2, 0, 0, 0),
                Cursor = Cursors.Hand,
                Child = new TextBlock { Text = labels[i], FontSize = 12, Foreground = Ui.Brush(on ? "InspectText1Brush" : "InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center },
            };
            segment.MouseLeftButtonUp += (_, _) => onSelect(index);
            panel.Children.Add(segment);
        }
        return new Border { Background = Ui.Brush("InspectInk3Brush"), CornerRadius = new CornerRadius(7), Child = panel };
    }

    private static FrameworkElement Selection(IReadOnlyList<string> options, int selected, Action<int> onSelect)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Cursor = Cursors.Hand, Background = Brushes.Transparent };
        row.Children.Add(new TextBlock { Text = selected >= 0 ? options[selected] : "", FontSize = 13, Foreground = Ui.Brush("InspectText2Brush"), VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(new TextBlock { Text = Ui.GlyphDown, FontFamily = Ui.IconFont, FontSize = 10, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) });
        row.MouseLeftButtonUp += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = row, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
            for (var i = 0; i < options.Count; i++)
            {
                var index = i;
                var item = new MenuItem { Header = options[i], IsChecked = i == selected };
                item.Click += (_, _) => onSelect(index);
                menu.Items.Add(item);
            }
            menu.IsOpen = true;
        };
        return row;
    }

    private static Button CaptionButton(string glyph, string tooltip, string styleKey, Action onClick)
    {
        var button = new Button
        {
            Content = new TextBlock { Text = glyph, FontFamily = Ui.IconFont, FontSize = 10, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            ToolTip = tooltip,
            Style = Ui.Style(styleKey),
            Height = 44,
        };
        button.Click += (_, _) => onClick();
        WindowChrome.SetIsHitTestVisibleInChrome(button, true);
        return button;
    }

    /// <summary>The Shizuka toggle: 30 × 18 pill with a 14 pt knob, 0.18 s slide.</summary>
    private sealed class Switch : Border
    {
        private readonly Ellipse _knob = new() { Width = 14, Height = 14, HorizontalAlignment = HorizontalAlignment.Left };
        private readonly TranslateTransform _offset = new();
        private readonly Action<bool> _changed;
        private bool _on;

        public Switch(bool on, Action<bool> changed)
        {
            _on = on;
            _changed = changed;
            Width = 30;
            Height = 18;
            CornerRadius = new CornerRadius(9);
            Focusable = true;
            Cursor = Cursors.Hand;
            _knob.RenderTransform = _offset;
            _knob.Margin = new Thickness(0, 2, 0, 2);
            Child = _knob;
            Apply(animated: false);
            MouseLeftButtonUp += (_, e) =>
            {
                Toggle();
                e.Handled = true;
            };
            KeyDown += (_, e) =>
            {
                if (e.Key is System.Windows.Input.Key.Space or System.Windows.Input.Key.Enter)
                {
                    Toggle();
                    e.Handled = true;
                }
            };
        }

        private void Toggle()
        {
            _on = !_on;
            Apply(animated: true);
            _changed(_on);
        }

        private void Apply(bool animated)
        {
            Background = Ui.Brush(_on ? "InspectText1Brush" : "InspectInk3Brush");
            _knob.Fill = Ui.Brush(_on ? "InspectInk1Brush" : "InspectText3Brush");
            var x = _on ? 14 : 2;
            if (animated) _offset.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(x, TimeSpan.FromMilliseconds(180)));
            else
            {
                _offset.BeginAnimation(TranslateTransform.XProperty, null);
                _offset.X = x;
            }
        }
    }
}
