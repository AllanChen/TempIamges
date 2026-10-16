# Glance viewer landscapes

Two original 1086 × 1448 PNGs for the Figma Image Viewer Focus and Compare
screens. `glance-alpine-before.png` is the natural version for Compare A;
`glance-alpine-after.png` is the matching warm edit for Compare B and Focus.

`scripts/refresh-brand-media.py` composites these generated photos into the
existing Glance window UI and writes `focus-alpine.png`, `compare-alpine.png`,
and the four corresponding `website-static/src/assets/img/` screenshots. The
same source pair is used by the promotional video renderers in `outputs/`.

Generated with the built-in image generation tool.

## Prompts

**Natural / before**

> Create one original premium editorial landscape photograph for a macOS image-inspection app promotional mockup. Vertical 3:4 composition. A quiet alpine lake in the Dolomites seen from a low rocky shore, pale mist over still turquoise water, dark evergreen forest, layered mountain peaks, soft overcast morning light, realistic natural colors and fine photographic detail, sophisticated restrained cinematic mood. Compose with a clear mountain silhouette in the upper half and a reflective lake/shore in the lower half so a centered portrait crop remains strong. This will be the unedited 'before' image in a side-by-side photo comparison; the follow-up image will use the exact same scene and framing. No people, no animals, no buildings, no logos, no text, no watermark, no UI, no borders.

**Warm edit / after** (edit target: the natural image)

> Edit the supplied alpine lake photograph into the premium 'after' image for a side-by-side photo-editing promotion. Preserve the exact same viewpoint, mountain silhouettes, forest, lake shoreline, foreground rocks, reflections, and portrait 3:4 framing. Change only the atmosphere and color grade: clear some clouds for a subtle warm apricot sunrise from the upper left, soft golden highlights on mountain peaks and lake reflection, richer teal water and forest greens, crisp yet natural detail, refined editorial photography. The scene must align closely with the original when placed side by side. No people, no animals, no buildings, no logos, no text, no watermark, no UI, no border.
