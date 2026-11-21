using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Glance.App.Localization;
using Glance.App.Media;
using Glance.App.Theme;
using Glance.Core.Detection;

namespace Glance.App.Peek;

/// <summary>
/// The visual for one item: a pulsing placeholder while loading, then the picture (image,
/// video frame, thumbnail) or the file-type icon with its format, plus a play badge for video.
/// Shared by the single card, grid tiles, split preview and sidebar thumbnails.
/// </summary>
internal sealed class MediaPreview : Border
{
    private readonly Grid _layers = new();
    private readonly Image _image = new() { Stretch = Stretch.Uniform };
    private readonly StackPanel _iconStack = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly Image _icon = new() { Width = 72, Height = 72, Stretch = Stretch.Uniform };
    private readonly TextBlock _iconGlyph;
    private readonly TextBlock _iconLabel;
    private readonly TextBlock _placeholder;
    private readonly Border _playBadge;
    private readonly bool _compact;

    public MediaPreview(MediaInfo info, bool fill, bool compact = false)
    {
        _compact = compact;
        Background = Ui.Brush("ImageCanvasBrush");
        _image.Stretch = fill ? Stretch.UniformToFill : Stretch.Uniform;
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);

        var iconSize = compact ? 32 : 72;
        _icon.Width = _icon.Height = iconSize;
        _iconGlyph = Ui.Glyph(GlyphFor(info.Kind), compact ? 20 : 44, "TextTertiaryBrush");
        _iconGlyph.Visibility = Visibility.Collapsed;
        _iconLabel = Ui.Text(info.Kind == MediaKind.Folder ? L.T("Folder") : info.FormatName, "CaptionText");
        _iconLabel.HorizontalAlignment = HorizontalAlignment.Center;
        _iconLabel.Margin = new Thickness(0, 8, 0, 0);
        _iconLabel.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        _iconStack.Children.Add(_icon);
        _iconStack.Children.Add(_iconGlyph);
        _iconStack.Children.Add(_iconLabel);
        _iconStack.Visibility = Visibility.Collapsed;

        _placeholder = Ui.Glyph(Ui.GlyphPhoto, compact ? 16 : 32, "TextTertiaryBrush");
        _placeholder.BeginAnimation(OpacityProperty, new DoubleAnimation(0.25, 0.7, TimeSpan.FromSeconds(0.9))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
        });

        _playBadge = new Border
        {
            Width = compact ? 20 : 44,
            Height = compact ? 20 : 44,
            CornerRadius = new CornerRadius(compact ? 10 : 22),
            Background = Ui.Brush("SurfaceElevatedBrush"),
            Opacity = 0.92,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Child = Ui.Glyph(Ui.GlyphPlay, compact ? 9 : 16, "TextPrimaryBrush"),
            Visibility = Visibility.Collapsed,
        };

        _layers.Children.Add(_placeholder);
        _layers.Children.Add(_image);
        _layers.Children.Add(_iconStack);
        _layers.Children.Add(_playBadge);
        Child = _layers;

        if (info.Kind == MediaKind.WebPage) ShowGlyphOnly();
    }

    /// <summary>Animated GIFs play in Peek (macOS 7f399a7); the first frame shows until frames are ready.</summary>
    private async Task AnimateAsync(MediaInfo info)
    {
        var animation = await GifAnimation.LoadAsync(info, 1200, CancellationToken.None);
        if (animation is null || !IsLoaded && !IsVisible) return;
        _image.BeginAnimation(Image.SourceProperty, animation.ToAnimation());
        Unloaded += (_, _) => _image.BeginAnimation(Image.SourceProperty, null);
    }

    public void Apply(LoadedMedia media)
    {
        _placeholder.BeginAnimation(OpacityProperty, null);
        _placeholder.Visibility = Visibility.Collapsed;

        if (media.Image is not null && !media.IsIcon)
        {
            _image.Source = media.Image;
            _image.Visibility = Visibility.Visible;
            _iconStack.Visibility = Visibility.Collapsed;
            if (GifAnimation.IsCandidate(media.Info)) _ = AnimateAsync(media.Info);
        }
        else if (media.Image is not null)
        {
            _image.Visibility = Visibility.Collapsed;
            _icon.Source = media.Image;
            _icon.Visibility = Visibility.Visible;
            _iconGlyph.Visibility = Visibility.Collapsed;
            _iconStack.Visibility = Visibility.Visible;
        }
        else
        {
            ShowGlyphOnly();
        }

        _playBadge.Visibility = media.Info.Kind == MediaKind.Video ? Visibility.Visible : Visibility.Collapsed;
        if (media.Failed && !_compact)
        {
            _iconLabel.Text = L.T("Couldn't load preview");
            _iconLabel.Visibility = Visibility.Visible;
        }
    }

    private void ShowGlyphOnly()
    {
        _placeholder.BeginAnimation(OpacityProperty, null);
        _placeholder.Visibility = Visibility.Collapsed;
        _image.Visibility = Visibility.Collapsed;
        _icon.Visibility = Visibility.Collapsed;
        _iconGlyph.Visibility = Visibility.Visible;
        _iconStack.Visibility = Visibility.Visible;
    }

    private static string GlyphFor(MediaKind kind) => kind switch
    {
        MediaKind.WebPage => Ui.GlyphGlobe,
        MediaKind.Folder => Ui.GlyphFolder,
        MediaKind.Video => Ui.GlyphPlay,
        MediaKind.Image => Ui.GlyphPhoto,
        _ => Ui.GlyphDocument,
    };
}
