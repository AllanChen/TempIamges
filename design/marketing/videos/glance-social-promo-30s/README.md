# Glance social promo · 30 seconds

Two localized editions for the first Glance social launch:

- `glance-social-promo-30s-en.mp4` — English master, intended for X and YouTube.
- `glance-social-promo-30s-zh.mp4` — Chinese edition, intended for Chinese-language channels.

Both are 1920 × 1080, 16:9, 30 fps, H.264 + AAC. The text is on-screen so the
feature sequence remains understandable with audio muted. The soundtrack is
the original instrumental from `glance-promo-20s`, looped and faded at the end.

| Time | Scene |
| --- | --- |
| 0–4s | Select a path and open a quick preview |
| 4–12s | Replace a busy city background with a green park |
| 12–20s | Expand a Paris selfie beyond its original crop |
| 20–25s | Show both image Widget outcomes |
| 25–30s | Glance brand, shortcut, and glancepreview.com |

The opening and Glance branding are composed from existing Figma exports. The
two before/after examples use the supplied image pairs in
`design/marketing/brand-assets/`: `clipboard-DA224852-373C-472B-A405-9260B85880B6.png`
and its `.Remove Objects.png` result for background replacement, plus
`Screenshot 2026-11-06 at 10.52.24.png` and its `.Expand.png` result for image
expansion. The interface is a product UI animation, not a recording of a live
app session; the before/after images are the provided examples.

To render a language edition, run `render.py --lang en` or `render.py --lang zh`
from the repository Python environment with Pillow, NumPy, and ffmpeg available.
The renderer reuses source assets from `design/marketing/videos/glance-promo-20s/`
and `design/marketing/brand-assets/`.
