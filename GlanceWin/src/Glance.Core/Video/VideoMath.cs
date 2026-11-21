using System.Globalization;
using Glance.Core.Imaging;

namespace Glance.Core.Video;

/// <summary>
/// Figma Shizuka <c>08 · Video Inspect</c> / <c>27 · Video Compare</c> geometry (port of macOS
/// <c>VideoInspectChromeLayout</c>), in top-origin DIPs: the 44 pt titlebar, the stage, a 28 pt
/// transport row 24 pt below the stage and 16 pt above the 92 pt bottom bar.
/// </summary>
public readonly record struct VideoChromeLayout(RectD Stage, RectD Transport)
{
    public const double TitlebarHeight = 44;
    public const double BottomBarHeight = 92;
    public const double TransportHeight = 28;
    public const double TransportTopGap = 24;
    public const double TransportBottomGap = 16;
    public const double CompareGap = 16;
    public const double CaptionGap = 16;
    public const double CaptionHeight = 40;
    public const double StageTopMargin = 28;
    public const double StageSideMargin = 44;
    public const double InfoPanelWidth = 320;
    /// <summary>Toasts clear the transport row and the bottom bar.</summary>
    public const double ToastInset = BottomBarHeight + TransportBottomGap + TransportHeight + 12;

    public static VideoChromeLayout For(SizeD size)
    {
        var transportTop = size.Height - BottomBarHeight - TransportBottomGap - TransportHeight;
        var transport = new RectD(0, transportTop, size.Width, TransportHeight);
        var bandTop = TitlebarHeight;
        var bandBottom = transportTop - TransportTopGap;
        var band = Math.Max(0, bandBottom - bandTop);
        var top = Math.Min(StageTopMargin, Math.Max(12, Math.Floor(band * 0.05)));
        var side = Math.Min(StageSideMargin, Math.Max(16, Math.Floor(size.Width * 0.04)));
        var stage = new RectD(side, bandTop + top, Math.Max(0, size.Width - side * 2), Math.Max(0, band - top));
        return new VideoChromeLayout(stage, transport);
    }

    /// <summary>A video aspect-fitted and centred in the stage (or the whole stage when its size is unknown).</summary>
    public static RectD FocusFrame(RectD stage, SizeD? natural)
    {
        if (natural is not { Width: > 0, Height: > 0 } n || stage.Width <= 0 || stage.Height <= 0) return stage;
        var fit = Math.Min(stage.Width / n.Width, stage.Height / n.Height);
        var w = n.Width * fit;
        var h = n.Height * fit;
        return new RectD(stage.X + (stage.Width - w) / 2, stage.Y + (stage.Height - h) / 2, w, h);
    }

    /// <summary>
    /// Compare: each complete video fitted beside the centred seam (16 pt apart), leaving room for
    /// the captions below; spare width stays at the outside edges.
    /// </summary>
    public static (RectD Left, RectD Right) CompareFrames(RectD stage, SizeD? left, SizeD? right)
    {
        var captionRoom = CaptionGap + CaptionHeight;
        var panes = new RectD(stage.X, stage.Y, stage.Width, Math.Max(1, stage.Height - captionRoom));
        var maxWidth = Math.Max(1, (panes.Width - CompareGap) / 2);
        var seam = panes.X + panes.Width / 2;
        var midY = panes.Y + panes.Height / 2;
        var l = Fitted(left);
        var r = Fitted(right);
        return (new RectD(seam - CompareGap / 2 - l.Width, midY - l.Height / 2, l.Width, l.Height),
                new RectD(seam + CompareGap / 2, midY - r.Height / 2, r.Width, r.Height));

        SizeD Fitted(SizeD? natural)
        {
            if (natural is not { Width: > 0, Height: > 0 } n) return new SizeD(maxWidth, panes.Height);
            var fit = Math.Min(maxWidth / n.Width, panes.Height / n.Height);
            return new SizeD(n.Width * fit, n.Height * fit);
        }
    }

    /// <summary>The transport lines up with the video in Focus, never narrower than 480 pt.</summary>
    public static (double X, double Width) TransportSpan(RectD stage, RectD shown, bool compare)
    {
        if (compare) return shown.Width > 0 ? (shown.X, shown.Width) : (stage.X, stage.Width);
        var width = Math.Min(stage.Width, Math.Max(shown.Width, 480));
        return (stage.X + (stage.Width - width) / 2, width);
    }

    /// <summary>
    /// Window content size in Focus: 1120 × 700 for landscape, 560 × 900 for portrait (window
    /// proportions don't follow the video); Compare uses the pair's combined size.
    /// </summary>
    public static SizeD PreferredWindowSize(bool compare, SizeD first, SizeD? second)
    {
        if (!compare || second is not { } b)
            return first.Width / Math.Max(1, first.Height) < 1 ? new SizeD(560, 900) : new SizeD(1120, 700);
        var height = Math.Max(first.Height, b.Height);
        var width = first.Width * height / Math.Max(1, first.Height) + b.Width * height / Math.Max(1, b.Height) + 2;
        return new SizeD(width, height);
    }
}

/// <summary>Text formatting and codec names for Video Inspect.</summary>
public static class VideoFormat
{
    /// <summary>"mm:ss" (minutes keep counting past an hour, as on macOS).</summary>
    public static string Time(double seconds)
    {
        var total = double.IsFinite(seconds) ? Math.Max(0, (int)Math.Floor(seconds)) : 0;
        return $"{total / 60:00}:{total % 60:00}";
    }

    /// <summary>"m:ss" for the information panel, or null when unknown.</summary>
    public static string? Duration(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return null;
        var total = (int)seconds;
        return $"{total / 60}:{total % 60:00}";
    }

    public static string? Bitrate(double? bitsPerSecond)
    {
        if (bitsPerSecond is not > 0 || !double.IsFinite(bitsPerSecond.Value)) return null;
        var value = bitsPerSecond.Value;
        return value >= 1_000_000
            ? (value / 1_000_000).ToString("0.0", CultureInfo.InvariantCulture) + " Mbps"
            : (value / 1_000).ToString("0", CultureInfo.InvariantCulture) + " kbps";
    }

    public static string? FrameRate(double? fps)
    {
        if (fps is not > 0 || !double.IsFinite(fps.Value)) return null;
        return Math.Round(fps.Value, 3).ToString("0.###", CultureInfo.InvariantCulture) + " fps";
    }

    /// <summary>A Windows FourCC (first character in the low byte) as text, e.g. 0x31637661 → "avc1".</summary>
    public static string FourCcText(uint code)
    {
        Span<char> chars = stackalloc char[4];
        for (var i = 0; i < 4; i++)
        {
            var b = (byte)((code >> (8 * i)) & 0xFF);
            if (b < 0x20 || b > 0x7E) return $"0x{code:X8}";
            chars[i] = (char)b;
        }
        return new string(chars).Trim();
    }

    /// <summary>Human names for common video codec FourCCs (matching the macOS labels).</summary>
    public static string VideoCodecName(string fourCc) => fourCc.ToLowerInvariant() switch
    {
        "avc1" or "avc3" or "h264" or "x264" => "H.264 / AVC",
        "hvc1" or "hev1" or "hevc" or "h265" => "H.265 / HEVC",
        "vp09" or "vp90" => "VP9",
        "vp80" or "vp08" => "VP8",
        "av01" => "AV1",
        "mp4v" or "fmp4" or "xvid" or "divx" or "dx50" => "MPEG-4 Part 2",
        "mp2v" or "mpg2" => "MPEG-2",
        "apch" => "ProRes 422 HQ",
        "apcn" => "ProRes 422",
        "apcs" => "ProRes 422 LT",
        "apco" => "ProRes 422 Proxy",
        "ap4h" or "ap4x" => "ProRes 4444",
        "dvh1" or "dvhe" => "Dolby Vision",
        "mjpg" or "jpeg" => "Motion JPEG",
        "wmv3" => "WMV 9",
        "wvc1" => "VC-1",
        _ => fourCc,
    };

    /// <summary>
    /// Audio codec from the shell's System.Audio.Format (a Media Foundation subtype GUID; the
    /// common ones are a WAVE_FORMAT tag in the first field of the base GUID).
    /// </summary>
    public static string? AudioCodecName(string? format)
    {
        if (string.IsNullOrWhiteSpace(format)) return null;
        if (!Guid.TryParse(format.Trim(), out var guid)) return format.Trim();
        switch (guid.ToString().ToLowerInvariant())
        {
            case "e06d802c-db46-11cf-b4d1-00805f6cbbea": return "AC-3";
            case "a7fb87af-2d02-42fb-a4d4-05cd93843bdd": return "E-AC-3";
        }
        var text = guid.ToString().ToLowerInvariant();
        if (!text.EndsWith("-0000-0010-8000-00aa00389b71", StringComparison.Ordinal)) return null;
        var tag = uint.Parse(text[..8], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return tag switch
        {
            0x1610 or 0x1600 or 0x00FF or 0x1602 => "AAC",
            0x0001 or 0x0003 => "LPCM",
            0x0055 => "MP3",
            0x0050 => "MPEG Audio",
            0x0092 or 0x2000 => "AC-3",
            0x704F => "Opus",
            0xF1AC => "FLAC",
            0x6C61 => "ALAC",
            0x0160 or 0x0161 => "WMA",
            0x0162 => "WMA Pro",
            0x0163 => "WMA Lossless",
            0x2001 => "DTS",
            _ => null,
        };
    }
}
