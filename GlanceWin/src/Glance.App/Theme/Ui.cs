using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Glance.App.Theme;

/// <summary>
/// Code-side access to Tokens.xaml / Controls.xaml plus small builders shared by panels
/// (Windows counterpart of PanelStyle helpers such as <c>makeIconButton</c>).
/// Views must take colors/fonts from here, never literals.
/// </summary>
internal static class Ui
{
    public const string IconFontName = "Segoe MDL2 Assets";

    // Segoe MDL2 Assets glyphs (present on Windows 10 and 11).
    public const string GlyphClose = "\uE711";
    public const string GlyphOpen = "\uE8A7";
    public const string GlyphFolder = "\uE838";
    public const string GlyphPlay = "\uE768";
    public const string GlyphGlobe = "\uE774";
    public const string GlyphDocument = "\uE8A5";
    public const string GlyphWarning = "\uE7BA";
    public const string GlyphSearch = "\uE721";
    public const string GlyphPhoto = "\uEB9F";
    public const string GlyphMinimize = "\uE921";
    public const string GlyphMaximize = "\uE922";
    public const string GlyphRestore = "\uE923";
    public const string GlyphChromeClose = "\uE8BB";
    public const string GlyphUp = "\uE70E";
    public const string GlyphDown = "\uE70D";

    public const string GlyphAdd = "\uE710";
    public const string GlyphChevronRight = "\uE76C";

    // Shizuka line icons (macOS Assets.xcassets/Shizuka*.svg, 24-unit viewBox, 1.5 stroke).
    public const string IconImage = "M5,3 H19 A2,2 0 0 1 21,5 V19 A2,2 0 0 1 19,21 H5 A2,2 0 0 1 3,19 V5 A2,2 0 0 1 5,3 Z M7,9 A2,2 0 1 1 11,9 A2,2 0 1 1 7,9 Z M21,15 L17.914,11.914 A2,2 0 0 0 15.086,11.914 L6,21";
    public const string IconCompare = "M5,3 H19 A2,2 0 0 1 21,5 V19 A2,2 0 0 1 19,21 H5 A2,2 0 0 1 3,19 V5 A2,2 0 0 1 5,3 Z M12,3 V21";
    public const string IconAdjust = "M21,4 H14 M10,4 H3 M21,12 H12 M8,12 H3 M21,20 H16 M12,20 H3 M14,2 V6 M8,10 V14 M16,18 V22";
    public const string IconText = "M4,7 V4 H20 V7 M9,20 H15 M12,4 V20";
    public const string IconInfo = "M2,12 A10,10 0 1 1 22,12 A10,10 0 1 1 2,12 Z M12,16 V12 M12,8 H12.01";
    public const string IconMore = "M4,12 A1,1 0 1 1 6,12 A1,1 0 1 1 4,12 Z M11,12 A1,1 0 1 1 13,12 A1,1 0 1 1 11,12 Z M18,12 A1,1 0 1 1 20,12 A1,1 0 1 1 18,12 Z";
    public const string IconClose = "M6,6 L18,18 M18,6 L6,18";
    // Figma Shizuka line icons (24-unit geometry; the 16 px Figma assets are these scaled by 2/3).
    public const string IconTasks = "M8,6 H21 M8,12 H21 M8,18 H21 M3,6 H3.01 M3,12 H3.01 M3,18 H3.01";
    public const string IconHistory = "M3,12 A9,9 0 1 0 12,3 A9.75,9.75 0 0 0 5.26,5.74 L3,8 M3,3 V8 H8 M12,7 V12 L16,14";
    public const string IconSearch = "M19,11 A8,8 0 1 1 3,11 A8,8 0 1 1 19,11 Z M21,21 L16.7,16.7";
    public const string IconPlay = "M7,4.5 L19,12 L7,19.5 Z";
    public const string IconPause = "M8,5 V19 M16,5 V19";
    public const string IconCamera = "M14.5,4 H9.5 L7,7 H4 A2,2 0 0 0 2,9 V18 A2,2 0 0 0 4,20 H20 A2,2 0 0 0 22,18 V9 A2,2 0 0 0 20,7 H17 Z M9,13 A3,3 0 1 0 15,13 A3,3 0 1 0 9,13 Z";
    public const string IconGrid = "M3,3 H10 V10 H3 Z M14,3 H21 V10 H14 Z M14,14 H21 V21 H14 Z M3,14 H10 V21 H3 Z";
    public const string IconVideo = "M3,6 H15 A2,2 0 0 1 17,8 V16 A2,2 0 0 1 15,18 H3 A2,2 0 0 1 1,16 V8 A2,2 0 0 1 3,6 Z M17,10 L23,7 V17 L17,14";

    /// <summary>A Shizuka line icon drawn at <paramref name="size"/> DIPs (16 in the Inspect toolbar).</summary>
    /// <param name="strokeWidth">Stroke in 24-unit icon coordinates. Figma's Shizuka icons use 2.25
    /// (1.5 px at 16 px); the default 1.5 is the lighter weight used by the older chrome.</param>
    public static FrameworkElement LineIcon(string data, double size, string brushKey, double strokeWidth = 1.5)
    {
        var path = new System.Windows.Shapes.Path
        {
            Data = Geometry.Parse(data),
            Stroke = Brush(brushKey),
            StrokeThickness = strokeWidth,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round,
        };
        return new Viewbox
        {
            Width = size,
            Height = size,
            Stretch = Stretch.Uniform,
            Child = new Canvas { Width = 24, Height = 24, Children = { path } },
            IsHitTestVisible = false,
        };
    }

    /// <summary>A palette color as 0xAARRGGBB for the Core image encoders.</summary>
    public static uint Argb(string colorKey, double opacity = 1)
    {
        var c = Color(colorKey);
        var a = (uint)Math.Round(c.A * Math.Clamp(opacity, 0, 1));
        return (a << 24) | ((uint)c.R << 16) | ((uint)c.G << 8) | c.B;
    }

    public static Brush Brush(string key) => (Brush)Application.Current.FindResource(key);
    public static double Number(string key) => (double)Application.Current.FindResource(key);
    public static CornerRadius Corner(string key) => (CornerRadius)Application.Current.FindResource(key);
    public static Style Style(string key) => (Style)Application.Current.FindResource(key);
    public static Effect Effect(string key) => (Effect)Application.Current.FindResource(key);
    public static FontFamily UiFont => (FontFamily)Application.Current.FindResource("UIFont");
    public static FontFamily IconFont { get; } = new(IconFontName);
    public static FontFamily CodeFont => (FontFamily)Application.Current.FindResource("CodeFont");
    public static FontFamily TitleFont => (FontFamily)Application.Current.FindResource("TitleFont");
    public static FontFamily InterFont => (FontFamily)Application.Current.FindResource("InterFont");
    public static Color Color(string key) => (Color)Application.Current.FindResource(key);

    /// <summary>"#RRGGBB" for a palette color (HTML/CSS generated from the tokens).</summary>
    public static string CssHex(string colorKey)
    {
        var c = Color(colorKey);
        return $"#{c.R:X2}{c.G:X2}{c.B:X2}";
    }

    /// <summary>"rgba(r,g,b,a)" for a palette color at an alpha.</summary>
    public static string CssRgba(string colorKey, double alpha)
    {
        var c = Color(colorKey);
        return $"rgba({c.R},{c.G},{c.B},{alpha.ToString(System.Globalization.CultureInfo.InvariantCulture)})";
    }

    public static TextBlock Text(string text, string styleKey, TextTrimming trimming = TextTrimming.CharacterEllipsis) => new()
    {
        Text = text,
        Style = Style(styleKey),
        TextTrimming = trimming,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static TextBlock Glyph(string glyph, double size, string brushKey) => new()
    {
        Text = glyph,
        FontFamily = IconFont,
        FontSize = size,
        Foreground = Brush(brushKey),
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Square icon button: control fill, hover highlight, centered glyph.</summary>
    public static Button IconButton(string glyph, string tooltip, Action onClick, double size = 28)
    {
        var button = new Button
        {
            Width = size,
            Height = size,
            Padding = new Thickness(0),
            ToolTip = tooltip,
            Style = Style("SecondaryButton"),
            Content = Glyph(glyph, 12, "TextSecondaryBrush"),
            Focusable = false,
        };
        button.Click += (_, _) => onClick();
        return button;
    }

    /// <summary>Clips an element to a rounded rectangle that follows its size.</summary>
    public static void RoundClip(FrameworkElement element, double radius)
    {
        void Update() => element.Clip = new RectangleGeometry(new Rect(0, 0, element.ActualWidth, element.ActualHeight), radius, radius);
        element.SizeChanged += (_, _) => Update();
    }

    /// <summary>Makes a surface drag its window (header bars).</summary>
    public static void DragsWindow(UIElement element, Window window)
    {
        element.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ButtonState == MouseButtonState.Pressed && e.ClickCount == 1)
            {
                try { window.DragMove(); } catch (InvalidOperationException) { /* mouse released already */ }
            }
        };
    }

    /// <summary>Windows-style file size (base 1024: "1.4 MB").</summary>
    public static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        return unit == 0 ? $"{bytes} B" : $"{value:0.#} {units[unit]}";
    }
}
