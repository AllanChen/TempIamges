import AppKit
import UniformTypeIdentifiers
import ImageIO
import libwebp
import WebKit
import Vision

let ossImageHostingWidgetID = "55e64c7e-f079-448a-b5bd-7315b2589019"

final class ImageInspectSession {
    enum Mode { case focus, browse, compare }
    enum ComparisonStyle { case sideBySide, slider }

    var infos: [MediaInfo]
    var images: [NSImage?]
    var focusedIndex: Int
    var mode: Mode
    var compareIndices: (Int, Int)?
    var comparisonStyle: ComparisonStyle = .sideBySide
    /// Which compare slot a filmstrip tap replaces: 0 = left (A), 1 = right (B).
    var activeCompareSlot = 1
    var metadata: [ImageTechnicalMetadata?]
    var failedIndices = Set<Int>()
    /// Results created in this inspect session keep their NEW tag even if
    /// their task history changes or is cleared.
    var generatedResultPaths = Set<String>()

    init(infos: [MediaInfo], images: [NSImage?], focusedIndex: Int, mode: Mode? = nil) {
        self.infos = infos
        self.images = images
        self.focusedIndex = min(max(0, focusedIndex), max(0, infos.count - 1))
        // Multiple items still open as a single-image Focus view. The
        // filmstrip remains available; Compare is entered explicitly.
        self.mode = mode ?? .focus
        self.metadata = Array(repeating: nil, count: infos.count)
        if self.mode == .compare, infos.count >= 2 {
            compareIndices = (0, 1)
        }
    }
}

final class ImageInspectWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onOpenVideo: ((MediaInfo) -> Void)?
    var onOpenContent: ((MediaInfo) -> Void)?

    private let imageLoader: ImageLoader
    private let pathDetector = PathDetector()
    private var session: ImageInspectSession?
    private var loadGeneration = UUID()
    private var pendingThumbnailIndices = Set<Int>()
    private var requestedDetailIndices = Set<Int>()

    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Image information".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let openURLButton = InspectToolbarButton(symbol: "globe", tooltip: "Open image URL".localized)
    private let actionsButton = InspectToolbarButton(symbol: "ellipsis", tooltip: "More".localized)
    private let widgetMarketButton = InspectToolbarButton(symbol: "square.grid.2x2", tooltip: "Widget Market".localized)
    private let widgetTasksButton = InspectToolbarButton(symbol: "tray.full", tooltip: "Tasks".localized)
    private let taskBadge = NSTextField(labelWithString: "")
    private let pinButton = InspectToolbarButton(symbol: "pin", tooltip: "Pin on Top".localized)
    private let flipIconButton = InspectToolbarButton(symbol: "arrow.left.and.right", tooltip: "Flip".localized)
    private let focusIconButton = InspectToolbarButton(symbol: "photo", tooltip: "Focus".localized)
    private let compareIconButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Compare".localized)
    private let sliderIconButton = InspectToolbarButton(symbol: "slider.horizontal.3", tooltip: "Slider".localized)
    private let fitIconButton = InspectToolbarButton(symbol: "arrow.up.left.and.arrow.down.right", tooltip: "Fit".localized)
    private let captureIconButton = InspectToolbarButton(symbol: "crop", tooltip: "Capture".localized)
    /// The capture overlay while it is open, and the view that had focus before it.
    private var captureEditor: CaptureEditorView?
    private weak var captureReturnResponder: NSResponder?
    /// Called with the saved file once a capture is written; the app opens it
    /// in a new Image Inspect window.
    var onCaptured: ((URL) -> Void)?
    private var isPinned = false
    private var autoHideChromeEnabled = true
    private var chromeIsHidden = false
    private var autoHideWorkItem: DispatchWorkItem?
    private var autoHideMouseMonitor: Any?
    // Figma workbench chrome: titlebar / toolbar / canvas+overlays / inspector / statusbar.
    private lazy var backButton = PanelStyle.makeQuietButton(title: "‹", target: self, action: #selector(backTapped))
    private lazy var rotateButton = PanelStyle.makeQuietButton(title: "Rotate".localized, target: self, action: #selector(directionTapped))
    private lazy var flipButton = PanelStyle.makeQuietButton(title: "A  Flip ▾".localized, target: self, action: #selector(flipMenuTapped))
    private lazy var tasksTextButton = PanelStyle.makeQuietButton(title: "•  Tasks".localized, target: self, action: #selector(widgetTasksTapped))
    private lazy var widgetTextButton = PanelStyle.makeQuietButton(title: "Widget".localized, target: self, action: #selector(widgetMarketTapped))
    private let directionButton = InspectToolbarButton(symbol: "arrow.clockwise", tooltip: "Direction".localized)
    private let zoomOutButton = InspectToolbarButton(symbol: "minus.magnifyingglass", tooltip: "Zoom Out".localized)
    private let zoomInButton = InspectToolbarButton(symbol: "plus.magnifyingglass", tooltip: "Zoom In".localized)
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private lazy var fitButton = PanelStyle.makeQuietButton(title: "Fit".localized, target: self, action: #selector(fitToWindowTapped))
    private let titlebar = FigmaInspectTitlebar()
    private let trialBadge = BillingTrialBadge()
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let windowFilenameLabel = NSTextField(labelWithString: "")
    private lazy var closeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTrafficTapped))
    private lazy var minimizeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTrafficTapped))
    private lazy var zoomTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTrafficTapped))
    /// The v3 operation chrome is deliberately a single floating five-action
    /// toolbar, leaving the image itself as the entire window surface.
    private let toolbarBar = NSView()
    private let modeSwitcher = CanvasModeSwitcher()
    private let statusbar = NSView()
    private let statusLeftLabel = NSTextField(labelWithString: "")
    private let statusCenterLabel = NSTextField(labelWithString: "Scroll to zoom  •  Drag to pan".localized)
    private let statusDot = PanelStyle.makeStatusDot(color: PanelStyle.accent)
    private let statusRightLabel = NSTextField(labelWithString: "")
    private let taskSummaryDot = PanelStyle.makeStatusDot(color: PanelStyle.accent)
    private let taskSummaryLabel = NSTextField(labelWithString: "")
    private let taskToast = TaskToastView()
    private let taskOverlayShade = InspectNonHitTestingView()
    private let runningImageBorder = InspectNonHitTestingView()
    private let runningImageIndicator = InspectNonHitTestingView()
    private let runningImageDot = PanelStyle.makeStatusDot(color: PanelStyle.success)
    private let copyResultURLButton = WidgetResultURLButton()
    /// Themed action menu panel (frosted dark, warm-cue selection); rebuilt
    /// per presentation so enabled states and titles are always fresh.
    private var actionsPanel: ActionMenuPanel?
    private lazy var toastWindow = InspectToastWindow()
    private let canvasContainer = MediaDropCanvasView()
    /// Frosted semi-transparent black base filling the window behind the media,
    /// so the 8pt inset between the image and the window edge reads as a dark
    /// frosted frame rather than a transparent gap.
    private let frostedBase = PanelStyle.makeFrostedBase(cornerRadius: 16)
    private let primaryViewport = InspectImageViewport()
    private let secondaryViewport = InspectImageViewport()
    private let sliderViewport = ImageRevealView()
    /// Figma Compare Mode "Compare / Divider": a 2pt dark seam (#0b0c0e)
    /// between the two panes so the split reads as an edge, not a gap.
    private let compareDivider = InspectNonHitTestingView()
    /// Inline file preview for mixed-content sessions: text/markdown/pdf/web
    /// render in the web view; video/unsupported/folder use the placeholder.
    private let fileWebView = InspectFileWebView()
    private let filePlaceholder = FilePlaceholderView()
    private var fileContentGeneration = UUID()
    private let filmstrip = ImageFilmstripView()
    private let infoPanel = FigmaImageInspectorView()
    /// The Image Information child window (attached to the right edge, outside
    /// the image), presenting `infoPanel` like the Widget Market panel.
    private lazy var infoWindow = ImageInfoPanel()
    private var isClosingProgrammatically = false
    /// In-window right inspector (280pt, collapsible) — V2 spec replaces the
    /// separate floating info window.
    private var infoVisible = false
    /// Slide-out OCR result panel — a child window.
    private lazy var ocrWindow = OCRResultWindow()
    private var ocrVisible = false
    private var ocrGeneration = UUID()
    private var ocrResults: [URL: InspectOCRResult] = [:]
    private var ocrPending = Set<URL>()
    private var ocrFailed = Set<URL>()
    private var ocrDisplayedURL: URL?
    private let ocrQueue = DispatchQueue(label: "Glance.ImageInspect.OCR", qos: .utility)
    private struct WidgetTextResultKey: Hashable {
        let taskID: UUID
        let outputPath: String
    }
    /// Each text artifact keeps its own result window beside the image.
    private var widgetTextResultWindows: [WidgetTextResultKey: WidgetTextResultWindow] = [:]
    private var widgetTextResultOrder: [WidgetTextResultKey] = []
    private var widgetTextResultSessionGeneration = UUID()
    private let widgetTextResultQueue = DispatchQueue(label: "Glance.WidgetTextResults", qos: .userInitiated)
    private var isRaisingWidgetTextResult = false
    private var widgetInputPanel: WidgetInputPanel?
    private var handledWidgetTaskIDs = Set<UUID>()

    init(imageLoader: ImageLoader) {
        self.imageLoader = imageLoader
        let initialFrame = Self.initialDesignFrame()
        super.init(contentRect: initialFrame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Image Inspect".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // The window contains several high-resolution CALayer viewports. The
        // default NSWindow.zoom animation repeatedly lays out and redraws
        // those layers, which appears as a stutter on zoom in/out.
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        // The window is the image: it takes the focused image's aspect ratio and
        // the media fills every point, so no dark plate should ever show through.
        // A clear background also prevents a one-frame black flash on open/resize.
        backgroundColor = .clear
        isOpaque = false
        minSize = NSSize(width: 240, height: 160)
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        delegate = self
        buildUI()
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        handledWidgetTaskIDs = Set(WidgetTaskManager.shared.records.filter { $0.phase == .completed }.map(\.id))
        autoHideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleAutoHideScreenPoint(NSEvent.mouseLocation)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(localizationDidChange),
                                               name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(widgetTasksDidChange),
                                               name: WidgetTaskManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(imageWindowGeometryDidChange),
                                               name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(imageWindowGeometryDidChange),
                                               name: NSWindow.didResizeNotification, object: self)
    }

    private static let designSize = NSSize(width: 1554, height: 1012)

    /// Aspect ratio (w/h) the window has been sized to. Nil until the first
    /// image resolves, at which point the window is resized to match it so the
    /// image fills the window with no letterbox plate. The floating toolbar
    /// keeps its Figma size whenever the image window has room for it.
    private var windowImageAspect: CGFloat?
    /// The last image size the window was fitted to, so we don't re-fit on every
    /// re-render of the same image.
    private var fittedImageSize: CGSize?

    private static func initialDesignFrame() -> NSRect {
        let location = NSEvent.mouseLocation
        guard let screen = ScreenManager.shared.screenForMouseLocation(location) ?? NSScreen.main else {
            return NSRect(origin: location, size: designSize)
        }
        let visible = screen.visibleFrame
        let scale = min(1, visible.width / designSize.width, visible.height / designSize.height)
        return ScreenManager.shared.centerFrame(
            for: NSSize(width: designSize.width * scale, height: designSize.height * scale),
            on: screen
        )
    }

    /// Resize the window so its content exactly matches the focused image's
    /// aspect ratio, keeping the window centered on its current position and
    /// clamped fully on-screen (CLAUDE.md rule #7). The image then fills the
    /// window edge to edge — no black background is ever visible.
    private func fitWindowToImage(_ imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        if let fitted = fittedImageSize, fitted == imageSize { return }
        fittedImageSize = imageSize

        let aspect = imageSize.width / imageSize.height
        windowImageAspect = aspect
        contentAspectRatio = NSSize(width: aspect, height: 1)

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = ScreenManager.shared.screenForMouseLocation(center)
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        // Prefer the image's native pixel size; shrink to fit the screen while
        // preserving aspect. Never upscale past the display.
        let maxW = visible.width * 0.96
        let maxH = visible.height * 0.96
        var contentW = imageSize.width
        var contentH = imageSize.height
        let downscale = min(1, maxW / contentW, maxH / contentH)
        contentW *= downscale
        contentH *= downscale

        let newContentSize = NSSize(width: contentW.rounded(), height: contentH.rounded())
        let newFrameSize = frameRect(forContentRect: NSRect(origin: .zero, size: newContentSize)).size
        // Keep the window centered on where it currently sits, then clamp.
        var origin = NSPoint(x: center.x - newFrameSize.width / 2,
                             y: center.y - newFrameSize.height / 2)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - newFrameSize.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - newFrameSize.height))
        setFrame(NSRect(origin: origin, size: newFrameSize), display: true, animate: false)
    }

    deinit {
        autoHideWorkItem?.cancel()
        if let autoHideMouseMonitor {
            NSEvent.removeMonitor(autoHideMouseMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func show(infos: [MediaInfo], loaded: [LoadedMedia?], focusedIndex: Int,
              preferredMode: ImageInspectSession.Mode? = nil) {
        guard !infos.isEmpty else { return }
        let images = loaded.map { media -> NSImage? in
            guard case .image(let image, _) = media else { return nil }
            return image
        }
        session = ImageInspectSession(infos: infos, images: images, focusedIndex: focusedIndex,
                                      mode: preferredMode)
        Logger.info("ImageInspectWindow: opened \(infos.count) item(s) in \(session?.mode == .compare ? "compare" : "focus") mode")
        // V3 opens directly into the Figma Simple Operation state: image first,
        // no persistent inspector, status bar, toast, or filmstrip.
        infoVisible = false
        infoButton.isActive = false
        infoWindow.dismiss()
        dismissWidgetTextResults()
        widgetInputPanel?.close()
        widgetInputPanel = nil
        // Re-fit the window to the next image that resolves.
        fittedImageSize = nil
        // If the focused image is already loaded (e.g. reopened), fit now so the
        // window opens at the right shape instead of the 3:2 design default.
        if session?.mode != .compare,
           let focused = session?.focusedIndex,
           let preloaded = images[safe: focused] ?? nil {
            fitWindowToImage(preloaded.size)
        }
        titlebar.alphaValue = 1
        titlebar.isHidden = false
        toolbarBar.alphaValue = 1
        toolbarBar.isHidden = false
        chromeIsHidden = false
        statusbar.isHidden = true
        filmstrip.alphaValue = 1
        // Multi-image sessions show the thumbnail strip for quick switching;
        // renderSession() re-applies this from the live session too.
        filmstrip.isHidden = !shouldShowFilmstrip(for: infos)
        taskOverlayShade.isHidden = filmstrip.isHidden
        taskOverlayShade.alphaValue = filmstrip.isHidden ? 0 : 1
        taskSummaryLabel.isHidden = true
        taskSummaryDot.isHidden = true
        taskToast.isHidden = true
        loadGeneration = UUID()
        ocrGeneration = UUID()
        ocrResults.removeAll()
        ocrPending.removeAll()
        ocrFailed.removeAll()
        ocrDisplayedURL = nil
        pendingThumbnailIndices.removeAll()
        requestedDetailIndices.removeAll()
        renderSession()
        loadSessionImages(generation: loadGeneration)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        handleAutoHideScreenPoint(NSEvent.mouseLocation)
    }

    func windowWillClose(_ notification: Notification) {
        actionsPanel?.dismissChain()
        actionsPanel = nil
        autoHideWorkItem?.cancel()
        infoWindow.dismiss()
        removeChildWindow(toastWindow)
        toastWindow.orderOut(nil)
        removeChildWindow(ocrWindow)
        ocrWindow.orderOut(nil)
        ocrVisible = false
        ocrGeneration = UUID()
        ocrResults.removeAll()
        ocrPending.removeAll()
        ocrFailed.removeAll()
        ocrDisplayedURL = nil
        dismissWidgetTextResults()
        widgetInputPanel?.close()
        widgetInputPanel = nil
        let closedSources = session?.infos.map(\.url) ?? []
        session = nil
        loadGeneration = UUID()
        pendingThumbnailIndices.removeAll()
        requestedDetailIndices.removeAll()
        // Failed/interrupted task markers are not permanent image metadata.
        // Clear them when this Image Inspect session closes.
        WidgetTaskManager.shared.clearFailed(for: closedSources)
        guard !isClosingProgrammatically else { return }
        onClose?()
    }

    /// Close without restoring the app that was active before Image Inspect.
    /// Used when a drop hands the user directly to another Glance viewer.
    func closeForViewerHandoff() {
        isClosingProgrammatically = true
        close()
        isClosingProgrammatically = false
    }

    override func cancelOperation(_ sender: Any?) {
        guard let session else { return }
        if session.mode == .compare {
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.compareIndices = nil
            renderSession()
        } else {
            closeAndRestore()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The capture overlay owns the keyboard while it is open.
        if let editor = captureEditor {
            let isShortcut = event.modifierFlags.contains([.command, .shift])
                && event.charactersIgnoringModifiers?.lowercased() == "x"
            if event.keyCode == 53 || isShortcut { endCapture(); return true }
            if event.keyCode == 36 || event.keyCode == 76 { editor.keyDown(with: event); return true }
            return super.performKeyEquivalent(with: event)
        }
        // A presented sheet owns its keyboard input. In particular, do not
        // let the image window's global ⌘V shortcut consume paste intended
        // for the URL field in the Open sheet.
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        guard session != nil else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            if key.lowercased() == "x", event.modifierFlags.contains(.shift) { beginCapture(); return true }
            if key == "0" { activeViewports.forEach { $0.fitToView() }; return true }
            if key == "1" { activeViewports.forEach { $0.setActualSize() }; return true }
            if key.lowercased() == "w" { closeAndRestore(); return true }
            if key.lowercased() == "i" { toggleInfo(); return true }
            // Image actions only intercept when the active item is an image —
            // otherwise fall through so e.g. ⌘C still copies text in the
            // inline file preview.
            if key.lowercased() == "l", activeItemIsImage { rotateActive(byQuarters: -1); return true }
            if key.lowercased() == "r", activeItemIsImage { rotateActive(byQuarters: 1); return true }
            if key.lowercased() == "c", activeItemIsImage {
                if session?.mode == .compare, session?.comparisonStyle == .slider,
                   sliderViewport.copySelectedText() { return true }
                if let selectedViewport = firstResponder as? InspectImageViewport,
                   activeViewports.contains(where: { $0 === selectedViewport }),
                   selectedViewport.copySelectedText() { return true }
                if activeViewports.contains(where: { $0.copySelectedText() }) { return true }
                copyActiveImage()
                return true
            }
            if key.lowercased() == "s", activeItemIsImage { quickSaveActiveImage(); return true }
            if key.lowercased() == "v", pasteRemoteImageFromClipboard() { return true }
        } else if activeItemIsImage, !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) {
            // Viewer keys without a modifier, like other image viewers. Only when
            // an image is active so typing in an inline file preview still works.
            switch key {
            case "0": activeViewports.forEach { $0.fitToView() }; return true
            case "1": activeViewports.forEach { $0.setActualSize() }; return true
            case "+", "=": activeViewports.forEach { $0.zoomBy(1.25) }; return true
            case "-", "_": activeViewports.forEach { $0.zoomBy(0.8) }; return true
            case "?": showKeyboardHelp(); return true
            default: break
            }
        }
        switch event.keyCode {
        case 53:  // Esc
            handleEscape()
            return true
        case 123:
            navigate(by: -1)
            return true
        case 124:
            navigate(by: 1)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// A red filmstrip tile explains itself when clicked: the failure reason
    /// with Retry / Dismiss right there, instead of a trip to the Task Center.
    private func offerFailureActions(forItemAt index: Int) {
        guard let session, session.infos.indices.contains(index),
              let record = WidgetTaskManager.shared.latestRecord(for: session.infos[index].url),
              record.phase.isFailure,
              let tile = filmstrip.screenFrame(ofItemAt: index) else { return }
        let reason = (record.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = reason.isEmpty ? "The task stopped without reporting a reason.".localized
                                   : (reason.count > 60 ? String(reason.prefix(60)) + "…" : reason)
        let id = record.id
        let panel = ActionMenuPanel(entries: [
            ActionMenuEntry(title: "\(record.commandName) · \("Failed".localized)", enabled: false),
            ActionMenuEntry(title: shown, enabled: false),
            .separator(),
            ActionMenuEntry(title: "Retry".localized, action: { WidgetTaskManager.shared.retry(id) }),
            ActionMenuEntry(title: "Dismiss".localized, action: { WidgetTaskManager.shared.remove(id) })
        ])
        actionsPanel?.dismissChain()
        actionsPanel = panel
        // Open upward from the tile so the menu never covers the filmstrip.
        panel.present(at: NSPoint(x: tile.minX, y: tile.maxY + 8 + panel.frame.height))
    }

    /// Esc steps back one level: leave Compare, then close the info panel,
    /// then the window itself.
    private func handleEscape() {
        if let session, session.mode == .compare {
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.compareIndices = nil
            renderSession()
            return
        }
        if infoWindow.isVisible { infoWindow.dismiss(); return }
        closeAndRestore()
    }

    private func showKeyboardHelp() {
        toastWindow.showShortcuts(over: self)
    }

    override func sendEvent(_ event: NSEvent) {
        // AppKit may deliver trackpad magnify events to the window's responder
        // instead of the image view under the cursor. Route them explicitly so
        // Focus, side-by-side, and slider all use the same viewport gesture.
        if event.type == .magnify, let session {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            // A pinch that starts over the filmstrip must not reach the image
            // viewport underneath it.
            if !filmstrip.isHidden, filmstrip.alphaValue >= 0.05,
               filmstrip.frame.contains(point) { return }
            var handled = true
            if session.mode == .compare, session.comparisonStyle == .sideBySide {
                if primaryViewport.frame.contains(point) {
                    primaryViewport.magnify(with: event)
                } else if secondaryViewport.frame.contains(point) {
                    secondaryViewport.magnify(with: event)
                }
            } else if session.mode == .compare, session.comparisonStyle == .slider {
                sliderViewport.magnify(with: event)
            } else if !primaryViewport.isHidden {
                primaryViewport.magnify(with: event)
            } else {
                handled = false
            }
            if handled { return }
        }
        if event.type == .scrollWheel, let session {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            // The filmstrip floats over the image viewport. Route the wheel
            // here first so a mouse wheel or trackpad scroll over any tile
            // moves the thumbnail row instead of zooming/panning the image.
            if !filmstrip.isHidden, filmstrip.alphaValue >= 0.05,
               filmstrip.frame.contains(point) {
                filmstrip.scrollWheel(with: event)
                return
            }
            if session.mode == .compare, session.comparisonStyle == .sideBySide {
                if primaryViewport.frame.contains(point) {
                    primaryViewport.scrollWheel(with: event)
                    return
                } else if secondaryViewport.frame.contains(point) {
                    secondaryViewport.scrollWheel(with: event)
                    return
                }
            } else if session.mode == .compare, session.comparisonStyle == .slider,
                      sliderViewport.frame.contains(point) {
                sliderViewport.scrollWheel(with: event)
                return
            } else if !primaryViewport.isHidden, primaryViewport.frame.contains(point) {
                primaryViewport.scrollWheel(with: event)
                return
            }
        }
        if event.type == .leftMouseDown,
           let session,
           session.mode == .compare,
           session.comparisonStyle == .sideBySide {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            let overlays: [NSView] = [titlebar, toolbarBar, filmstrip, statusbar,
                                      modeSwitcher, taskToast,
                                      taskSummaryLabel, taskSummaryDot]
            let hitsVisibleOverlay = overlays.contains { view in
                !view.isHidden && view.alphaValue >= 0.05 && view.frame.contains(point)
            }
            if !hitsVisibleOverlay {
                if primaryViewport.frame.contains(point) {
                    selectCompareSlot(0)
                } else if secondaryViewport.frame.contains(point) {
                    selectCompareSlot(1)
                }
            }
        }
        if event.type == .mouseMoved {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            updateInfoHighlight(atWindowPoint: event.locationInWindow)
            handleAutoHideMouse(atCanvasPoint: point)
        }
        super.sendEvent(event)
    }

    override func mouseEntered(with event: NSEvent) {
        handleAutoHideScreenPoint(NSEvent.mouseLocation)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        autoHideWorkItem?.cancel()
        hideChrome(animated: true)
        super.mouseExited(with: event)
    }

    /// Highlight the info block for whichever on-screen image the cursor is over.
    private func updateInfoHighlight(atWindowPoint windowPoint: NSPoint) {
        guard let session, infoVisible else { return }
        let p = canvasContainer.convert(windowPoint, from: nil)

        var hovered: Int?
        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.comparisonStyle == .sideBySide {
            if primaryViewport.frame.contains(p) { hovered = a }
            else if secondaryViewport.frame.contains(p) { hovered = b }
        } else if session.mode == .compare, let (a, _) = session.compareIndices {
            // Slider shows A underneath B; treat the whole canvas as image A.
            if sliderViewport.frame.contains(p) { hovered = a }
        } else if primaryViewport.frame.contains(p) {
            hovered = session.focusedIndex
        }
        // No image under the cursor: fall back to the default (active compare
        // slot in compare mode), instead of clearing the glow entirely.
        if hovered == nil {
            if session.mode == .compare, let (a, b) = session.compareIndices {
                hovered = session.activeCompareSlot == 0 ? a : b
            } else {
                hovered = session.focusedIndex
            }
        }
        infoPanel.highlight(index: hovered)
    }

    private var activeViewports: [InspectImageViewport] {
        guard let session else { return [] }
        if session.mode == .compare, session.comparisonStyle == .sideBySide {
            return [primaryViewport, secondaryViewport]
        }
        if session.mode == .compare { return [sliderViewport.viewport] }
        return [primaryViewport]
    }

    private func containsRecognizedText(atCanvasPoint point: NSPoint) -> Bool {
        guard let session else { return false }
        if session.mode == .compare, session.comparisonStyle == .slider {
            guard sliderViewport.frame.contains(point) else { return false }
            return sliderViewport.containsRecognizedText(
                at: sliderViewport.convert(point, from: canvasContainer))
        }
        for viewport in activeViewports where viewport.frame.contains(point) {
            if viewport.containsRecognizedText(at: viewport.convert(point, from: canvasContainer)) {
                return true
            }
        }
        return false
    }

    private func buildUI() {
        // Make the registered drop target the window's content view itself.
        // AppKit can otherwise lose the drag destination while walking the
        // layered viewport/WebKit hierarchy above a registered child view.
        contentView = canvasContainer
        let root = canvasContainer
        root.wantsLayer = true
        root.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        // Frosted semi-transparent black panel: the media is inset 8pt so this
        // dark frosted base shows as a thin frame around the image. Rounded
        // corners + a hairline edge make it read as a floating window.
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        root.layer?.masksToBounds = true
        // Backmost: the frosted base fills the whole window behind everything.
        frostedBase.frame = root.bounds
        frostedBase.autoresizingMask = [.width, .height]
        root.addSubview(frostedBase)

        // Image Inspect is the general mixed-content window: accept any file
        // or URL, then classify it after drop. Images stay here; videos route
        // to Video Inspect; documents replace the canvas content inline.
        canvasContainer.acceptsExtension = { _ in true }
        canvasContainer.acceptsImageData = true
        canvasContainer.onDrop = { [weak self] url, point in
            self?.handleDroppedResource(url: url, at: point)
        }
        primaryViewport.dropTarget = canvasContainer
        secondaryViewport.dropTarget = canvasContainer
        sliderViewport.dropTarget = canvasContainer
        fileWebView.dropTarget = canvasContainer
        filePlaceholder.dropTarget = canvasContainer

        for view in [primaryViewport, secondaryViewport, sliderViewport, fileWebView, filePlaceholder] {
            view.autoresizingMask = [.width, .height]
            canvasContainer.addSubview(view)
        }
        // Compare seam (#0b0c0e), above the two panes; hidden outside compare.
        compareDivider.wantsLayer = true
        compareDivider.layer?.backgroundColor = NSColor(
            srgbRed: 11 / 255, green: 12 / 255, blue: 14 / 255, alpha: 1
        ).cgColor
        compareDivider.isHidden = true
        canvasContainer.addSubview(compareDivider, positioned: .above, relativeTo: secondaryViewport)
        fileWebView.isHidden = true
        filePlaceholder.isHidden = true
        primaryViewport.onViewportChange = { [weak self] state in
            self?.syncViewport(state, source: self?.primaryViewport)
            self?.updateZoomLabel()
        }
        secondaryViewport.onViewportChange = { [weak self] state in
            self?.syncViewport(state, source: self?.secondaryViewport)
            self?.updateZoomLabel()
        }
        sliderViewport.viewport.onViewportChange = { [weak self] _ in self?.updateZoomLabel() }
        filmstrip.onSelect = { [weak self] index in
            self?.focus(index: index)
            self?.offerFailureActions(forItemAt: index)
        }
        filmstrip.onCompare = { [weak self] index in self?.compare(focusedWith: index) }
        filmstrip.onVisibleIndicesChanged = { [weak self] indices in
            guard let self else { return }
            let generation = self.loadGeneration
            DispatchQueue.main.async { [weak self] in
                self?.loadThumbnails(at: indices, generation: generation)
            }
        }
        filmstrip.onAdd = { [weak self] in self?.presentAddImagesPanel() }
        canvasContainer.addSubview(filmstrip)

        // MARK: V3 transparent drag region — only the bare traffic controls are visible.
        windowTitleLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        windowTitleLabel.textColor = PanelStyle.textPrimary
        windowTitleLabel.alignment = .center
        windowTitleLabel.lineBreakMode = .byTruncatingTail
        windowTitleLabel.stringValue = "Image Inspect".localized
        windowTitleLabel.isHidden = true
        titlebar.addSubview(trialBadge)
        titlebar.addSubview(windowTitleLabel)
        windowFilenameLabel.font = PanelStyle.inspectFont(ofSize: 11)
        windowFilenameLabel.textColor = PanelStyle.textTertiary
        windowFilenameLabel.alignment = .center
        windowFilenameLabel.lineBreakMode = .byTruncatingMiddle
        windowFilenameLabel.isHidden = true
        titlebar.addSubview(windowFilenameLabel)
        titlebar.addSubview(closeTrafficButton)
        titlebar.addSubview(minimizeTrafficButton)
        titlebar.addSubview(zoomTrafficButton)
        titlebar.passesThroughTextAtPoint = { [weak self] point in
            self?.containsRecognizedText(atCanvasPoint: point) == true
        }
        canvasContainer.addSubview(titlebar, positioned: .above, relativeTo: nil)

        // MARK: V3 Floating Toolbar — exact five-action operation cluster.
        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = NSColor(
            srgbRed: 22 / 255, green: 23 / 255, blue: 25 / 255, alpha: 0.90
        ).cgColor
        toolbarBar.layer?.borderWidth = 1
        toolbarBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        toolbarBar.layer?.cornerRadius = 15
        toolbarBar.layer?.shadowColor = NSColor(
            srgbRed: 20 / 255, green: 23 / 255, blue: 26 / 255, alpha: 0.24
        ).cgColor
        toolbarBar.layer?.shadowOpacity = 1
        toolbarBar.layer?.shadowOffset = CGSize(width: 0, height: -8)
        toolbarBar.layer?.shadowRadius = 12
        toolbarBar.layer?.masksToBounds = false

        directionButton.target = self
        directionButton.action = #selector(directionTapped)
        flipIconButton.target = self
        flipIconButton.action = #selector(flipMenuTapped)
        focusIconButton.target = self
        focusIconButton.action = #selector(focusModeTapped)
        compareIconButton.target = self
        compareIconButton.action = #selector(sideBySideTapped)
        sliderIconButton.target = self
        sliderIconButton.action = #selector(sliderTapped)
        captureIconButton.target = self
        captureIconButton.action = #selector(captureTapped)
        fitIconButton.target = self
        fitIconButton.action = #selector(fitToWindowTapped)
        infoButton.target = self
        infoButton.action = #selector(infoTapped)
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOutTapped)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomInTapped)
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOutTapped)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomInTapped)
        zoomLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        zoomLabel.textColor = PanelStyle.textSecondary
        zoomLabel.alignment = .center
        revealButton.target = self
        revealButton.action = #selector(revealInFinderTapped)
        openURLButton.target = self
        openURLButton.action = #selector(openURLTapped)
        actionsButton.target = self
        actionsButton.action = #selector(actionsTapped)
        widgetMarketButton.target = self
        widgetMarketButton.action = #selector(widgetMarketTapped)
        widgetTasksButton.target = self
        widgetTasksButton.action = #selector(widgetTasksTapped)
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        pinButton.isActive = isPinned
        for view in [directionButton, flipIconButton, focusIconButton,
                     compareIconButton, sliderIconButton, captureIconButton, fitIconButton,
                     zoomOutButton, zoomInButton,
                     widgetTasksButton, widgetMarketButton, infoButton,
                     actionsButton] {
            toolbarBar.addSubview(view)
        }
        for button in [directionButton, flipIconButton, focusIconButton,
                       compareIconButton, sliderIconButton, captureIconButton, fitIconButton,
                       zoomOutButton, zoomInButton,
                       widgetTasksButton, widgetMarketButton, infoButton,
                       actionsButton] {
            button.usesFigmaStyle = true
        }
        for button in [focusIconButton, compareIconButton, sliderIconButton, captureIconButton,
                       widgetMarketButton, actionsButton] {
            button.isBorderlessFigmaTile = true
        }
        focusIconButton.setDesignIcon("ToolbarFocus")
        compareIconButton.setDesignIcon("ToolbarCompare")
        sliderIconButton.setDesignIcon("ToolbarSlider")
        captureIconButton.setDesignIcon("ToolbarCapture")
        widgetMarketButton.setDesignIcon("ToolbarGrid")
        infoButton.setDesignIcon("ToolbarInfo")
        taskBadge.wantsLayer = true
        taskBadge.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
        taskBadge.layer?.cornerRadius = 4
        taskBadge.isHidden = WidgetTaskManager.shared.activeCount == 0
        toolbarBar.addSubview(taskBadge)
        toolbarBar.alphaValue = 1
        toolbarBar.isHidden = false
        canvasContainer.addSubview(toolbarBar, positioned: .above, relativeTo: nil)

        // MARK: Image Information — presented OUTSIDE the image as its own
        // child window attached to the right edge (same pattern as the Widget
        // Market panel), not overlaid on the picture. The hosting panel owns
        // `infoPanel`; nothing is added to the canvas here.
        infoPanel.autoresizingMask = [.width, .height]
        infoPanel.onClose = { [weak self] in self?.dismissInfoPanel() }

        // MARK: Statusbar (26pt) — file summary left, task polling right.
        statusbar.wantsLayer = true
        statusbar.layer?.backgroundColor = PanelStyle.inspectStatus.cgColor
        statusbar.layer?.borderWidth = 1
        statusbar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        configureIdentityLabel(statusLeftLabel, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textSecondary)
        configureIdentityLabel(statusCenterLabel, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textSecondary)
        configureIdentityLabel(statusRightLabel, font: PanelStyle.inspectFont(ofSize: 12, weight: .medium), color: PanelStyle.accent)
        statusCenterLabel.alignment = .center
        statusRightLabel.alignment = .left
        statusbar.addSubview(statusLeftLabel)
        statusbar.addSubview(statusCenterLabel)
        statusbar.addSubview(statusRightLabel)
        statusbar.addSubview(statusDot)
        statusDot.isHidden = true
        statusRightLabel.isHidden = true
        statusbar.isHidden = true
        canvasContainer.addSubview(statusbar, positioned: .above, relativeTo: nil)

        // MARK: Canvas overlays — task summary, filmstrip, and processing toast.
        modeSwitcher.onSelect = { [weak self] index in
            switch index {
            case 1: self?.sideBySideTapped()
            case 2: self?.sliderTapped()
            default: self?.focusModeTapped()
            }
        }
        configureIdentityLabel(taskSummaryLabel, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium), color: PanelStyle.textPrimary)
        taskSummaryLabel.stringValue = ""
        taskSummaryLabel.isHidden = true
        taskSummaryDot.isHidden = true
        taskOverlayShade.wantsLayer = true
        taskOverlayShade.layer?.backgroundColor = NSColor(
            srgbRed: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 0.34
        ).cgColor
        taskOverlayShade.isHidden = true
        canvasContainer.addSubview(taskOverlayShade, positioned: .below, relativeTo: filmstrip)
        canvasContainer.addSubview(taskSummaryDot, positioned: .above, relativeTo: nil)
        canvasContainer.addSubview(taskSummaryLabel, positioned: .above, relativeTo: nil)
        taskToast.isHidden = true
        canvasContainer.addSubview(taskToast, positioned: .above, relativeTo: nil)
        // The processing cues sit above the image and stay visible when chrome hides.
        runningImageBorder.wantsLayer = true
        runningImageBorder.layer?.borderWidth = 2
        runningImageBorder.layer?.borderColor = PanelStyle.accent.withAlphaComponent(0.8).cgColor
        runningImageBorder.layer?.cornerRadius = 12
        runningImageBorder.layer?.shadowColor = PanelStyle.accent.cgColor
        runningImageBorder.layer?.shadowOpacity = 0.28
        runningImageBorder.layer?.shadowOffset = .zero
        runningImageBorder.layer?.shadowRadius = 16
        runningImageBorder.isHidden = true
        canvasContainer.addSubview(runningImageBorder, positioned: .above, relativeTo: nil)
        runningImageIndicator.isHidden = true
        runningImageDot.frame = NSRect(x: 9, y: 9, width: 16, height: 16)
        runningImageDot.layer?.cornerRadius = 8
        runningImageDot.layer?.shadowColor = PanelStyle.success.cgColor
        runningImageDot.layer?.shadowOpacity = 0.85
        runningImageDot.layer?.shadowOffset = .zero
        runningImageDot.layer?.shadowRadius = 10
        runningImageIndicator.addSubview(runningImageDot)
        runningImageIndicator.setAccessibilityElement(true)
        runningImageIndicator.setAccessibilityLabel("Task running".localized)
        canvasContainer.addSubview(runningImageIndicator, positioned: .above, relativeTo: nil)
        copyResultURLButton.isHidden = true
        copyResultURLButton.onPress = { [weak self] in self?.copyWidgetResultURL() }
        canvasContainer.addSubview(copyResultURLButton, positioned: .above, relativeTo: nil)

        // The same themed action menu serves the toolbar ⋯ button and
        // right-clicks on every image surface.
        let menuHandler: (NSEvent, Int?) -> Void = { [weak self] event, slot in
            guard let self, let window = event.window else { return }
            if let slot { self.selectCompareSlot(slot) }
            let origin = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
            self.presentActionsMenu(atScreenPoint: origin, entries: self.buildActionEntries(includeWindowSettings: false))
        }
        primaryViewport.onActionMenu = { menuHandler($0, 0) }
        secondaryViewport.onActionMenu = { menuHandler($0, 1) }
        sliderViewport.onActionMenu = { menuHandler($0, nil) }
        layoutContent()
    }

    private func configureIdentityLabel(_ label: NSTextField, font: NSFont, color: NSColor) {
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.isSelectable = true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        guard contentView === canvasContainer else { return }
        let width = canvasContainer.bounds.width
        let height = canvasContainer.bounds.height
        guard width > 0, height > 0 else { return }

        // The window takes the focused image's aspect ratio, so the media
        // fills every point and the chrome floats over it. The image frame
        // scales uniformly; the toolbar uses its own scale so its 18pt Figma
        // icons remain legible on ordinary image window sizes.
        let scale = min(max(min(width / Self.designSize.width,
                                height / Self.designSize.height), 0.62), 1.25)
        // The running dot is pinned to the window's right inset. Keep the
        // toolbar clear of it on narrow windows without changing idle layout.
        let runningIndicatorX = max(8, width - 24 - 34)
        let toolbarAvailableW = runningImageIndicator.isHidden
            ? width - 16 : runningIndicatorX - 20
        let toolbarScale = max(0.1, min(1, min(toolbarAvailableW / 326,
                                               (height - 16) / 77)))
        // Rounded frosted panel: the media is inset 8pt so the frosted base
        // reads as a dark frame; a hairline edge finishes the window.
        canvasContainer.layer?.cornerRadius = 16 * scale
        canvasContainer.layer?.borderWidth = 1
        frostedBase.layer?.cornerRadius = 16 * scale
        toolbarBar.layer?.borderWidth = 1
        toolbarBar.layer?.cornerRadius = 15 * toolbarScale

        // Transparent 44pt drag region at the top (scaled uniformly).
        trialBadge.frame = NSRect(x: max(92,width-166),y:8,width:min(146,max(0,width-102)),height:26)
        trialBadge.refresh()
        let dragHeight = 44 * scale
        titlebar.frame = NSRect(x: 0, y: height - dragHeight, width: width, height: dragHeight)
        // Standard macOS traffic lights: fixed 12pt dots (NOT scaled down with
        // the window), 20pt between centers, left dot at x≈20, vertically
        // centered in the drag region. Fixed size keeps them at the normal
        // system size regardless of how small the image window gets.
        let dot: CGFloat = 12
        let dotY = (dragHeight / 2 - dot / 2) - 5
        closeTrafficButton.frame = NSRect(x: 20, y: dotY, width: dot, height: dot)
        minimizeTrafficButton.frame = NSRect(x: 40, y: dotY, width: dot, height: dot)
        zoomTrafficButton.frame = NSRect(x: 60, y: dotY, width: dot, height: dot)
        for button in [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton] {
            button.layer?.cornerRadius = dot / 2
        }

        // 326×54 floating toolbar, centered horizontally, 23pt from the top.
        // Six 38pt tiles with 14pt of breathing room between them.
        let toolbarW = 326 * toolbarScale
        let toolbarH = 54 * toolbarScale
        let centeredToolbarX = (width - toolbarW) / 2
        let toolbarX = runningImageIndicator.isHidden
            ? centeredToolbarX : min(centeredToolbarX, runningIndicatorX - 12 - toolbarW)
        toolbarBar.frame = NSRect(x: toolbarX,
                                  y: height - (23 * toolbarScale) - toolbarH,
                                  width: toolbarW, height: toolbarH)
        layoutToolbar(width: toolbarW)

        // No bottom bar or strip in the Simple Operation default state.
        statusbar.frame = .zero
        // Inset between the media and the window edge (scaled uniformly), so the
        // frosted base shows as a thin frame: 12pt top/bottom, 8pt left/right.
        let mediaInsetX = 8 * scale
        let mediaInsetY = 12 * scale
        let canvasRect = canvasContainer.bounds.insetBy(dx: mediaInsetX, dy: mediaInsetY)
        runningImageBorder.frame = canvasRect
        runningImageBorder.layer?.cornerRadius = 12 * scale
        let toolbarCenterY = toolbarBar.frame.midY
        runningImageIndicator.frame = NSRect(x: runningIndicatorX,
                                             y: toolbarCenterY - 17,
                                             width: 34, height: 34)
        // Keep the icon-only result URL action aligned with the floating toolbar.
        copyResultURLButton.frame = NSRect(x: runningIndicatorX,
                                        y: toolbarCenterY - 17,
                                        width: 34, height: 34)

        // Image Information is presented as a separate child window (see
        // toggleInfo / ImageInfoPanel), so it no longer occupies canvas space.

        guard let session else {
            primaryViewport.frame = canvasRect
            return
        }
        if session.mode == .compare, session.comparisonStyle == .sideBySide {
            // Figma Compare Mode: two equal panes split by a 2pt divider.
            let gap: CGFloat = 2
            let half = (canvasRect.width - gap) / 2
            primaryViewport.frame = NSRect(x: canvasRect.minX, y: canvasRect.minY,
                                           width: half, height: canvasRect.height)
            secondaryViewport.frame = NSRect(x: canvasRect.minX + half + gap, y: canvasRect.minY,
                                             width: half, height: canvasRect.height)
            compareDivider.isHidden = false
            compareDivider.frame = NSRect(x: canvasRect.minX + half, y: canvasRect.minY,
                                          width: gap, height: canvasRect.height)
        } else {
            primaryViewport.frame = canvasRect
            sliderViewport.frame = canvasRect
            compareDivider.isHidden = true
            compareDivider.frame = .zero
        }
        // Round the media corners a touch so they sit inside the frosted frame.
        let mediaRadius = 8 * scale
        for v in [primaryViewport, secondaryViewport, sliderViewport] {
            v.layer?.cornerRadius = mediaRadius
            v.layer?.masksToBounds = true
        }
        // File previews always fill the canvas; only visible in Focus/Browse.
        fileWebView.frame = canvasRect
        filePlaceholder.frame = canvasRect

        // Figma "05 / Task and Filmstrip Overlay": a full-width scrim bar
        // (#07080a @ 34%) pinned to the bottom, with the centered thumbnail
        // strip floating inside it. Keep the previously requested thumbnail
        // scale, while the strip shows up to eight and a half fixed-size tiles.
        if !shouldShowFilmstrip(for: session.infos) {
            taskOverlayShade.frame = .zero
            filmstrip.frame = .zero
        } else {
            // The scrim bar keeps its current size; only the thumbnails inside
            // shrink a further 20% (96 × 0.8 × 0.8 ≈ 61.4pt) and are centered
            // vertically within the bar.
            let barH = (117 * 0.8) * scale
            let barRect = NSRect(x: canvasRect.minX, y: canvasRect.minY,
                                 width: canvasRect.width, height: barH)
            taskOverlayShade.frame = barRect

            let tile = 96 * 0.8 * 0.8 * scale
            let gap = 8 * scale
            let slotCount = max(1, session.infos.count)
            let visibleW = slotCount <= 8
                ? CGFloat(slotCount) * tile + CGFloat(slotCount - 1) * gap
                : 8.5 * tile + 8 * gap
            let stripW = min(visibleW, max(1, canvasRect.width - 48 * scale))
            let stripY = barRect.minY + (barH - tile) / 2
            filmstrip.setGeometry(tileSize: tile, gap: gap)
            filmstrip.frame = NSRect(x: barRect.midX - stripW / 2,
                                     y: stripY, width: stripW, height: tile)
        }
        taskSummaryDot.isHidden = true
        taskSummaryLabel.isHidden = true
        taskToast.isHidden = true
    }

    /// Image-first icon toolbar. Text remains available through tooltips and
    /// VoiceOver labels, while the canvas stays visually quiet.
    private func layoutToolbar(width: CGFloat) {
        // The toolbar frame is scaled uniformly, so a single scale drives the
        // tiles and keeps every icon square (no oval/stretched glyphs).
        // Base design width is 326 (6×38pt tiles at a 52pt pitch, 14pt insets).
        let scale = width / 326
        func place(_ view: NSView, x: CGFloat) {
            // 38pt tiles, y=8 from top, 52pt horizontal pitch.
            view.frame = NSRect(x: x * scale, y: 8 * scale, width: 38 * scale, height: 38 * scale)
        }
        let v3Buttons = [focusIconButton, compareIconButton, sliderIconButton, captureIconButton,
                         widgetMarketButton, actionsButton]
        for button in v3Buttons {
            button.layer?.cornerRadius = 9 * scale
            button.layer?.borderWidth = 0
            // Match the Figma reference: an 18pt glyph centered in the 38pt tile.
            button.setSymbolPointSize(18 * scale)
        }
        place(focusIconButton, x: 14)
        place(compareIconButton, x: 66)
        place(sliderIconButton, x: 118)
        place(captureIconButton, x: 170)
        place(widgetMarketButton, x: 222)
        place(actionsButton, x: 274)

        // Retained actions still exist in the controller and keyboard paths,
        // but are intentionally absent from the v3 five-action toolbar.
        for button in [directionButton, flipIconButton, fitIconButton,
                       zoomOutButton, zoomInButton, widgetTasksButton, infoButton] {
            button.frame = .zero
            button.isHidden = true
        }
        taskBadge.frame = .zero
        taskBadge.isHidden = true
    }

    private func renderSession() {
        guard let session, session.infos.indices.contains(session.focusedIndex) else { return }
        let info = session.infos[session.focusedIndex]
        windowFilenameLabel.stringValue = info.filename
        // Multi-image sessions keep a floating thumbnail strip along the bottom
        // so the user can flip between images quickly. Single images stay
        // image-only. The strip floats over the media; it never shrinks it.
        let resultFilmstripVisible = isFocusedWidgetResult && shouldShowFilmstrip(for: session.infos)
        filmstrip.isHidden = (chromeIsHidden && !resultFilmstripVisible) || !shouldShowFilmstrip(for: session.infos)
        taskOverlayShade.isHidden = filmstrip.isHidden
        filmstrip.alphaValue = filmstrip.isHidden ? 0 : 1
        taskOverlayShade.alphaValue = filmstrip.isHidden ? 0 : 1
        updateMediaToolbarVisibility(for: info, session: session)
        updateWindowTitle(for: info, index: session.focusedIndex)
        updateStatusbar(for: info, index: session.focusedIndex)
        // Compare needs two IMAGES; focus/browse only needs multiple items.
        let imageCount = session.infos.filter { $0.kind == .image }.count
        focusIconButton.isEnabled = true
        compareIconButton.isEnabled = imageCount >= 2
        sliderIconButton.isEnabled = imageCount >= 2
        focusIconButton.isActive = session.mode != .compare
        compareIconButton.isActive = session.mode == .compare && session.comparisonStyle == .sideBySide
        sliderIconButton.isActive = session.mode == .compare && session.comparisonStyle == .slider
        infoButton.isActive = infoVisible
        updateZoomLabel()
        updateRevealButtonState()
        updateTaskChrome()
        updateRunningImageIndicator(for: session)
        copyResultURLButton.isHidden = session.mode == .compare || currentWidgetResultURLString == nil

        primaryViewport.isHidden = true
        secondaryViewport.isHidden = true
        sliderViewport.isHidden = true
        fileWebView.isHidden = true
        filePlaceholder.isHidden = true
        primaryViewport.isActiveSlot = false
        secondaryViewport.isActiveSlot = false
        primaryViewport.setCompareDimmed(false)
        secondaryViewport.setCompareDimmed(false)
        primaryViewport.setWidgetProcessing(nil)
        secondaryViewport.setWidgetProcessing(nil)
        sliderViewport.viewport.setWidgetProcessing(nil)

        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.infos.indices.contains(a), session.infos.indices.contains(b),
           session.infos[a].kind == .image, session.infos[b].kind == .image {
            if session.comparisonStyle == .sideBySide {
                primaryViewport.isHidden = false
                secondaryViewport.isHidden = false
                primaryViewport.setLoadFailed(session.failedIndices.contains(a))
                secondaryViewport.setLoadFailed(session.failedIndices.contains(b))
                primaryViewport.image = session.images[safe: a] ?? nil
                secondaryViewport.image = session.images[safe: b] ?? nil
                primaryViewport.setRecognizedText(ocrResults[session.infos[a].url])
                secondaryViewport.setRecognizedText(ocrResults[session.infos[b].url])
                primaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[a].url).first)
                secondaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[b].url).first)
                // Show which side a filmstrip tap will replace.
                primaryViewport.isActiveSlot = session.activeCompareSlot == 0
                secondaryViewport.isActiveSlot = session.activeCompareSlot == 1
                primaryViewport.setCompareDimmed(session.activeCompareSlot != 0)
                secondaryViewport.setCompareDimmed(session.activeCompareSlot != 1)
            } else {
                sliderViewport.isHidden = false
                sliderViewport.setImages(a: session.images[safe: a] ?? nil,
                                         b: session.images[safe: b] ?? nil,
                                         failed: session.failedIndices.contains(a)
                                             || session.failedIndices.contains(b))
                sliderViewport.setRecognizedText(a: ocrResults[session.infos[a].url],
                                                 b: ocrResults[session.infos[b].url])
                let activeIndex = session.activeCompareSlot == 0 ? a : b
                sliderViewport.viewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[activeIndex].url).first)
            }
            infoPanel.show(items: [
                (a, session.infos[a], session.metadata[safe: a] ?? nil),
                (b, session.infos[b], session.metadata[safe: b] ?? nil),
            ])
        } else {
            // Focus/Browse: images go to the viewport; other kinds render
            // inline (web view for text/markdown/pdf/web, placeholder icon
            // for video/unsupported/folders).
            switch info.kind {
            case .image:
                primaryViewport.isHidden = false
                primaryViewport.setLoadFailed(session.failedIndices.contains(session.focusedIndex))
                primaryViewport.image = session.images[safe: session.focusedIndex] ?? nil
                primaryViewport.setRecognizedText(ocrResults[info.url])
                primaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: info.url).first)
            case .text, .markdown, .pdf, .webPage:
                fileWebView.isHidden = false
                loadFileContent(for: info)
            default:
                filePlaceholder.isHidden = false
                filePlaceholder.configure(info: info)
            }
            infoPanel.show(items: [
                (session.focusedIndex, info, session.metadata[safe: session.focusedIndex] ?? nil),
            ])
        }

        filmstrip.configure(infos: session.infos, images: session.images,
                            selectedIndex: session.focusedIndex, compareIndices: session.compareIndices,
                            generatedResultPaths: session.generatedResultPaths)

        // Default glow marks the active compare slot so the user sees which
        // side a filmstrip tap will replace; hover overrides this.
        if session.mode == .compare, let (a, b) = session.compareIndices {
            infoPanel.highlight(index: session.activeCompareSlot == 0 ? a : b)
        } else {
            infoPanel.highlight(index: nil)
        }
        layoutContent()
        refreshOCRPanelIfNeeded()
    }

    private func shouldShowFilmstrip(for infos: [MediaInfo]) -> Bool {
        infos.count >= 2 || infos.contains { !WidgetTaskManager.shared.activeRecords(for: $0.url).isEmpty }
    }

    private func updateMediaToolbarVisibility(for info: MediaInfo, session: ImageInspectSession) {
        let showingImage = info.kind == .image ||
            (session.mode == .compare && session.compareIndices.map { session.infos.indices.contains($0.0) && session.infos.indices.contains($0.1) && session.infos[$0.0].kind == .image && session.infos[$0.1].kind == .image } == true)
        // The floating toolbar exposes Focus, Compare, Slider, Widget and More.
        // Image information remains available from the More menu.
        directionButton.isHidden = true
        flipIconButton.isHidden = true
        fitIconButton.isHidden = true
        zoomOutButton.isHidden = true
        zoomInButton.isHidden = true
        focusIconButton.isHidden = !showingImage
        compareIconButton.isHidden = !showingImage
        sliderIconButton.isHidden = !showingImage
        captureIconButton.isHidden = !showingImage
        widgetTasksButton.isHidden = true
        widgetMarketButton.isHidden = !showingImage
        actionsButton.isHidden = !showingImage
        infoButton.isHidden = true
    }

    private func loadSessionImages(generation: UUID) {
        guard let session else { return }
        // The filmstrip requests only on-screen thumbnails as it scrolls. A
        // folder may contain thousands of images; opening it must not queue
        // decoding and metadata work for every file ahead of the focused one.
        loadThumbnails(at: [session.focusedIndex] + filmstrip.visibleItemIndices,
                       generation: generation)
        loadFullResolutionForActiveItems(generation: generation)
    }

    private func loadThumbnails(at indices: [Int], generation: UUID) {
        guard generation == loadGeneration, let session else { return }
        for index in indices where session.infos.indices.contains(index) {
            guard session.infos[index].kind == .image,
                  session.images[safe: index] ?? nil == nil,
                  !session.failedIndices.contains(index),
                  pendingThumbnailIndices.insert(index).inserted else { continue }
            imageLoader.loadImage(from: session.infos[index].url) { [weak self] image in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.images.indices.contains(index) else { return }
                self.pendingThumbnailIndices.remove(index)
                if let image, session.images[index] == nil {
                    session.failedIndices.remove(index)
                    session.images[index] = image
                } else if image == nil && session.images[index] == nil {
                    session.failedIndices.insert(index)
                }
                self.renderSession()
            }
        }
    }

    private func loadDetails(at indices: [Int], generation: UUID) {
        guard generation == loadGeneration, let session else { return }
        for index in indices where session.infos.indices.contains(index) {
            let info = session.infos[index]
            guard info.isLocal, requestedDetailIndices.insert(index).inserted else { continue }
            imageLoader.loadFileSize(from: info.url) { [weak self] bytes in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.infos.indices.contains(index) else { return }
                session.infos[index].fileSize = bytes
                if index == session.focusedIndex { self.renderSession() }
            }
            imageLoader.loadTechnicalMetadata(from: info.url) { [weak self] metadata in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.metadata.indices.contains(index) else { return }
                session.metadata[index] = metadata
                if index == session.focusedIndex { self.renderSession() }
            }
        }
    }

    private func loadFullResolutionForActiveItems(generation: UUID) {
        guard let session else { return }
        var indices = [session.focusedIndex]
        if session.mode == .compare, let pair = session.compareIndices {
            indices = [pair.0, pair.1]
        }
        loadThumbnails(at: indices, generation: generation)
        loadDetails(at: indices, generation: generation)
        for index in Set(indices) where session.infos.indices.contains(index) {
            let info = session.infos[index]
            guard info.kind == .image else { continue }
            imageLoader.loadFullResolutionImage(from: info.url) { [weak self] image in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.images.indices.contains(index) else { return }
                if let image {
                    session.failedIndices.remove(index)
                    session.images[index] = image
                    session.infos[index].dimensions = image.size
                    // In the single-image Simple Operation state, the window
                    // takes the image's exact aspect ratio so the media fills
                    // it with no black plate.
                    if session.mode != .compare, index == session.focusedIndex {
                        self.fitWindowToImage(image.size)
                    }
                    self.scheduleOCR(for: session.infos[index].url, image: image)
                } else {
                    session.failedIndices.insert(index)
                    if let displayed = session.images[index] {
                        self.scheduleOCR(for: info.url, image: displayed)
                    }
                }
                self.renderSession()
            }
        }
    }

    @objc private func focusModeTapped() {
        guard let session else { return }
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        renderSession()
    }

    /// Inline file preview for the focused non-image item. Text/markdown are
    /// fetched and rendered through the shared ContentViewerWindow HTML
    /// helpers; pdf/web pages load directly.
    private func loadFileContent(for info: MediaInfo) {
        let token = UUID()
        fileContentGeneration = token
        switch info.kind {
        case .pdf:
            fileWebView.loadFileURL(info.url, allowingReadAccessTo: info.url.deletingLastPathComponent())
        case .webPage:
            fileWebView.load(URLRequest(url: info.url))
        case .text, .markdown:
            let url = info.url
            let isMarkdown = info.kind == .markdown
            Task { [weak self] in
                let content = await ContentViewerWindow.fetchTextContent(from: url)
                await MainActor.run {
                    guard let self, self.fileContentGeneration == token else { return }
                    let html = isMarkdown
                        ? ContentViewerWindow.wrapMarkdownInHTML(content)
                        : ContentViewerWindow.wrapCodeInHTML(content, language: url.pathExtension)
                    self.fileWebView.loadHTMLString(html, baseURL: nil)
                }
            }
        default:
            break
        }
    }
    @objc private func sideBySideTapped() {
        activateCompare(style: .sideBySide)
    }

    @objc private func sliderTapped() {
        activateCompare(style: .slider)
    }

    private func activateCompare(style: ImageInspectSession.ComparisonStyle) {
        guard let session else { return }
        // Compare is images-only: file items never enter a compare pair.
        let imageIndices = session.infos.indices.filter { session.infos[$0].kind == .image }
        guard imageIndices.count >= 2 else { return }
        session.comparisonStyle = style
        // A stored pair may reference non-image items after session changes —
        // validate before reusing it.
        if let pair = session.compareIndices,
           session.infos[safe: pair.0]?.kind != .image || session.infos[safe: pair.1]?.kind != .image {
            session.compareIndices = nil
        }
        // A Widget result (or the source it came from) always compares as
        // (original, result), so A is the original regardless of item order.
        let focused = imageIndices.contains(session.focusedIndex) ? session.focusedIndex : imageIndices[0]
        let storedContainsFocused = session.compareIndices.map { $0.0 == focused || $0.1 == focused } ?? false
        if !storedContainsFocused, let widgetPair = widgetComparePair(in: session, focused: focused) {
            session.compareIndices = widgetPair
            session.activeCompareSlot = 1
        }
        if session.compareIndices == nil {
            let first = focused
            let second = imageIndices.first { $0 != first } ?? imageIndices[0]
            session.compareIndices = (first, second)
            session.activeCompareSlot = 1
        }
        BillingManager.shared.trackTrialActivity("compare")
        session.mode = .compare
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    /// (source, result) indices when `focused` is a finished Widget result, or a
    /// source whose result is also in this session; nil for unrelated items.
    private func widgetComparePair(in session: ImageInspectSession, focused: Int) -> (Int, Int)? {
        guard session.infos.indices.contains(focused) else { return nil }
        let manager = WidgetTaskManager.shared
        let imageIndices = session.infos.indices.filter { session.infos[$0].kind == .image }
        if let source = manager.sourceURL(forResult: session.infos[focused].url),
           let sourceIndex = imageIndices.first(where: { manager.isSameMedia(session.infos[$0].url, source) }) {
            return (sourceIndex, focused)
        }
        for output in manager.completedOutputs(for: session.infos[focused].url) {
            if let resultIndex = imageIndices.first(where: { manager.isSameMedia(session.infos[$0].url, output) }) {
                return (focused, resultIndex)
            }
        }
        return nil
    }

    @objc private func infoTapped() { toggleInfo() }

    @objc private func localizationDidChange() {
        title = "Image Inspect".localized
        windowTitleLabel.stringValue = "Image Inspect".localized
        statusCenterLabel.stringValue = "Scroll to zoom  •  Drag to pan".localized
        infoButton.updateTooltip("Image information".localized)
        directionButton.updateTooltip("Rotate".localized)
        flipIconButton.updateTooltip("Flip".localized)
        focusIconButton.updateTooltip("Focus".localized)
        compareIconButton.updateTooltip("Compare".localized)
        sliderIconButton.updateTooltip("Slider".localized)
        captureIconButton.updateTooltip("Capture".localized)
        fitIconButton.updateTooltip("Fit".localized)
        zoomOutButton.updateTooltip("Zoom Out".localized)
        zoomInButton.updateTooltip("Zoom In".localized)
        widgetTasksButton.updateTooltip("Tasks".localized)
        widgetMarketButton.updateTooltip("Widget Market".localized)
        revealButton.updateTooltip("Reveal in Finder".localized)
        openURLButton.updateTooltip("Open image URL".localized)
        actionsButton.updateTooltip("More".localized)
        rotateButton.attributedTitle = NSAttributedString(
            string: "Rotate".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                         .foregroundColor: PanelStyle.textPrimary]
        )
        tasksTextButton.attributedTitle = NSAttributedString(
            string: "•  " + "Tasks".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                         .foregroundColor: PanelStyle.textPrimary]
        )
        widgetTextButton.attributedTitle = NSAttributedString(
            string: "Widget".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                         .foregroundColor: PanelStyle.textPrimary]
        )
        fitButton.attributedTitle = NSAttributedString(
            string: "Fit".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                         .foregroundColor: PanelStyle.textPrimary]
        )
        pinButton.updateTooltip((isPinned ? "Unpin" : "Pin on Top").localized)
        modeSwitcher.reloadTitles()
        ocrWindow.reloadLocalization()
        renderSession()
    }

    @objc private func revealInFinderTapped() {
        guard let info = currentRevealInfo, info.isLocal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    @objc private func pinTapped() {
        isPinned.toggle()
        pinButton.isActive = isPinned
        pinButton.updateTooltip((isPinned ? "Unpin" : "Pin on Top").localized)
        level = isPinned ? .floating : .normal
    }

    // MARK: - Image actions (rotate / export)

    private func toggleAutoHideChrome() {
        autoHideChromeEnabled.toggle()
        if autoHideChromeEnabled {
            resetAutoHideTimer()
        } else {
            autoHideWorkItem?.cancel()
            showChrome(animated: true)
        }
    }

    private func resetAutoHideTimer() {
        guard autoHideChromeEnabled else { return }
        autoHideWorkItem?.cancel()
        showChrome(animated: true)
        guard actionsPanel?.isVisible != true else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.autoHideChromeEnabled else { return }
            self.hideChrome(animated: true)
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func handleAutoHideMouse(atCanvasPoint point: NSPoint) {
        guard autoHideChromeEnabled else { return }
        guard isPointOverActiveImage(point) else {
            autoHideWorkItem?.cancel()
            hideChrome(animated: true)
            return
        }
        if actionsPanel?.isVisible == true {
            autoHideWorkItem?.cancel()
            showChrome(animated: true)
            return
        }
        resetAutoHideTimer()
    }

    private func handleAutoHideScreenPoint(_ screenPoint: NSPoint) {
        guard autoHideChromeEnabled, isVisible else { return }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let canvasPoint = canvasContainer.convert(windowPoint, from: nil)
        handleAutoHideMouse(atCanvasPoint: canvasPoint)
    }

    private func isPointOverActiveImage(_ point: NSPoint) -> Bool {
        guard actionsPanel?.isVisible != true else { return true }
        let candidates: [NSView]
        if let session, session.mode == .compare, session.comparisonStyle == .sideBySide {
            candidates = [primaryViewport, secondaryViewport]
        } else if session?.mode == .compare {
            candidates = [sliderViewport]
        } else {
            candidates = [primaryViewport]
        }
        return candidates.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    private func hideChrome(animated: Bool) {
        guard autoHideChromeEnabled, !chromeIsHidden,
              actionsPanel?.isVisible != true else { return }
        chromeIsHidden = true
        let keepFilmstrip = isFocusedWidgetResult
        let apply = {
            self.toolbarBar.alphaValue = 0
            self.filmstrip.alphaValue = keepFilmstrip ? 1 : 0
            self.taskOverlayShade.alphaValue = keepFilmstrip ? 1 : 0
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.toolbarBar.animator().alphaValue = 0
                self.filmstrip.animator().alphaValue = keepFilmstrip ? 1 : 0
                self.taskOverlayShade.animator().alphaValue = keepFilmstrip ? 1 : 0
            }, completionHandler: {
                guard self.chromeIsHidden else { return }
                self.toolbarBar.isHidden = true
                self.filmstrip.isHidden = !keepFilmstrip
                self.taskOverlayShade.isHidden = !keepFilmstrip
            })
        } else {
            apply()
            toolbarBar.isHidden = true
            filmstrip.isHidden = !keepFilmstrip
            taskOverlayShade.isHidden = !keepFilmstrip
        }
    }

    private func showChrome(animated: Bool) {
        guard chromeIsHidden || toolbarBar.alphaValue < 1 else { return }
        chromeIsHidden = false
        let showFilmstrip = session.map { shouldShowFilmstrip(for: $0.infos) } ?? false
        toolbarBar.isHidden = false
        filmstrip.isHidden = !showFilmstrip
        taskOverlayShade.isHidden = !showFilmstrip
        layoutContent()
        let apply = {
            self.toolbarBar.alphaValue = 1
            self.filmstrip.alphaValue = showFilmstrip ? 1 : 0
            self.taskOverlayShade.alphaValue = showFilmstrip ? 1 : 0
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.toolbarBar.animator().alphaValue = 1
                self.filmstrip.animator().alphaValue = showFilmstrip ? 1 : 0
                self.taskOverlayShade.animator().alphaValue = showFilmstrip ? 1 : 0
            }
        } else { apply() }
    }

    /// Full contextual menu for right-clicking an image surface.
    /// The one image menu, opened by right-click and by the toolbar ⋯ button.
    /// Local tools are grouped by purpose (Edit / Export) so the top level stays
    /// short; submenus are one level deep because ActionMenuPanel cascades once.
    /// `includeWindowSettings` adds view settings that only make sense from ⋯.
    private func buildActionEntries(includeWindowSettings: Bool) -> [ActionMenuEntry] {
        let activeTask = currentRevealInfo.map { !WidgetTaskManager.shared.activeRecords(for: $0.url).isEmpty } ?? false
        let hasImage: Bool = {
            guard let session, let index = currentActionIndex,
                  session.infos.indices.contains(index), session.infos[index].kind == .image else { return false }
            return (session.images[safe: index] ?? nil) != nil
        }()
        // A running Widget task only locks view transforms on its source; copy,
        // export, OCR, compress and other Widgets stay available.
        let canTransform = hasImage && !activeTask
        let hasImageInfo = currentRevealInfo?.kind == .image
        let localLocked = !BillingManager.shared.localToolsAllowed
        let exportLocked = localLocked && currentRevealInfo.map { WidgetTaskManager.shared.completedRecord(for: $0.url) == nil && !BillingResultAccess.contains($0.url) && !CaptureOutput.isCapture($0.url) } != false
        var entries: [ActionMenuEntry] = [
            ActionMenuEntry(title: "Copy Image".localized, shortcut: "⌘C", enabled: hasImage, requiresPro: exportLocked, action: { [weak self] in self?.copyActiveImage() }),
            ActionMenuEntry(title: "Edit".localized, enabled: canTransform, submenu: [
                ActionMenuEntry(title: "Rotate Left".localized, shortcut: "⌘L", action: { [weak self] in self?.rotateActive(byQuarters: -1) }),
                ActionMenuEntry(title: "Rotate Right".localized, shortcut: "⌘R", action: { [weak self] in self?.rotateActive(byQuarters: 1) }),
                ActionMenuEntry(title: "Flip Horizontally".localized, action: { [weak self] in self?.flipActive(horizontal: true) }),
                ActionMenuEntry(title: "Flip Vertically".localized, action: { [weak self] in self?.flipActive(horizontal: false) })
            ]),
            // Export is only "save this image as a format".
            ActionMenuEntry(title: "Export".localized, enabled: hasImage, requiresPro: exportLocked, submenu: [
                ActionMenuEntry(title: "Save as PNG…".localized, action: { [weak self] in self?.exportActive(as: .png) }),
                ActionMenuEntry(title: "Save as JPG…".localized, action: { [weak self] in self?.exportActive(as: .jpeg) }),
                ActionMenuEntry(title: "Save as WebP…".localized, action: { [weak self] in self?.exportActive(as: .webP) }),
                ActionMenuEntry(title: "Save as Icon…".localized, action: { [weak self] in self?.exportActive(as: .icns) })
            ]),
            // Everything else that processes the image. Always openable:
            // "Base64 → Image…" does not depend on the current item.
            ActionMenuEntry(title: "Tools".localized, submenu: [
                ActionMenuEntry(title: "Capture…".localized, shortcut: "⌘⇧X", enabled: hasImage, action: { [weak self] in self?.beginCapture() }),
                .separator(),
                ActionMenuEntry(title: "Recognize Text".localized, enabled: hasImage, action: { [weak self] in self?.recognizeTextTapped() }),
                ActionMenuEntry(title: "Compress…".localized, enabled: hasImage, requiresPro: localLocked, action: { [weak self] in self?.compressImageTapped() }),
                .separator(),
                ActionMenuEntry(title: "Copy as Base64".localized, enabled: hasImage, requiresPro: localLocked, action: { [weak self] in self?.copyActiveImageAsBase64() }),
                ActionMenuEntry(title: "Base64 → Image…".localized, requiresPro: localLocked, action: { [weak self] in self?.presentBase64ImageInput() })
            ]),
            .separator(),
            ActionMenuEntry(title: "Reveal in Finder".localized, enabled: currentRevealInfo?.isLocal == true,
                            action: { [weak self] in self?.revealInFinderTapped() }),
            ActionMenuEntry(title: "Image information".localized, shortcut: "⌘I", enabled: hasImageInfo,
                            action: { [weak self] in self?.toggleInfo() })
        ]
        if includeWindowSettings {
            entries.append(.separator())
            entries.append(ActionMenuEntry(title: "Automatic hide".localized + (autoHideChromeEnabled ? " ✓" : ""),
                                           action: { [weak self] in self?.toggleAutoHideChrome() }))
        }
        let widgets = WidgetRegistry.shared.compatible(with: "image")
        let marketEntry = ActionMenuEntry(title: "Widget Market…".localized,
                                          showsDisclosure: true,
                                          action: { [weak self] in self?.widgetMarketTapped() })
        var widgetEntries: [ActionMenuEntry] = widgets.compactMap { widget in
            let commands = widget.localizedCommands.filter { $0.inputTypes.contains("image") }
            guard !commands.isEmpty else { return nil }
            let commandEntries = commands.map { command in
                let duplicate = currentRevealInfo.map { info in WidgetTaskManager.shared.activeRecords(for: info.url).contains { $0.widgetID == widget.id && $0.commandID == command.id } } ?? false
                return ActionMenuEntry(title: commands.count == 1 ? widget.displayName : command.name,
                    creditCost: widget.taskCreditCost, enabled: hasImage && !duplicate,
                    action: { [weak self] in self?.runWidget(widgetID: widget.id, commandID: command.id) })
            }
            return commands.count == 1 ? commandEntries[0]
                : ActionMenuEntry(title: widget.displayName, creditCost: widget.taskCreditCost, submenu: commandEntries)
        }
        if widgetEntries.isEmpty {
            // Nothing installed (or nothing fits this image): keep the Market one click away.
            entries.insert(.separator(), at: 0)
            entries.insert(marketEntry, at: 0)
        } else {
            widgetEntries.append(.separator())
            widgetEntries.append(marketEntry)
            entries.insert(.separator(), at: 0)
            entries.insert(ActionMenuEntry(title: "Widgets".localized, submenu: widgetEntries), at: 0)
        }
        // A running task on this image can be stopped from the same menu.
        let manager = WidgetTaskManager.shared
        let cancellable = currentRevealInfo.map { manager.activeRecords(for: $0.url).filter(manager.canCancel) } ?? []
        if !cancellable.isEmpty {
            let cancelEntries = cancellable.map { record in
                ActionMenuEntry(title: String(format: "Cancel %@".localized, record.commandName),
                                action: { WidgetTaskManager.shared.cancel(record.id) })
            }
            entries.insert(contentsOf: cancelEntries + [.separator()], at: 0)
        }
        return entries
    }

    private func presentActionsMenu(atScreenPoint point: NSPoint) {
        presentActionsMenu(atScreenPoint: point, entries: buildActionEntries(includeWindowSettings: true))
    }

    private func presentActionsMenu(atScreenPoint point: NSPoint, entries: [ActionMenuEntry]) {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: entries)
        prepareActionsPanelForAutoHide(panel)
        actionsPanel = panel
        // A right-click can arrive while Glance is inactive. The menu panel
        // hides on deactivation, so activate the owning app before ordering it.
        NSApp.activate(ignoringOtherApps: true)
        panel.present(at: point)
    }

    @objc private func actionsTapped() {
        autoHideWorkItem?.cancel()
        showChrome(animated: true)
        // Anchor the menu to the toolbar's bottom-right corner so it drops
        // down from the toolbar with an 8pt gap and right-aligns with it.
        let windowPoint = toolbarBar.convert(NSPoint(x: toolbarBar.bounds.maxX, y: 0), to: nil)
        let screenPoint = convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
        presentActionsMenuBelowToolbar(atScreenPoint: screenPoint)
    }

    private func presentActionsMenuBelowToolbar(atScreenPoint point: NSPoint) {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: buildActionEntries(includeWindowSettings: true), style: .more)
        prepareActionsPanelForAutoHide(panel)
        actionsPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.presentBelowToolbar(at: point)
    }

    private func prepareActionsPanelForAutoHide(_ panel: ActionMenuPanel) {
        autoHideWorkItem?.cancel()
        showChrome(animated: true)
        panel.onDismiss = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.handleAutoHideScreenPoint(NSEvent.mouseLocation)
            }
        }
    }

    @objc private func widgetMarketTapped() {
        WidgetMarketPanel.shared.toggle(from: self)
    }

    @objc private func widgetTasksTapped() {
        (NSApp.delegate as? AppDelegate)?.openTasks()
    }

    private func runWidget(widgetID: String, commandID: String) {
        guard let info = currentRevealInfo, info.kind == .image,
              let widget = WidgetRegistry.shared.installed.first(where: { $0.id == widgetID }),
              let command = widget.localizedCommand(id: commandID) else { return }
        let capabilities = command.inputCapabilities
        guard capabilities.needsImageDialog else {
            _ = WidgetTaskManager.shared.start(widget: widget, command: command, media: info)
            return
        }
        widgetInputPanel?.close()
        let sourceImage = session.flatMap { session in
            session.infos.firstIndex(where: { $0.url == info.url })
                .flatMap { session.images[safe: $0] ?? nil }
        }
        let panel = WidgetInputPanel(widgetName: widget.displayName, sourceURL: info.url,
                                     sourceImage: sourceImage, capabilities: capabilities)
        panel.onSubmit = { [weak self] input in
            guard self != nil, let source = input.mediaURLs.first else { return }
            let media = MediaInfo(url: source, isLocal: source.isFileURL, kind: .image)
            _ = WidgetTaskManager.shared.start(widget: widget, command: command,
                                               media: media, input: input)
        }
        panel.onDismiss = { [weak self, weak panel] in
            if self?.widgetInputPanel === panel { self?.widgetInputPanel = nil }
        }
        widgetInputPanel = panel
        panel.present(over: self)
    }

    @objc private func widgetTasksDidChange() {
        // Task state remains available from Widget Market / the tasks window;
        // it never grows extra chrome inside the v3 Simple Operation canvas.
        taskBadge.isHidden = true
        statusDot.isHidden = true
        statusRightLabel.isHidden = true
        taskToast.hide()
        let completed = WidgetTaskManager.shared.records.filter { $0.phase == .completed && !handledWidgetTaskIDs.contains($0.id) }
        completed.forEach { handledWidgetTaskIDs.insert($0.id) }
        guard let session else { return }
        renderSession()
        for task in completed.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard let output = task.output, let source = task.source,
                  session.infos.contains(where: { $0.url.absoluteString == source.absoluteString }) else { continue }
            if isPlainTextWidgetResult(task, output: output) {
                presentWidgetTextResult(task, output: output, source: source)
                continue
            }
            if let existingIndex = session.infos.firstIndex(where: {
                $0.url.standardizedFileURL == output.standardizedFileURL
            }) {
                selectWidgetResult(at: existingIndex)
                loadFullResolutionForActiveItems(generation: loadGeneration)
                continue
            }
            insertWidgetResult(info: MediaInfo(url: output, isLocal: true, kind: .image),
                               after: source)
        }
    }

    private func isPlainTextWidgetResult(_ task: WidgetTaskRecord, output: URL) -> Bool {
        let textExtensions = Set(["txt", "text", "md", "markdown"])
        if textExtensions.contains(output.pathExtension.lowercased()) { return true }
        if UTType(filenameExtension: output.pathExtension)?.conforms(to: .image) == true { return false }
        if task.outputTypes?.contains("text") == true { return true }
        guard let widget = WidgetRegistry.shared.installed.first(where: { $0.id == task.widgetID }),
              let command = widget.commands.first(where: { $0.id == task.commandID }) else { return false }
        return command.outputs.contains("text")
    }

    private func presentWidgetTextResult(_ task: WidgetTaskRecord, output: URL, source: URL) {
        guard let session,
              let sourceIndex = session.infos.firstIndex(where: {
                  $0.url.absoluteString == source.absoluteString
              }) else { return }
        let sourceInfo = session.infos[sourceIndex]
        let sourceImage = session.images.indices.contains(sourceIndex)
            ? session.images[sourceIndex] : nil
        let generation = widgetTextResultSessionGeneration
        widgetTextResultQueue.async { [weak self] in
            let textOutputs = Self.textResultFiles(in: output)
            DispatchQueue.main.async {
                guard let self, self.widgetTextResultSessionGeneration == generation else { return }
                for textOutput in textOutputs {
                    self.presentWidgetTextArtifact(task, output: textOutput,
                                                   sourceInfo: sourceInfo, sourceImage: sourceImage)
                }
            }
        }
    }

    private static func textResultFiles(in output: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [output] }
        let files = (try? FileManager.default.contentsOfDirectory(at: output,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let textExtensions = Set(["txt", "text", "md", "markdown"])
        return files.filter { textExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func presentWidgetTextArtifact(_ task: WidgetTaskRecord, output: URL,
                                           sourceInfo: MediaInfo, sourceImage: NSImage?) {
        let key = WidgetTextResultKey(taskID: task.id, outputPath: output.standardizedFileURL.path)
        guard widgetTextResultWindows[key] == nil else { return }
        let resultWindow = WidgetTextResultWindow()
        widgetTextResultWindows[key] = resultWindow
        widgetTextResultOrder.append(key)
        resultWindow.onDismiss = { [weak self] in
            self?.widgetTextResultWindows.removeValue(forKey: key)
            self?.widgetTextResultOrder.removeAll { $0 == key }
            self?.positionWidgetTextResults()
        }
        // The result stack owns the right side while it is open.
        infoVisible = false
        infoButton.isActive = false
        infoWindow.dismiss()
        removeChildWindow(ocrWindow)
        ocrWindow.orderOut(nil)
        ocrVisible = false
        resultWindow.showLoading(task: task, source: sourceInfo,
                                 sourceImage: sourceImage)
        positionWidgetTextResults()
        resultWindow.present(alongside: self)
        resultWindow.onBecomeKey = { [weak self, weak resultWindow] in
            guard let self, let resultWindow else { return }
            self.raiseWidgetTextResult(resultWindow)
        }

        if sourceImage == nil {
            imageLoader.loadImage(from: sourceInfo.url) { [weak self, weak resultWindow] image in
                guard let self, let resultWindow,
                      self.widgetTextResultWindows[key] === resultWindow,
                      let image else { return }
                resultWindow.updateSourceImage(image)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak resultWindow] in
            let result = Result { try String(contentsOf: output, encoding: .utf8) }
            DispatchQueue.main.async {
                guard let self, let resultWindow,
                      self.widgetTextResultWindows[key] === resultWindow else { return }
                switch result {
                case .success(let text): resultWindow.showResult(text)
                case .failure(let error):
                    Logger.error("Widget text result read failed: \(error.localizedDescription)")
                    resultWindow.showError("Unable to read Widget text result".localized)
                }
            }
        }
    }

    private func dismissWidgetTextResults() {
        widgetTextResultSessionGeneration = UUID()
        for window in Array(widgetTextResultWindows.values) {
            window.onDismiss = nil
            window.dismiss()
        }
        widgetTextResultWindows.removeAll()
        widgetTextResultOrder.removeAll()
    }

    private func positionWidgetTextResults() {
        let count = widgetTextResultOrder.count
        for (index, id) in widgetTextResultOrder.enumerated() {
            widgetTextResultWindows[id]?.position(alongside: self, stackIndex: index,
                                                  stackCount: count)
        }
    }

    @objc private func imageWindowGeometryDidChange(_ notification: Notification) {
        positionWidgetTextResults()
    }

    private func raiseWidgetTextResult(_ window: WidgetTextResultWindow) {
        guard !isRaisingWidgetTextResult,
              widgetTextResultWindows.values.contains(where: { $0 === window }) else { return }
        isRaisingWidgetTextResult = true
        defer { isRaisingWidgetTextResult = false }
        if window.parent === self {
            removeChildWindow(window)
            addChildWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func updateTaskChrome() {
        guard let info = currentRevealInfo,
              let task = WidgetTaskManager.shared.activeRecords(for: info.url).first else {
            taskSummaryDot.isHidden = true
            taskSummaryLabel.isHidden = true
            taskToast.hide()
            return
        }
        taskSummaryDot.isHidden = true
        taskSummaryLabel.isHidden = true
        let state: String
        switch task.phase {
        case .uploading: state = "Uploading"
        case .submitting: state = "Submitting"
        case .processing: state = "Processing"
        case .downloading: state = "Downloading"
        default: state = "Processing"
        }
        taskSummaryLabel.stringValue = "\(task.commandName)  •  \(state)"
        taskToast.hide()
    }

    private func updateRunningImageIndicator(for session: ImageInspectSession) {
        let isRunning: Bool
        if session.mode != .compare,
           session.infos.indices.contains(session.focusedIndex) {
            let info = session.infos[session.focusedIndex]
            isRunning = info.kind == .image &&
                !WidgetTaskManager.shared.activeRecords(for: info.url).isEmpty
        } else {
            isRunning = false
        }
        if runningImageBorder.isHidden != !isRunning {
            runningImageBorder.isHidden = !isRunning
        }
        if runningImageIndicator.isHidden != !isRunning {
            runningImageIndicator.isHidden = !isRunning
        }
        if let dotLayer = runningImageDot.layer {
            if isRunning && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if dotLayer.animation(forKey: "widgetRunningDotBreathing") == nil {
                    let glow = CABasicAnimation(keyPath: "shadowOpacity")
                    glow.fromValue = 0.3
                    glow.toValue = 1.0
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 0.55
                    fade.toValue = 1.0
                    let breathing = CAAnimationGroup()
                    breathing.animations = [glow, fade]
                    breathing.duration = 0.9
                    breathing.autoreverses = true
                    breathing.repeatCount = .infinity
                    breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    dotLayer.add(breathing, forKey: "widgetRunningDotBreathing")
                }
            } else {
                dotLayer.removeAnimation(forKey: "widgetRunningDotBreathing")
            }
        }
        guard let layer = runningImageBorder.layer else { return }
        if isRunning && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if layer.animation(forKey: "widgetMainBreathing") == nil {
                let animation = CABasicAnimation(keyPath: "borderColor")
                animation.fromValue = PanelStyle.accent.withAlphaComponent(0.35).cgColor
                animation.toValue = PanelStyle.accent.withAlphaComponent(0.8).cgColor
                animation.duration = 0.75
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "widgetMainBreathing")
            }
        } else {
            layer.removeAnimation(forKey: "widgetMainBreathing")
        }
    }

    /// Insert a completed widget result immediately after its source image,
    /// then show and select the result in the filmstrip.
    private func insertWidgetResult(info: MediaInfo, after source: URL) {
        guard let session,
              let sourceIndex = session.infos.firstIndex(where: { $0.url.absoluteString == source.absoluteString }) else { return }
        let insertionIndex = insertDerivedItem(info, afterSourceIndex: sourceIndex, in: session)
        selectWidgetResult(at: insertionIndex)
        loadDroppedItem(at: insertionIndex, generation: loadGeneration)
    }

    /// Inserts a file derived from the item at `sourceIndex` (Widget result,
    /// compressed copy) right after it and keeps per-index session state
    /// aligned. Callers decide what to show afterwards. Returns the new index.
    private func insertDerivedItem(_ info: MediaInfo, afterSourceIndex sourceIndex: Int,
                                   in session: ImageInspectSession) -> Int {
        let insertionIndex = sourceIndex + 1
        session.infos.insert(info, at: insertionIndex)
        session.images.insert(nil, at: insertionIndex)
        session.metadata.insert(nil, at: insertionIndex)
        session.generatedResultPaths.insert(info.url.standardizedFileURL.path)
        session.failedIndices = Set(session.failedIndices.map {
            $0 >= insertionIndex ? $0 + 1 : $0
        })
        return insertionIndex
    }

    private func selectWidgetResult(at index: Int) {
        guard let session, session.infos.indices.contains(index) else { return }
        session.mode = .browse
        session.compareIndices = nil
        session.focusedIndex = index
        refitFocusedImageIfNeeded()
        renderSession()
        showChrome(animated: false)
    }

    /// The viewport the actions menu acts on: focused image in Focus/Browse,
    /// the active slot in side-by-side, the shared pair state in slider.
    private var currentActionViewport: InspectImageViewport {
        guard let session, session.mode == .compare else { return primaryViewport }
        if session.comparisonStyle == .slider { return sliderViewport.viewport }
        return session.activeCompareSlot == 0 ? primaryViewport : secondaryViewport
    }

    private var currentActionIndex: Int? {
        guard let session else { return nil }
        if session.mode == .compare, let pair = session.compareIndices {
            return session.activeCompareSlot == 0 ? pair.0 : pair.1
        }
        return session.focusedIndex
    }

    /// True when the actions target is an image — gates the ⌘C/⌘S/⌘L/⌘R
    /// shortcuts so they don't swallow keys meant for the file preview.
    private var activeItemIsImage: Bool {
        guard let session, let index = currentActionIndex,
              session.infos.indices.contains(index) else { return false }
        return session.infos[index].kind == .image
    }

    private func rotateActive(byQuarters delta: Int) {
        guard let session else { return }
        if session.mode == .compare, session.comparisonStyle == .slider {
            sliderViewport.rotate(byQuarters: delta)
        } else {
            currentActionViewport.rotate(byQuarters: delta)
        }
    }

    private func flipActive(horizontal: Bool) {
        if session?.mode == .compare, session?.comparisonStyle == .slider { sliderViewport.flip(horizontal: horizontal) }
        else { currentActionViewport.flip(horizontal: horizontal) }
    }

    /// The active image as a CGImage with the current view rotation applied
    /// (WYSIWYG), or nil when the active item is not a loaded image.
    private func currentActionCGImage() -> CGImage? {
        guard let session, let index = currentActionIndex,
              session.infos[index].kind == .image,
              let image = session.images[safe: index] ?? nil,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rotation = ((currentActionViewport.rotationQuarters % 4) + 4) % 4
        guard rotation != 0 else { return cgImage }
        return ImageExporter.rotate(cgImage, quarters: rotation) ?? cgImage
    }

    /// ⌘C — copy the active image (rotation applied) to the general
    /// pasteboard as PNG data plus an NSImage (TIFF) fallback.
    private func copyActiveImage() {
        guard BillingCoordinator.shared.requireLocalTool("Copy Image".localized, over: self, source: currentRevealInfo?.url) else { return }
        guard let cgImage = currentActionCGImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        pasteboard.writeObjects([NSImage(cgImage: cgImage,
                                         size: NSSize(width: cgImage.width, height: cgImage.height))])
        toastWindow.show(message: "Copied ✓".localized, over: self)
    }

    private func copyActiveImageAsBase64() {
        guard BillingCoordinator.shared.requireLocalTool("Copy as Base64".localized, over: self) else { return }
        guard let cgImage = currentActionCGImage(),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(png.base64EncodedString(), forType: .string)
        toastWindow.show(message: "Base64 copied ✓".localized, over: self)
    }

    private func presentBase64ImageInput() {
        guard BillingCoordinator.shared.requireLocalTool("Base64 to Image".localized, over: self) else { return }
        let alert = NSAlert()
        alert.messageText = "Base64 to Image".localized
        alert.informativeText = "Paste a Base64 image string below".localized
        let area = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        area.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        area.textColor = PanelStyle.textPrimary
        area.backgroundColor = PanelStyle.controlFill
        area.drawsBackground = true
        area.isRichText = false
        area.isEditable = true
        area.textContainerInset = NSSize(width: 10, height: 10)
        alert.accessoryView = area
        alert.addButton(withTitle: "Convert".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.window.initialFirstResponder = area
        alert.beginSheetModal(for: self) { [weak self, weak area] response in
            guard response == .alertFirstButtonReturn,
                  let raw = area?.string.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            self?.decodeBase64Image(raw)
        }
        DispatchQueue.main.async { alert.window.makeFirstResponder(area) }
    }

    private func decodeBase64Image(_ raw: String) {
        // Accept both plain Base64 and data URLs such as data:image/png;base64,...
        let payload: String = {
            if let comma = raw.range(of: ","), raw[..<comma.lowerBound].lowercased().contains("base64") {
                return String(raw[comma.upperBound...])
            }
            return raw
        }()
        let compact = payload.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]),
              let image = NSImage(data: data), image.isValid,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            toastWindow.show(message: "Invalid Base64 image".localized, kind: .error, over: self); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlanceBase64", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("base64-\(UUID().uuidString).png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return }
        appendOrFocusImage(info: MediaInfo(url: url, isLocal: true, kind: .image))
    }

    /// ⌘S — silently save the current view as PNG into ~/Documents/Glance/.
    /// Focus saves one image; Compare saves both images as the visible
    /// side-by-side or slider comparison.
    private func quickSaveActiveImage() {
        guard BillingCoordinator.shared.requireLocalTool("Export".localized, over: self, source: currentRevealInfo?.url) else { return }
        guard let source = quickSaveSource() else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glance", isDirectory: true)
        let filename = UUID().uuidString.prefix(8).uppercased() + ".png"
        let url = directory.appendingPathComponent(filename)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ok = source.render().map {
                ImageExporter.write(cgImage: $0, to: url, format: .png)
            } ?? false
            DispatchQueue.main.async {
                if ok {
                    guard let self else { return }
                    self.toastWindow.show(message: "Saved ✓".localized + "\n" + url.path,
                                          over: self)
                } else {
                    if let self { self.toastWindow.show(message: "Export failed".localized, kind: .error, over: self) }
                }
            }
        }
    }

    // MARK: Capture

    @objc private func captureTapped() { beginCapture() }

    /// Shows a brief toast over this window (used for "Capture saved").
    func showToast(_ message: String) {
        toastWindow.show(message: message, over: self)
    }

    /// Freezes what the viewports show right now, at the source's full
    /// resolution, and opens the capture editor over the window.
    private func beginCapture() {
        guard captureEditor == nil, let session, activeItemIsImage || session.mode == .compare,
              let frozen = makeFrozenCapture() else { return }
        actionsPanel?.dismissChain()
        autoHideWorkItem?.cancel()
        let editor = CaptureEditorView(image: frozen, displayRect: captureDisplayRect())
        editor.frame = canvasContainer.bounds
        editor.wantsLayer = true
        editor.layer?.cornerRadius = canvasContainer.layer?.cornerRadius ?? 0
        editor.layer?.masksToBounds = true
        editor.onCancel = { [weak self] in self?.endCapture() }
        editor.onCapture = { [weak self] cropped in self?.finishCapture(cropped) }
        canvasContainer.addSubview(editor)
        captureEditor = editor
        captureReturnResponder = firstResponder
        makeFirstResponder(editor)
    }

    private func endCapture() {
        guard let editor = captureEditor else { return }
        captureEditor = nil
        editor.removeFromSuperview()
        makeFirstResponder(captureReturnResponder ?? canvasContainer)
        captureReturnResponder = nil
        resetAutoHideTimer()
    }

    private func finishCapture(_ image: CGImage) {
        let name = currentActionIndex.flatMap { index -> String? in
            session?.infos.indices.contains(index) == true ? session?.infos[index].filename : nil
        }
        endCapture()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = CaptureOutput.save(image, sourceName: name)
            DispatchQueue.main.async {
                guard let self else { return }
                if let url { self.onCaptured?(url) }
                else { self.toastWindow.show(message: "Could not save capture".localized, kind: .error, over: self) }
            }
        }
    }

    /// Where the frozen composite sits on screen: the displayed image of the
    /// single / slider viewport, or both viewports together side by side.
    private func captureDisplayRect() -> CGRect? {
        guard let session else { return nil }
        if session.mode == .compare {
            if session.comparisonStyle == .slider {
                return sliderViewport.viewport.captureDisplayRect(in: canvasContainer)
            }
            guard let a = primaryViewport.captureDisplayRect(in: canvasContainer),
                  let b = secondaryViewport.captureDisplayRect(in: canvasContainer) else { return nil }
            return a.union(b)
        }
        return primaryViewport.captureDisplayRect(in: canvasContainer)
    }

    private func makeFrozenCapture() -> CGImage? {
        guard let session else { return nil }
        if session.mode == .compare {
            switch session.comparisonStyle {
            case .sideBySide:
                guard let a = primaryViewport.capturePane, let b = secondaryViewport.capturePane else { return nil }
                return CaptureFreeze.sideBySide(a, b)
            case .slider:
                guard let panes = sliderViewport.capturePanes else { return nil }
                return CaptureFreeze.slider(base: panes.base, overlay: panes.overlay,
                                            fraction: sliderViewport.revealFraction)
            }
        }
        guard let pane = primaryViewport.capturePane else { return nil }
        return CaptureFreeze.single(pane)
    }

    private func quickSaveSource() -> QuickSaveSource? {
        guard let session else { return nil }
        if session.mode == .compare {
            guard let pair = session.compareIndices,
                  session.images.indices.contains(pair.0), session.images.indices.contains(pair.1),
                  let a = session.images[pair.0], let b = session.images[pair.1] else { return nil }
            switch session.comparisonStyle {
            case .sideBySide:
                return .sideBySide(a, comparisonRotation(slot: 0),
                                   b, comparisonRotation(slot: 1))
            case .slider:
                return .slider(a, comparisonRotation(slot: 0),
                               b, comparisonRotation(slot: 1),
                               sliderViewport.revealFraction)
            }
        }
        guard let index = currentActionIndex,
              let image = session.images[safe: index] ?? nil else { return nil }
        return .single(image, currentActionViewport.rotationQuarters)
    }

    private func comparisonRotation(slot: Int) -> Int {
        guard let session, session.comparisonStyle == .sideBySide else {
            return sliderViewport.viewport.rotationQuarters
        }
        return slot == 0 ? primaryViewport.rotationQuarters : secondaryViewport.rotationQuarters
    }

    private func recognizeTextTapped() {
        guard let session, let index = currentActionIndex,
              session.infos.indices.contains(index),
              let image = session.images[safe: index] ?? nil else { return }
        let url = session.infos[index].url
        presentOCRWindow()
        ocrDisplayedURL = url
        if let result = ocrResults[url] {
            ocrWindow.showResult(result.text)
        } else {
            ocrWindow.showLoading()
            ocrFailed.remove(url) // An explicit request can retry a failed scan.
            scheduleOCR(for: url, image: image)
        }
    }

    /// Scan the full-resolution image once per session. OCR stays off the main
    /// thread and never delays the first visible image or filmstrip rendering.
    private func scheduleOCR(for url: URL, image: NSImage) {
        guard ocrResults[url] == nil, !ocrPending.contains(url), !ocrFailed.contains(url) else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            if ocrVisible && ocrDisplayedURL == url { ocrWindow.showResult("") }
            return
        }
        ocrPending.insert(url)
        let token = ocrGeneration
        ocrQueue.async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            if let supported = try? request.supportedRecognitionLanguages() {
                let preferred = ["zh-Hans", "en-US"].filter { supported.contains($0) }
                if !preferred.isEmpty { request.recognitionLanguages = preferred }
            }
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var result: InspectOCRResult?
            do {
                try handler.perform([request])
                var lines: [String] = []
                var lineBounds: [CGRect] = []
                var glyphs: [InspectOCRGlyph] = []
                for observation in request.results ?? [] {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let line = lines.count
                    lines.append(candidate.string)
                    lineBounds.append(observation.boundingBox)
                    let count = max(candidate.string.count, 1)
                    for (offset, start) in candidate.string.indices.enumerated() {
                        let end = candidate.string.index(after: start)
                        let fallback = CGRect(x: observation.boundingBox.minX
                                                + observation.boundingBox.width * CGFloat(offset) / CGFloat(count),
                                              y: observation.boundingBox.minY,
                                              width: observation.boundingBox.width / CGFloat(count),
                                              height: observation.boundingBox.height)
                        let box = (try? candidate.boundingBox(for: start..<end))?.boundingBox ?? fallback
                        glyphs.append(InspectOCRGlyph(character: String(candidate.string[start..<end]),
                                                      boundingBox: box, line: line))
                    }
                }
                result = InspectOCRResult(text: lines.joined(separator: "\n"),
                                          lineBounds: lineBounds, glyphs: glyphs)
            } catch {
                Logger.error("OCR failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                guard let self, self.ocrGeneration == token else { return }
                self.ocrPending.remove(url)
                if let result {
                    self.ocrResults[url] = result
                } else {
                    self.ocrFailed.insert(url)
                }
                self.renderSession()
                if self.ocrVisible && self.ocrDisplayedURL == url {
                    self.ocrWindow.showResult(result?.text ?? "")
                }
            }
        }
    }

    private func refreshOCRPanelIfNeeded() {
        guard ocrVisible, let session, let index = currentActionIndex,
              session.infos.indices.contains(index) else { return }
        let url = session.infos[index].url
        guard ocrDisplayedURL != url else { return }
        ocrDisplayedURL = url
        if let result = ocrResults[url] {
            ocrWindow.showResult(result.text)
        } else if ocrFailed.contains(url) {
            ocrWindow.showResult("")
        } else {
            ocrWindow.showLoading()
        }
    }

    /// Dock the OCR panel beside the main window, sliding in from the right
    /// on first presentation.
    private func presentOCRWindow() {
        let gap: CGFloat = 2
        var origin = NSPoint(x: frame.maxX + gap, y: frame.minY)
        let size = NSSize(width: 320, height: frame.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if origin.x + size.width > visible.maxX {
                origin.x = max(visible.minX, frame.minX - size.width - gap)
            }
            origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        }
        let target = NSRect(origin: origin, size: size)
        if ocrVisible && ocrWindow.isVisible {
            ocrWindow.setFrame(target, display: true)
            return
        }
        removeChildWindow(ocrWindow)
        ocrWindow.setFrame(target.offsetBy(dx: 48, dy: 0), display: false)
        ocrWindow.alphaValue = 0
        addChildWindow(ocrWindow, ordered: .above)
        ocrVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ocrWindow.animator().setFrame(target, display: true)
            ocrWindow.animator().alphaValue = 1
        }
    }

    /// Export the active image through a Save panel. The export is WYSIWYG:
    /// it carries the current view rotation, but never touches the source file.
    private func exportActive(as format: ImageExportFormat) {
        guard BillingCoordinator.shared.requireLocalTool("Export".localized, over: self, source: currentRevealInfo?.url) else { return }
        guard let session, let index = currentActionIndex,
              let image = session.images[safe: index] ?? nil else { return }
        let rotation = currentActionViewport.rotationQuarters
        let baseName = (session.infos[index].filename as NSString).deletingPathExtension
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.utType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = ImageExporter.write(image: image, rotatedQuarters: rotation,
                                         to: url, format: format)
            DispatchQueue.main.async {
                if ok {
                    guard let self else { return }
                    self.toastWindow.show(message: "Exported ✓".localized + "\n" + url.path,
                                          over: self)
                } else {
                    if let self { self.toastWindow.show(message: "Export failed".localized, kind: .error, over: self) }
                }
            }
        }
    }

    /// Present a dialog to pick quality and show the resulting file size, then compress
    /// the active image and insert it next to the original for side-by-side comparison.
    @objc private func compressImageTapped() {
        guard BillingCoordinator.shared.requireLocalTool("Compress…".localized, over: self) else { return }
        guard let session, let index = currentActionIndex,
              session.infos.indices.contains(index),
              session.infos[index].kind == .image,
              let image = session.images[safe: index] ?? nil,
              let content = contentView else { return }

        let dimmer = CompressionDimmerView(frame: content.bounds)
        dimmer.autoresizingMask = [.width, .height]
        dimmer.wantsLayer = true
        dimmer.layer?.backgroundColor = NSColor(srgbRed: 6 / 255, green: 7 / 255, blue: 10 / 255, alpha: 0.48).cgColor
        content.addSubview(dimmer)

        let sourceBytes = session.infos[index].fileSize ?? {
            let pixels = image.representations.reduce(0) { current, representation in
                max(current, representation.pixelsWide * representation.pixelsHigh)
            }
            return max(1_048_576, Int64(Double(max(1, pixels)) * 0.5))
        }()
        let dialog = CompressionDialogPanel(sourceByteCount: sourceBytes)
        dialog.onConfirm = { [weak self, weak dialog, weak dimmer] quality, targetByteCount, keepOriginalDimensions in
            dialog?.close()
            dimmer?.removeFromSuperview()
            self?.compressImage(at: index, quality: quality, targetByteCount: targetByteCount,
                                keepOriginalDimensions: keepOriginalDimensions)
        }
        dialog.onCancel = { [weak dialog, weak dimmer] in
            dialog?.close()
            dimmer?.removeFromSuperview()
        }
        dialog.present(over: self)
    }

    /// Compress the image at `index` and insert the result at `index + 1`, then
    /// enter side-by-side compare mode so the user can see before/after.
    private func compressImage(at index: Int, quality: CGFloat, targetByteCount: Int64,
                               keepOriginalDimensions: Bool) {
        guard let session,
              let image = session.images[safe: index] ?? nil else { return }

        let sourceURL = session.infos[index].url
        guard let format = ImageCompressionFormat.exportFormat(for: sourceURL) else {
            showCompressionError()
            return
        }
        let baseName = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let outputDir: URL
        if sourceURL.isFileURL {
            outputDir = sourceURL.deletingLastPathComponent()
        } else {
            outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }

        let sourceExtension = sourceURL.pathExtension.lowercased()
        let targetURL = uniqueURL(in: outputDir, baseName: baseName + ".compressed",
                                  fileExtension: sourceExtension.isEmpty ? format.fileExtension : sourceExtension)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cgImage = ImageExporter.cgImage(from: image, rotatedQuarters: 0) else {
                DispatchQueue.main.async { self?.showCompressionError() }
                return
            }
            let success = ImageExporter.writeCompressed(cgImage: cgImage, to: targetURL,
                                                        format: format, quality: quality,
                                                        targetByteCount: targetByteCount,
                                                        allowResizing: !keepOriginalDimensions)
            DispatchQueue.main.async {
                guard let self, success else {
                    self?.showCompressionError()
                    return
                }
                self.insertCompressedImage(at: index, url: targetURL)
            }
        }
    }

    private func uniqueURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        var url = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName)-\(counter).\(fileExtension)")
            counter += 1
        }
        return url
    }

    private func insertCompressedImage(at index: Int, url: URL) {
        guard let session, session.infos.indices.contains(index) else { return }
        let compressedInfo = MediaInfo(url: url, isLocal: url.isFileURL, kind: .image)
        let insertIndex = insertDerivedItem(compressedInfo, afterSourceIndex: index, in: session)

        BillingManager.shared.trackTrialActivity("compare")
        session.mode = .compare
        session.comparisonStyle = .sideBySide
        session.compareIndices = (index, insertIndex)
        session.activeCompareSlot = 1
        session.focusedIndex = index

        renderSession()
        loadDroppedItem(at: insertIndex, generation: loadGeneration)

        toastWindow.show(message: "Compressed ✓".localized + "\n" + url.path, over: self)
    }

    private func showCompressionError() {
        toastWindow.show(message: "Compression failed".localized, kind: .error, over: self)
    }

    private var currentRevealInfo: MediaInfo? {
        guard let session else { return nil }
        let index: Int
        if session.mode == .compare, let pair = session.compareIndices {
            index = session.activeCompareSlot == 0 ? pair.0 : pair.1
        } else {
            index = session.focusedIndex
        }
        guard session.infos.indices.contains(index) else { return nil }
        return session.infos[index]
    }

    private var currentWidgetResultRecord: WidgetTaskRecord? {
        guard let session, session.mode != .compare,
              session.infos.indices.contains(session.focusedIndex) else { return nil }
        let info = session.infos[session.focusedIndex]
        guard info.kind == .image, info.isLocal,
              let record = WidgetTaskManager.shared.completedRecord(for: info.url),
              record.copyableMediaResultURL != nil else { return nil }
        return record
    }

    private var currentWidgetResultURLString: String? {
        currentWidgetResultRecord?.copyableMediaResultURL
    }

    private var isFocusedWidgetResult: Bool {
        guard let session, session.mode != .compare,
              session.infos.indices.contains(session.focusedIndex) else { return false }
        let info = session.infos[session.focusedIndex]
        guard info.kind == .image, info.isLocal else { return false }
        return session.generatedResultPaths.contains(info.url.standardizedFileURL.path)
            || WidgetTaskManager.shared.completedRecord(for: info.url) != nil
    }

    private func copyWidgetResultURL() {
        guard let record = currentWidgetResultRecord,
              let storedURL = record.copyableMediaResultURL else { return }
        guard let taskID = record.remoteTaskID else {
            copyWidgetResultURLToPasteboard(storedURL)
            return
        }
        WidgetTaskClient.shared.fetchResultURL(taskID: taskID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.currentWidgetResultRecord?.id == record.id else { return }
                switch result {
                case .success(let url): self.copyWidgetResultURLToPasteboard(url.absoluteString)
                case .failure:
                    if let url = URL(string: storedURL), url.host != "api.glance.mcreator.ai" {
                        self.copyWidgetResultURLToPasteboard(storedURL)
                    } else {
                        self.toastWindow.show(message: "Could not refresh result URL".localized, kind: .error, over: self)
                    }
                }
            }
        }
    }

    private func copyWidgetResultURLToPasteboard(_ url: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(url, forType: .string) {
            toastWindow.show(message: "URL copied ✓".localized, over: self)
        }
    }

    private func updateRevealButtonState() {
        revealButton.isEnabled = currentRevealInfo?.isLocal == true
    }

    private func toggleInfo() {
        infoVisible.toggle()
        infoButton.isActive = infoVisible
        // The information panel is a child window attached to the right edge,
        // shown outside the image (like the Widget Market panel).
        if infoVisible {
            infoWindow.setContent(infoPanel)
            infoWindow.present(alongside: self)
            renderSession()   // populate before it appears
        } else {
            infoWindow.dismiss()
        }
    }

    /// Called by the info panel's own close button so the toolbar toggle state
    /// stays in sync when the panel is dismissed from outside.
    func dismissInfoPanel() {
        guard infoVisible else { return }
        infoVisible = false
        infoButton.isActive = false
        infoWindow.dismiss()
    }

    private func updateStatusbar(for info: MediaInfo, index: Int) {
        var parts: [String] = []
        if let size = info.dimensions { parts.append("\(Int(size.width)) × \(Int(size.height))") }
        if info.formatName.isDisplayableValue { parts.append(info.formatName) }
        if let bytes = info.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        statusLeftLabel.stringValue = parts.joined(separator: "  •  ")
    }

    /// Zoom percentage readout between the − and + buttons.
    private func updateZoomLabel() {
        zoomLabel.stringValue = "\(currentActionViewport.zoomPercent)%"
    }

    @objc private func fitToWindowTapped() {
        activeViewports.forEach { $0.fitToView() }
        updateZoomLabel()
    }

    @objc private func backTapped() {
        cancelOperation(nil)
    }

    @objc private func closeTrafficTapped() { closeAndRestore() }
    @objc private func minimizeTrafficTapped() { miniaturize(nil) }
    @objc private func zoomTrafficTapped() { zoom(nil) }

    @objc private func zoomOutTapped() {
        activeViewports.forEach { $0.zoomBy(1 / 1.25) }
        updateZoomLabel()
    }

    @objc private func zoomInTapped() {
        activeViewports.forEach { $0.zoomBy(1.25) }
        updateZoomLabel()
    }

    /// Direction button: rotate/flip through the same themed menu used by the
    /// actions panel (spec `.direction-control`).
    @objc private func directionTapped() {
        let entries: [ActionMenuEntry] = [
            ActionMenuEntry(title: "Rotate Left".localized, shortcut: "⌘L", action: { [weak self] in self?.rotateActive(byQuarters: -1) }),
            ActionMenuEntry(title: "Rotate Right".localized, shortcut: "⌘R", action: { [weak self] in self?.rotateActive(byQuarters: 1) }),
            ActionMenuEntry(title: "Flip Horizontally".localized, action: { [weak self] in self?.flipActive(horizontal: true) }),
            ActionMenuEntry(title: "Flip Vertically".localized, action: { [weak self] in self?.flipActive(horizontal: false) })
        ]
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: entries)
        prepareActionsPanelForAutoHide(panel)
        actionsPanel = panel
        let point = directionButton.convert(NSPoint(x: 0, y: -4), to: nil)
        panel.present(at: convertToScreen(NSRect(origin: point, size: .zero)).origin)
    }

    @objc private func flipMenuTapped() {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: [
            ActionMenuEntry(title: "Flip Horizontally".localized,
                            action: { [weak self] in self?.flipActive(horizontal: true) }),
            ActionMenuEntry(title: "Flip Vertically".localized,
                            action: { [weak self] in self?.flipActive(horizontal: false) })
        ])
        prepareActionsPanelForAutoHide(panel)
        actionsPanel = panel
        let point = flipIconButton.convert(NSPoint(x: 0, y: -4), to: nil)
        panel.present(at: convertToScreen(NSRect(origin: point, size: .zero)).origin)
    }

    /// Filmstrip "+" tile: an explicit alternative to drag-and-drop
    /// (spec: 拖放必须有“添加”按钮作为替代).
    private func presentAddImagesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.handleDroppedResource(url: url, at: .zero)
            }
        }
    }

    private func focus(index: Int) {
        guard let session, session.infos.indices.contains(index) else { return }
        if session.mode == .compare {
            // Tapping a non-image thumbnail in compare mode exits compare and
            // focuses the file — files never join a compare pair.
            guard session.infos[index].kind == .image else {
                session.mode = session.infos.count > 1 ? .browse : .focus
                session.compareIndices = nil
                session.focusedIndex = index
                renderSession()
                return
            }
            if let pair = session.compareIndices {
                // Replace whichever slot is active (left or right), so both sides
                // can be changed. Avoid pointing both slots at the same image.
                if session.activeCompareSlot == 0 {
                    guard index != pair.1 else { return }
                    session.compareIndices = (index, pair.1)
                } else {
                    guard index != pair.0 else { return }
                    session.compareIndices = (pair.0, index)
                }
            }
        } else {
            session.focusedIndex = index
        }
        refitFocusedImageIfNeeded()
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    /// When the focused image changes, re-fit the window to it. If the image is
    /// already loaded, fit immediately; otherwise the load completion fits it.
    private func refitFocusedImageIfNeeded() {
        guard let session, session.mode != .compare else { return }
        fittedImageSize = nil
        if let image = session.images[safe: session.focusedIndex] ?? nil {
            fitWindowToImage(image.size)
        }
    }

    /// Choose which compare slot subsequent filmstrip taps replace, by clicking
    /// the left or right image in side-by-side mode.
    private func selectCompareSlot(_ slot: Int) {
        guard let session,
              session.mode == .compare,
              session.comparisonStyle == .sideBySide,
              session.activeCompareSlot != slot else { return }
        session.activeCompareSlot = slot
        Logger.debug("ImageInspectWindow: active compare slot = \(slot == 0 ? "left" : "right")")
        primaryViewport.isActiveSlot = slot == 0
        secondaryViewport.isActiveSlot = slot == 1
        primaryViewport.setCompareDimmed(slot != 0)
        secondaryViewport.setCompareDimmed(slot != 1)
        updateRevealButtonState()
        if let pair = session.compareIndices {
            infoPanel.highlight(index: slot == 0 ? pair.0 : pair.1)
        }
    }

    private func navigate(by delta: Int) {
        guard let session, !session.infos.isEmpty else { return }
        if session.mode == .compare, let pair = session.compareIndices {
            // Cycle only among images (excluding the pinned left slot).
            let pool = session.infos.indices.filter {
                session.infos[$0].kind == .image && $0 != pair.0
            }
            guard let position = pool.firstIndex(of: pair.1), pool.count > 1 else { return }
            let candidate = pool[(position + delta + pool.count) % pool.count]
            session.compareIndices = (pair.0, candidate)
        } else {
            session.focusedIndex = (session.focusedIndex + delta + session.infos.count) % session.infos.count
        }
        refitFocusedImageIfNeeded()
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    private func compare(focusedWith index: Int) {
        guard let session, session.infos.indices.contains(index), index != session.focusedIndex,
              session.infos[index].kind == .image,
              session.infos[session.focusedIndex].kind == .image else { return }
        BillingManager.shared.trackTrialActivity("compare")
        session.mode = .compare
        session.compareIndices = (session.focusedIndex, index)
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    /// Append a freshly captured frame (from video capture handoff) to the
    /// current session and focus it; leaves compare mode so the capture shows.
    func appendImage(info: MediaInfo) {
        guard let session, isVisible else {
            show(infos: [info], loaded: [nil], focusedIndex: 0)
            return
        }
        session.infos.append(info)
        session.images.append(nil)
        session.metadata.append(nil)
        let newIndex = session.infos.count - 1
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        session.focusedIndex = newIndex
        renderSession()
        loadDroppedItem(at: newIndex, generation: loadGeneration)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Accept an image file dragged onto the window. The file is appended to
    /// the end of the filmstrip; which on-screen slot shows it depends on the
    /// current mode:
    ///   - Focus/Browse: display the dropped image directly.
    ///   - Side by side: replace the side the drop landed on.
    ///   - Slider: replace the base (A) image.
    private func handleDroppedImage(url: URL, at point: NSPoint) {
        guard let session else { return }
        // A repeated resource selects the existing item instead of creating a
        // duplicate thumbnail. Exit Compare so the selected image is shown as
        // the single focused image immediately.
        let identity = mediaIdentity(for: url)
        if let existingIndex = session.infos.firstIndex(where: {
            mediaIdentity(for: $0.url) == identity
        }) {
            session.mode = .focus
            session.compareIndices = nil
            session.focusedIndex = existingIndex
            renderSession()
            loadFullResolutionForActiveItems(generation: loadGeneration)
            return
        }
        session.infos.append(MediaInfo(url: url, isLocal: url.isFileURL, kind: .image))
        session.images.append(nil)
        session.metadata.append(nil)
        let newIndex = session.infos.count - 1
        if session.mode == .compare, let pair = session.compareIndices {
            if session.comparisonStyle == .sideBySide {
                let slot = primaryViewport.frame.contains(point) ? 0 : 1
                session.activeCompareSlot = slot
                session.compareIndices = slot == 0 ? (newIndex, pair.1) : (pair.0, newIndex)
            } else {
                session.compareIndices = (newIndex, pair.1)
            }
        } else {
            // A single-image Focus session becomes Browse after the append:
            // the dropped image is the main image and both items remain in
            // the filmstrip.
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.focusedIndex = newIndex
        }
        Logger.debug("ImageInspectWindow: dropped image \(Logger.redact(url.lastPathComponent)) at index \(newIndex)")
        renderSession()
        loadDroppedItem(at: newIndex, generation: loadGeneration)
    }

    private func mediaIdentity(for url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.path : url.absoluteURL.absoluteString
    }

    private func sessionIndex(for url: URL, in session: ImageInspectSession) -> Int? {
        let identity = mediaIdentity(for: url)
        return session.infos.firstIndex { mediaIdentity(for: $0.url) == identity }
    }

    /// Clipboard text for URL pasting. Browser address-bar copies and some
    /// apps only provide an NSURL object (public.url) without a plain-string
    /// type, so readObjects is required as a fallback.
    static func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return text }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            return url.absoluteString
        }
        return nil
    }

    /// ⌘V: classify clipboard text through the same PathDetector used by the
    /// selection-hotkey pipeline, then display a remote image URL directly.
    /// A copied URL can coexist with image data on the pasteboard; prefer the
    /// explicit text URL so it enters the remote download path.
    private func pasteRemoteImageFromClipboard() -> Bool {
        if let text = NSPasteboard.general.string(forType: .string),
           pasteRemoteImage(from: text) { return true }
        if let imageURL = Self.materializeClipboardImage() {
            appendOrFocusImage(info: MediaInfo(url: imageURL, isLocal: true, kind: .image))
            return true
        }
        guard let text = Self.clipboardText() else { return false }
        return pasteRemoteImage(from: text)
    }

    private func pasteRemoteImage(from text: String) -> Bool {
        guard let info = imageInfo(from: text, allowExtensionlessRemoteURL: true),
              !info.isLocal else { return false }
        appendOrFocusImage(info: info)
        return true
    }

    private static func materializeClipboardImage() -> URL? {
        let pasteboard = NSPasteboard.general
        let types: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(rawValue: UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(rawValue: "public.heic"),
            NSPasteboard.PasteboardType(rawValue: "org.webmproject.webp")
        ]
        guard let type = pasteboard.availableType(from: types),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlanceClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Toolbar "globe" button: a sheet accepting an image URL OR a local
    /// path. Local files display immediately; remote URLs show the loading
    /// animation while downloading into the persistent cache.
    @objc private func openURLTapped() {
        let alert = NSAlert()
        alert.messageText = "Open image URL".localized
        alert.informativeText = "Paste an image URL or local path".localized
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 88))
        field.font = PanelStyle.body
        field.textColor = PanelStyle.textPrimary
        field.backgroundColor = PanelStyle.controlFill
        field.drawsBackground = true
        field.isRichText = false
        field.string = ""
        field.textContainerInset = NSSize(width: 8, height: 8)
        alert.accessoryView = field
        alert.addButton(withTitle: "Open".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.window.initialFirstResponder = field
        var pasteMonitor: Any?
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.window === alert.window,
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                if field.window?.firstResponder === field {
                    field.paste(nil)
                } else if let text = Self.clipboardText() {
                    field.string = text
                }
                return nil
            }
            return event
        }
        alert.beginSheetModal(for: self) { [weak self, weak field] response in
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            guard response == .alertFirstButtonReturn,
                  let text = field?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            self?.openImageFromInput(text)
        }
        // NSAlert creates its field editor only after the sheet is attached.
        // Make the accessory field first responder on the next run-loop turn
        // so native typing and ⌘V both target it reliably.
        DispatchQueue.main.async { [weak self, weak alert, weak field] in
            guard let self, let alert, let field,
                  self.attachedSheet === alert.window else { return }
            alert.window.makeFirstResponder(field)
        }
    }

    private func openImageFromInput(_ text: String) {
        guard let info = imageInfo(from: text, allowExtensionlessRemoteURL: true) else {
            toastWindow.show(message: "No image URL found".localized, kind: .error, over: self)
            return
        }
        appendOrFocusImage(info: info)
    }

    /// Return a normal detected image, or let the image-specific URL entry
    /// point probe an extensionless HTTP URL by sending it to the decoder.
    /// Generic selection detection still treats unknown URLs as webpages.
    private func imageInfo(from text: String, allowExtensionlessRemoteURL: Bool) -> MediaInfo? {
        for path in pathDetector.detectAll(text) {
            guard let info = MediaInfo.from(path) else { continue }
            if info.kind == .image { return info }
            if allowExtensionlessRemoteURL, info.kind == .webPage, !info.isLocal {
                return MediaInfo(url: info.url, isLocal: false, kind: .image)
            }
        }
        return nil
    }

    /// Shared append-or-focus path for URL input, ⌘V, and remote drops:
    /// duplicates focus the existing item; new items append to the filmstrip
    /// end and take focus.
    private func appendOrFocusImage(info: MediaInfo) {
        guard let session else {
            show(infos: [info], loaded: [nil], focusedIndex: 0, preferredMode: .focus)
            return
        }
        let identity = mediaIdentity(for: info.url)
        if let index = session.infos.firstIndex(where: { mediaIdentity(for: $0.url) == identity }) {
            session.mode = .focus
            session.compareIndices = nil
            session.focusedIndex = index
            renderSession()
            loadFullResolutionForActiveItems(generation: loadGeneration)
            return
        }
        session.infos.append(info)
        session.images.append(nil)
        session.metadata.append(nil)
        let index = session.infos.count - 1
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        session.focusedIndex = index
        renderSession()
        loadDroppedItem(at: index, generation: loadGeneration)
        if !info.isLocal { Logger.info("ImageInspectWindow: pasted remote image") }
    }

    private func handleDroppedResource(url: URL, at point: NSPoint) {
        let info: MediaInfo?
        if url.isFileURL {
            info = MediaInfo.from(pathDetector.localKind(for: url.path))
        } else {
            info = pathDetector.detectAll(url.absoluteString)
                .compactMap(MediaInfo.from).first
        }
        guard let info else { return }
        switch info.kind {
        case .image:
            handleDroppedImage(url: info.url, at: point)
        case .video:
            onOpenVideo?(info)
        case .markdown, .text, .pdf, .webPage:
            onOpenContent?(info)
        case .other, .folder:
            closeForViewerHandoff()
            if info.isLocal {
                NSWorkspace.shared.activateFileViewerSelecting([info.url])
            } else {
                NSWorkspace.shared.open(info.url)
            }
        }
    }

    /// Load only the newly appended item — the rest of the session is already
    /// loaded, so a full loadSessionImages pass would redo work.
    private func loadDroppedItem(at index: Int, generation: UUID) {
        guard let session, session.infos.indices.contains(index) else { return }
        let info = session.infos[index]
        // Populate the filmstrip immediately for local drops. The full
        // decoder below can take a moment (especially for large RAW/PNG
        // files), and waiting for it leaves a blank thumbnail in the meantime.
        if info.isLocal, session.images[index] == nil,
           let quickThumbnail = NSImage(contentsOf: info.url) {
            session.images[index] = quickThumbnail
            renderSession()
        }
        imageLoader.loadFullResolutionImage(from: info.url) { [weak self] image in
            guard let self, generation == self.loadGeneration,
                  let session = self.session,
                  let currentIndex = self.sessionIndex(for: info.url, in: session) else { return }
            if let image {
                session.failedIndices.remove(currentIndex)
                session.images[currentIndex] = image
                session.infos[currentIndex].dimensions = image.size
                if session.mode != .compare, currentIndex == session.focusedIndex {
                    self.fitWindowToImage(image.size)
                }
                self.scheduleOCR(for: info.url, image: image)
            } else {
                session.failedIndices.insert(currentIndex)
                if let displayed = session.images[currentIndex] {
                    self.scheduleOCR(for: info.url, image: displayed)
                }
            }
            self.renderSession()
        }
        imageLoader.loadFileSize(from: info.url) { [weak self] bytes in
            guard let self, generation == self.loadGeneration,
                  let session = self.session,
                  let currentIndex = self.sessionIndex(for: info.url, in: session) else { return }
            session.infos[currentIndex].fileSize = bytes
            self.renderSession()
        }
        imageLoader.loadTechnicalMetadata(from: info.url) { [weak self] metadata in
            guard let self, generation == self.loadGeneration,
                  let session = self.session,
                  let currentIndex = self.sessionIndex(for: info.url, in: session) else { return }
            session.metadata[currentIndex] = metadata
            self.renderSession()
        }
    }

    private func syncViewport(_ state: InspectViewportState, source: InspectImageViewport?) {
        guard session?.mode == .compare, session?.comparisonStyle == .sideBySide else { return }
        for viewport in [primaryViewport, secondaryViewport] where viewport !== source {
            viewport.apply(state: state, notify: false)
        }
    }

    private func closeAndRestore() {
        isClosingProgrammatically = true
        orderOut(nil)
        isClosingProgrammatically = false
        onClose?()
    }

    private func updateWindowTitle(for info: MediaInfo, index: Int) {
        // The window title stays generic; the filename shows in the bottom bar.
        title = "Image Inspect".localized
        representedURL = nil
    }
}
