# Glance for Windows — Plan

Status: approved 2026-11-19. Branch: `feat/windows-client`.

The Windows client is a port of the macOS app in `../clients/macos/Glance`. `server/` (GlanceService,
glance-cli, widgets) and the macOS app are **out of scope** and stay
untouched; Windows is just another client of the same backend API.

## Decisions

| Topic | Decision |
|---|---|
| Stack | C# / .NET 10 (LTS) / WPF + Win32 interop |
| Libraries | WebView2, AvalonEdit, Markdig, LibVLCSharp, SkiaSharp, NSec, Velopack (tray icon: own Shell_NotifyIcon wrapper) |
| Minimum OS | Windows 10 22H2 x64, Windows 11 |
| Default hotkey | `Alt+Q` via `RegisterHotKey` (no low-level hook in v1) |
| Theme | Light only. Figma layout/geometry is kept 1:1; colors come from the light token set in `src/Glance.App/Theme/Tokens.xaml` |
| Window chrome | Windows-style caption buttons (right side), light |
| Distribution | Velopack: `GlanceSetup.exe` + portable zip + auto-update feed hosted on the website. Unsigned (SmartScreen "More info → Run anyway" on first run) |
| Data | Settings/history/log in `%APPDATA%\Glance`, caches in `%LOCALAPPDATA%\Glance` |

## Layout

```
GlanceWin/
  Glance.slnx
  Directory.Build.props
  src/Glance.Core/       platform-neutral: settings, logging, path detection, resolver, models, API clients
  src/Glance.Platform/   Win32 interop: single instance, hotkey, UIA, clipboard, search index, shell, DWM
  src/Glance.App/        WPF: tray, panels, windows, theme tokens
  tests/Glance.Tests/    xUnit
```

## macOS → Windows mapping

| macOS | Windows |
|---|---|
| `CGEventTap` hotkey | `RegisterHotKey` on a message-only window |
| AX `kAXSelectedText` | UI Automation `TextPattern.GetSelection()`; fallback clipboard snapshot → `SendInput` Ctrl+C → poll `GetClipboardSequenceNumber` → restore |
| Spotlight (`mdfind`) | Windows Search `SystemIndex` (OLE DB) + bounded filesystem walk, same 3-layer cascade/time limits |
| QuickLook thumbnails | `IShellItemImageFactory` |
| Vision OCR | `Windows.Media.Ocr` |
| ImageIO / libwebp | WIC + SkiaSharp |
| AVFoundation / WebM fallback | LibVLCSharp |
| WKWebView / Highlightr | WebView2 / AvalonEdit |
| CryptoKit Ed25519 | NSec |
| `NSStatusItem` + popover | `Shell_NotifyIcon` (Platform/TrayIcon.cs) + borderless popup near the tray |
| `UNUserNotification` | Toast notifications |
| `glance://` deep link | `HKCU\Software\Classes\glance` + single-instance pipe forwarding |
| Finder "Open With" | File associations + Explorer context menu |
| Keychain / UserDefaults | DPAPI-protected file / JSON settings |
| Login item | `HKCU\...\Run` |
| `.strings` en / zh-Hans | `.resx` (converted, same keys) |

## Phases

| # | Phase | Deliverable |
|---|---|---|
| 0 | Scaffolding | Solution, settings, logging, single instance, tray, light tokens, Windows rules in CLAUDE.md |
| 1 | Core Peek | Alt+Q, selected-text reader, Windows PathDetector, resolver cascade, Peek panel (images + file cards), error tooltip, history, ScreenManager port |
| 2 | Content viewers | Markdown, code (edit + Ctrl+S), PDF, web, Git diff, open / reveal in Explorer |
| 3 | Image Inspect | Zoom/pan, filmstrip, compare (side-by-side/slider), info diff, rotate/copy/export, compression, OCR, drag-drop, capture editor |
| 4 | Video | Player, filmstrip, video compare, frame capture |
| 5 | Account & Widgets | Email-code + Google login (`glance://`), Market (signature check), input panels, task client/manager, Task Center, toasts |
| 6 | Shell | Home, Preferences, Onboarding, zh/en, Explorer integration, autostart, tray character icon |
| 7 | Release | Velopack installer/zip, website update feed, release script |

## Phase 0–1 tasks

1. [x] Solution + projects (`net10.0-windows10.0.19041.0`)
2. [x] Settings (JSON, atomic write), logger (rotation, redaction), single instance + arg forwarding, tray menu
3. [x] Light design tokens + base styles
4. [x] `Alt+Q` hotkey with conflict message
5. [x] `SelectedTextReader` (UIA → clipboard fallback, same timeouts as macOS)
6. [x] `PathDetector` port + Windows path forms (xUnit tests; shared JSON fixtures with macOS not done)
7. [x] Resolver cascade (cache → quick walk → Search index + deep walk)
8. [x] `ScreenManager` port (cursor monitor, clamp to work area, per-monitor DPI)
9. [x] Peek panel (no-activate, Esc), image card / grid / file cards, error tooltip, history

## Phase 1 notes

- Opening an item (click, Open button, single document hit) goes through `Peek/ItemRouter.cs`
  (Phase 2: documents and web pages use the content viewer).
- Esc is registered as a global hotkey only while Peek is visible.
- Tray menu has "Peek Clipboard Text" for testing detection without a selection.
- Selections inside elevated (admin) apps can't be read (UIPI).

## Phase 2 tasks

1. [x] Content window (`Content/ContentWindow.cs`, port of `ContentPanel`): one reusable, activating
   window with a custom light title bar — file name + "folder · Modified date" (address bar for web
   pages), Find, Reveal in File Explorer, Diff, Save, window buttons
2. [x] Markdown: rendered offline with Markdig in WebView2; relative images served from the document
   folder through a virtual host; links open in the browser / in the viewer (md, text, pdf)
3. [x] Text / code: AvalonEdit with highlighting (built-in grammars only), Ctrl+F search panel,
   Ctrl+S save in the original encoding (UTF-8 / BOM / UTF-16 / ANSI e.g. GBK), atomic write,
   "save changes?" prompt on close / next document / quit
4. [x] PDF: WebView2 built-in PDF viewer (its own Ctrl+F)
5. [x] Web pages: WebView2, editable address bar, find bar (macOS `__tdfind` helper)
6. [x] Git diff: `GitDiffService` + `LineDiff` (Core, tested) and a side-by-side `GitDiffWindow`
7. [x] Zoom (Ctrl +/−/0, Ctrl+wheel), Esc closes (find bar first), Ctrl+W
8. [x] Peek routes Markdown / text / PDF / web pages to the viewer (`Peek/ItemRouter.cs`)

## Phase 2 notes

- WebView2 can't be overlaid by WPF (airspace): the find bar is its own row and the loading
  indicator is a sweep line under the toolbar instead of the centered macOS sweep.
- WebView2 Runtime is preinstalled on Windows 11 and on updated Windows 10. Without it Markdown
  falls back to the editor; PDF / web show "Get WebView2" + "Open with Default App". Phase 7
  (Velopack) can bootstrap the runtime.
- WebView2 profile: `%LOCALAPPDATA%\Glance\WebView2`.
- Rendered Markdown runs no scripts of its own (CSP); raw HTML in Markdown is still rendered.
- Git diff needs git.exe on PATH or in the default Git for Windows folder.
- Videos open in Video Inspect (Phase 4); images in Image Inspect (Phase 3).

## Phase 3 tasks

1. [x] Core: `Imaging/ViewportMath` (zoom / pan / fit / visible rect), `CaptureGeometry`, `OcrLayout`
   (XY-cut reading order), `ImageTools` (estimates, names, Base64), `ImageCodec` (SkiaSharp: orient,
   resize, crop, compare composites, PNG / JPEG / WebP / ICO, compress-to-size), `Inspect/InspectSession`
   (focus / compare / navigation / drop rules) — all unit-tested (`InspectTests.cs`)
2. [x] `Inspect/InspectWindow`: 44 pt titlebar (Focus / Compare / Slider, Recognize Text, Info, More,
   window buttons), stage with Figma margins, 92 pt bottom bar, window fitted to the image, chrome
   auto-hide, pin on top; Washi light palette tokens (`Inspect*` in Tokens.xaml)
3. [x] `ImageViewport`: wheel zoom at the cursor, drag pan, double-click Fit / 100 %, rotate / flip
   (view only), synced side-by-side panes, slider divider + handle
4. [x] Filmstrip (lazy thumbnails, A / B captions, failure mark, Alt+click compare), compare tags,
   load-error view with Reveal / Try again
5. [x] Image information panel (attached right, non-activating) with compare differences marked
6. [x] Actions: copy (PNG + DIB), Base64 out / in, save to Documents\Glance, Save as PNG / JPG / WebP /
   ICO, compress / resize dialogs (copy inserted next to the source and compared), open image URL,
   add images, reveal, keyboard shortcuts sheet
7. [x] Recognize Text (`Platform/OcrService`, Windows.Media.Ocr) in a docked result panel
8. [x] Drag and drop (files, links), Ctrl+V (image paths / URLs, clipboard bitmaps)
9. [x] Capture editor (ratios, handles, size tag) → Pictures\Glance, opened in a new Inspect window
10. [x] Peek image clicks and Explorer "Open with" arguments open Image Inspect

## Phase 3 notes

- Sessions hold images only. Documents / videos dropped on the window open in the content viewer /
  default app (macOS previews them inline).
- Not ported yet: selecting OCR text directly on the image (use the Recognize Text panel), animated
  WebP playback (first frame; GIFs animate since the macOS 7f399a7 sync), Widget actions, task chips and result marks (Phase 5),
  billing locks.
- Display bitmaps are capped at 8192 px; copy / export / compress re-decode the original. Captures
  are cut from the display bitmap.
- ICO replaces the macOS ICNS export. WebP and the other encoders come from SkiaSharp (Core).
- OCR uses the first Windows OCR language for the user's profile languages (one language per scan,
  unlike Vision's zh-Hans + en-US).
- Pasted / Base64 images are written to `%TEMP%\Glance\Images`.

## Phase 4 tasks

1. [x] Core: `Video/VideoMath` — `VideoChromeLayout` (stage / transport / compare panes / window size,
   Figma `08 · Video Inspect` + `27 · Video Compare`) and `VideoFormat` (timecodes, bitrate, fps,
   FourCC and Media Foundation audio names) — unit-tested (`VideoTests.cs`)
2. [x] `Platform/VideoMetadataReader`: dimensions, duration, codec, frame rate, bitrate, audio codec
   from the Windows property system (off the UI thread)
3. [x] `Video/VideoPane`: WPF `MediaPlayer` (Media Foundation) drawn into the pane; WebM and anything
   Media Foundation can't open fall back to a WebView2 `<video>` player (separate profile with an
   autoplay switch); play / pause / seek / mute, frame grab, double-click 2×
4. [x] `Video/VideoWindow`: Image Inspect chrome (Focus / Capture / Compare, Information, More,
   window buttons), transport row (play, time, scrubber, duration, Capture frame), bottom bar and the
   shared filmstrip (shell thumbnails; remote videos use a grabbed frame), window fitted to the video
5. [x] Compare: two panes side by side in sync (seek / play / replay together), A / B captions with
   sound state and metadata, active pane, independent mute
6. [x] Frame capture → the shared capture editor over the video (Compare: both frames with the
   on-screen seam) → Pictures\Glance, opened in Image Inspect
7. [x] Information panel (320 pt, Figma `28 · Video Inspect / Info`), More / right-click menu
   (information, mute, replay, capture, reveal, pin)
8. [x] Drag and drop and Ctrl+V of videos (Compare: replaces the pane it lands on); dropped images and
   documents open in their viewers. Peek video clicks and Explorer arguments open Video Inspect

## Phase 4 notes

- Media Foundation plays MP4 / MOV (H.264, HEVC with the HEVC extension), WMV, AVI and MKV; WebM
  (VP8 / VP9 / AV1) plays in the WebView2 fallback. Without WebView2 those show "can't play".
- The WebView2 fallback can't be covered by WPF (airspace): its pane isn't dimmed in Compare, and
  it's hidden while the capture editor is open. Its frame capture is at display size.
- Remote videos stream directly; there is no persistent download cache yet (macOS
  `RemoteMediaDiskCache`).
- Remote videos have no codec / frame rate / bitrate (the property system only reads local files).
- Widget actions, task chips and result URLs on videos come with Phase 5.

## Phase 5 tasks

1. [x] Core `Account/`: `GlanceApi` (hosts, envelope + macOS error precedence), `AuthService` — email
   code, Google in the browser with PKCE and `glance://auth/callback`, `/auth/me` refresh, 401 →
   expire locally, sign-out; session + device id in a DPAPI store (`Platform/DpapiSecureStore`)
2. [x] Core `Widgets/`: `WidgetManifest` (commands, input capabilities, cost, localization, search,
   update detection), `WidgetSignature` (Ed25519 via the built-in RFC 8032 verifier `Ed25519.cs` over Swift-identical canonical JSON;
   official manifests accepted unverified, as on macOS), `WidgetRegistry` (`widgets.json`, delisting),
   `WidgetMarketClient` (catalog, verified install)
3. [x] Core `Billing/BillingClient`: pricing, wallet + transactions, task quotes, credit orders
   (browser checkout), order status / abandon
4. [x] Core `Tasks/`: `WidgetTaskClient` (uploads, create with `Idempotency-Key`, poll, cancel,
   settle / abandon, fresh result links, validated downloads to `Downloads\Glance`) and
   `WidgetTaskManager` (lifecycle, `widget-tasks.json`, resume after restart, settlement retries until
   the refund / delivery is confirmed, re-quote on `insufficient_credits` / `price_changed` /
   `quote_expired` / `input_changed`)
5. [x] `Account/AccountWindow`: sign-in (Google, email code with resend timer and attempts left),
   wallet, top-up packs with currency choice, payment confirmation polling, sign-out
6. [x] `Widgets/WidgetRunner`: sign-in gate → input panel → quote → top-up → start; Widgets menu in
   Image / Video Inspect (cost badges, text Widgets, Market, Cancel), running chip, results inserted
   next to their source (images compared side by side), Widget Market button in both titlebars
7. [x] `WidgetMarketWindow` (Marketplace / Installed / Updates, search, detail, install / update /
   remove / run), `TaskCenterWindow` (filters, search, detail with credit status, cancel / retry /
   open / reveal / copy URL / remove), input panel, text-Widget window, text result window
8. [x] `glance://` registered per user (`Platform/ProtocolRegistration`); auth and payment returns
   routed through single-instance arguments; "Widget completed" notifications from the tray icon;
   tray menu: Widget Market, Task Center, Account and Credits

## Phase 5 notes

- Not ported yet: Pro licence (trial, device slots, offline credential, redeem codes), refund
  requests and order history, team management, the mask editor (mask Widgets explain that they
  can't run yet, before anything is uploaded or charged), the China image-host upload path
  (`freeimage.host`) and the `ipapi.co` country fallback, Apple sign-in (Mac App Store only),
  analytics events, demo videos in the Market, the Task Center timeline.
- Remote inputs are downloaded to `Downloads\Glance` before upload, as on macOS.
- The canonical-JSON signature check must stay byte-identical to Swift's `JSONEncoder`
  (`.sortedKeys`, `.withoutEscapingSlashes`); `AccountWidgetTests` pin the format, but it still
  needs a check against a real signed manifest from the service.

## Phase 6 tasks

1. [x] `Shell/HomeWindow` (Figma `02 · Home`, `46 · Home / Folder loaded`, `47 · Empty states`): open
   drop zone, Open Files / Open Folder, folder grid, Recent column from history, status bar, drop /
   Ctrl+O / Ctrl+Shift+O / Ctrl+V, right-click Widgets menu; shown on a plain launch and when Glance is
   started again; hides after handing media to an inspector
2. [x] `Shell/PreferencesWindow` (`05 · Preferences`): General (start with Windows, Explorer
   integration, default apps), Peek (enable, hotkey presets + recorder with reserved-key checks,
   conflict message, clipboard fallback), Language; Account / first-run guide / About; reset
3. [x] `Shell/OnboardingWindow` (`12 · Onboarding` layout): Windows first-run guide — hotkey, Open with
   Glance, start with Windows; shown once (`OnboardingShown`)
4. [x] zh-Hans: the macOS `Localizable.strings` embedded as-is and parsed by `Core/Localization/StringsFile`
   (`%@`, `%d`, positional `%1$d`); language follows the system on first run; switching rebuilds the
   shell windows and reopens Preferences
5. [x] `Platform/ShellIntegration`: `Autostart` (HKCU Run, `--background`, Task Manager state) and
   `ExplorerIntegration` ("Open with Glance" for images / videos, Open-with list)
6. [x] Tray: drawn character icon (macOS `MenuBarCharacterIcon` geometry; light / dark taskbar; animates
   while Widget tasks run; Peek off = hands over eyes), left-click popover (`06 · Menu Bar Popover`),
   right-click menu

## Phase 6 notes

- Not ported: the Pro pill / Pro purchase entry, the Preview History window (Home's Recent column
  covers recent items), ja / de translations (the AppLanguage setting has English and Chinese).
- Windows doesn't let apps set themselves as the default viewer; Preferences opens Settings ▸ Default apps.
- Inspect / Video windows switch language when reopened (as on macOS).

## macOS sync log

- 2026-11-20, macOS `4a19a60` + `7f399a7`: animated GIFs in Image Inspect and Peek
  (`Media/GifAnimation`), Market walkthroughs (`WidgetDemos` GIF / MP4, bundled), link text + target
  counted once by the path detector, Peek shows "Searching…" at once. The 200 ms Option-hold change
  doesn't apply (Windows uses a regular hotkey). Also fixed independently: a dot inside a name
  ("x.Remove Objects.png") no longer cuts a rooted path short.

## Open items

- Light palette in `Tokens.xaml` is derived from the dark Figma tokens — needs user approval. macOS now ships an
  official light theme (Shizuka "Washi", `PanelStyle.Washi`); Image Inspect already uses it, the rest of the
  palette could switch to it.
- Website update-feed URL (needed in Phase 7).
- Figma Desktop MCP must be running before UI phases (Figma frames remain the layout source of truth).
