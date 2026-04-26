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
