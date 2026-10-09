# Glance UI Builder (Figma Plugin)

This local development plugin creates a fully editable Glance Image Inspect design without Dev Mode or MCP.

## Import

1. Open Figma Desktop in normal Design mode.
2. Open any Figma Design file.
3. Choose `Plugins > Development > Import plugin from manifest...`.
4. Select `layout/GlanceFigmaPlugin/manifest.json`.
5. Run `Plugins > Development > Glance UI Builder v2`.

The manifest allows import from both Figma Design and Dev Mode. Creation still
requires **Design Mode** because Dev Mode plugins cannot edit canvas contents.
If the plugin reports `Switch to Design Mode`, use the toolbar mode toggle or
`Shift+D`, then run the generator in Design Mode.

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

Click **Generate Image Filmstrip Scroll Study** to add an isolated review frame
for the Image Inspect filmstrip. It keeps six 96 × 96 thumbnails visible, puts
additional images in a clipped horizontal content row, and replaces the native
macOS scroller with a 3px dark Glance track and warm-apricot draggable thumb.

Click **Generate Home Folder Scroll Study** to add one editable 1080 × 720 Home
review frame. It shows a 12-image folder in the current two-column Home layout,
with a clipped thumbnail row, a 3px inset track, an apricot draggable thumb,
and a compact next-images control. The original Home frame is preserved.

## Generate the Image Compression Flow

Click **Generate Image Compression Flow** to add a single `Image Compression
Flow` frame containing three scenes placed side by side:

1. **01 / Image Inspect + More menu** — the floating toolbar with the More
   menu open and "Compress Image" highlighted.
2. **02 / Compression Dialog** — the same viewer dimmed, with a centered
   compression dialog (quality slider + keep-original-dimensions checkbox +
   live compressed size + Cancel/Compress).
3. **03 / Compare Result** — the bordered Compare Mode with original (A) on
   the left and compressed (B) on the right, plus the bottom filmstrip showing
   both source and compressed thumbnails.

The flow matches the current Swift implementation and reuses the existing
Glance color palette, floating toolbar, compare chrome, and typography. Running
the action again selects the existing frame instead of duplicating it.

## Review the Widget input and output pages

For the revised plain-text result, click **Generate Widget Text Result Side
Window** in Figma Design Mode. It creates the current full-size main image
window plus a separate 456 × 720 result window docked 16 px to its right. The
source image is not resized. The right window starts with a 128 × 96 input-image
preview and its filename/format metadata, followed by the returned text rendered
directly in the content area with no inner preview card. A compact Copy action
sits in the title bar and mint green is limited to the text-result status cue.
You may choose a **Reference image** for the source photo. Running the action
again upgrades an older generated result window with the input preview, then
selects the existing two windows while preserving edited result text.

For the running-state design, click **Generate Widget Task Running Study** in
Figma Design Mode. It creates two editable 1554 × 1012 frames:
`Image Inspect / Widget Task Running / Focused Source` shows the warm apricot
breathing border and persistent **Task running** label while the filmstrip is
hidden; `Image Inspect / Widget Task Running / Browsing Another Image` shows
the source thumbnail breathing while another image is selected. The thumbnail
size remains the current Image Inspect size of 61.44 pt at the design scale.
You may choose a **Reference image** for the source photo. Running the action
again selects the existing frames and preserves manual edits.

For the Widget that returns an OSS image URL, click **Refine OSS Result Page** in
Figma Design Mode. The action updates an existing `Widget Output / Image URL /
OSS Result / Refined` frame, or copies the user's edited `Widget Output / Image
URL / OSS Result` frame when the refined one does not exist. The result has a
plain **OSS RESULT** label and a compact **Copy URL** button. The image and
bottom filmstrip are left unchanged. Running the button again selects the
refined frame without replacing later edits. If the edited source frame is
absent, the plugin builds the same minimal layout; the optional Reference image
fills its generated image preview.

Open the plugin in Figma **Design Mode** and click
**Generate Revised Widget Pages (7 Screens)** at the top of the plugin
window. The optional **Reference image** supplies preview artwork; otherwise
the plugin uses Glance gradients.

The action creates seven separate editable frames: image + text input,
image + text + mask input, image + mask input with the prompt disabled, a draw
mask editor, direct text output alongside the source image, a video URL preview,
and an audio URL player. Video and audio results show a **Copy URL** action.
The inputs form one row and the outputs form another. The existing plain image
and video input flows and plain image result flow remain the reference for
those cases.

For the multi-image input study, click **Generate Multi-Image Widget Input (4 Max)**
in Figma Design Mode. It adds two editable 1554 × 1012 frames: `Widget Input / 04 /
Multi Image + Text / Add Image` shows three selected images and a fourth add slot;
`Widget Input / 04 / Multi Image + Text / Four Images` shows the four-image limit.
Both include the prompt field, image order, individual remove controls and the
Run Widget action. The optional Reference image fills the first image preview.
Running the action again selects the existing frames without replacing edits.
This is a design study; the Glance client is unchanged.

The older one-page overview, five-screen study, and eight-page draft are hidden and archived,
preserving any edits. Running the button again selects the first input page
without duplicating the others. These are design review pages; the Glance
client is unchanged.

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

## Update Widget Market for a 50-widget catalog

Click **Update Widget Market (50 widgets)** in the current Figma file.
The plugin keeps the existing `Widget Market / Install / Clean Editable` as
`Widget Market / Install / Previous` and replaces it at the same position
with a VS Code-inspired marketplace built for a 50-widget catalog. The new
editable frame contains:

- search plus Marketplace, Installed, and Updates filters;
- a dense scroll viewport backed by 50 editable Widget rows, including
  publisher, usage, rating, update state, and Install/Installed actions;
- a persistent selected-Widget detail view with Overview, Commands,
  Changelog, and Permissions tabs;
- a thin scrollbar sized to communicate the full catalog without making
  every row visible at once.

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
