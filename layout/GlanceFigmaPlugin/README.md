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

## Generate the simplified operation view

1. In Figma, open **Plugins → Development → Glance UI Builder v2**.
2. Manually select the image to preview in the existing **Reference image**
   field. If no image is selected, the plugin uses its built-in warm landscape
   artwork.
3. Click **Generate Simple Image Viewer**.
3. The plugin creates one idempotent `Image Viewer / Simple Operation` frame
   on the `Glance Production UI` page. With a selected image, the frame adopts
   that image's native pixel dimensions, so the image and window are exactly
   the same size with no black background. The only overlay is a light floating
   toolbar containing Focus, Compare, Slider, Widget, and Information.

Running the action again with a selected image updates only the frame's image
fill and preserves its generated layers and manual edits. Running it without
an image simply selects the existing frame. The frame remains part of the
normal plugin-generated page and is included the next time
`figma-page-metadata.xml` is captured.

## Generate the 13-screen Dark Refresh review set

1. In Figma, open **Plugins → Development → Glance UI Builder v2**.
2. Optionally choose the Image Viewer reference image yourself in
   **Reference image**. The plugin never imports a file automatically.
3. Click **Generate Dark Refresh v2 (13 Screens)**.

The action preserves all existing frames and adds a separate comparison grid:

- Image Viewer / Simple Operation
- Video Inspect
- Task Center
- Widget Market / Install
- Quick Preview
- Home / Launcher
- Content Viewer
- Widget Web / States
- Base64 Toolkit
- Preview History
- Preferences
- Onboarding / Permissions
- Tray Popover

Every generated frame is prefixed `Dark Refresh v2 /`, leaving the first
`Dark Refresh /` review set intact for side-by-side comparison. The Image Viewer keeps the
image at its native size with no page background and uses a `#161719` 90%
opaque floating toolbar with background blur, a subtle white border, light
icons, and the existing warm-orange active state. Its separate system control
group contains Close, Minimize, and Fullscreen, so these window actions do not
count against the five-button product toolbar. Video Inspect uses the same
full-bleed viewer shell and adds only a bottom floating playback controller.
The other screens retain their product-specific content while their titlebars,
toolbars, and action chrome use the same dark treatment. Running the action
again selects the existing review set instead of duplicating it.

## Generate the borderless window-control study

Click **Generate Viewer Chrome Study** to add
`Dark Refresh v3 / Image Viewer / Simple Operation`. It reuses the image and
native dimensions from the newest existing Simple Operation frame when
available. The study keeps a transparent 44px drag region, removes the dark
capsule around the macOS controls, and places bare Close, Minimize, and
Fullscreen dots at the top-left with only a subtle per-dot shadow. The centered
five-button product toolbar is unchanged. Existing frames are preserved.

Click **Generate Image Inspect Chrome Study** to add
`Dark Refresh v3 / Image Inspect / Clean Editable`. It applies the same bare
window controls and transparent drag region to Image Inspect, keeps the image
as the full canvas, and demonstrates the Information state as a dark floating
panel instead of a permanently attached inspector. The five-button toolbar and
the processing toast remain above the image as separate glass layers.

## Generate the Image Compression Flow

Click **Generate Image Compression Flow** to add a single `Image Compression
Flow` frame containing three scenes placed side by side:

1. **01 / Image Inspect + More menu** — the floating toolbar with the More
   menu open and "Compress Image" highlighted.
2. **02 / Compression Dialog** — the same viewer dimmed, with a centered
   compression dialog (quality slider + format dropdown + Cancel/Compress).
3. **03 / Compare Result** — the bordered Compare Mode with original (A) on
   the left and compressed (B) on the right, plus the bottom filmstrip showing
   both source and compressed thumbnails.

The flow matches the current Swift implementation and reuses the existing
Glance color palette, floating toolbar, compare chrome, and typography. Running
the action again selects the existing frame instead of duplicating it.

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
