using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Glance.App.Theme;

namespace Glance.App.Inspect;

/// <summary>
/// The thumbnail row in the bottom bar (port of macOS <c>ImageFilmstripView</c>). Figma thumb:
/// a 48 pt tile with a 40 pt image inset 4 pt; unselected images rest at 55 %, the selected /
/// paired tiles get a 1 pt rule (B in text/2) and an A / B caption in the 18 pt headroom above.
/// Click selects, Alt+click compares with the focused image. The wheel scrolls the row.
/// </summary>
internal sealed class Filmstrip : ScrollViewer
{
    public const double TileSize = 48;
    public const double TileGap = 8;
    public const double Headroom = 18;

    private readonly StackPanel _row = new() { Orientation = Orientation.Horizontal };
    private readonly List<Tile> _tiles = [];
    private IReadOnlyList<int> _lastVisible = [];

    public Filmstrip()
    {
        HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden;
        VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
        CanContentScroll = false;
        Focusable = false;
        Height = TileSize + Headroom;
        Content = _row;
        ScrollChanged += (_, _) => ReportVisible();
        SizeChanged += (_, _) => ReportVisible();
    }

    /// <summary>Tile index and whether Alt was held (compare with the focused image).</summary>
    public event Action<int, bool>? TileClicked;

    /// <summary>Indices on screen (plus one either side) — the window loads only their thumbnails.</summary>
    public event Action<IReadOnlyList<int>>? VisibleIndicesChanged;

    public int Count => _tiles.Count;

    /// <summary>Width that shows up to eight tiles in full, eight and a half for longer sessions.</summary>
    public static double PreferredWidth(int count)
    {
        var n = Math.Max(1, count);
        return n <= 8 ? n * TileSize + (n - 1) * TileGap : 8.5 * TileSize + 8 * TileGap;
    }

    public void SetCount(IReadOnlyList<string> names)
    {
        if (_tiles.Count != names.Count)
        {
            _row.Children.Clear();
            _tiles.Clear();
            for (var i = 0; i < names.Count; i++)
            {
                var index = i;
                var tile = new Tile();
                tile.Margin = new Thickness(i == 0 ? 0 : TileGap, 0, 0, 0);
                tile.MouseLeftButtonUp += (_, e) =>
                {
                    e.Handled = true;
                    TileClicked?.Invoke(index, Keyboard.Modifiers.HasFlag(ModifierKeys.Alt));
                };
                _tiles.Add(tile);
                _row.Children.Add(tile);
            }
            _lastVisible = [];
        }
        for (var i = 0; i < names.Count; i++) _tiles[i].ToolTip = names[i];
        Dispatcher.BeginInvoke(new Action(ReportVisible), System.Windows.Threading.DispatcherPriority.Background);
    }

    /// <summary>Selection / compare / failure state; geometry never changes between states.</summary>
    public void SetState(int selected, (int A, int B)? pair, Func<int, bool> failed)
    {
        for (var i = 0; i < _tiles.Count; i++)
        {
            string? slot = pair is { } p ? (p.A == i ? "A" : p.B == i ? "B" : null) : null;
            var isSelected = pair is null && i == selected;
            _tiles[i].Apply(isSelected, slot, failed(i));
        }
    }

    public void SetThumbnail(int index, ImageSource? image)
    {
        if (index >= 0 && index < _tiles.Count) _tiles[index].SetImage(image);
    }

    /// <summary>Scrolls just enough to show the tile.</summary>
    public void Reveal(int index)
    {
        if (index < 0 || index >= _tiles.Count || ViewportWidth <= 0) return;
        var start = index * (TileSize + TileGap);
        var end = start + TileSize;
        if (start < HorizontalOffset) ScrollToHorizontalOffset(start);
        else if (end > HorizontalOffset + ViewportWidth) ScrollToHorizontalOffset(end - ViewportWidth);
    }

    public IReadOnlyList<int> VisibleIndices()
    {
        if (_tiles.Count == 0) return [];
        var width = ViewportWidth > 0 ? ViewportWidth : ActualWidth;
        if (width <= 0) return [];
        const double pitch = TileSize + TileGap;
        var first = Math.Max(0, (int)(HorizontalOffset / pitch) - 1);
        var last = Math.Min(_tiles.Count - 1, (int)((HorizontalOffset + width) / pitch) + 1);
        return first > last ? [] : Enumerable.Range(first, last - first + 1).ToList();
    }

    protected override void OnPreviewMouseWheel(MouseWheelEventArgs e)
    {
        base.OnPreviewMouseWheel(e);
        if (ScrollableWidth <= 0) return;
        ScrollToHorizontalOffset(Math.Clamp(HorizontalOffset - e.Delta / 2.0, 0, ScrollableWidth));
        e.Handled = true;
    }

    private void ReportVisible()
    {
        var visible = VisibleIndices();
        if (visible.SequenceEqual(_lastVisible)) return;
        _lastVisible = visible;
        VisibleIndicesChanged?.Invoke(visible);
    }

    /// <summary>One Figma thumb: 18 pt headroom (A / B caption), then the 48 pt tile.</summary>
    private sealed class Tile : Grid
    {
        private readonly Border _frame;
        private readonly Image _image = new() { Stretch = Stretch.UniformToFill };
        private readonly TextBlock _caption;
        private readonly Border _failureMark;

        public Tile()
        {
            Width = TileSize;
            Height = TileSize + Headroom;
            Background = Brushes.Transparent;
            Cursor = Cursors.Hand;
            RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);

            var imageHost = new Border
            {
                Width = 40,
                Height = 40,
                CornerRadius = Ui.Corner("CornerThumb"),
                Background = Ui.Brush("InspectInk3Brush"),
                Child = _image,
            };
            Ui.RoundClip(imageHost, 3);
            _frame = new Border
            {
                Width = TileSize,
                Height = TileSize,
                VerticalAlignment = VerticalAlignment.Bottom,
                CornerRadius = Ui.Corner("CornerControl"),
                BorderThickness = new Thickness(0),
                Child = imageHost,
            };

            _caption = new TextBlock
            {
                FontFamily = Ui.CodeFont,
                FontSize = 10,
                Foreground = Ui.Brush("InspectText2Brush"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 1, 0, 0),
                Visibility = Visibility.Collapsed,
            };

            // Figma failure mark: 14 pt vermilion disc at (34, −2) of the tile.
            var bang = new TextBlock
            {
                Text = "!",
                FontFamily = Ui.UiFont,
                FontSize = 9,
                FontWeight = FontWeights.SemiBold,
                Foreground = Ui.Brush("InspectInk1Brush"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            _failureMark = new Border
            {
                Width = 14,
                Height = 14,
                CornerRadius = new CornerRadius(7),
                Background = Ui.Brush("InspectShuBrush"),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(34, Headroom - 2, 0, 0),
                Child = bang,
                Visibility = Visibility.Collapsed,
                IsHitTestVisible = false,
            };

            Children.Add(_frame);
            Children.Add(_caption);
            Children.Add(_failureMark);
        }

        public void SetImage(ImageSource? image) => _image.Source = image;

        public void Apply(bool selected, string? slot, bool failed)
        {
            var emphasized = selected || slot is not null;
            _image.Opacity = emphasized ? 1 : 0.55;
            Brush? rule = failed ? Ui.Brush("InspectShuBrush")
                : slot == "B" ? Ui.Brush("InspectText2Brush")
                : emphasized ? Ui.Brush("InspectText1Brush") : null;
            _frame.BorderBrush = rule;
            _frame.BorderThickness = new Thickness(rule is null ? 0 : 1);
            _caption.Text = slot ?? "";
            _caption.Visibility = slot is null ? Visibility.Collapsed : Visibility.Visible;
            _failureMark.Visibility = failed ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}
