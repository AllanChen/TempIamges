# ImageHoverPreview

A native macOS menubar utility that shows image previews when holding Cmd+Shift and hovering over URLs or local file paths in any application.

## Features

- Global keyboard monitoring (Cmd+Shift) to activate preview mode
- Accessibility API text extraction under mouse cursor
- URL and local file path detection with security validation
- Floating preview window with rounded corners and shadow
- Error tooltip for invalid paths
- Preferences panel for hotkey customization, max preview size, and enable toggle
- Multi-monitor support with edge detection
- Menu bar icon with status indicators
- Permission onboarding on first launch

## Supported Image Formats

JPEG, PNG, GIF, WebP, HEIC, HEIF, BMP, TIFF

## Requirements

- macOS 12.0+
- Xcode 14.0+ (for building)
- Input Monitoring permission
- Accessibility permission

## Building

```bash
./build.sh
```

Or manually:

```bash
xcodegen generate
xcodebuild -project ImageHoverPreview.xcodeproj -scheme ImageHoverPreview build
```

## Installation

1. Build the project
2. Copy `build/Release/ImageHoverPreview.app` to `/Applications`
3. Launch the app
4. Grant required permissions when prompted

## Permissions

The app requires two system permissions:

1. **Input Monitoring** - To detect Cmd+Shift key presses globally
2. **Accessibility** - To extract text under the mouse cursor

Both permissions can be granted through System Settings > Privacy & Security.

### Development Workflow for Permissions

When developing with Xcode, requesting Input Monitoring permission requires restarting the app, which disconnects Xcode's console. To solve this:

#### 1. Xcode Scheme Configuration (Already Configured)

The project includes `IDELogRedirectionPolicy=oslogToStdio` in the shared scheme, which redirects logs to standard IO so they continue appearing in Xcode console even after app restart.

#### 2. Permission Polling

The onboarding window automatically polls for permission status changes every second when System Settings is opened. This means:
- Click "Open Settings" in the onboarding window
- Enable the permission in System Settings
- Return to the app - it will detect the change without restart

#### 3. Alternative: Manual Permission Reset

If you need to re-test the permission flow:

```bash
# Reset Input Monitoring permission
tccutil reset ListenEvent com.imagehoverpreview.app

# Reset Accessibility permission
tccutil reset Accessibility com.imagehoverpreview.app

# Reset all permissions for the app
tccutil reset All com.imagehoverpreview.app
```

#### 4. Viewing Logs

Logs are available in multiple ways:
- **Xcode Console**: Real-time logs during debugging (with `IDELogRedirectionPolicy`)
- **Console.app**: Open Applications > Utilities > Console, search for "ImageHoverPreview"
- **Log File**: `~/Library/Application Support/ImageHoverPreview/app.log`

#### 5. Testing Permission Changes Without Restart

The app polls for permission status in the onboarding window. If you need to check permissions programmatically:

```swift
let permissionManager = PermissionManager.shared

// Check current status
let inputMonitoringGranted = permissionManager.isInputMonitoringGranted
let accessibilityGranted = permissionManager.isAccessibilityGranted

// Request permissions
permissionManager.requestInputMonitoring()
permissionManager.requestAccessibility()

// Open system settings
permissionManager.openInputMonitoringSettings()
permissionManager.openAccessibilitySettings()
```

## Usage

1. Launch the app (it runs as a menubar app with no dock icon)
2. Hold **Cmd+Shift** while hovering over image URLs or file paths
3. A preview window will appear near the cursor
4. Release the keys to dismiss the preview

## Preferences

Click the menubar icon and select "Preferences..." to customize:

- Enable/disable preview functionality
- Maximum preview size (200px - 800px)
- Activation hotkey (Command, Shift, or both)
- Launch at login option

## Architecture

```
Sources/
├── AppDelegate.swift           - App lifecycle and component coordination
├── KeyboardMonitor.swift       - Global CGEventTap for modifier key detection
├── MouseTracker.swift          - Mouse position polling at 60Hz
├── TextExtractor.swift         - Accessibility API text extraction with debouncing
├── PathDetector.swift          - URL and file path detection/validation
├── PreviewPanel.swift          - Borderless floating preview window
├── ImageLoader.swift           - Async image loading with caching
├── ErrorTooltip.swift          - Semi-transparent error tooltip
├── Preferences.swift           - UserDefaults preference model
├── PreferencesWindow.swift     - Preferences panel UI
├── ScreenManager.swift         - Multi-monitor support and positioning
├── StatusBarController.swift   - Menu bar icon and menu
├── PermissionManager.swift     - TCC permission checks and requests
├── OnboardingWindow.swift      - First-launch permission onboarding
└── main.swift                  - App entry point
```

## License

Copyright 2026. All rights reserved.
