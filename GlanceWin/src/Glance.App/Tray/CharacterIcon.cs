using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Glance.Platform;
using Microsoft.Win32;

namespace Glance.App.Tray;

internal enum CharacterState { Default, PeekOff, LookLeft, LookRight, Blink }

/// <summary>
/// The tray character (port of macOS <c>MenuBarCharacterIcon</c>, Figma "Brand · App Icon" ›
/// "Tray · B · Peek"): a dome head with cut-out eyes on a rim, hands on the rim; Peek off covers the
/// eyes with the hands. Drawn from the 18 × 18 macOS geometry and rendered to an HICON at the tray
/// size (16 px × the system DPI scale).
/// </summary>
internal static class CharacterIcon
{
    // CLAUDE.md rule 24 exception: notification-area glyphs aren't tinted by Windows (unlike macOS
    // template images), so the glyph must contrast with the taskbar itself, not with the app theme.
    private static readonly Color GlyphOnLightTaskbar = Colors.Black;
    private static readonly Color GlyphOnDarkTaskbar = Colors.White;

    /// <summary>Renders <paramref name="state"/> as an HICON (caller owns it), or zero on failure.</summary>
    public static IntPtr Render(CharacterState state)
    {
        var px = TrayPixelSize();
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var scale = (px - 2) / 18.0;
            dc.PushTransform(new TranslateTransform(1, 1));
            dc.PushTransform(new ScaleTransform(scale, scale));
            var brush = new SolidColorBrush(TaskbarIsLight() ? GlyphOnLightTaskbar : GlyphOnDarkTaskbar);
            brush.Freeze();
            dc.DrawGeometry(brush, null, Shape(state));
            dc.Pop();
            dc.Pop();
        }
        var bitmap = new RenderTargetBitmap(px, px, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var pixels = new byte[px * px * 4];
        bitmap.CopyPixels(pixels, px * 4, 0);
        return TrayIcon.CreateIcon(px, pixels);
    }

    /// <summary>The 18-unit character geometry for a state (eyes and Peek-off cut-outs excluded).</summary>
    public static Geometry Shape(CharacterState state)
    {
        var head = new StreamGeometry();
        using (var ctx = head.Open())
        {
            ctx.BeginFigure(new Point(3.6, 13.4), isFilled: true, isClosed: true);
            ctx.BezierTo(new Point(3.6, 9.0), new Point(6.0, 5.6), new Point(9, 5.6), true, true);
            ctx.BezierTo(new Point(12.0, 5.6), new Point(14.4, 9.0), new Point(14.4, 13.4), true, true);
        }
        head.Freeze();

        Geometry cutouts;
        if (state == CharacterState.PeekOff)
        {
            cutouts = Group(new RectangleGeometry(new Rect(4.75, 8.25, 3.9, 2.9), 1.45, 1.45),
                new RectangleGeometry(new Rect(9.35, 8.25, 3.9, 2.9), 1.45, 1.45));
        }
        else if (state == CharacterState.Blink)
        {
            cutouts = Group(Pill(6.2, 9.4, 2.1, 0.7), Pill(9.7, 9.4, 2.1, 0.7));
        }
        else
        {
            var shift = state switch { CharacterState.LookLeft => -0.8, CharacterState.LookRight => 0.8, _ => 0 };
            const double d = 2.3;
            cutouts = Group(new EllipseGeometry(new Rect(7.25 - d / 2 + shift, 8.55, d, d)),
                new EllipseGeometry(new Rect(10.75 - d / 2 + shift, 8.55, d, d)));
        }

        Geometry shape = new CombinedGeometry(GeometryCombineMode.Exclude, head, cutouts);
        shape = new CombinedGeometry(GeometryCombineMode.Union, shape, Pill(1.4, 12.6, 15.2, 2.2));
        shape = state == CharacterState.PeekOff
            ? new CombinedGeometry(GeometryCombineMode.Union, shape, Group(Pill(5.15, 8.65, 3.1, 2.1), Pill(9.75, 8.65, 3.1, 2.1)))
            : new CombinedGeometry(GeometryCombineMode.Union, shape, Group(Pill(3.2, 11.6, 3.4, 2.1), Pill(11.4, 11.6, 3.4, 2.1)));
        shape.Freeze();
        return shape;
    }

    private static Geometry Pill(double x, double y, double w, double h) =>
        new RectangleGeometry(new Rect(x, y, w, h), h / 2, h / 2);

    private static GeometryGroup Group(params Geometry[] children)
    {
        var group = new GeometryGroup { FillRule = FillRule.Nonzero };
        foreach (var child in children) group.Children.Add(child);
        return group;
    }

    /// <summary>16 px at 100 %, scaled with the system DPI (20 / 24 / 32 px).</summary>
    public static int TrayPixelSize()
    {
        uint dpi = 96;
        try
        {
            dpi = GetDpiForSystem();
        }
        catch (EntryPointNotFoundException)
        {
        }
        return Math.Max(16, (int)Math.Round(16 * dpi / 96.0));
    }

    /// <summary>The taskbar follows "Choose your default Windows mode": 1 = light.</summary>
    public static bool TaskbarIsLight()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("SystemUsesLightTheme") is int value && value == 1;
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();
}
