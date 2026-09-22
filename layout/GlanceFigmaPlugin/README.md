# Glance UI Builder (Figma Plugin)

This local development plugin creates a fully editable Glance Image Inspect design without Dev Mode or MCP.

## Import

1. Open Figma Desktop in normal Design mode.
2. Open any Figma Design file.
3. Choose `Plugins > Development > Import plugin from manifest...`.
4. Select `layout/GlanceFigmaPlugin/manifest.json`.
5. Run `Plugins > Development > Glance UI Builder v2`.

## Generate

1. Optionally select `layout/image-inspect-ui.png` in the plugin window.
2. Click **Create editable design**.
3. The plugin creates:
   - a locked 1554 × 1012 reference frame when the PNG is supplied;
   - a pixel-perfect frame backed by the source PNG, with a same-size editable overlay that is hidden by default;
   - a separate clean editable 1554 × 1012 Image Inspect frame;
   - named titlebar, toolbar, canvas, inspector, task tray, filmstrip, and statusbar layers;
   - reusable Glance paint styles.

To calibrate positions, open `Image Inspect / Pixel Match` and toggle the
visibility of `Editable Overlay / toggle visibility`. The clean frame also
contains a hidden 35% `Calibration Overlay` for visual difference checks.

The plugin uses SF Pro Text when available and falls back to Inter.

## Generate the remaining production screens

Run `Glance UI Builder v2` and click:

**Generate Video + Tasks + Widget Market**

The plugin adds three editable 1554 × 1012 frames to the current page:

- `Video Inspect / Clean Editable`
- `Task Center / Clean Editable`
- `Widget Market / Install / Clean Editable`

They reuse the Image Inspect palette, Inter typography, titlebar, icon-only
toolbar, statusbar, radii, and spacing. Existing Image Inspect frames are not
modified or replaced.

## Complete the Figma file

Click **Generate Remaining 7 Screens** to add:

- `Quick Preview / Clean Editable`
- `Content Viewer / Clean Editable`
- `Widget Web / States / Clean Editable` (loading, success, error)
- `Base64 Toolkit / Clean Editable`
- `Preview History / Clean Editable`
- `Preferences / Clean Editable`
- `Onboarding / Permissions / Clean Editable`

The screens are placed to the right of existing frames. Running this action
again skips any frame with the same name, so edited pages remain untouched.

## Redesign Widget Market without changing the product flow

Click **Redesign Widget Market (keep previous)** in the current Figma file.
The plugin keeps the existing `Widget Market / Install / Clean Editable` as
`Widget Market / Install / Previous` and replaces it at the same position
with a compact, VS Code-style 380pt catalog. The new editable frame contains:

- one vertical list of the three official Widgets, with icon, name, version,
  cloud badge, summary, command and an inline Install/Installed action;
- a secondary detail-drawer state shown next to the list for design review.

The existing WebView and Widget installation flow in the macOS app are not
modified by this Figma-only design update.

## Export your edited frame for AppKit implementation

1. Select exactly one frame, normally `Image Inspect / Clean Editable`.
2. Run `Glance UI Builder` again.
3. Click **Export selected frame (JSON + PNG)**.
4. Move the two downloaded files into `layout/figma-export/`:
   - `image-inspect-clean-editable.json`
   - `image-inspect-clean-editable.png`

The JSON contains the full node tree, relative and absolute coordinates,
fills, strokes, effects, corner radii, text styles, and auto-layout values.
The 1x PNG is the visual regression reference for the production AppKit view.
