using System.Text;

namespace Glance.Core.Localization;

/// <summary>
/// Parser for Apple <c>Localizable.strings</c> files (<c>"key" = "value";</c> with <c>/* */</c> and
/// <c>//</c> comments and C-style escapes). The Windows client reuses the macOS translation files
/// as-is, so both clients share one set of keys.
/// </summary>
public static class StringsFile
{
    public static IReadOnlyDictionary<string, string> Parse(string text)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var i = 0;
        while (true)
        {
            SkipTrivia(text, ref i);
            if (i >= text.Length) break;
            if (text[i] != '"')
            {
                // Not an entry: skip to the end of the line.
                while (i < text.Length && text[i] != '\n') i++;
                continue;
            }
            var key = ReadString(text, ref i);
            SkipTrivia(text, ref i);
            if (key is null || i >= text.Length || text[i] != '=') continue;
            i++;
            SkipTrivia(text, ref i);
            if (i >= text.Length || text[i] != '"') continue;
            var value = ReadString(text, ref i);
            SkipTrivia(text, ref i);
            if (i < text.Length && text[i] == ';') i++;
            if (value is not null) result[key] = value;
        }
        return result;
    }

    private static void SkipTrivia(string s, ref int i)
    {
        while (i < s.Length)
        {
            if (char.IsWhiteSpace(s[i]))
            {
                i++;
            }
            else if (s[i] == '/' && i + 1 < s.Length && s[i + 1] == '*')
            {
                var end = s.IndexOf("*/", i + 2, StringComparison.Ordinal);
                i = end < 0 ? s.Length : end + 2;
            }
            else if (s[i] == '/' && i + 1 < s.Length && s[i + 1] == '/')
            {
                while (i < s.Length && s[i] != '\n') i++;
            }
            else
            {
                return;
            }
        }
    }

    private static string? ReadString(string s, ref int i)
    {
        var sb = new StringBuilder();
        i++; // opening quote
        while (i < s.Length)
        {
            var c = s[i++];
            if (c == '"') return sb.ToString();
            if (c != '\\' || i >= s.Length)
            {
                sb.Append(c);
                continue;
            }
            var e = s[i++];
            switch (e)
            {
                case 'n': sb.Append('\n'); break;
                case 't': sb.Append('\t'); break;
                case 'r': sb.Append('\r'); break;
                case '0': sb.Append('\0'); break;
                case 'U' or 'u' when i + 4 <= s.Length && int.TryParse(s.AsSpan(i, 4), System.Globalization.NumberStyles.HexNumber, null, out var code):
                    sb.Append((char)code);
                    i += 4;
                    break;
                default: sb.Append(e); break;
            }
        }
        return null;
    }

    /// <summary>
    /// Formats a macOS-style string: <c>%@</c>, <c>%d</c>, <c>%ld</c>, <c>%lld</c>, <c>%u</c> take the next
    /// argument; positional <c>%1$@</c> / <c>%2$d</c> take that argument; <c>%%</c> is a percent sign.
    /// </summary>
    public static string Format(string format, params object?[] args)
    {
        var result = new StringBuilder(format.Length + 16);
        var next = 0;
        for (var i = 0; i < format.Length; i++)
        {
            var c = format[i];
            if (c != '%' || i + 1 >= format.Length)
            {
                result.Append(c);
                continue;
            }
            if (format[i + 1] == '%')
            {
                result.Append('%');
                i++;
                continue;
            }
            var j = i + 1;
            int? position = null;
            var digits = j;
            while (digits < format.Length && char.IsAsciiDigit(format[digits])) digits++;
            if (digits > j && digits < format.Length && format[digits] == '$')
            {
                position = int.Parse(format.AsSpan(j, digits - j), System.Globalization.CultureInfo.InvariantCulture) - 1;
                j = digits + 1;
            }
            while (j < format.Length && format[j] == 'l') j++;
            if (j < format.Length && format[j] is '@' or 'd' or 'i' or 'u')
            {
                var index = position ?? next++;
                result.Append(index >= 0 && index < args.Length ? Convert.ToString(args[index], System.Globalization.CultureInfo.CurrentCulture) : "");
                i = j;
                continue;
            }
            result.Append(c);
        }
        return result.ToString();
    }
}
