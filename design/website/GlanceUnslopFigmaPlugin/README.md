# Glance website — Shizuka 3.0

The macOS App UI file is a **read-only design reference**. Generate the website in the separate [Glance — Website / Unslop file](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw).

## Completed Figma website

The latest revision is a [Widget-first promotional homepage](demos/WIDGET-PROMO.md). Four large feature stories present background removal, object removal, image expansion and outfit swapping. The second story uses original/result slider comparison, so comparison is woven between Widget features. Browsing and other local conveniences follow the four stories. The previous duplicate film gallery is removed, and nine Pro demonstrations remain excluded.

All 16 homepages are synchronized across Chinese, English, Japanese and German, with four playable feature stories each. [Japanese/German localization](demos/LOCALIZATION.md) includes translated film captions, Japanese typography, regional prices and a four-language selector. The hero introduces the uses and shows the newly supplied portrait inputs; all eight new photos appear in its filmstrip. Native copy, window chrome, shared controls and media states stay editable. Existing real result pairs are reused. Earlier gallery and upper-film revisions remain archived in `demos/`.

Open the existing Figma file to review the current interactive design. The optional legacy plugin below produces the earlier static foundation; the current film library/gallery source and committed ledger live in `demos/`.

On 14 November 2026, the user explicitly authorized direct writes to the independent website file. The completed page is **Glance / Website / Shizuka · Latest** (`0:1`). No plugin run is needed to view it.

The earlier portrait revision replaced landscape photos using the user's original portrait and `handbag-removed.png` result. The current revision also uses eight supplied photos from `design/marketing/brand-assets/website-photos/`. No new images were generated and no competitor artwork was copied. The legacy static generator preserves its earlier portrait foundation; the current promotional composition is maintained in `demos/figma-promo.js`.

Current native proofs: [Sumi desktop](demos/promo-sumi-zh-desktop.png), [Washi comparison](demos/promo-washi-en-comparison.png), [Sumi mobile feature](demos/promo-sumi-en-mobile-outfit.png), [Washi mobile](demos/promo-washi-zh-mobile.png). See [the current native ledger](demos/promo-result.json). Earlier proofs and ledgers are historical.

- [Sumi Chinese desktop](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=15-1545)
- [Washi Chinese desktop](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=15-4759)
- Sixteen homepages in four languages and two earlier design-note boards. Existing button, typography, variable and product-preview foundations are reused.
- Native auto-layout structure, editable text, shared controls, theme bindings, and prototype links. The App reference file was not modified.
- Final native checks: no missing fonts, empty image fills, or overflowing button labels. [Navigation](preview/native-navigation.png) and [mobile hero](preview/native-mobile-hero.png) were rechecked after fixes.
- [Direct-write node ledger](direct-write-result.json) records the actual node IDs. `direct-renderer.js` contains the native MCP rendering adapter.
- [Japanese](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=70-6285) · [German](https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw?node-id=70-8831) · [Localization ledger](demos/i18n-result.json).

## Optional plugin generation

1. Open the independent website file linked above. Press **Shift+D** for Design Mode.
2. Close any older plugin window. Run **Glance Website — Unslop** from **Plugins → Development**.
3. Confirm the title shows **Shizuka 3.0**, then click **生成网站 · 最新设计**.

If the development plugin has not been imported, import [manifest.json](manifest.json) first. An already imported plugin reads the updated bundle when restarted.

The plugin creates a new **Glance / Website / Shizuka · Latest** page in the website file. Its **10 boards** contain Sumi/Washi English/Chinese desktop and mobile homepages plus two design notes boards. It preserves earlier website pages and manual edits on subsequent runs.

[The App UI file](https://www.figma.com/design/3oIkv5jBJpRUORxliJZdHl/Untitled) supplies the visual identity and reference assets only. The generator no longer queries its node IDs, requires its pages, or links to its variables/components at runtime. Running inside the known App reference file is blocked before canvas creation.

## What is editable

Website copy, layout frames, controls, rules, and prototype destinations are native Figma layers. Product views are imported as self-contained **SVG reference groups**, with vector chrome, SVG text, resolved theme colors, and bundled photos. They are portable reference assets, not live cross-file App component instances. Source image crop transforms and SVG root dimensions are retained.

The App frames were initially exported read-only. The current website-specific copies preserve the native window chrome and use four portrait assets, including the exact user-provided before/after PNGs. The bundle deduplicates image bytes and contains no temporary image URLs. All source fonts are loaded before SVG import.

## Static proofs

- Sumi: [hero](preview/desktop-hero.png), [English desktop](preview/desktop-en.png), [English mobile](preview/mobile-en.png), [Chinese desktop](preview/desktop-zh.png), [Chinese mobile](preview/mobile-zh.png)
- Washi: [hero](preview/washi-desktop-hero.png), [English desktop](preview/washi-desktop-en.png), [English mobile](preview/washi-mobile-en.png), [Chinese desktop](preview/washi-desktop-zh.png), [Chinese mobile](preview/washi-mobile-zh.png)
- [Sumi notes](preview/design-notes.png) · [Washi notes](preview/washi-design-notes.png)
- [Design report](REPORT.md) · [Portable source assets](portable/README.md)

The static proofs use the same portable SVG data packaged by the generator. The two native checks above are actual Figma exports of the completed design.

## Maintenance

```sh
node design/website/GlanceUnslopFigmaPlugin/build.cjs
node --check design/website/GlanceUnslopFigmaPlugin/code.js
node design/website/GlanceUnslopFigmaPlugin/test-generation.cjs
```

Optional static proofs use the local `sharp` package and downloaded reference fonts:

```sh
node design/website/GlanceUnslopFigmaPlugin/render-preview.cjs
```

`portable/app-views.json` and `photo-views.json` contain the read-only SVG exports with image placeholders. `build.cjs` verifies the exact matching photo bytes, normalizes exported UTF-8 entities, and bundles the data once. To refresh the App references, repeat those read-only exports; the user still runs the website plugin only in the independent website file.

Typography follows Shippori Mincho / Inter / Geist Mono, with Noto Serif SC and Noto Sans SC for Chinese, and Noto Sans JP plus Shippori Mincho for Japanese. Font license files remain in `reference/fonts/`. Content and billing data follow current local website sources and the retained product snapshot.

Unslop method by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
