# Japanese and German website versions

The current Widget promotional website now has 16 homepage boards: Chinese, English, Japanese and German × Sumi/Washi × desktop/mobile. The four-feature story order remains background removal, object removal with slider comparison, image expansion and outfit swapping. There is no duplicate film gallery and no Pro demonstration section.

- [Japanese desktop](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=70-6285)
- [German desktop](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=70-8831)
- [Native node ledger and validation](i18n-result.json)

Page copy, buttons, plan descriptions, FAQ, native window labels and all four film captions are localized. Japanese uses Noto Sans JP for interface/body copy and the existing Shippori Mincho for display headings. German retains the Latin brand typography. Localized text grows with its container while preserving the existing layout's minimum spacing.

Every homepage now includes a four-language selector. It navigates to the matching language board while preserving theme and viewport. The selector includes Closed/Open states and native clickable language rows. Secondary production pages are currently available in Chinese/English only, so Japanese/German secondary links retain their valid English destinations; the relevant detailed CTA labels identify this.

## Prices

Amounts come from `website/static/src/public-snapshot.json`. The JPY zero-decimal convention is confirmed in `server/GlanceService/src/pricing.ts` and `docs/glance-billing-v1.md`.

| Product | Japanese | German |
| --- | --- | --- |
| Personal Pro | ¥1,480 | 9,99 € |
| Team, five accounts | ¥2,980 | 19,99 € |
| 600 credits | ¥480 | 2,99 € |

No prices, identifiers, billing settings or deployment state were changed.

## Media and native evidence

Four scenes have 14 localized media renditions: three Widget films in each language, plus comparison in two themes and two viewport sizes for each language. GIFs, posters and H.264 MP4 files are in `media-i18n/`. These reuse the same real result pairs. No new image generation, paid task or app recording was performed.

- [Japanese Sumi desktop](i18n-ja-sumi-desktop.png) · [Japanese Washi mobile](i18n-ja-washi-mobile.png)
- [German Washi desktop](i18n-de-washi-desktop.png) · [German Sumi mobile](i18n-de-sumi-mobile.png)
- [Japanese hero](i18n-ja-desktop-hero.png) · [German mobile hero](i18n-de-mobile-hero.png)
- [Language selector states](i18n-language-selector.png)

Native checks cover original GIF signatures, 19–38 frames per film, full durations, reciprocal play/pause reactions, 32 selector variants, 64 valid language-row destinations, eight added homepages with four films each, no missing fonts, no story-copy overlaps and no overflowing text wrappers. All 14 MP4 files have the expected dimensions, H.264 encoding and full duration.

## Sources

`i18n-copy.json` covers the current English source text inventory. `render-i18n.py` renders localized content without changing the source photos; it uses the system Hiragino font for Japanese raster captions and does not redistribute that font. `figma-i18n.js` builds the native localized media/copy components, clones the current English compositions, preserves local anchors and adds language navigation. `i18n-upload-data.json` contains committed image hashes; temporary transfer nodes were removed after integration.

The optional legacy plugin remains the earlier Chinese/English static generator. No production website build or deployment was performed.

Unslop method by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
