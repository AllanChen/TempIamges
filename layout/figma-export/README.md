# Figma Export Drop Folder

Snapshots and structural exports of the `Glance Production UI` Figma page.

## Latest page structure

`figma-page-metadata.xml` is the authoritative snapshot of the whole Figma
page, captured via the read-only Figma Desktop MCP. It lists every top-level
frame with its node id, position, size, and full child tree. Regenerate it by
re-running `get_metadata` on the page node (`0:1`) and overwriting the file.

### Top-level frames currently in Figma (12)

| # | Node | Name | x |
|---|------|------|---|
| 1 | `2:270`  | Reference / image-inspect-ui.png | 0 |
| 2 | `2:271`  | Image Inspect / Pixel Match | 1750 |
| 3 | `2:359`  | Image Inspect / Clean Editable | 3500 |
| 4 | `10:2`   | Video Inspect / Clean Editable | 5250 |
| 5 | `10:76`  | Task Center / Clean Editable | 7000 |
| 6 | `18:841` | Widget Market / Install / Clean Editable (compact list) | 8750 |
| 7 | `16:437` | Content Viewer / Clean Editable | 12250 |
| 8 | `16:566` | Base64 Toolkit / Clean Editable | 15750 |
| 9 | `16:619` | Preview History / Clean Editable | 17500 |
| 10 | `16:690` | Preferences / Clean Editable | 19250 |
| 11 | `16:778` | Onboarding / Permissions / Clean Editable | 21000 |
| 12 | `10:195` | Widget Market / Install / Previous (old two-column, superseded) | 22750 |

Notes:
- `18:841` is the redesigned VS Code-style Widget Market (single-column
  catalog + detail drawer). `10:195` is the old two-column draft, kept only
  for comparison and safe to delete.
- `Quick Preview / Clean Editable` was intentionally removed — that screen is
  not needed.

## Per-frame exports

To export one frame as implementation source, select it and use the
`Glance UI Builder` plugin's `Export selected frame (JSON + PNG)` button, then
drop both files here, e.g.:

- `image-inspect-clean-editable.json`
- `image-inspect-clean-editable.png`

The JSON is the implementation source of truth. The PNG is the 1x visual
regression reference used to compare the production AppKit window.
