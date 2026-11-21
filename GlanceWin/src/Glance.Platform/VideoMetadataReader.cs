using Glance.Core.Logging;
using Glance.Core.Video;
using Windows.Storage;

namespace Glance.Platform;

/// <summary>Technical details of one local video (macOS <c>VideoTechnicalMetadata</c>). Every field is optional.</summary>
public sealed record VideoMetadata(
    int? Width,
    int? Height,
    double? DurationSeconds,
    double? FramesPerSecond,
    string? VideoCodec,
    string? AudioCodec,
    double? VideoBitrate,
    long? FileSize);

/// <summary>
/// Reads video metadata from the Windows property system (the same values Explorer shows), off the
/// UI thread. Remote videos have none: the player reports their size and duration.
/// </summary>
public static class VideoMetadataReader
{
    private const string FourCcKey = "System.Video.FourCC";
    private const string FrameRateKey = "System.Video.FrameRate";
    private const string EncodingBitrateKey = "System.Video.EncodingBitrate";
    private const string FrameWidthKey = "System.Video.FrameWidth";
    private const string FrameHeightKey = "System.Video.FrameHeight";
    private const string DurationKey = "System.Media.Duration";
    private const string AudioFormatKey = "System.Audio.Format";
    private const string SizeKey = "System.Size";

    public static Task<VideoMetadata?> ReadAsync(string path, CancellationToken ct = default) => Task.Run(async () =>
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path).AsTask(ct).ConfigureAwait(false);
            var values = await file.Properties.RetrievePropertiesAsync(
                [FourCcKey, FrameRateKey, EncodingBitrateKey, FrameWidthKey, FrameHeightKey, DurationKey, AudioFormatKey, SizeKey])
                .AsTask(ct).ConfigureAwait(false);

            string? codec = null;
            if (Number(values, FourCcKey) is { } fourCc && fourCc > 0)
                codec = VideoFormat.VideoCodecName(VideoFormat.FourCcText((uint)fourCc));
            // FrameRate is frames per 1000 seconds; Duration is in 100 ns units.
            var fps = Number(values, FrameRateKey) is { } rate && rate > 0 ? rate / 1000.0 : (double?)null;
            var bitrate = Number(values, EncodingBitrateKey) is { } bps && bps > 0 ? bps : (double?)null;
            var duration = Number(values, DurationKey) is { } ticks && ticks > 0 ? ticks / 10_000_000.0 : (double?)null;
            var width = Number(values, FrameWidthKey) is { } w && w > 0 ? (int)w : (int?)null;
            var height = Number(values, FrameHeightKey) is { } h && h > 0 ? (int)h : (int?)null;
            var size = Number(values, SizeKey) is { } bytes && bytes >= 0 ? (long)bytes : (long?)null;
            var audio = VideoFormat.AudioCodecName(values.TryGetValue(AudioFormatKey, out var format) ? format?.ToString() : null);
            return new VideoMetadata(width, height, duration, fps, codec, audio, bitrate, size);
        }
        catch (OperationCanceledException)
        {
            return null;
        }
        catch (Exception ex)
        {
            Log.Info($"VideoMetadataReader: no properties for '{Log.Redact(path)}': {ex.GetType().Name}");
            return null;
        }
    }, ct);

    private static double? Number(IDictionary<string, object> values, string key)
    {
        if (!values.TryGetValue(key, out var value) || value is null) return null;
        try
        {
            return Convert.ToDouble(value, System.Globalization.CultureInfo.InvariantCulture);
        }
        catch (Exception ex) when (ex is FormatException or InvalidCastException or OverflowException)
        {
            return null;
        }
    }
}
