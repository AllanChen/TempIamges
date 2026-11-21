using System.Runtime.InteropServices.WindowsRuntime;
using Glance.Core.Imaging;
using Glance.Core.Logging;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace Glance.Platform;

/// <summary>One recognized line, in source-image pixels (top-left origin).</summary>
public sealed record OcrLine(string Text, RectD Bounds);

/// <summary>Recognized text laid out in reading order, plus the line boxes.</summary>
public sealed record OcrOutput(string Text, IReadOnlyList<OcrLine> Lines);

/// <summary>
/// Text recognition for Image Inspect (macOS Vision → <c>Windows.Media.Ocr</c>). Uses the
/// first OCR language installed for the user's profile languages (Settings ▸ Time &amp;
/// Language ▸ Language adds OCR with the language pack). Runs off the UI thread.
/// </summary>
public static class OcrService
{
    /// <summary>False when Windows has no OCR language installed at all.</summary>
    public static bool IsAvailable
    {
        get
        {
            try { return OcrEngine.AvailableRecognizerLanguages.Count > 0; }
            catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException or TypeLoadException) { return false; }
        }
    }

    public static async Task<OcrOutput?> RecognizeAsync(PixelImage image, CancellationToken ct = default)
    {
        return await Task.Run(async () =>
        {
            var engine = OcrEngine.TryCreateFromUserProfileLanguages()
                         ?? OcrEngine.AvailableRecognizerLanguages.Select(OcrEngine.TryCreateFromLanguage).FirstOrDefault(e => e is not null);
            if (engine is null)
            {
                Log.Warning("OCR: no recognizer language is installed");
                return null;
            }

            var maxSide = (int)Math.Max(1, OcrEngine.MaxImageDimension);
            var source = ImageCodec.LimitSide(image, maxSide);
            var scaleX = (double)image.Width / source.Width;
            var scaleY = (double)image.Height / source.Height;

            using var bitmap = SoftwareBitmap.CreateCopyFromBuffer(source.Pixels.AsBuffer(), BitmapPixelFormat.Bgra8,
                source.Width, source.Height, BitmapAlphaMode.Premultiplied);
            var result = await engine.RecognizeAsync(bitmap).AsTask(ct);

            var lines = new List<OcrLine>();
            foreach (var line in result.Lines)
            {
                var words = line.Words.ToList();
                if (words.Count == 0) continue;
                var bounds = default(RectD);
                foreach (var word in words)
                {
                    var r = word.BoundingRect;
                    bounds = bounds.Union(new RectD(r.X * scaleX, r.Y * scaleY, r.Width * scaleX, r.Height * scaleY));
                }
                var text = OcrLayout.JoinWords(words.Select(w => w.Text));
                if (text.Length > 0) lines.Add(new OcrLine(text, bounds));
            }

            var (order, laidOut) = OcrLayout.Layout(lines.Select(l => new OcrLayout.Fragment(l.Text, l.Bounds)).ToList());
            Log.Info($"OCR: {lines.Count} line(s) recognized with {engine.RecognizerLanguage.LanguageTag}");
            return new OcrOutput(laidOut, order.Select(i => lines[i]).ToList());
        }, ct);
    }
}
