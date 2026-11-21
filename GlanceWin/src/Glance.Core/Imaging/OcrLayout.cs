using System.Text;

namespace Glance.Core.Imaging;

/// <summary>
/// Rebuilds reading order and line structure from OCR line boxes, which arrive in no
/// guaranteed order and know nothing about columns or paragraphs (port of macOS
/// <c>InspectOCRLayout</c>). Recursive XY-cut: split into horizontal bands at empty rows, split
/// bands into columns at wide gutters, keep fragments sharing a visual row on one line.
/// </summary>
public static class OcrLayout
{
    /// <param name="Rect">Pixels, top-left origin.</param>
    public readonly record struct Fragment(string Text, RectD Rect);

    private sealed record Item(int Index, string Text, RectD Rect);

    private sealed class Line(List<Item> items)
    {
        public List<Item> Items { get; } = items;
        public bool ParagraphBefore { get; set; }
    }

    /// <summary>Fragment indices in reading order and the laid-out text.</summary>
    public static (IReadOnlyList<int> Order, string Text) Layout(IReadOnlyList<Fragment> fragments)
    {
        var items = new List<Item>();
        for (var i = 0; i < fragments.Count; i++)
        {
            var text = fragments[i].Text.Trim();
            if (text.Length > 0 && fragments[i].Rect.Height > 0) items.Add(new Item(i, text, fragments[i].Rect));
        }
        var lines = Cut(items);
        var builder = new StringBuilder();
        for (var i = 0; i < lines.Count; i++)
        {
            if (i > 0) builder.Append(lines[i].ParagraphBefore ? "\n\n" : "\n");
            builder.Append(Join(lines[i].Items));
        }
        return (lines.SelectMany(l => l.Items.Select(item => item.Index)).ToList(), builder.ToString());
    }

    /// <summary>
    /// Joins the words of one OCR line: no space between CJK characters (Windows OCR returns
    /// Chinese as single-character words), one space elsewhere.
    /// </summary>
    public static string JoinWords(IEnumerable<string> words)
    {
        var builder = new StringBuilder();
        foreach (var raw in words)
        {
            var word = raw.Trim();
            if (word.Length == 0) continue;
            if (builder.Length > 0 && !(IsCjk(builder[^1]) && IsCjk(word[0]))) builder.Append(' ');
            builder.Append(word);
        }
        return builder.ToString();
    }

    private static List<Line> Cut(List<Item> items)
    {
        if (items.Count == 0) return [];
        if (items.Count == 1) return [new Line(items)];

        var bands = Split(items, vertical: true, minGap: 0);
        if (bands.Count > 1)
        {
            var lines = new List<Line>();
            List<Item>? previous = null;
            foreach (var band in bands)
            {
                var sub = Cut(band);
                if (previous is not null && sub.Count > 0)
                {
                    var gap = band.Min(i => i.Rect.Top) - previous.Max(i => i.Rect.Bottom);
                    var lineHeight = Math.Min(MedianHeight(previous), MedianHeight(band));
                    if (gap > lineHeight * 0.8) sub[0].ParagraphBefore = true;
                }
                lines.AddRange(sub);
                previous = band;
            }
            return lines;
        }

        // Fragments that all share some common row stay on one line (label / value pairs, tables).
        var commonTop = items.Max(i => i.Rect.Top);
        var commonBottom = items.Min(i => i.Rect.Bottom);
        if (commonTop < commonBottom) return [new Line(items.OrderBy(i => i.Rect.Left).ToList())];

        var columns = Split(items, vertical: false, minGap: MedianHeight(items));
        if (columns.Count > 1)
        {
            var lines = new List<Line>();
            for (var c = 0; c < columns.Count; c++)
            {
                var sub = Cut(columns[c]);
                if (c > 0 && sub.Count > 0) sub[0].ParagraphBefore = true;
                lines.AddRange(sub);
            }
            return lines;
        }
        return Rows(items);
    }

    /// <summary>Splits wherever the projection on one axis leaves a gap wider than <paramref name="minGap"/>.</summary>
    private static List<List<Item>> Split(List<Item> items, bool vertical, double minGap)
    {
        double Lower(Item i) => vertical ? i.Rect.Top : i.Rect.Left;
        double Upper(Item i) => vertical ? i.Rect.Bottom : i.Rect.Right;
        var groups = new List<List<Item>>();
        var current = new List<Item>();
        var reach = double.MinValue;
        foreach (var item in items.OrderBy(Lower))
        {
            if (current.Count > 0 && Lower(item) - reach > minGap)
            {
                groups.Add(current);
                current = [];
            }
            current.Add(item);
            reach = Math.Max(reach, Upper(item));
        }
        if (current.Count > 0) groups.Add(current);
        return groups;
    }

    /// <summary>Tightly packed text whose boxes overlap between lines: group by half-height overlap.</summary>
    private static List<Line> Rows(List<Item> items)
    {
        var rows = new List<(RectD Rect, List<Item> Items)>();
        foreach (var item in items.OrderBy(i => i.Rect.MidY))
        {
            var match = -1;
            for (var r = rows.Count - 1; r >= 0; r--)
            {
                var row = rows[r].Rect;
                var overlap = Math.Min(row.Bottom, item.Rect.Bottom) - Math.Max(row.Top, item.Rect.Top);
                if (overlap >= Math.Min(row.Height, item.Rect.Height) * 0.5) { match = r; break; }
            }
            if (match >= 0)
            {
                rows[match].Items.Add(item);
                rows[match] = (rows[match].Rect.Union(item.Rect), rows[match].Items);
            }
            else
            {
                rows.Add((item.Rect, [item]));
            }
        }
        return rows.Select(r => new Line(r.Items.OrderBy(i => i.Rect.Left).ToList())).ToList();
    }

    private static string Join(List<Item> items)
    {
        var builder = new StringBuilder();
        Item? previous = null;
        foreach (var item in items)
        {
            if (previous is not null)
            {
                var gap = item.Rect.Left - previous.Rect.Right;
                var height = Math.Min(previous.Rect.Height, item.Rect.Height);
                if (gap > height * 2) builder.Append('\t');
                else if (!(IsCjk(previous.Text[^1]) && IsCjk(item.Text[0]))) builder.Append(' ');
            }
            builder.Append(item.Text);
            previous = item;
        }
        return builder.ToString();
    }

    private static double MedianHeight(List<Item> items)
    {
        var heights = items.Select(i => i.Rect.Height).OrderBy(h => h).ToList();
        return heights.Count == 0 ? 0 : heights[heights.Count / 2];
    }

    public static bool IsCjk(char c)
    {
        int v = c;
        return v is (>= 0x3000 and <= 0x303F) or (>= 0x3040 and <= 0x30FF) or (>= 0x3400 and <= 0x4DBF)
            or (>= 0x4E00 and <= 0x9FFF) or (>= 0xAC00 and <= 0xD7AF) or (>= 0xF900 and <= 0xFAFF)
            or (>= 0xFF00 and <= 0xFFEF);
    }
}
