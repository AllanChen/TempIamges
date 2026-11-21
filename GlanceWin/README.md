# Glance for Windows

Windows port of the macOS Glance client (`../clients/macos/Glance`). See [PLAN.md](PLAN.md)
for decisions, the macOS → Windows mapping and phase status.

## Requirements

- Windows 10 22H2 or Windows 11, x64
- .NET 10 SDK (GA release; preview SDKs are not supported)
- Visual Studio 2022 17.14+ / Rider, or the `dotnet` CLI

## Build and run

`run.py` stops a running Glance, rebuilds, and launches the new build:

```powershell
python GlanceWin/run.py            # Debug build + launch
python GlanceWin/run.py --test     # run unit tests first
python GlanceWin/run.py --release  # Release build
python GlanceWin/run.py --clean    # wipe bin/obj first
python GlanceWin/run.py --no-launch
```

## Using Peek

Select text containing a path, URL or filename in any app and press **Alt+Q**
(change `hotkey` in `%APPDATA%\Glance\settings.json`). Press Alt+Q again or Esc to close.

Glance starts in the notification area (no window). Right- or left-click the
icon for the menu.

Markdown, text/code, PDF and web pages open in Glance's viewer (single hit, or
click a Peek card). In the viewer: Ctrl+F find, Ctrl+S save (text/code),
Ctrl +/−/0 zoom, Esc or Ctrl+W close. "Diff" appears for files in a Git
repository. Web pages, PDF and rendered Markdown need the Microsoft Edge
WebView2 Runtime (included in Windows 11 and updated Windows 10).

Clicking an image in Peek opens **Image Inspect** with the other images of that
Peek in the filmstrip (images opened with Glance from Explorer open there too):

- Wheel zooms around the cursor, drag pans, double-click toggles Fit / 100 %;
  0 fit, 1 actual size, + / − zoom, ← / → previous / next.
- Compare (titlebar) shows two images side by side with synced zoom; Slider
  overlays them with a draggable divider. Alt+click a thumbnail compares it with
  the current image; click a side to choose which slot the filmstrip replaces.
- ⋯ / right-click: copy (Ctrl+C), save to `Documents\Glance` (Ctrl+S),
  rotate (Ctrl+L / Ctrl+R) and flip, save as PNG / JPG / WebP / ICO, compress,
  resize, Base64 in and out, open an image URL, add images, capture (Ctrl+Shift+X,
  saved to `Pictures\Glance`), image information (Ctrl+I), pin on top.
- Recognize Text uses Windows OCR (install a language with OCR in Settings ▸
  Time & language ▸ Language & region).
- Drop files or links on the window, or paste with Ctrl+V. ? shows all shortcuts.

Clicking a video opens **Video Inspect** with the other videos of that Peek:

- Space plays / pauses, the scrubber seeks, M mutes, ← / → previous / next video.
- Compare plays two videos side by side in sync; click a side to choose which
  one the filmstrip replaces, and mute each side from the ⋯ menu.
- Capture frame (camera button or Ctrl+Shift+X) freezes the frame in the capture
  editor and opens the saved PNG in Image Inspect.
- WebM and other formats Windows can't decode play in a WebView2 player.
- Drop videos on the window or paste a video link with Ctrl+V.

## Account and Widgets

- Tray ▸ **Account and Credits…** signs in (Google opens in the browser and returns via
  `glance://`, or use an email code) and shows the credit wallet and top-up.
- Tray ▸ **Widget Market…** (or the grid button in Image / Video Inspect) installs Widgets.
  Installed Widgets appear under ⋯ ▸ Widgets with their credit cost.
- Runs show a chip over the image / video; results are saved to `Downloads\Glance` and open next
  to their source. Tray ▸ **Task Center** lists every task with its credit / refund status.
  Failed or cancelled tasks are refunded automatically; the status stays visible until the service
  confirms it.

## Data

| Path | Contents |
|---|---|
| `%APPDATA%\Glance\settings.json` | Preferences |
| `%APPDATA%\Glance\app.log` | Log (rotates to `app.log.1` above 5 MB) |
| `%APPDATA%\Glance\history.json` | Preview history (Phase 1) |
| `%APPDATA%\Glance\secure\` | Account session and device id (DPAPI-encrypted) |
| `%APPDATA%\Glance\widgets.json` | Installed Widgets |
| `%APPDATA%\Glance\widget-tasks.json` | Widget task history and pending refunds |
| `Downloads\Glance\` | Widget results |
| `%LOCALAPPDATA%\Glance\` | Rebuildable caches (incl. `WebView2\` and `WebView2Video\` browser profiles) |
| `%TEMP%\Glance\Images\` | Pasted / Base64 images opened in Image Inspect |
