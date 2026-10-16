# Figma Export Drop Folder

Snapshots and structural exports of the `Glance Production UI` Figma page.

## Latest page structure

### Widget Market / Details + Loading

The Widget Market implementation follows the live Figma board `262:744`,
inspected through the read-only Desktop MCP on 2026-10-15. Its six scenes are
Browse (`262:745`), Installed (`262:827`), Not Installed (`262:867`), Update
Available (`262:907`), Free (`262:949`), and Loading (`262:989`). Each panel is
448 × 824. The reference omits publisher/version/command-count metadata and
uses two-line list descriptions. The related snapshots are:

- `widget-market-details-loading.xml`: the board's actual node geometry;
- `widget-market-details-loading-context.txt`: high-fidelity design context;
- `widget-market-details-loading.png`: the rendered reference board.

The back and loading SVGs are bundled as `MarketIconBack` (16 × 16, rotated
180° at its callsite) and `MarketIconLoading` (20 × 20). Widget artwork remains
dynamic, supplied by each Widget's `iconURL`.

### Widget Context Menu / Compact Credits

The compact submenu follows the inspected Figma board `267:1112`. Its reference
files are `widget-context-menu-compact-credits.xml`,
`widget-context-menu-compact-credits-context.txt`, and
`widget-context-menu-compact-credits.png`. Names and credit badges are separate;
the shared header names the cost unit once, and a zero cost is displayed as Free.

At the user's request, the client replaces the study's fixed 280 pt width with
measured content width, bounded to 176–360 pt and the available screen width.
The calculation includes the localized name, full price badge, disclosure arrow
when present, and padding. Names truncate at the upper bound and retain their
complete tooltip/accessibility label. `WidgetMenuChevron` is the study's actual
12 × 12 SVG; paid/Free/hover/disabled styles retain the reference colors.

### Earlier full-page snapshot

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
