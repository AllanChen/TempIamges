# Glance — Project Rules

Engineering rules for this codebase. These are hard constraints — do not violate them.

## Global keyboard event tap (CGEventTap)

Glance installs an **active global `CGEventTap`** to detect the activation hotkey
(`Glance/Sources/KeyboardMonitor.swift`). An active head-insert session tap makes
the WindowServer **block delivery of every keystroke system-wide until the
callback returns**. Getting this wrong freezes the whole Mac and "intercepts" all
keyboard input. Rules:

1. **Service the tap on a dedicated thread** with its own run loop. NEVER add its
   run-loop source to the main run loop (`CFRunLoopGetCurrent()` from the main
   thread).
2. **Keep the callback trivial and non-blocking.** Update cheap state and return
   immediately. Post notifications / build UI with `DispatchQueue.main.async` —
   never run panel building or any synchronous/heavy work inside the callback.
3. **Handle `tapDisabledByTimeout` and `tapDisabledByUserInput`** by re-enabling
   the tap (`CGEvent.tapEnable(tap:enable:true)`).
4. **Pass events through with `Unmanaged.passUnretained(event)`**, not
   `passRetained` (the latter leaks a `CGEvent` on every keystroke).
5. **Guard shared state with a lock** — the callback runs on the tap thread while
   preference/wake handlers touch the same state on the main thread.

## Main-thread responsiveness

6. **Prefer event-driven over polling on hot paths.** E.g. keep panels docked via
   `NSWindow.didMoveNotification`, not a recurring `Timer`. Never do synchronous
   network/file I/O or `semaphore.wait()` on the main thread.

## Window placement

7. Panels open **centered on the cursor's screen and fully on-screen**. Use
   `ScreenManager` (`centerFrame` / `contentFrame` / `centeredFrame` /
   `clampedToVisible`), which shrink-to-fit and clamp to `visibleFrame`. Do not
   reintroduce mouse-anchored placement that can land a window off-screen.

## Design language

8. All panels share the frosted-dark-glass chrome via `PanelStyle.swift`
   (`makeBarBlur`, `makeFrostedBase`, `makeIconButton`, color/type tokens). Reuse
   these instead of rolling per-view colors/fonts.

## Building

9. The user builds and runs Glance themselves. Do not run the build or offer to.

## Figma plugin (layout/GlanceFigmaPlugin)

10. The user imports and runs the Figma plugin themselves. Do NOT try to trigger
    it via AppleScript / GUI automation / `screencapture` / CGEvent clicks — this
    wastes time and is unreliable. When a Figma generation change is ready, just:
    (a) `node --check code.js` and run `test-generation.cjs`, then
    (b) tell the user exactly which button to click in Figma **Design Mode**
    (Shift+D first — Dev Mode cannot create layers). Nothing else.
11. Figma Desktop MCP is **read-only** (`get_metadata` / `get_design_context` /
    `get_screenshot` for verification only). All canvas writes go through the
    plugin the user runs.
