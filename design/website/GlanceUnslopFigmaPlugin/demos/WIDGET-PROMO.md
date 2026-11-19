# Widget promotional homepage

The current [Figma website](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=15-1545) leads with Widget capabilities and visible results. It contains four distinct films per homepage, rather than separate viewer films and a duplicate Widget gallery.

| Story | Promotional outcome | Display |
| --- | --- | --- |
| 01 · Background removal | Separate a person as a transparent PNG | Existing real original/transparent result film |
| 02 · Remove objects | Remove an unwanted object and inspect the change | Existing real handbag-removal pair, side-by-side then moving slider |
| 03 · Expand image | Extend a portrait's composition | Existing real original/expanded result film |
| 04 · Outfit swap | Try clothing with a person image and outfit reference | Existing real original/result film |

Comparison sits within the second story, between other Widget features. The fourth story includes a link and short introduction to the remaining public Widgets. Local viewing, OCR and other conveniences follow these four promotional stories. Nine Pro demonstrations remain excluded; normal plan/pricing information is retained.

The hero explains the uses and shows original photo inputs from the newly supplied collection. All eight photos appear in its filmstrip. Photos are not presented as generated results. No new image generation, cloud task, app launch or production website deployment occurred.

## Editability and playback

Website text, layouts, photos, controls and source window chrome remain native editable Figma layers. Existing Poster/Playing components are reused. Enter Presentation View and click the play control to see the GIF; the editor canvas shows the poster. GIF and MP4 assets remain in `media/` and `media-upper/`.

Sixteen homepages cover Chinese, English, Japanese and German, with Sumi/Washi and desktop/mobile versions. Each has four media stories and no duplicate gallery. Shared copy components use the existing typography and theme variables. Headlines grow with content and maintain a 16 px gap above the explanation. [Japanese/German localization details and native proof](LOCALIZATION.md).

## Native evidence

- [Sumi Chinese desktop](promo-sumi-zh-desktop.png)
- [Washi English comparison story](promo-washi-en-comparison.png)
- [Sumi English mobile outfit story](promo-sumi-en-mobile-outfit.png)
- [Washi Chinese mobile](promo-washi-zh-mobile.png)
- [Committed node ledger and checks](promo-result.json)

`figma-promo.js` is the current composition source. It reuses the media IDs in the earlier `figma-result.json` and `upper-result.json`, plus the portrait hashes in `upper-upload-data.json`. Those earlier ledgers and rendering scripts are retained as source/history. The optional plugin still produces its earlier static foundation.

Unslop method by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
