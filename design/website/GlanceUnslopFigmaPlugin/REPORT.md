# Glance website — latest design adaptation

## Current Widget promotional revision

Japanese and German versions now extend the current composition to 16 homepages in four languages. All four Widget film captions, page copy, FAQ and plan labels are localized. Japanese uses the verified Noto Sans JP font with Shippori Mincho display type; German keeps the existing Latin typography. Existing pricing configuration supplies JPY/EUR amounts, with JPY correctly treated as a zero-decimal currency. Every homepage now has a four-language selector preserving theme and viewport. Native GIF bytes, playback reactions, font availability, copy gaps, text bounds and 64 selector destinations pass validation. [Localization evidence](demos/LOCALIZATION.md).

The user clarified that Widget capabilities should lead the website's promotional story, with comparison woven between them. The eight homepages now present background removal, object removal with slider comparison, image expansion and outfit swapping as four large feature stories. The hero names these uses and displays the new photo inputs. The duplicate media gallery has been removed, and local viewer conveniences follow the Widget stories. Nine Pro demonstrations remain excluded.

The current composition reuses existing real result pairs, shared GIF players, native window chrome, fonts and theme variables. New editable story-copy components and static portrait-input components use the same foundations. Initial visual review exposed fixed headline heights; shared headlines now grow with their content, and all 32 copy instances preserve a 16 px gap before the explanation. [Current native result and proofs](demos/WIDGET-PROMO.md).

## Earlier upper-homepage motion revision

The user clarified that the four upper static product illustrations, rather than the existing Widget gallery, should become animated demonstrations. All eight homepages now use captioned films in their hero, view, right-click tools and comparison sections. Eight newly supplied portraits populate the main scenes and native filmstrip. The comparison uses the existing real original/result pair. No image-generation provider or paid cloud task was used, and Glance was not launched.

The native product window chrome, text and playback controls remain editable; animation is a GIF fill inside the content viewport. Poster/Playing variants toggle in Presentation View. Desktop and mobile content have separate compositions, localized captions and theme palettes. MP4 versions are packaged locally. Native GIF bytes, play/pause reactions, fonts, placed bounds and resized mobile section captions were verified. See [motion evidence](demos/UPPER-FILMS.md) and [the committed result](demos/upper-result.json).

## Earlier portrait revision

The user requested people instead of landscape photos, with the supplied `clipboard-DA224852-373C-472B-A405-9260B85880B6-handbag-removed.png` as the visual reference. The supplied PhotoDirector page was inspected for its portrait-led transformation demonstrations. Its artwork was not reused.

All eight website homepages now use portraits. The hero and Compare views show the exact original portrait beside the actual handbag-removal result; mobile shows both complete images instead of splitting one person down the middle. Focus and secondary imagery use existing editorial portraits. Landscape thumbnails were also replaced. The Widget menu example now shows Remove Objects at its verified 30-credit cost.

No new image generation was needed, so no alternative image model was substituted. Both PNG reference files are copied unchanged into `portable/photos/`. Current native Figma screenshots pass visual review for both themes and desktop/mobile layouts. Each homepage has zero fills using the retired landscape or old studio-portrait hashes. See `portrait-revision-result.json` and `preview/portrait-*.png` for the committed evidence. The following sections document the original style adaptation.

## Source inspected

[Glance UI 2.0](https://www.figma.com/design/3oIkv5jBJpRUORxliJZdHl/Untitled):

| Reference | Sumi · Dark | Washi · Light |
| --- | --- | --- |
| Page | `0:1` | `30:2346` |
| Foundations | `8:386` | `30:3049` |
| Focus | `5:207` | `30:2603` |
| Compare | `10:386` | `30:3183` |

Also inspected Home, Widget Market, Widget input, Widget running, sample illustration components, available fonts, and resolved variable modes. Source hierarchy and design context were read before this revision. Calls to the App reference file were read-only. The independent website file was written after explicit user authorization on 14 November 2026.

## Audit and direction

The latest app design already has a deliberate identity. The required correction was to the earlier website concept: its peach accent, system sans display, larger control radii, illustrated logo treatment, and old alpine screenshots no longer matched the supplied app design.

- Product: a Mac image and video viewer, with in-place cloud tools and comparison.
- Character: quiet, spacious, exact.
- World: Sumi ink and Washi paper.
- Moments: the source file’s Focus/Compare views and current photo assets, packaged for the separate website file.
- Signature: Ma (space), Sen (hairline), and Shu (a small vermilion mark).

The website adopts this identity while retaining the homepage feature order and current verified product facts. It does not redesign the original app frames.

## Nine Unslop passes

1. **Spacing.** Retain a 4 px rhythm, generous 96 px desktop edges and readable 24 px mobile edges. Separate information with space. Text overlap and bounds checks cover both languages and themes.
2. **Color.** Sumi uses `#151514`, `#1B1B1A`, `#242422`, `#34342F`, `#EAE7E0`, and `#A19D94`; Washi uses `#FAF9F5`, `#F3F1EB`, `#EAE7DF`, `#D5D1C6`, `#1C1B19`, and `#5C5952`. Vermilion is `#C65A40` / `#B5462E`, used as a small mark or fine rule. No large vermilion-filled actions. Website metadata uses the source’s secondary text color for at least 4.5:1 contrast; original cloned app text retains its source tokens.
3. **Icons.** Keep quiet 16 px, 1.5 px stroke glyphs. Native source frames retain their own icon components. The site wordmark follows the latest typographic identity.
4. **Copy.** English hero: “A quiet place / for your images”; Chinese: “让图片说话 / 让下一步更近”. Product facts, upload disclosure, failed-task refunds, and actual prices remain grounded in current project sources.
5. **Type.** Shippori Mincho titles, Inter interface text, and Geist Mono metadata follow the source foundations. Chinese display/interface use Noto Serif SC / Noto Sans SC. No negative tracking. Regular and Medium weights provide the hierarchy.
6. **Layout.** A restrained asymmetric hero; native product views; an editable Widget menu composition; open feature and pricing rows. Both Sumi and Washi receive English/Chinese desktop and mobile layouts. Section order remains hero → workflow → more tools → Widgets → pricing → download → FAQ → footer.
7. **Details.** Controls use 6 px radii and product windows 12 px, matching the foundations. The source comparison uses its exported SVG geometry rather than a flattened screenshot. Small-screen compositions show source artwork with readable controls rather than tiny full-window labels.
8. **Visuals.** Focus/Compare frames and three current photo components are exported read-only as SVG reference assets, then imported into the independent website file. Their resolved theme colors and exact photo bytes travel with the bundle. There are no live cross-file component or variable links. No new image generation or paid image service was used. Reference PNG screenshots are not implementation assets.
9. **Motion.** Keep the existing restrained ease-out guidance. Static Figma compositions specify states; no decorative looping, parallax, or animated layout is introduced.

## Product data boundary

The Figma file contains app design examples such as “Relight”, sample Widget costs, and sample balances. Those do not establish current saleable tools or prices. The website menu composition uses current **Edit Area: 1 credit** and **Upscale: 30 credits**. Other public Widget and plan prices remain sourced from the existing project snapshot; no backend configuration or prices were changed.

## Output and validation

- Generation target: the independent website file `kWvE51F9IfI3oSN6ZoxeKw`. The macOS App file is a read-only reference.
- Ten website boards: eight homepages and two notes boards.
- Seven self-contained SVG reference groups and seven deduplicated exact photos. No temporary asset URLs or runtime App node queries.
- All required website and SVG fonts load before canvas creation.
- SVG exports carry resolved Sumi/Washi colors, so destination files need no App variable collections.
- Regression tests reproduce the actual independent website document with only `Page 1` and the old website page. App node lookup is a trap; successful generation makes zero lookup calls.
- Tests cover an unavailable file key, App-reference-file protection, geometry, text collisions, Chinese punctuation, source image integrity, SVG dimensions, font loading, links, duplicate clicks, preserved edits, and rollback after render/import failures.
- Website text roles pass 4.5:1 contrast on their neutral surfaces in both themes.
- The completed website is on page `0:1`, **Glance / Website / Shizuka · Latest**, in the independent website file. Eight homepages and two notes boards were committed through Figma MCP after the user explicitly authorized direct writes.
- The native composition contains 1,938 auto-layout containers, 1,078 website text nodes, 68 component instances, and 40 populated product-image slots. Local foundations contain 16 button variants, 48 text styles, 41 variables, and seven product components.
- Native screenshots were reviewed for Sumi English/Chinese desktop, Washi English desktop, and Washi Chinese mobile. The English navigation button wrap and mobile photo letterboxing were repaired; targeted native screenshots then passed. All eight homepage boards have no missing fonts or empty image fills. All 20 live homepage buttons fit on one line.
- Source App frames and production website code were not changed. See `direct-write-result.json` for committed node IDs and evidence.

Shizuka 3.0 corrects the previous coupling between the App reference file and the website destination. The plugin no longer asks the user to generate a website inside the App UI document.

Unslop by **Damir Sokolovsky**, [heydamir/unslop](https://github.com/heydamir/unslop), **CC BY 4.0**.
