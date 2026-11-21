using Glance.Core.Detection;

namespace Glance.Core.Inspect;

public enum InspectMode { Focus, Compare }

public enum CompareStyle { SideBySide, Slider }

/// <summary>
/// The images open in one Image Inspect window and what is shown (port of macOS
/// <c>ImageInspectSession</c> plus the window's focus / compare / navigation rules). Pure state;
/// the window renders it. Windows sessions hold images only — documents and videos dropped on
/// the window go to their own viewers.
/// </summary>
public sealed class InspectSession
{
    private readonly List<MediaInfo> _items;

    public InspectSession(IEnumerable<MediaInfo> items, int focusedIndex, InspectMode mode = InspectMode.Focus)
    {
        _items = items.ToList();
        if (_items.Count == 0) throw new ArgumentException("A session needs at least one item", nameof(items));
        FocusedIndex = Math.Clamp(focusedIndex, 0, _items.Count - 1);
        if (mode == InspectMode.Compare && _items.Count >= 2)
        {
            Mode = InspectMode.Compare;
            Pair = (FocusedIndex, FocusedIndex == 0 ? 1 : 0);
            if (Pair.Value.B < Pair.Value.A) Pair = (Pair.Value.B, Pair.Value.A);
        }
    }

    public IReadOnlyList<MediaInfo> Items => _items;
    public int Count => _items.Count;
    public int FocusedIndex { get; private set; }
    public InspectMode Mode { get; private set; }
    public CompareStyle Style { get; private set; } = CompareStyle.SideBySide;
    /// <summary>Compare pair: A (left / revealed on the right of the slider) and B.</summary>
    public (int A, int B)? Pair { get; private set; }
    /// <summary>Which compare slot a filmstrip click replaces: 0 = A, 1 = B.</summary>
    public int ActiveSlot { get; private set; } = 1;

    public bool IsComparing => Mode == InspectMode.Compare && Pair is not null;
    public bool CanCompare => _items.Count >= 2;

    /// <summary>The item actions apply to: the focused image, or the active compare slot.</summary>
    public int ActiveIndex => IsComparing ? (ActiveSlot == 0 ? Pair!.Value.A : Pair!.Value.B) : FocusedIndex;

    public MediaInfo this[int index] => _items[index];

    /// <summary>Enters compare. A stored pair is kept if it still contains the focused image.</summary>
    public bool EnterCompare(CompareStyle style)
    {
        if (!CanCompare) return false;
        Style = style;
        var focused = FocusedIndex;
        var keep = Pair is { } p && Valid(p.A) && Valid(p.B) && p.A != p.B && (p.A == focused || p.B == focused);
        if (!keep)
        {
            var other = Enumerable.Range(0, _items.Count).First(i => i != focused);
            Pair = (focused, other);
            ActiveSlot = 1;
        }
        Mode = InspectMode.Compare;
        return true;
    }

    public void ExitCompare()
    {
        Mode = InspectMode.Focus;
        Pair = null;
    }

    public void SetStyle(CompareStyle style) => Style = style;

    /// <summary>
    /// Filmstrip click. Focus: show that image. Compare: replace the active slot (never both
    /// slots on one image). Returns false when nothing changed.
    /// </summary>
    public bool Select(int index)
    {
        if (!Valid(index)) return false;
        if (IsComparing)
        {
            var (a, b) = Pair!.Value;
            if (ActiveSlot == 0)
            {
                if (index == b || index == a) return false;
                Pair = (index, b);
            }
            else
            {
                if (index == a || index == b) return false;
                Pair = (a, index);
            }
            return true;
        }
        if (index == FocusedIndex) return false;
        FocusedIndex = index;
        return true;
    }

    public bool SelectSlot(int slot)
    {
        if (!IsComparing || slot is not (0 or 1) || ActiveSlot == slot) return false;
        ActiveSlot = slot;
        return true;
    }

    /// <summary>← / →. Compare cycles B among the other images; A stays pinned.</summary>
    public bool Navigate(int delta)
    {
        if (_items.Count < 2) return false;
        if (IsComparing)
        {
            var (a, b) = Pair!.Value;
            var pool = Enumerable.Range(0, _items.Count).Where(i => i != a).ToList();
            var position = pool.IndexOf(b);
            if (position < 0 || pool.Count < 2) return false;
            Pair = (a, pool[((position + delta) % pool.Count + pool.Count) % pool.Count]);
            return true;
        }
        FocusedIndex = ((FocusedIndex + delta) % _items.Count + _items.Count) % _items.Count;
        return true;
    }

    /// <summary>Alt+click on a tile: compare the focused image with it.</summary>
    public bool CompareWith(int index)
    {
        if (!Valid(index) || index == FocusedIndex) return false;
        Mode = InspectMode.Compare;
        Pair = (FocusedIndex, index);
        ActiveSlot = 1;
        return true;
    }

    /// <summary>
    /// URL input, paste and the Add command: a duplicate focuses the existing item, a new item is
    /// appended and focused. Either way compare ends so the image shows on its own.
    /// </summary>
    public int AppendOrFocus(MediaInfo info)
    {
        var existing = IndexOf(info);
        ExitCompare();
        if (existing >= 0)
        {
            FocusedIndex = existing;
            return existing;
        }
        _items.Add(info);
        FocusedIndex = _items.Count - 1;
        return FocusedIndex;
    }

    /// <summary>
    /// Drag and drop: duplicates focus the existing item. A new image replaces the slot it was
    /// dropped on (side by side), the A image (slider), or becomes the focused image.
    /// </summary>
    public int AddDropped(MediaInfo info, int dropSlot)
    {
        var existing = IndexOf(info);
        if (existing >= 0)
        {
            ExitCompare();
            FocusedIndex = existing;
            return existing;
        }
        _items.Add(info);
        var index = _items.Count - 1;
        if (IsComparing)
        {
            var (a, b) = Pair!.Value;
            if (Style == CompareStyle.SideBySide)
            {
                ActiveSlot = dropSlot == 0 ? 0 : 1;
                Pair = ActiveSlot == 0 ? (index, b) : (a, index);
            }
            else
            {
                Pair = (index, b);
            }
        }
        else
        {
            FocusedIndex = index;
        }
        return index;
    }

    /// <summary>
    /// A compressed / resized / exported copy: inserted right after its source and compared
    /// side by side with it (source = A, copy = B).
    /// </summary>
    public int InsertDerived(MediaInfo info, int sourceIndex, bool compare = true)
    {
        if (!Valid(sourceIndex)) sourceIndex = _items.Count - 1;
        var existing = IndexOf(info);
        if (existing >= 0)
        {
            _items[existing] = info;
        }
        else
        {
            existing = sourceIndex + 1;
            _items.Insert(existing, info);
            if (FocusedIndex >= existing) FocusedIndex++;
            if (Pair is { } p) Pair = (p.A >= existing ? p.A + 1 : p.A, p.B >= existing ? p.B + 1 : p.B);
        }
        if (compare && existing != sourceIndex)
        {
            Mode = InspectMode.Compare;
            Style = CompareStyle.SideBySide;
            Pair = (sourceIndex, existing);
            ActiveSlot = 1;
            FocusedIndex = sourceIndex;
        }
        else
        {
            ExitCompare();
            FocusedIndex = existing;
        }
        return existing;
    }

    /// <summary>Updates an item with discovered details (dimensions, size, saved location).</summary>
    public void Replace(int index, MediaInfo info)
    {
        if (Valid(index)) _items[index] = info;
    }

    public int IndexOf(MediaInfo info)
    {
        var identity = Identity(info);
        return _items.FindIndex(i => Identity(i) == identity);
    }

    /// <summary>Same file / URL regardless of spelling (case-insensitive full paths on Windows).</summary>
    public static string Identity(MediaInfo info)
    {
        if (!info.IsLocal) return info.Location;
        try { return Path.GetFullPath(info.Location).TrimEnd('\\').ToUpperInvariant(); }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException) { return info.Location.ToUpperInvariant(); }
    }

    private bool Valid(int index) => index >= 0 && index < _items.Count;
}
