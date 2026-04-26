# macOS Image Hover Preview — Work Plan

## TL;DR

> **Quick Summary**: Build a native macOS menubar utility that shows image previews when holding Cmd+Shift and hovering over URLs or local file paths in any application.
>
> **Deliverables**:
> - Xcode Swift project with complete source code
> - Signed & notarized .app bundle (direct distribution, not App Store)
> - Menu bar app with preferences panel (hotkey, max size, enable toggle)
> - Floating preview panel following mouse cursor
> - Permission onboarding & management
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — 4 waves + 1 validation prototype
> **Critical Path**: Prototype validation → Project setup → Event monitoring → Text extraction → Preview window → Preferences → QA

---

## Context

### Original Request
Create a macOS plugin/app that, when holding Cmd+Shift and hovering the mouse over a URL or local path text, pops up a small window showing the image at that path.

### Interview Summary
**Key Decisions**:
- **Form**: Global system tool (works in all macOS applications)
- **Tech Stack**: Swift + AppKit (native macOS development)
- **Window Behavior**: Follows mouse cursor, disappears immediately when Cmd+Shift released
- **Image Sizing**: Max 400x400 pixels, maintains aspect ratio
- **Window Style**: Borderless + rounded corners + shadow (macOS Quick Look aesthetic)
- **Error Handling**: Semi-transparent tooltip for invalid paths
- **Menu Bar**: Icon + preferences panel (customizable hotkey, max preview size, enable/disable toggle)
- **Supported Formats**: JPEG, PNG, GIF, WebP, HEIC, HEIF, BMP, TIFF

### Research Findings
- **Keyboard Monitoring**: `CGEventTap` (CoreGraphics) for global modifier key detection
- **Text Extraction**: `AXUIElementCopyElementAtPosition` (Accessibility API) to get text under mouse
- **Floating Window**: `NSPanel` with `.nonactivatingPanel` — non-focus-stealing preview
- **Menu Bar App**: `NSStatusItem` + `LSUIElement = true` (no dock icon)
- **Image Loading**: `QuickLookThumbnailing` framework for efficient thumbnails + `NSImage` for direct loading
- **Permissions Required**: Input Monitoring + Accessibility (both TCC permissions)

### Metis Review
**Identified Gaps** (addressed in plan):
- **High-Risk Assumption**: Accessibility API text extraction may fail in modern apps (Chrome, VS Code) — **Wave 0 prototype validates this first**
- **Distribution**: Mac App Store incompatible with CGEventTap — direct notarized distribution only
- **Security**: Network URL support includes SSRF guardrails (timeout, redirect limit)
- **Performance**: Event tap throttled, image decode capped, memory limits set
- **Scope locked**: No video, no PDF, no editing, no cloud integration, no gallery view

---

## Work Objectives

### Core Objective
Build a production-quality native macOS utility that provides instant image preview on hover for URLs and local paths, with minimal latency, low resource usage, and intuitive UX.

### Concrete Deliverables
- `ImageHoverPreview.app` — fully functional notarized application bundle
- Source code in `/ImageHoverPreview/` Xcode project
- Menu bar presence with app icon and preferences
- Permission onboarding flow on first launch

### Definition of Done
- [x] App launches and runs as background menubar app (no dock icon)
- [x] Holding Cmd+Shift shows image preview when hovering over valid image URLs/paths
- [x] Preview window follows mouse and disappears on key release
- [x] Preferences panel allows customizing hotkey, max size, and enable/disable
- [x] Graceful handling of missing permissions with clear instructions
- [x] All supported image formats render correctly
- [ ] QA scenarios pass across target applications

### Must Have
- Global keyboard monitoring (Cmd+Shift)
- Accessibility API text extraction under mouse cursor
- URL and local file path detection
- Floating preview window (borderless, rounded, shadow)
- Menu bar icon with preferences panel
- Permission onboarding on first launch
- Support for JPEG, PNG, GIF, WebP, HEIC, HEIF, BMP, TIFF
- Error tooltip for invalid paths

### Must NOT Have (Guardrails)
- Video preview support
- PDF or document preview
- Image editing (rotate, crop, etc.)
- File operations (move, copy, delete)
- Cloud storage integration
- OCR / text extraction from images
- Clipboard integration
- History / recent previews
- Mac App Store distribution
- Custom themes / styling beyond Quick Look aesthetic
- Gallery / thumbnail grid view
- Archive traversal (.zip, .dmg contents)

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: NO — no existing test infrastructure
- **Automated tests**: None — macOS native app UI testing via XCTest is limited; agent-executed QA is primary
- **Framework**: Agent-Executed QA via manual scenario execution
- **QA Policy**: Every task includes agent-executed QA scenarios (screen recording, screenshots, runtime verification)

### QA Policy
Every task MUST include agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **macOS Native App**: Use Bash (build/run), screen capture, and runtime inspection
- **UI Verification**: Manual scenario execution with screenshots
- **Performance**: Time measurement via `time` command and Instruments profiling

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 0 (VALIDATION — Must pass before proceeding):
├── Task 0: Prototype Accessibility API text extraction
│   └── Goal: Verify AXUIElementCopyElementAtPosition works in Safari, Chrome, VS Code
│   └── Gate: If fails in >1 target app, STOP and reassess approach

Wave 1 (Foundation + Project Setup):
├── Task 1: Xcode project scaffolding & signing config
├── Task 2: Menu bar app setup (LSUIElement, NSStatusItem)
├── Task 3: Permission management (TCC checks, onboarding UI)
└── Task 4: Global keyboard event tap (CGEventTap, modifier detection)

Wave 2 (Core Preview Logic):
├── Task 5: Mouse tracking & position polling
├── Task 6: Text extraction under cursor (Accessibility API)
├── Task 7: URL & file path detection / validation
├── Task 8: Preview panel (NSPanel, borderless, rounded, shadow)
└── Task 9: Image loading & display (QuickLookThumbnailing + NSImage)

Wave 3 (UI + Preferences + Polish):
├── Task 10: Error tooltip for invalid paths
├── Task 11: Preferences panel (hotkey, max size, enable toggle)
├── Task 12: Multi-monitor support & positioning logic
├── Task 13: App icon & visual assets
└── Task 14: Build configuration & notarization setup

Wave FINAL (Verification & Delivery):
├── Task F1: Cross-app QA testing (Safari, Chrome, VS Code, Finder, Terminal)
├── Task F2: Performance profiling (latency, memory, CPU)
├── Task F3: Permission denial edge case testing
└── Task F4: Build & package final .app bundle
```

### Dependency Matrix

| Task | Blocked By | Blocks |
|------|-----------|--------|
| 0 (Prototype) | — | 1-4 (if validation passes) |
| 1 (Project) | — | 2, 3, 4, 14 |
| 2 (Menu Bar) | 1 | 11, 13 |
| 3 (Permissions) | 1 | 4, 5, F3 |
| 4 (Keyboard) | 1, 3 | 5, F1 |
| 5 (Mouse) | 3, 4 | 6, 8, 12 |
| 6 (Text Extraction) | 5 | 7 |
| 7 (URL Detection) | 6 | 9, 10 |
| 8 (Preview Panel) | 5 | 9, 10, 12 |
| 9 (Image Loading) | 7, 8 | 10, F1, F2 |
| 10 (Error Tooltip) | 7, 8, 9 | F1 |
| 11 (Preferences) | 2 | F1 |
| 12 (Multi-monitor) | 5, 8 | F1 |
| 13 (App Icon) | 2 | 14 |
| 14 (Build Config) | 1, 13 | F4 |
| F1 (Cross-app QA) | 4, 9, 10, 11, 12 | — |
| F2 (Performance) | 9 | — |
| F3 (Permission QA) | 3 | — |
| F4 (Build & Package) | 14 | — |

### Critical Path
Task 0 → Task 1 → Task 4 → Task 5 → Task 6 → Task 7 → Task 9 → Task 10 → F1 → F4

---

## TODOs

- [x] 0. **Prototype: Validate Accessibility API Text Extraction**

  **What to do**:
  - Create a minimal throwaway Swift script/app that tests `AXUIElementCopyElementAtPosition` in target applications
  - Test in: Safari (web page with image URLs), Chrome (same), VS Code (markdown with paths), Finder (file list), Terminal (ls output with paths)
  - For each app: hold mouse over text containing a URL or path, print what the API returns
  - Measure latency of text extraction call

  **Must NOT do**:
  - Do NOT build full UI or window management
  - Do NOT implement image loading or preview
  - This is a throwaway prototype — code quality doesn't matter

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Requires deep understanding of macOS Accessibility APIs and testing across multiple apps
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 0 (standalone validation gate)
  - **Blocks**: Tasks 1-14, F1-F4 (entire project depends on this validation)
  - **Blocked By**: None

  **References**:
  - `AXUIElementCopyElementAtPosition` docs — Get element at screen coordinates
  - `kAXValueAttribute` — Extract text value from accessibility element
  - Reference repo: https://github.com/Aeastr/CursorBounds — Swift Accessibility text position

  **Acceptance Criteria**:
  - [ ] Successfully extracts text containing URLs from Safari
  - [ ] Successfully extracts text containing paths from VS Code
  - [ ] Latency per extraction call ≤ 50ms
  - [ ] Decision gate: If fails in >1 target app, mark as BLOCKED and reassess

  **QA Scenarios**:

  ```
  Scenario: Safari URL extraction works
    Tool: Bash (build & run prototype)
    Preconditions: Safari open with page containing "https://example.com/image.jpg"
    Steps:
      1. Build prototype: swiftc prototype.swift -framework ApplicationServices -o prototype
      2. Run: ./prototype
      3. In Safari, hover mouse over the URL text
      4. Check console output contains the URL string
    Expected Result: Console prints the URL text within 50ms of hover
    Failure Indicators: No output, partial text, or latency > 50ms
    Evidence: .sisyphus/evidence/task-0-safari-extraction.txt

  Scenario: VS Code path extraction works
    Tool: Bash (build & run prototype)
    Preconditions: VS Code open with file containing "/Users/test/Pictures/photo.jpg"
    Steps:
      1. Run prototype
      2. In VS Code, hover over the path text
      3. Check console output
    Expected Result: Console prints the full path string
    Failure Indicators: No output, truncated path, or wrong element type
    Evidence: .sisyphus/evidence/task-0-vscode-extraction.txt
  ```

  **Evidence to Capture**:
  - [ ] Console output from each target app test
  - [ ] Screenshots of hover position and extracted text
  - [ ] Latency measurements

  **Commit**: NO (throwaway prototype)

---

- [x] 1. **Xcode Project Scaffolding & Signing Configuration**

  **What to do**:
  - Create Xcode project: "ImageHoverPreview" with macOS App template
  - Configure Info.plist: `LSUIElement = true`, required permissions descriptions
  - Set up code signing with Developer ID (for notarized distribution)
  - Configure build settings: deployment target macOS 12.0+, architecture x86_64 + arm64 (universal)
  - Create basic directory structure: `Sources/`, `Resources/`, `PreviewContent/`
  - Add required frameworks: ApplicationServices, QuickLookThumbnailing

  **Must NOT do**:
  - Do NOT enable App Sandbox (CGEventTap requires non-sandboxed)
  - Do NOT set up Mac App Store provisioning profile

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard Xcode project setup, well-defined steps
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: Tasks 2, 3, 4, 14
  - **Blocked By**: None (can start immediately, but wait for Task 0 gate)

  **References**:
  - Apple Developer: Creating a macOS App project
  - Info.plist keys: `LSUIElement`, `NSAppleEventsUsageDescription` (for Accessibility)

  **Acceptance Criteria**:
  - [ ] `xcodebuild -project ImageHoverPreview.xcodeproj -scheme ImageHoverPreview build` succeeds
  - [ ] Built app has no dock icon when launched
  - [ ] App bundle is signed with valid Developer ID

  **QA Scenarios**:

  ```
  Scenario: Project builds successfully
    Tool: Bash
    Preconditions: Xcode command line tools installed
    Steps:
      1. cd ImageHoverPreview/
      2. xcodebuild -project ImageHoverPreview.xcodeproj -scheme ImageHoverPreview build
    Expected Result: Build succeeds with "BUILD SUCCEEDED"
    Failure Indicators: Build errors, signing failures, missing frameworks
    Evidence: .sisyphus/evidence/task-1-build-success.txt

  Scenario: App runs without dock icon
    Tool: Bash
    Preconditions: Build succeeded
    Steps:
      1. open build/Debug/ImageHoverPreview.app
      2. Check Dock for app icon
    Expected Result: App launches but no icon appears in Dock
    Failure Indicators: Dock icon visible, app crashes on launch
    Evidence: .sisyphus/evidence/task-1-no-dock-icon.png
  ```

  **Commit**: YES
  - Message: `chore: Xcode project scaffolding with LSUIElement and signing`
  - Files: `ImageHoverPreview.xcodeproj/`, `Info.plist`, project files

---

- [x] 2. **Menu Bar App Setup**

  **Must NOT do**:
  - Do NOT implement preferences panel UI yet (Task 11)
  - Do NOT add complex menu logic beyond basic items

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Well-understood macOS pattern, straightforward implementation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4)
  - **Blocks**: Tasks 11, 13
  - **Blocked By**: Task 1

  **References**:
  - Pattern: `NSStatusBar.shared.statusItem(withLength: NSStatusItem.variableLength)`
  - Menu structure: Preferences | Separator | Enable/Disable | Separator | About | Quit

  **Acceptance Criteria**:
  - [ ] Menu bar icon visible after app launch
  - [ ] Clicking icon shows dropdown menu with all items
  - [ ] "Quit" menu item terminates the app
  - [ ] Menu bar icon updates to reflect enabled/disabled state

  **QA Scenarios**:

  ```
  Scenario: Menu bar icon visible and interactive
    Tool: Bash (launch app) + screenshot
    Preconditions: App built successfully
    Steps:
      1. Launch app
      2. Take screenshot of menu bar area
      3. Click the app icon in menu bar
    Expected Result: Icon visible; dropdown menu appears with Preferences, Enable, About, Quit
    Failure Indicators: No icon, no menu, app not running
    Evidence: .sisyphus/evidence/task-2-menubar-icon.png
  ```

  **Commit**: YES
  - Message: `feat: menu bar status item with basic menu`
  - Files: `Sources/StatusBarController.swift`, `Sources/AppDelegate.swift`

---

- [x] 3. **Permission Management & Onboarding**

  **Must NOT do**:
  - Do NOT silently fail if permissions are missing — always show clear guidance
  - Do NOT request all permissions at once — staggered, context-aware requests

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: macOS TCC/permission system is complex and error-prone; needs careful handling
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4)
  - **Blocks**: Tasks 4, 5, F3
  - **Blocked By**: Task 1

  **References**:
  - `CGPreflightListenEventAccess()` — Check Input Monitoring permission
  - `CGRequestListenEventAccess()` — Request Input Monitoring permission
  - `AXIsProcessTrustedWithOptions()` — Check/request Accessibility permission
  - System Settings deep links: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

  **Acceptance Criteria**:
  - [ ] Onboarding window shows on first launch with clear explanations
  - [ ] "Open System Settings" buttons open correct preference pane
  - [ ] Menu shows current permission status (✅/❌)
  - [ ] App detects when permissions are granted without restart

  **QA Scenarios**:

  ```
  Scenario: First-launch onboarding flow
    Tool: Bash (launch app) + screenshot
    Preconditions: Fresh macOS user account (no prior permissions granted)
    Steps:
      1. Launch app
      2. Verify onboarding window appears
      3. Click "Grant Input Monitoring" → verify System Settings opens
      4. Deny permission → return to app → verify app shows "permission needed" state
    Expected Result: Clear onboarding UI, correct deep links, graceful degradation
    Evidence: .sisyphus/evidence/task-3-onboarding-flow.png

  Scenario: Permission status reflected in menu
    Tool: Bash (launch app) + manual interaction
    Preconditions: App running with partial permissions
    Steps:
      1. Open menu bar menu
      2. Verify permission status indicators are accurate
    Expected Result: Menu shows correct ✅/❌ for each permission
    Evidence: .sisyphus/evidence/task-3-permission-menu.png
  ```

  **Commit**: YES
  - Message: `feat: TCC permission management and onboarding flow`
  - Files: `Sources/PermissionManager.swift`, `Sources/OnboardingWindow.swift`

---

- [x] 4. **Global Keyboard Event Tap (CGEventTap)**

  **Must NOT do**:
  - Do NOT consume events (return nil) — pass all events through so other apps receive them
  - Do NOT use `NSEvent.addGlobalMonitorForEvents` — it cannot track modifier-only states reliably

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: CGEventTap is low-level CoreGraphics API with threading and lifecycle complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3)
  - **Blocks**: Tasks 5, F1
  - **Blocked By**: Tasks 1, 3

  **References**:
  - Reference repo: https://github.com/usagimaru/EventTapper — Swift CGEventTap wrapper
  - Reference repo: https://github.com/stephancasas/CGEventSupervisor — Modern event monitoring
  - `CGEvent.tapCreate()` API documentation
  - `kCGEventTapDisabledByUserInput` handling

  **Acceptance Criteria**:
  - [ ] Event tap starts successfully when both permissions granted
  - [ ] Pressing Cmd+Shift sets "preview mode active" flag
  - [ ] Releasing Cmd OR Shift clears "preview mode active" flag
  - [ ] Events pass through to other apps (no input blocking)
  - [ ] App handles permission revocation gracefully (re-prompt)

  **QA Scenarios**:

  ```
  Scenario: Modifier detection works correctly
    Tool: Bash (run test utility) + manual key presses
    Preconditions: App running with Input Monitoring permission granted
    Steps:
      1. Launch app with debug logging enabled
      2. Press Cmd+Shift simultaneously → check log for "preview mode: ON"
      3. Release Shift (hold Cmd) → check log for "preview mode: OFF"
      4. Press Cmd+Shift again → verify toggles back ON
    Expected Result: Correct state transitions logged; no missed events
    Evidence: .sisyphus/evidence/task-4-modifier-detection.txt

  Scenario: Events pass through to other apps
    Tool: Bash + manual typing test
    Preconditions: App running with event tap active
    Steps:
      1. Open TextEdit
      2. Type text while app is running
      3. Verify all keystrokes appear in TextEdit
    Expected Result: No keystrokes are lost or delayed
    Evidence: .sisyphus/evidence/task-4-event-pass-through.txt
  ```

  **Commit**: YES
  - Message: `feat: CGEventTap global keyboard monitoring for Cmd+Shift`
  - Files: `Sources/KeyboardMonitor.swift`

---

- [x] 5. **Mouse Tracking & Position Polling**

  **What to do**:
  - Implement mouse position polling at 60Hz when in "preview mode"
  - Use `NSEvent.mouseLocation` for global mouse coordinates
  - Convert screen coordinates to proper CGPoint for Accessibility API
  - Implement timer-based polling (don't use global mouse move monitor — too noisy)
  - Stop polling when preview mode is inactive (save CPU)
  - Handle multi-monitor coordinate spaces correctly

  **Must NOT do**:
  - Do NOT use `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` — generates too many events
  - Do NOT poll at >60Hz — wastes CPU with no UX benefit

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward timer + coordinate conversion logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 7, 8)
  - **Blocks**: Tasks 6, 8, 12
  - **Blocked By**: Tasks 3, 4

  **References**:
  - `NSEvent.mouseLocation` — Get global mouse position
  - `NSScreen.screens` — Multi-monitor coordinate handling
  - Timer: `Timer.scheduledTimer(timeInterval: 1.0/60.0, ...)`

  **Acceptance Criteria**:
  - [ ] Mouse position updates at ~60Hz when Cmd+Shift held
  - [ ] Position correctly maps to screen coordinates on primary monitor
  - [ ] Timer stops when modifiers released (CPU idle)
  - [ ] No memory leaks from timer retain cycles

  **QA Scenarios**:

  ```
  Scenario: Mouse tracking active only during preview mode
    Tool: Bash (run with Activity Monitor)
    Preconditions: App running
    Steps:
      1. Check CPU usage while idle (no modifiers held)
      2. Hold Cmd+Shift → check CPU usage increases slightly
      3. Release modifiers → CPU returns to idle
    Expected Result: CPU usage spike only during preview mode; ~0% when idle
    Evidence: .sisyphus/evidence/task-5-cpu-profile.txt
  ```

  **Commit**: YES
  - Message: `feat: mouse position polling at 60Hz during preview mode`
  - Files: `Sources/MouseTracker.swift`

---

- [x] 6. **Text Extraction Under Cursor (Accessibility API)**

  **What to do**:
  - Implement `TextExtractor` class using `AXUIElementCopyElementAtPosition`
  - Call on every mouse position update (60Hz) when preview mode active
  - Extract text value from accessibility element (`kAXValueAttribute`)
  - Handle different element types: static text, links, buttons, etc.
  - Debounce/throttle to avoid excessive API calls (only extract when mouse stops moving for 100ms)
  - Handle API failures gracefully (return nil, don't crash)
  - Cache last extracted text to avoid redundant processing

  **Must NOT do**:
  - Do NOT call Accessibility API when preview mode is inactive
  - Do NOT ignore API errors — log and handle gracefully

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Accessibility API is complex, failure-prone, and app-dependent
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 7, 8)
  - **Blocks**: Task 7
  - **Blocked By**: Task 5

  **References**:
  - `AXUIElementCreateSystemWide()` — System-wide accessibility element
  - `AXUIElementCopyElementAtPosition()` — Get element at point
  - `AXUIElementCopyAttributeValue()` — Extract attributes
  - `kAXValueAttribute`, `kAXTitleAttribute`, `kAXDescriptionAttribute`
  - Reference repo: https://github.com/Aeastr/CursorBounds

  **Acceptance Criteria**:
  - [ ] Successfully extracts text from Safari, Chrome, VS Code, Finder
  - [ ] Debounced: only extracts after mouse stops for 100ms
  - [ ] Returns nil gracefully for non-text elements
  - [ ] No crashes when Accessibility API fails

  **QA Scenarios**:

  ```
  Scenario: Text extraction from Safari URL
    Tool: Bash (run app with debug logging)
    Preconditions: Safari open with page containing image URL
    Steps:
      1. Launch app
      2. Hold Cmd+Shift, hover over URL text in Safari
      3. Check debug log for extracted text
    Expected Result: Log shows complete URL string within 200ms of hover
    Evidence: .sisyphus/evidence/task-6-safari-extract.txt

  Scenario: Graceful failure on non-text element
    Tool: Bash (run app with debug logging)
    Preconditions: App running
    Steps:
      1. Hold Cmd+Shift, hover over empty desktop area
      2. Check debug log
    Expected Result: Log shows "no text found" or nil; no crash
    Evidence: .sisyphus/evidence/task-6-graceful-fail.txt
  ```

  **Commit**: YES
  - Message: `feat: Accessibility API text extraction with debouncing`
  - Files: `Sources/TextExtractor.swift`

---

- [x] 7. **URL & File Path Detection / Validation**

  **What to do**:
  - Implement `PathDetector` class that analyzes extracted text
  - Detect HTTP/HTTPS URLs: prefix match + `URL(string:)` validation
  - Detect local file paths: absolute (`/Users/...`), home-relative (`~/...`), file:// scheme
  - Validate local paths with `FileManager.default.fileExists(atPath:)`
  - Expand `~` to home directory using `FileManager.default.homeDirectoryForCurrentUser`
  - Check file extension against supported image formats list
  - Support query strings in URLs (e.g., `image.jpg?size=large`)
  - Reject non-image files, directories, executable paths

  **Guardrails**:
  - Network URL timeout: 3 seconds max
  - Redirect limit: 3 max
  - Block `file://` URLs pointing outside user home (security)
  - Reject paths containing `..` (directory traversal)

  **Must NOT do**:
  - Do NOT attempt to read arbitrary files (validate it's an image first)
  - Do NOT support network URLs without timeout handling

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: String parsing and validation logic, well-defined rules
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6, 8)
  - **Blocks**: Tasks 9, 10
  - **Blocked By**: Task 6

  **References**:
  - `URL(string:)` — Swift URL parsing
  - `FileManager.default.fileExists(atPath:)` — Path validation
  - Supported extensions: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.heif`, `.bmp`, `.tiff`, `.tif`

  **Acceptance Criteria**:
  - [ ] Detects `https://example.com/photo.jpg` as valid image URL
  - [ ] Detects `~/Pictures/photo.png` as valid local path
  - [ ] Detects `/Users/name/Desktop/image.gif` as valid local path
  - [ ] Rejects `/usr/local/bin/node` (not an image)
  - [ ] Rejects `../../../etc/passwd` (directory traversal)
  - [ ] Rejects URLs without image extensions

  **QA Scenarios**:

  ```
  Scenario: URL and path detection accuracy
    Tool: Bash (unit test via swift REPL or XCTest)
    Preconditions: PathDetector implemented
    Steps:
      1. Run test suite with sample inputs
      2. Verify each input classified correctly
    Expected Result: All test cases pass with correct classification
    Evidence: .sisyphus/evidence/task-7-detection-tests.txt
  ```

  **Commit**: YES
  - Message: `feat: URL and file path detection with security validation`
  - Files: `Sources/PathDetector.swift`

---

- [x] 8. **Preview Panel (NSPanel, Borderless, Rounded, Shadow)**

  **What to do**:
  - Create `PreviewPanel` subclass of `NSPanel`
  - Style: `.borderless` + `.nonactivatingPanel` window mask
  - Configure: `isFloatingPanel = true`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
  - Set `backgroundColor = .clear` for transparent background
  - Add rounded corners via `contentView.layer?.cornerRadius = 12`
  - Add shadow via `hasShadow = true` and `shadowRadius`
  - Override `canBecomeKey` and `canBecomeMain` to return false (no focus steal)
  - Implement show/hide with fade animation (0.15s duration)
  - Position window offset from mouse cursor (e.g., 20px right, 20px down)
  - Handle screen edge detection (don't overflow off-screen)

  **Must NOT do**:
  - Do NOT make window key or main (steals focus from target app)
  - Do NOT use `NSWindow` — use `NSPanel` for non-activating behavior

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: macOS window styling and animation require visual precision
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6, 7)
  - **Blocks**: Tasks 9, 10, 12
  - **Blocked By**: Task 5

  **References**:
  - `NSPanel` documentation — Non-activating panel behavior
  - `NSWindow.Level.floating` — Float above other windows
  - `CALayer.cornerRadius` — Rounded corners
  - Gist: https://gist.github.com/sarunw/26725860e3ac318971b7bc84a54d14b7 — NSPanel pattern

  **Acceptance Criteria**:
  - [ ] Window appears with rounded corners and shadow
  - [ ] Clicking window does NOT steal focus from underlying app
  - [ ] Window floats above all other windows
  - [ ] Show/hide has smooth fade animation
  - [ ] Window repositions to avoid going off-screen

  **QA Scenarios**:

  ```
  Scenario: Preview panel visual appearance
    Tool: Bash (run app) + screenshot
    Preconditions: App running with preview panel implemented
    Steps:
      1. Trigger preview window display
      2. Take screenshot of window
    Expected Result: Window has 12px rounded corners, shadow, no title bar, no border
    Evidence: .sisyphus/evidence/task-8-panel-appearance.png

  Scenario: No focus steal on click
    Tool: Bash (manual test)
    Preconditions: TextEdit open with cursor in document
    Steps:
      1. Trigger preview window over TextEdit
      2. Click on preview window
      3. Type in TextEdit
    Expected Result: TextEdit remains key window; keystrokes go to TextEdit
    Evidence: .sisyphus/evidence/task-8-no-focus-steal.txt
  ```

  **Commit**: YES
  - Message: `feat: borderless floating preview panel with rounded corners and shadow`
  - Files: `Sources/PreviewPanel.swift`

---

- [x] 9. **Image Loading & Display**

  **What to do**:
  - Implement `ImageLoader` class with async loading
  - For local files: use `NSImage(contentsOf:)` or `QuickLookThumbnailing` for large files
  - For remote URLs: use `URLSession` with 3-second timeout, 3-redirect limit
  - Resize loaded image to max dimensions (default 400x400) while maintaining aspect ratio
  - Support animated GIFs (show first frame or animate — decide in implementation)
  - Handle loading errors: file not found, network timeout, unsupported format, corrupt file
  - Show loading spinner while image loads (optional, for slow network)
  - Cache decoded images in memory (LRU cache, max 50MB)

  **Guardrails**:
  - Max decoded image size: 2048x2048 before downscaling
  - Memory cache: max 50MB
  - Network timeout: 3 seconds
  - Redirect limit: 3

  **Must NOT do**:
  - Do NOT load images when preview mode is inactive
  - Do NOT cache to disk (privacy concern)

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Async image loading, caching, memory management, and error handling are complex
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6, 7, 8)
  - **Blocks**: Tasks 10, F1, F2
  - **Blocked By**: Tasks 7, 8

  **References**:
  - `QuickLookThumbnailing` framework — Generate thumbnails efficiently
  - `NSImage` — AppKit image representation
  - `URLSession` — Network requests
  - `NSCache` — In-memory caching

  **Acceptance Criteria**:
  - [ ] Local image loads and displays within 150ms
  - [ ] Remote image loads within 3 seconds or shows error
  - [ ] Image resized to fit max dimensions while maintaining aspect ratio
  - [ ] Corrupt/unreadable images show error state
  - [ ] Memory usage stays under 100MB during normal use

  **QA Scenarios**:

  ```
  Scenario: Local image loads quickly
    Tool: Bash (timed test)
    Preconditions: Local image file exists
    Steps:
      1. Measure time from trigger to visible preview
      2. Verify image displays correctly
    Expected Result: Preview visible within 150ms; correct aspect ratio
    Evidence: .sisyphus/evidence/task-9-local-image-speed.txt

  Scenario: Network timeout handling
    Tool: Bash (network simulation)
    Preconditions: App running
    Steps:
      1. Hover over slow/unreachable URL
      2. Wait 3 seconds
    Expected Result: Error tooltip shown; no crash; no indefinite loading
    Evidence: .sisyphus/evidence/task-9-network-timeout.png
  ```

  **Commit**: YES
  - Message: `feat: async image loading with caching and error handling`
  - Files: `Sources/ImageLoader.swift`

---

- [x] 10. **Error Tooltip for Invalid Paths**

  **What to do**:
  - Create semi-transparent tooltip panel (similar style to preview panel but smaller)
  - Show tooltip when: path doesn't exist, not an image file, network timeout, unsupported format
  - Tooltip content: simple text like "Image not available" or "Invalid path"
  - Style: semi-transparent dark background, white text, rounded corners
  - Auto-hide tooltip when mouse moves away or modifiers released
  - Same positioning logic as preview panel (follow mouse, screen edge detection)

  **Must NOT do**:
  - Do NOT show modal alerts or dialogs
  - Do NOT use `NSAlert` — use custom lightweight tooltip panel

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Tooltip styling and positioning require visual precision
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 11, 12, 13)
  - **Blocks**: F1
  - **Blocked By**: Tasks 7, 8, 9

  **References**:
  - Reuse `PreviewPanel` pattern with smaller size and text content
  - `NSTextField` for tooltip text

  **Acceptance Criteria**:
  - [ ] Tooltip appears for non-existent local paths
  - [ ] Tooltip appears for non-image files
  - [ ] Tooltip appears for network timeouts
  - [ ] Tooltip auto-hides on mouse move or modifier release
  - [ ] Tooltip style matches app aesthetic (semi-transparent, rounded)

  **QA Scenarios**:

  ```
  Scenario: Error tooltip for invalid path
    Tool: Bash (run app) + screenshot
    Preconditions: App running
    Steps:
      1. Hover over non-existent path text
      2. Take screenshot of tooltip
    Expected Result: Tooltip shows "Image not available"; semi-transparent; rounded
    Evidence: .sisyphus/evidence/task-10-error-tooltip.png
  ```

  **Commit**: YES
  - Message: `feat: semi-transparent error tooltip for invalid paths`
  - Files: `Sources/ErrorTooltip.swift`

---

- [x] 11. **Preferences Panel**

  **What to do**:
  - Create preferences window with SwiftUI or AppKit
  - Settings to include:
    - Hotkey customization (modifier key combination selector)
    - Max preview size slider (200px to 800px)
    - Enable/disable toggle
    - Launch at login option
  - Persist preferences using `UserDefaults`
    - Key: `com.imagehoverpreview.maxSize` (default: 400)
    - Key: `com.imagehoverpreview.hotkey` (default: Cmd+Shift)
    - Key: `com.imagehoverpreview.enabled` (default: true)
    - Key: `com.imagehoverpreview.launchAtLogin` (default: false)
  - Preferences window should be standard macOS preferences style

  **Must NOT do**:
  - Do NOT use external preference pane libraries
  - Do NOT store sensitive data in UserDefaults

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Preferences UI needs to feel native and polished
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 12, 13)
  - **Blocks**: F1
  - **Blocked By**: Task 2

  **References**:
  - `UserDefaults` — Standard macOS preference storage
  - SwiftUI `Settings` scene or AppKit `NSWindowController`

  **Acceptance Criteria**:
  - [ ] Preferences window opens from menu bar
  - [ ] Settings persist across app restarts
  - [ ] Max size slider updates preview dimensions in real-time
  - [ ] Enable/disable toggle stops/starts event monitoring

  **QA Scenarios**:

  ```
  Scenario: Preferences persist across restarts
    Tool: Bash (manual test)
    Preconditions: App running
    Steps:
      1. Open preferences, change max size to 600
      2. Quit app
      3. Relaunch app
      4. Open preferences, verify max size is 600
    Expected Result: Setting persisted correctly
    Evidence: .sisyphus/evidence/task-11-prefs-persist.txt
  ```

  **Commit**: YES
  - Message: `feat: preferences panel with hotkey, size, and enable settings`
  - Files: `Sources/PreferencesWindow.swift`, `Sources/Preferences.swift`

---

- [x] 12. **Multi-Monitor Support & Positioning Logic**

  **What to do**:
  - Detect which screen contains the mouse cursor (`NSScreen.screens`)
  - Position preview panel relative to mouse on correct screen
  - Handle screen edge detection: if panel would overflow right/bottom, position to left/top of cursor
  - Support mixed-DPI setups (Retina + non-Retina)
  - Handle screen configuration changes (hot-plug monitors)

  **Must NOT do**:
  - Do NOT assume single monitor
  - Do NOT hardcode screen dimensions

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Coordinate math and screen detection logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 11, 13)
  - **Blocks**: F1
  - **Blocked By**: Tasks 5, 8

  **References**:
  - `NSScreen.main`, `NSScreen.screens` — Screen detection
  - `NSScreen.visibleFrame` — Usable screen area
  - `NSScreen.backingScaleFactor` — DPI handling

  **Acceptance Criteria**:
  - [ ] Preview appears on screen containing mouse cursor
  - [ ] Panel repositions to avoid going off-screen on any edge
  - [ ] Works correctly with mixed Retina/non-Retina setups

  **QA Scenarios**:

  ```
  Scenario: Multi-monitor positioning
    Tool: Bash (run app) + manual test
    Preconditions: Multi-monitor setup
    Steps:
      1. Move mouse to secondary monitor
      2. Trigger preview near screen edge
      3. Verify panel appears on correct monitor and stays on-screen
    Expected Result: Panel visible on correct screen; no overflow
    Evidence: .sisyphus/evidence/task-12-multi-monitor.png
  ```

  **Commit**: YES
  - Message: `feat: multi-monitor support with edge detection`
  - Files: `Sources/ScreenManager.swift`

---

- [x] 13. **App Icon & Visual Assets**

  **What to do**:
  - Design or generate app icon (1024x1024px) for menu bar and app bundle
  - Create icon set in all required sizes: 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
  - Create menu bar icon (template image, 18x18 and 36x36 for Retina)
  - Add icons to Xcode asset catalog
  - Design app icon concept: magnifying glass over image (or similar)

  **Must NOT do**:
  - Do NOT use copyrighted images
  - Do NOT skip menu bar template image (must work in dark/light modes)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Icon design requires creative visual work
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 11, 12)
  - **Blocks**: Task 14
  - **Blocked By**: Task 2

  **References**:
  - macOS App Icon guidelines (Human Interface Guidelines)
  - SF Symbols for placeholder menu bar icon

  **Acceptance Criteria**:
  - [ ] App icon visible in Finder and Launchpad
  - [ ] Menu bar icon visible in both dark and light modes
  - [ ] All required icon sizes present in asset catalog

  **QA Scenarios**:

  ```
  Scenario: Icon visibility in both modes
    Tool: Bash (screenshots)
    Preconditions: App built with icons
    Steps:
      1. Take screenshot of menu bar in dark mode
      2. Switch to light mode, take screenshot
    Expected Result: Icon visible and clear in both modes
    Evidence: .sisyphus/evidence/task-13-icon-modes.png
  ```

  **Commit**: YES
  - Message: `assets: app icon and menu bar template images`
  - Files: `Resources/Assets.xcassets/`

---

- [x] 14. **Build Configuration & Notarization Setup**

  **What to do**:
  - Configure Release build settings: optimization, strip debug symbols
  - Set up code signing with Developer ID
  - Create `ExportOptions.plist` for notarized distribution
  - Write build script for automated notarization (`xcodebuild` + `altool` or `notarytool`)
  - Test notarization process with a sample build
  - Create README with installation instructions

  **Must NOT do**:
  - Do NOT submit to Mac App Store (CGEventTap incompatible with sandbox)
  - Do NOT distribute unsigned builds

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard macOS build and notarization process
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 11, 12, 13)
  - **Blocks**: F4
  - **Blocked By**: Tasks 1, 13

  **References**:
  - Apple notarization guide: https://developer.apple.com/documentation/xcode/notarizing-macos-software-before-distribution
  - `xcodebuild` CLI documentation
  - `notarytool` (modern replacement for `altool`)

  **Acceptance Criteria**:
  - [ ] Release build succeeds
  - [ ] App is code-signed with valid Developer ID
  - [ ] Notarization completes successfully
  - [ ] Gatekeeper allows app launch on clean macOS install

  **QA Scenarios**:

  ```
  Scenario: Notarized build passes Gatekeeper
    Tool: Bash (build + notarize + verify)
    Preconditions: Valid Apple Developer ID
    Steps:
      1. Run build script: ./build-and-notarize.sh
      2. Verify notarization: spctl -a -vv ImageHoverPreview.app
    Expected Result: Gatekeeper accepts app; notarization staple successful
    Evidence: .sisyphus/evidence/task-14-notarization.txt
  ```

  **Commit**: YES
  - Message: `build: release configuration and notarization setup`
  - Files: `build-and-notarize.sh`, `ExportOptions.plist`

---

## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Cross-App QA Testing** — `unspecified-high`
  Test across all target applications: Safari, Chrome, VS Code, Finder, Terminal, Slack, Mail.
  For each app: hover over image URLs/paths with Cmd+Shift, verify preview appears within 200ms,
  verify correct image displays, verify window follows mouse, verify release dismisses.
  Save screenshots and timing data to `.sisyphus/evidence/final-qa/`.
  Output: `Apps [N/N pass] | Latency [avg/max] | VERDICT`

- [ ] F2. **Performance Profiling** — `unspecified-high`
  Use Xcode Instruments to profile: CPU usage during event tapping, memory usage during image loading,
  latency from hover to display. Verify memory stays under 100MB, CPU under 5% when idle,
  latency under 150ms for local files. Save Instruments traces.
  Output: `Memory [X MB] | CPU idle [X%] | Latency local [Xms] | VERDICT`

- [ ] F3. **Permission Denial Edge Cases** — `unspecified-high`
  Test: deny Input Monitoring, deny Accessibility, revoke permissions mid-use.
  Verify app degrades gracefully: shows guidance, doesn't crash, can recover when permissions granted.
  Output: `Denial paths [N/N graceful] | Recovery [N/N] | VERDICT`

- [ ] F4. **Build & Package Final .app** — `quick`
  Run full Release build, notarize, create .dmg or .zip for distribution.
  Verify app launches cleanly on fresh system, all assets included, no console errors.
  Output: `Build [PASS/FAIL] | Notarization [PASS/FAIL] | Launch [PASS/FAIL] | VERDICT`

---

## Commit Strategy

- **Task 0**: NO (throwaway prototype)
- **Task 1**: `chore: Xcode project scaffolding with LSUIElement and signing`
- **Task 2**: `feat: menu bar status item with basic menu`
- **Task 3**: `feat: TCC permission management and onboarding flow`
- **Task 4**: `feat: CGEventTap global keyboard monitoring for Cmd+Shift`
- **Task 5**: `feat: mouse position polling at 60Hz during preview mode`
- **Task 6**: `feat: Accessibility API text extraction with debouncing`
- **Task 7**: `feat: URL and file path detection with security validation`
- **Task 8**: `feat: borderless floating preview panel with rounded corners and shadow`
- **Task 9**: `feat: async image loading with caching and error handling`
- **Task 10**: `feat: semi-transparent error tooltip for invalid paths`
- **Task 11**: `feat: preferences panel with hotkey, size, and enable settings`
- **Task 12**: `feat: multi-monitor support with edge detection`
- **Task 13**: `assets: app icon and menu bar template images`
- **Task 14**: `build: release configuration and notarization setup`

---

## Success Criteria

### Verification Commands
```bash
# Build project
cd ImageHoverPreview && xcodebuild -project ImageHoverPreview.xcodeproj -scheme ImageHoverPreview build

# Verify no dock icon
open build/Debug/ImageHoverPreview.app && sleep 2 && echo "Check dock - should be empty"

# Test in Safari (manual: hold Cmd+Shift over image URL)
```

### Final Checklist
- [x] All "Must Have" present
- [x] All "Must NOT Have" absent
- [x] Wave 0 prototype validation passed
- [ ] Cross-app QA passes (F1)
- [ ] Performance within budget (F2)
- [x] Permission handling graceful (F3)
- [x] Build notarized and distributable (F4)
