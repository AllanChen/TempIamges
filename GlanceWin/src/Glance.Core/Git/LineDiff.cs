namespace Glance.Core.Git;

public enum DiffKind { Unchanged, Deleted, Inserted, Placeholder }

/// <summary>One side of a diff row. <see cref="Number"/> is the 1-based line number, null for placeholders.</summary>
public readonly record struct DiffCell(int? Number, string Text, DiffKind Kind)
{
    public static DiffCell Empty => new(null, "", DiffKind.Placeholder);
}

public readonly record struct DiffRow(DiffCell Left, DiffCell Right);

/// <summary>
/// Side-by-side line diff (port of macOS <c>GitDiffWindow.diffRows</c>): LCS over lines, runs of
/// deletions/insertions paired up row by row, the shorter side padded with placeholders.
/// Common prefix/suffix are matched first so typical edits only run LCS on the changed middle.
/// </summary>
public static class LineDiff
{
    /// <summary>LCS table cell budget; larger changed regions fall back to a positional diff.</summary>
    public const long MaxCells = 4_000_000;

    public static IReadOnlyList<string> SplitLines(string text)
    {
        if (text.Length == 0) return [];
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        return lines.Length > 0 && lines[^1].Length == 0 ? lines[..^1] : lines;
    }

    public static IReadOnlyList<DiffRow> Rows(string before, string after) => Rows(SplitLines(before), SplitLines(after));

    public static IReadOnlyList<DiffRow> Rows(IReadOnlyList<string> before, IReadOnlyList<string> after)
    {
        var prefix = 0;
        while (prefix < before.Count && prefix < after.Count && before[prefix] == after[prefix]) prefix++;
        var suffix = 0;
        while (suffix < before.Count - prefix && suffix < after.Count - prefix
               && before[before.Count - 1 - suffix] == after[after.Count - 1 - suffix]) suffix++;

        var midBefore = Slice(before, prefix, before.Count - prefix - suffix);
        var midAfter = Slice(after, prefix, after.Count - prefix - suffix);

        var rows = new List<DiffRow>(Math.Max(before.Count, after.Count) + 1);
        for (var i = 0; i < prefix; i++)
            rows.Add(new DiffRow(new DiffCell(i + 1, before[i], DiffKind.Unchanged), new DiffCell(i + 1, after[i], DiffKind.Unchanged)));

        if ((long)(midBefore.Count + 1) * (midAfter.Count + 1) > MaxCells)
            AppendPositional(rows, midBefore, midAfter, prefix + 1, prefix + 1);
        else
            AppendLcs(rows, midBefore, midAfter, prefix + 1, prefix + 1);

        var leftLine = before.Count - suffix + 1;
        var rightLine = after.Count - suffix + 1;
        for (var i = 0; i < suffix; i++)
        {
            rows.Add(new DiffRow(
                new DiffCell(leftLine + i, before[before.Count - suffix + i], DiffKind.Unchanged),
                new DiffCell(rightLine + i, after[after.Count - suffix + i], DiffKind.Unchanged)));
        }

        if (rows.Count == 0) rows.Add(new DiffRow(DiffCell.Empty, DiffCell.Empty));
        return rows;
    }

    private static void AppendLcs(List<DiffRow> rows, IReadOnlyList<string> before, IReadOnlyList<string> after, int leftLine, int rightLine)
    {
        var columns = after.Count + 1;
        var table = new int[(before.Count + 1) * columns];
        for (var i = before.Count - 1; i >= 0; i--)
        {
            for (var j = after.Count - 1; j >= 0; j--)
            {
                table[i * columns + j] = before[i] == after[j]
                    ? table[(i + 1) * columns + j + 1] + 1
                    : Math.Max(table[(i + 1) * columns + j], table[i * columns + j + 1]);
            }
        }

        var deleted = new List<string>();
        var inserted = new List<string>();
        void Flush()
        {
            var count = Math.Max(deleted.Count, inserted.Count);
            for (var k = 0; k < count; k++)
            {
                var left = k < deleted.Count ? new DiffCell(leftLine++, deleted[k], DiffKind.Deleted) : DiffCell.Empty;
                var right = k < inserted.Count ? new DiffCell(rightLine++, inserted[k], DiffKind.Inserted) : DiffCell.Empty;
                rows.Add(new DiffRow(left, right));
            }
            deleted.Clear();
            inserted.Clear();
        }

        int a = 0, b = 0;
        while (a < before.Count || b < after.Count)
        {
            if (a < before.Count && b < after.Count && before[a] == after[b])
            {
                Flush();
                rows.Add(new DiffRow(new DiffCell(leftLine++, before[a], DiffKind.Unchanged), new DiffCell(rightLine++, after[b], DiffKind.Unchanged)));
                a++;
                b++;
            }
            else if (b < after.Count && (a == before.Count || table[a * columns + b + 1] >= table[(a + 1) * columns + b]))
            {
                inserted.Add(after[b++]);
            }
            else
            {
                deleted.Add(before[a++]);
            }
        }
        Flush();
    }

    private static void AppendPositional(List<DiffRow> rows, IReadOnlyList<string> before, IReadOnlyList<string> after, int leftLine, int rightLine)
    {
        var count = Math.Max(before.Count, after.Count);
        for (var i = 0; i < count; i++)
        {
            if (i < before.Count && i < after.Count && before[i] == after[i])
            {
                rows.Add(new DiffRow(new DiffCell(leftLine + i, before[i], DiffKind.Unchanged), new DiffCell(rightLine + i, after[i], DiffKind.Unchanged)));
                continue;
            }
            rows.Add(new DiffRow(
                i < before.Count ? new DiffCell(leftLine + i, before[i], DiffKind.Deleted) : DiffCell.Empty,
                i < after.Count ? new DiffCell(rightLine + i, after[i], DiffKind.Inserted) : DiffCell.Empty));
        }
    }

    private static IReadOnlyList<string> Slice(IReadOnlyList<string> source, int start, int count)
    {
        var result = new string[count];
        for (var i = 0; i < count; i++) result[i] = source[start + i];
        return result;
    }
}
