# Glance website feature films

The current Figma homepage promotes **four Widget functions through large feature stories**: background removal, object removal, image expansion and outfit swapping. Object removal contains the original/result slider comparison between the other features. The former duplicate gallery is removed. See [the current promotional composition](WIDGET-PROMO.md).

The 16 homepage boards contain 64 playable story media instances in Chinese, English, Japanese and German. The [Japanese/German extension](LOCALIZATION.md) adds localized film captions, regional prices and a four-language selector. Existing real results are reused; comparison has theme and mobile renditions. Normal Pro pricing remains, while the nine Pro demonstrations stay excluded. `selection.json`, `index.html` and the earlier 40-film library preserve the previous standalone media review.

- [Current promotional homepage in Figma](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=15-1545)
- [Current source and native result](WIDGET-PROMO.md)
- [Archived standalone media review](index.html)

Figma's canvas shows the matching still poster. In Presentation View, click the play control to switch to the actual animated GIF; clicking again returns to the poster. The 40 GIFs were read back from Figma and checked for their original GIF signature, multiple frames, duration, and reciprocal play/pause reactions. Each contains 12–49 frames and about six seconds of captioned explanation. Native website headings, descriptions, plan labels, cards and layout stay editable.

## Media archive

The following coverage describes the retained source library. Only the four selected Widgets above appear on the current homepage. The Pro film section is absent.

| Widget | Demo |
| --- | --- |
| Edit Area / 局部编辑 | Paint a region, choose the tool, compare an existing result |
| Upscale / 高清放大 | Resolution/detail workflow illustration |
| Background Remover Pro / 人物背景分离 | Original portrait and existing transparent PNG |
| Remove Objects / 移除物体 | Exact user-provided original and handbag-removal result |
| Video Watermark Remover / 视频去水印 | Portrait-derived sample clip and labelled demo watermark workflow |
| Free Image Host / 免费图床 | Media selection, upload/link generation, copy link workflow |
| Image to Prompt / 图片转提示词 | Portrait analysis and reusable description workflow |
| Watermark Remover / 图片去水印 | Labelled demo watermark and cleanup workflow |
| Expand Image / 智能扩图 | Existing portrait/framing result pair |
| Outfit Swap / AI 换装 | Existing source portrait and completed clothing result |
| Redraw & Reframe / 图生图 | Existing portrait and completed regenerated result |

| Pro operation | Coverage |
| --- | --- |
| Convert & Save As | PNG, JPG, WebP and saving a new file |
| Export a Mac Icon | ICNS export |
| Compress Images | Quality/format and smaller-file workflow |
| Resize Images | Pixel dimensions and scaling |
| Copy an Image | Clipboard and paste workflow; Free capture/Widget-result exceptions are retained |
| Rotate & Export | Left/right rotation followed by file export; view-only rotation stays Free |
| Flip & Export | Horizontal/vertical flip followed by file export; view-only flipping stays Free |
| Image to Base64 | Encode and copy |
| Base64 to Image | Decode and view |

The current public catalog was fetched read-only on 14 November 2026. Runtime manifests, billing guards and export menus were inspected. No unsupported independent markup editor is represented as a Pro feature. Cloud Widget prices remain separate from Pro.

## Evidence and maintenance

`manifest.json` records every film and labels existing results versus workflow illustrations. These are product demonstrations, not live App screen recordings; no cloud task was submitted and Glance was not launched. Sources copied into `source/` are limited to the selected portrait assets/results. No new image-generation model was used.

`figma-promo.js` maintains the current four-story promotional composition, recorded in `promo-result.json`. `figma-library.js` created the shared media library. `figma-gallery.js` and `figma-result.json` describe the previous gallery composition; `figma-result-full-gallery.json` preserves the older full-gallery ledger. `build-review.cjs` applies `selection.json` to the archived standalone media review.

Current [native composition proofs](WIDGET-PROMO.md) supersede the earlier `curated-*.png` gallery exports.

```sh
python3 design/website/GlanceUnslopFigmaPlugin/demos/render.py
node design/website/GlanceUnslopFigmaPlugin/demos/build-review.cjs
```

The animation purpose is explanation. It reuses Shizuka's ease-out timing for operation feedback, avoids decorative looping movement, provides play/pause, and uses static posters until the user starts a film. MP4 review players pause when scrolled out of view and do not autoplay, including for reduced-motion users.

Unslop method by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
