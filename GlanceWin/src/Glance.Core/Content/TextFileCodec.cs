using System.Globalization;
using System.Text;

namespace Glance.Core.Content;

/// <summary>Decoded file text plus the encoding needed to write it back unchanged.</summary>
public sealed record DecodedText(string Text, Encoding Encoding)
{
    public bool HasBom => Encoding.GetPreamble().Length > 0;
}

/// <summary>
/// Reads and writes text files the way Windows editors do: BOM first (UTF-8 / UTF-16),
/// then strict UTF-8, then the system ANSI code page (e.g. GBK on Chinese Windows).
/// Saving re-uses the detected encoding and BOM so a round trip doesn't rewrite the file.
/// </summary>
public static class TextFileCodec
{
    /// <summary>Files above this are not opened in the editor.</summary>
    public const long MaxEditableBytes = 64L * 1024 * 1024;

    private static readonly Encoding Utf8NoBom = new UTF8Encoding(false, false);
    private static readonly Encoding Utf8Bom = new UTF8Encoding(true, false);
    private static readonly Encoding Utf8Strict = new UTF8Encoding(false, true);

    static TextFileCodec()
    {
        // Makes GBK, Shift-JIS, Windows-125x etc. available on .NET.
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    public static Encoding Utf8 => Utf8NoBom;

    public static DecodedText Decode(byte[] bytes, Encoding? fallback = null)
    {
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            return new DecodedText(Utf8NoBom.GetString(bytes, 3, bytes.Length - 3), Utf8Bom);
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
            return new DecodedText(Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2), Encoding.Unicode);
        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
            return new DecodedText(Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2), Encoding.BigEndianUnicode);

        try
        {
            return new DecodedText(Utf8Strict.GetString(bytes), Utf8NoBom);
        }
        catch (DecoderFallbackException)
        {
            var legacy = fallback ?? AnsiEncoding();
            return new DecodedText(legacy.GetString(bytes), legacy);
        }
    }

    /// <summary>
    /// Encodes for saving: preamble + text. Throws <see cref="EncoderFallbackException"/> when a
    /// legacy code page can't represent a typed character, so the caller can offer UTF-8.
    /// </summary>
    public static byte[] Encode(string text, Encoding encoding)
    {
        var strict = encoding.CodePage switch
        {
            65001 => encoding, // UTF-8 represents everything
            1200 or 1201 => encoding,
            _ => Encoding.GetEncoding(encoding.CodePage, EncoderFallback.ExceptionFallback, DecoderFallback.ReplacementFallback),
        };
        var preamble = encoding.GetPreamble();
        var body = strict.GetBytes(text);
        if (preamble.Length == 0) return body;
        var result = new byte[preamble.Length + body.Length];
        preamble.CopyTo(result, 0);
        body.CopyTo(result, preamble.Length);
        return result;
    }

    /// <summary>
    /// Writes through a temp file in the same folder, then swaps it in (keeps attributes/ACLs).
    /// Falls back to a direct write where <see cref="File.Replace(string,string,string)"/> isn't supported.
    /// </summary>
    public static void WriteAtomic(string path, byte[] bytes)
    {
        var directory = Path.GetDirectoryName(path) ?? ".";
        var temp = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid().ToString("N")[..8]}.tmp");
        try
        {
            File.WriteAllBytes(temp, bytes);
            if (File.Exists(path))
            {
                try
                {
                    File.Replace(temp, path, null, ignoreMetadataErrors: true);
                    return;
                }
                catch (IOException)
                {
                    // e.g. some network shares / FAT volumes: write in place instead.
                }
                catch (PlatformNotSupportedException)
                {
                }
                File.WriteAllBytes(path, bytes);
            }
            else
            {
                File.Move(temp, path);
            }
        }
        catch (UnauthorizedAccessException) when (!File.Exists(temp))
        {
            // Folder not writable for temp files: try the file itself (it may still be writable).
            File.WriteAllBytes(path, bytes);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    public static Encoding AnsiEncoding()
    {
        try
        {
            var codePage = CultureInfo.CurrentCulture.TextInfo.ANSICodePage;
            return codePage is 0 or 65001 ? Encoding.Latin1 : Encoding.GetEncoding(codePage);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
        {
            return Encoding.Latin1;
        }
    }

    /// <summary>Short label for the toolbar, e.g. "UTF-8", "UTF-8 BOM", "GBK".</summary>
    public static string DisplayName(Encoding encoding) => encoding.CodePage switch
    {
        65001 => encoding.GetPreamble().Length > 0 ? "UTF-8 BOM" : "UTF-8",
        1200 => "UTF-16 LE",
        1201 => "UTF-16 BE",
        936 => "GBK",
        _ => encoding.WebName.ToUpperInvariant(),
    };
}
