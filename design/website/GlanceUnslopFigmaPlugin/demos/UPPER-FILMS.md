# Four upper-homepage films

This is the earlier viewer-focused motion revision. The current [Widget-first promotional composition](WIDGET-PROMO.md) replaces its browsing, zoom and menu films with Widget feature stories and reuses its slider comparison inside object removal.

The static product illustrations above the Widget gallery have been replaced on all eight homepages in the [independent website Figma file](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=15-1574). The Widget gallery itself is unchanged. Nine Pro demonstrations remain excluded.

| Position | Animation | People |
| --- | --- | --- |
| Hero | Open and switch between portraits | Three newly supplied portraits |
| View | Zoom into a face and pan across the image | Newly supplied monochrome male portrait |
| In-place tools | Open image tools, choose background removal, confirm input and credits | Newly supplied silver-haired portrait |
| Compare | Side-by-side original/result, then moving slider | Existing real handbag-removal pair |

All eight supplied photos also appear in the native desktop filmstrip. Originals in `design/marketing/brand-assets/website-photos/` are preserved. `upper-manifest.json` records their exact filenames and which scenes use them.

## Playback and editability

Click **播放演示 / Play demo** in Figma Presentation View. Click again to return to the poster. The editor canvas uses a still poster. Native window chrome, labels, website copy, layout and playback controls remain editable; the film occupies the content viewport inside that window. Desktop and mobile have separate content compositions, with matching Sumi/Washi palettes and Chinese/English captions. Each film is about eight seconds. The 32 media variants are renditions of four scenes.

These are authored operation demonstrations based on the current design, not live app recordings. The tool animation stops at input/cost confirmation. The comparison reuses a real result. Glance was not launched and no paid cloud task or image-generation request was submitted.

Local Chinese Sumi desktop media:

| Scene | GIF | MP4 |
| --- | --- | --- |
| Hero | [GIF](media-upper/hero-zh-sumi-desktop.gif) | [MP4](media-upper/hero-zh-sumi-desktop.mp4) |
| View | [GIF](media-upper/view-zh-sumi-desktop.gif) | [MP4](media-upper/view-zh-sumi-desktop.mp4) |
| Tools | [GIF](media-upper/edit-zh-sumi-desktop.gif) | [MP4](media-upper/edit-zh-sumi-desktop.mp4) |
| Compare | [GIF](media-upper/compare-zh-sumi-desktop.gif) | [MP4](media-upper/compare-zh-sumi-desktop.mp4) |

## Evidence

- [Native result and node ledger](upper-result.json): 32 placed upper-film instances, 64 playback variants, unchanged four Widget cards per homepage, original GIF bytes/frames/durations, reciprocal play/pause reactions, no missing fonts and fitted viewport/caption bounds.
- [Hero](upper-hero-sumi-zh-desktop.png), [View](upper-view-sumi-en-desktop.png), [Tools](upper-edit-washi-zh-desktop.png), [Compare](upper-compare-washi-en-desktop.png).
- Mobile: [Hero](upper-hero-washi-zh-mobile.png), [View section](upper-final-view-sumi-en-mobile-section.png), [Tools](upper-edit-sumi-zh-mobile.png), [Compare](upper-compare-washi-zh-mobile.png).

Desktop playback controls were moved into the footer after visual review so they leave the zoom readout visible. Mobile section heights were expanded to accommodate the taller films.

## Sources and maintenance

`render-upper.py` renders the captioned content viewports, matching posters and MP4 files. `figma-upper.js` creates the native window/player variants, replaces the four upper slots and preserves the existing homepage structure. `upper-upload-data.json` records committed image hashes and transfer-node IDs; the transfer nodes were removed after integration. `upper-result.json` records the actual committed nodes and validation. The optional legacy plugin still produces its earlier static foundation.

```sh
python3 design/website/GlanceUnslopFigmaPlugin/demos/render-upper.py
```

No production website build or deployment was performed.

Unslop method by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
