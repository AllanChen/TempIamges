using Glance.Core.Imaging;
using Glance.Core.Video;
using Xunit;

namespace Glance.Tests;

public class VideoChromeLayoutTests
{
    [Fact]
    public void DesignSizeLayoutMatchesFigma()
    {
        var layout = VideoChromeLayout.For(new SizeD(1554, 1012));
        // Transport: 16 pt above the 92 pt bottom bar.
        Assert.Equal(1012 - 92 - 16 - 28, layout.Transport.Y);
        // Stage: 44 pt side margins, 28 pt below the titlebar, 24 pt above the transport.
        Assert.Equal(44, layout.Stage.X);
        Assert.Equal(44 + 28, layout.Stage.Y);
        Assert.Equal(layout.Transport.Y - 24, layout.Stage.Bottom, 3);
        Assert.Equal(1554 - 88, layout.Stage.Width);
    }

    [Fact]
    public void SmallWindowKeepsPositiveStage()
    {
        var layout = VideoChromeLayout.For(new SizeD(560, 488));
        Assert.True(layout.Stage.Width > 0);
        Assert.True(layout.Stage.Height > 0);
        Assert.True(layout.Stage.X >= 16);
    }

    [Fact]
    public void FocusFrameAspectFitsAndCentres()
    {
        var stage = new RectD(0, 0, 1000, 500);
        var frame = VideoChromeLayout.FocusFrame(stage, new SizeD(1920, 1080));
        Assert.Equal(500 * 1920 / 1080.0, frame.Width, 3);
        Assert.Equal(500, frame.Height, 3);
        Assert.Equal(500, frame.MidX, 3);
        Assert.Equal(stage, VideoChromeLayout.FocusFrame(stage, null));
    }

    [Fact]
    public void CompareFramesMeetAtTheSeam()
    {
        var stage = new RectD(0, 0, 1016, 600);
        var (left, right) = VideoChromeLayout.CompareFrames(stage, new SizeD(1920, 1080), new SizeD(1080, 1920));
        Assert.Equal(508 - 8, left.Right, 3);
        Assert.Equal(508 + 8, right.X, 3);
        // Room for the 16 + 40 pt caption below the panes.
        Assert.True(left.Bottom <= 600 - 56 + 0.001);
        Assert.True(right.Bottom <= 600 - 56 + 0.001);
        Assert.Equal(1920 / 1080.0, left.Width / left.Height, 3);
    }

    [Fact]
    public void TransportIsAtLeast480WideInFocus()
    {
        var stage = new RectD(44, 72, 1000, 600);
        var (x, width) = VideoChromeLayout.TransportSpan(stage, new RectD(400, 72, 300, 600), compare: false);
        Assert.Equal(480, width);
        Assert.Equal(44 + (1000 - 480) / 2.0, x);
        var (cx, cw) = VideoChromeLayout.TransportSpan(stage, new RectD(100, 72, 800, 400), compare: true);
        Assert.Equal((100.0, 800.0), (cx, cw));
    }

    [Fact]
    public void PreferredWindowSizeFollowsOrientation()
    {
        Assert.Equal(new SizeD(1120, 700), VideoChromeLayout.PreferredWindowSize(false, new SizeD(1920, 1080), null));
        Assert.Equal(new SizeD(560, 900), VideoChromeLayout.PreferredWindowSize(false, new SizeD(1080, 1920), null));
        var pair = VideoChromeLayout.PreferredWindowSize(true, new SizeD(1920, 1080), new SizeD(1280, 720));
        Assert.Equal(1080, pair.Height);
        Assert.Equal(1920 + 1920 + 2, pair.Width, 3);
    }
}

public class VideoFormatTests
{
    [Theory]
    [InlineData(0, "00:00")]
    [InlineData(59.9, "00:59")]
    [InlineData(61, "01:01")]
    [InlineData(3725, "62:05")]
    [InlineData(-3, "00:00")]
    [InlineData(double.NaN, "00:00")]
    public void TimeIsMinutesAndSeconds(double seconds, string expected) => Assert.Equal(expected, VideoFormat.Time(seconds));

    [Fact]
    public void DurationAndRates()
    {
        Assert.Equal("1:05", VideoFormat.Duration(65));
        Assert.Null(VideoFormat.Duration(0));
        Assert.Equal("8.5 Mbps", VideoFormat.Bitrate(8_500_000));
        Assert.Equal("640 kbps", VideoFormat.Bitrate(640_000));
        Assert.Null(VideoFormat.Bitrate(null));
        Assert.Equal("29.97 fps", VideoFormat.FrameRate(29.97));
        Assert.Equal("30 fps", VideoFormat.FrameRate(30));
    }

    [Fact]
    public void FourCcAndCodecNames()
    {
        Assert.Equal("avc1", VideoFormat.FourCcText(0x31637661));
        Assert.Equal("H.264 / AVC", VideoFormat.VideoCodecName("H264"));
        Assert.Equal("H.265 / HEVC", VideoFormat.VideoCodecName("hvc1"));
        Assert.Equal("VP9", VideoFormat.VideoCodecName("VP90"));
        Assert.Equal("ABCD", VideoFormat.VideoCodecName("ABCD"));
        Assert.StartsWith("0x", VideoFormat.FourCcText(0x00000001));
    }

    [Fact]
    public void AudioCodecFromMediaFoundationSubtype()
    {
        Assert.Equal("AAC", VideoFormat.AudioCodecName("{00001610-0000-0010-8000-00AA00389B71}"));
        Assert.Equal("MP3", VideoFormat.AudioCodecName("00000055-0000-0010-8000-00aa00389b71"));
        Assert.Equal("AC-3", VideoFormat.AudioCodecName("{E06D802C-DB46-11CF-B4D1-00805F6CBBEA}"));
        Assert.Null(VideoFormat.AudioCodecName("{12345678-1234-1234-1234-123456789ABC}"));
        Assert.Null(VideoFormat.AudioCodecName(""));
        Assert.Equal("Vorbis", VideoFormat.AudioCodecName("Vorbis"));
    }
}
