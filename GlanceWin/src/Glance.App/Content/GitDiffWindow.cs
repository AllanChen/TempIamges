using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Git;
using Glance.Platform;
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Rendering;

namespace Glance.App.Content;

/// <summary>
/// Side-by-side Git diff (port of macOS <c>GitDiffWindow</c>): path + summary header, a
/// "Before" and an "After" column with line numbers, -/+ markers and tinted rows, scrolled together.
/// </summary>
internal sealed class GitDiffWindow : Window
{
    private static readonly Size DefaultSize = new(1200, 760);
    private readonly TextEditor _left;
    private readonly TextEditor _right;
    private bool _syncing;

    public GitDiffWindow(GitSnapshot snapshot, IReadOnlyList<DiffRow> rows)
    {
        Title = $"Git Diff - {Path.GetFileName(snapshot.FilePath)}";
        Width = DefaultSize.Width;
        Height = DefaultSize.Height;
        MinWidth = 600;
        MinHeight = 320;
        Background = Ui.Brush("CanvasBrush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.Manual;

        _left = MakeColumnEditor(rows.Select(r => r.Left).ToList());
        _right = MakeColumnEditor(rows.Select(r => r.Right).ToList());

        var path = Ui.Text(snapshot.FilePath, "LabelText");
        path.Height = 18;
        var summary = Ui.Text($"{L.T(snapshot.Summary)}  •  {snapshot.RelativePath}", "CaptionText");
        summary.Height = 16;
        summary.Margin = new Thickness(0, 2, 0, 0);
        var header = new Border
        {
            Height = 56,
            Background = Ui.Brush("SurfaceBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(14, 9, 14, 0),
            Child = new StackPanel { Children = { path, summary } },
        };

        var columns = new Grid { Background = Ui.Brush("HairlineBrush") };
        columns.ColumnDefinitions.Add(new ColumnDefinition());
        columns.ColumnDefinitions.Add(new ColumnDefinition());
        var before = Column(L.T(snapshot.BeforeTitle), _left);
        before.Margin = new Thickness(0, 0, 0.5, 0);
        var after = Column(L.T(snapshot.AfterTitle), _right);
        after.Margin = new Thickness(0.5, 0, 0, 0);
        Grid.SetColumn(after, 1);
        columns.Children.Add(before);
        columns.Children.Add(after);

        var root = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        root.Children.Add(columns);
        Content = root;

        _left.TextArea.TextView.ScrollOffsetChanged += (_, _) => Sync(_left, _right);
        _right.TextArea.TextView.ScrollOffsetChanged += (_, _) => Sync(_right, _left);
        SourceInitialized += (_, _) =>
            ScreenManager.Place(this, ScreenManager.CenterFrame(DefaultSize, ScreenGeometry.MonitorAtCursor()));
    }

    private void Sync(TextEditor source, TextEditor target)
    {
        if (_syncing) return;
        _syncing = true;
        target.ScrollToVerticalOffset(source.TextArea.TextView.ScrollOffset.Y);
        _syncing = false;
    }

    private static FrameworkElement Column(string title, TextEditor editor)
    {
        var label = Ui.Text(title, "HeadlineText");
        label.FontSize = Ui.Number("LabelSize");
        label.HorizontalAlignment = HorizontalAlignment.Center;
        var titleBar = new Border
        {
            Height = 32,
            Background = Ui.Brush("SurfaceBrush"),
            BorderBrush = Ui.Brush("HairlineBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = label,
        };
        var panel = new DockPanel { Background = Ui.Brush("CanvasBrush") };
        DockPanel.SetDock(titleBar, Dock.Top);
        panel.Children.Add(titleBar);
        panel.Children.Add(editor);
        return panel;
    }

    private static TextEditor MakeColumnEditor(IReadOnlyList<DiffCell> cells)
    {
        var text = new StringBuilder();
        for (var i = 0; i < cells.Count; i++)
        {
            var cell = cells[i];
            if (cell.Kind != DiffKind.Placeholder)
            {
                var marker = cell.Kind switch { DiffKind.Deleted => '-', DiffKind.Inserted => '+', _ => ' ' };
                text.Append((cell.Number?.ToString() ?? "").PadLeft(5)).Append(' ').Append(marker).Append(' ').Append(cell.Text);
            }
            if (i < cells.Count - 1) text.Append('\n');
        }

        var editor = new TextEditor
        {
            Document = new TextDocument(text.ToString()),
            IsReadOnly = true,
            ShowLineNumbers = false,
            WordWrap = false,
            FontFamily = Ui.CodeFont,
            FontSize = Ui.Number("LabelSize"),
            Background = Ui.Brush("CanvasBrush"),
            Foreground = Ui.Brush("TextPrimaryBrush"),
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(0, 4, 0, 4),
        };
        editor.Options.EnableHyperlinks = false;
        editor.Options.EnableEmailHyperlinks = false;
        editor.TextArea.SelectionBrush = Ui.Brush("AccentSubtleFillBrush");
        editor.TextArea.SelectionBorder = null;
        var kinds = cells.Select(c => c.Kind).ToArray();
        editor.TextArea.TextView.BackgroundRenderers.Add(new DiffRowBackground(kinds));
        editor.TextArea.TextView.LineTransformers.Add(new DiffGutterColorizer(kinds));
        return editor;
    }

    /// <summary>Tints deleted / inserted / placeholder rows across the full width.</summary>
    private sealed class DiffRowBackground(DiffKind[] kinds) : IBackgroundRenderer
    {
        private readonly Brush _deleted = Ui.Brush("DiffDeletedBrush");
        private readonly Brush _inserted = Ui.Brush("DiffInsertedBrush");
        private readonly Brush _placeholder = Ui.Brush("ControlFillBrush");

        public KnownLayer Layer => KnownLayer.Background;

        public void Draw(TextView textView, DrawingContext drawingContext)
        {
            foreach (var line in textView.VisualLines)
            {
                var index = line.FirstDocumentLine.LineNumber - 1;
                if (index < 0 || index >= kinds.Length) continue;
                var brush = kinds[index] switch
                {
                    DiffKind.Deleted => _deleted,
                    DiffKind.Inserted => _inserted,
                    DiffKind.Placeholder => _placeholder,
                    _ => null,
                };
                if (brush is null) continue;
                drawingContext.DrawRectangle(brush, null,
                    new Rect(0, line.VisualTop - textView.ScrollOffset.Y, textView.ActualWidth, line.Height));
            }
        }
    }

    /// <summary>Line numbers in tertiary text, the -/+ marker in the failure/success color.</summary>
    private sealed class DiffGutterColorizer(DiffKind[] kinds) : DocumentColorizingTransformer
    {
        private readonly Brush _number = Ui.Brush("TextTertiaryBrush");
        private readonly Brush _deleted = Ui.Brush("FailureBrush");
        private readonly Brush _inserted = Ui.Brush("SuccessBrush");

        protected override void ColorizeLine(DocumentLine line)
        {
            var index = line.LineNumber - 1;
            if (index < 0 || index >= kinds.Length || kinds[index] == DiffKind.Placeholder || line.Length < 7) return;
            ChangeLinePart(line.Offset, line.Offset + 5, element => element.TextRunProperties.SetForegroundBrush(_number));
            var marker = kinds[index] switch { DiffKind.Deleted => _deleted, DiffKind.Inserted => _inserted, _ => null };
            if (marker is not null)
                ChangeLinePart(line.Offset + 6, line.Offset + 7, element => element.TextRunProperties.SetForegroundBrush(marker));
        }
    }
}
