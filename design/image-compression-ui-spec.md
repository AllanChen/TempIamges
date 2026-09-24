# Image Compression UI Spec

This document describes the Figma UI稿 for the Glance image-compression feature. It is based entirely on the existing Glance design system (dark chrome, Inter typeface, 8-pt grid, frosted panels) and the current Swift implementation.

## Feature scope (no new behavior)

- Trigger: right-click context menu **and** the toolbar **More (⋯)** menu.
- Action: open a small modal dialog.
- Dialog controls:
  - Quality slider: 10 % – 100 %, default 70 %.
  - Output format: Same as original / JPEG / PNG / WebP.
  - Primary: **Compress**; Secondary: **Cancel**.
- Result:
  - Save a new file next to the source (`{name}.compressed.{ext}`).
  - Insert it at `index + 1`.
  - Enter **Compare / Side-by-Side** with the original on the left and the compressed image on the right.

---

## 1. More menu entry

Reuse the existing **Motion / More menu** component in the Figma file.

| Property | Value |
|----------|-------|
| Menu background | `#1C1D21` |
| Border radius | 10 px |
| Stroke | 1 px `#34353A` |
| Shadow | `0 18 48 rgba(0,0,0,0.45)` |
| Width | 216 px |
| Row height | 34 px |
| Row padding | 12 px horizontal, 8 px vertical (gap 6 px between rows) |
| Icon size | 18 × 18 px |
| Icon color | `#AAA4A0` |
| Label font | Inter Medium, 13 px, `#F3EEE8` |
| Divider | optional 1 px `#34353A` between destructive/non-destructive groups |

**New row**

- Icon: a small compression glyph (two inward arrows or a shrinking frame).
- Label: **Compress Image** / **压缩图片**.
- Position: place above destructive actions (e.g. above any "Delete" rows if present), below normal actions like Copy / Save / Rotate.

---

## 2. Compression dialog

The dialog is a centered modal over a dimmed Image Inspect window.

### Dialog container

| Property | Value |
|----------|-------|
| Width | 320 px |
| Padding | 20 px |
| Background | `#1C1D21` |
| Border radius | 14 px |
| Stroke | 1 px `#34353A` |
| Shadow | `0 18 48 rgba(0,0,0,0.45)` |

### Content stack (vertical, gap 16 px)

1. **Title**
   - Font: Inter Semi Bold, 15 px, `#F3EEE8`
   - Text: "Compress Image" / "压缩图片"

2. **Caption**
   - Font: Inter Regular, 12 px, `#AAA4A0`
   - Text: "Lower quality means a smaller file." / "质量越低，文件越小。"

3. **Quality row**
   - Label: "Quality: 70%" / "质量：70%"
     - Font: Inter Medium, 12 px, `#F3EEE8`
   - Slider track below label:
     - Track: 280 × 4 px, rounded 2 px, fill `#34353A`
     - Filled portion (0.1 → 0.7): `#E8A87C`
     - Knob: 14 × 14 px circle, fill `#F3EEE8`, shadow `0 2 4 rgba(0,0,0,0.35)`
   - Helper text under slider:
     - Font: Inter Regular, 11 px, `#726D69`
     - Text: "10% – 100%"

4. **Format row**
   - Label: "Format:" / "格式："
     - Font: Inter Medium, 12 px, `#F3EEE8`, width 52 px
   - Dropdown to the right:
     - Width: 228 px
     - Height: 30 px
     - Background: `#17181D`
     - Border radius: 8 px
     - Stroke: 1 px `#34353A`
     - Text: Inter Medium, 12 px, `#F3EEE8`
     - Chevron icon on the right (use existing chevron icon, color `#AAA4A0`)

5. **Button row** (horizontal, gap 10 px, justify end)
   - **Cancel** button
     - Width: 80 px, height 32 px
     - Background: `#17181D`
     - Stroke: 1 px `#34353A`
     - Border radius: 8 px
     - Text: Inter Medium, 12 px, `#F3EEE8`
   - **Compress** button (primary)
     - Width: 90 px, height 32 px
     - Background: `#E8A87C`
     - Border radius: 8 px
     - Text: Inter Semi Bold, 12 px, `#21130D`

### Backdrop

A full-screen overlay behind the dialog:
- Fill: `#06070A` at 48 % opacity
- No blur (keeps it feeling like a native NSAlert)

---

## 3. After-comparison state

Reuse the existing **Compare Mode (bordered)** screen.

| Property | Value |
|----------|-------|
| Window border | 2 px `#5A5B62` |
| Window shadow | `0 18 48 rgba(0,0,0,0.45)` |
| Split gap | 2 px `#0B0C0E` |
| A/B chips | 32 × 32 px, frosted (`#161719` at 82 %), rounded 8 px, text `#F3EEE8` |

**Left pane (A)**: original image, chip label **A**.
**Right pane (B)**: compressed image, chip label **B**.

### Filmstrip overlay

At the bottom of the canvas, show the existing filmstrip with two highlighted thumbnails:
- Source thumbnail (left) selected as compare slot A.
- Compressed thumbnail (right) selected as compare slot B.
- Use the existing thumbnail style (96 × 96 px, 5 px padding, 1 px accent stroke when active).

### Status bar update

Show the saved path and size reduction:
- Left status text: `alpine-lake.compressed.jpg  •  128 KB → 34 KB  •  saved`
- Use existing status bar style (`#1A1B20`, 37 px height, 12 px Inter Regular `#AAA4A0`).

---

## 4. Suggested Figma page layout

Create a new top-level frame named **"Image Compression Flow"** placed to the right of the existing screens.

Inside, arrange three scenes side by side with 196 px spacing (same as the plugin's screen spacing):

1. **01 / Image Inspect + More menu** (1554 × 1012)
   - Reuse the editable Image Inspect screen.
   - Overlay the More menu under the toolbar's right edge with 8 px gap.
   - Highlight the "Compress Image" row.

2. **02 / Compression Dialog** (1554 × 1012)
   - Reuse the Image Inspect screen as a dimmed background.
   - Center the compression dialog on the canvas.

3. **03 / Compare Result** (1554 × 1012)
   - Reuse the bordered Compare Mode screen.
   - Show A/B chips and the filmstrip with source + compressed thumbnails.

---

## 5. Notes for engineers

- The Swift dialog currently uses `NSAlert` with an `accessoryView`. This spec preserves that layout while polishing the visual style to match Glance.
- The quality slider format string is `"Quality: %.0f%%"`; the default label is `"Quality: 70%"`.
- The format popup index order is: 0 = Same as original, 1 = JPEG, 2 = PNG, 3 = WebP.
- The toast after compression uses `"Compressed ✓"` followed by the saved path.
