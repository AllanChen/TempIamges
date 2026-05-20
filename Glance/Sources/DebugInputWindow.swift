#if DEBUG
import AppKit

/// Floating window that holds a multi-line text view + a "Run" button.
/// Used in DEBUG builds to iterate on path-detection inputs without
/// re-selecting text in another app — paste content, click Run, the
/// preview pipeline gets fed the text.
final class DebugInputWindow: NSWindow {
    private let textView: NSTextView

    /// Fired when the user clicks Run. The argument is the current text-view
    /// contents (no trimming — pass through verbatim so you can test
    /// whitespace edge cases).
    var onRun: ((String) -> Void)?

    init() {
        let w: CGFloat = 560
        let h: CGFloat = 400

        // Build the text view first so the stored property is initialised
        // before super.init.
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 32, height: h - 80))
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(
            width: w - 32,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        self.textView = tv

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Glance Debug".localized
        isReleasedWhenClosed = false

        // Stay visible across spaces, on top of normal app windows, and
        // don't auto-hide when the user clicks into another app. The user
        // can drag it from anywhere (title bar or background).
        level = .floating
        collectionBehavior = [.canJoinAllSpaces]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        // Park the window in the top-left of the main screen so it doesn't
        // sit on top of the preview panel (which targets screen centre).
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: visible.minX + 24,
                y: visible.maxY - h - 24
            ))
        } else {
            center()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: w - 32, height: h - 80))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tv
        root.addSubview(scroll)

        let runBtn = NSButton(title: "Run".localized, target: self, action: #selector(runTapped))
        runBtn.bezelStyle = .rounded
        runBtn.keyEquivalent = "\r"   // Enter triggers Run
        runBtn.frame = NSRect(x: w - 96, y: 16, width: 80, height: 28)
        runBtn.autoresizingMask = [.minXMargin]
        root.addSubview(runBtn)

        let cleanBtn = NSButton(title: "Clean".localized, target: self, action: #selector(cleanTapped))
        cleanBtn.bezelStyle = .rounded
        cleanBtn.frame = NSRect(x: w - 184, y: 16, width: 80, height: 28)
        cleanBtn.autoresizingMask = [.minXMargin]
        root.addSubview(cleanBtn)

        let hint = NSTextField(labelWithString:
            "Paste any text — click Run (or press ⏎) to test detection.".localized)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 22, width: w - 208, height: 16)
        hint.autoresizingMask = [.width]
        root.addSubview(hint)

        contentView = root
    }

    /// Replace the text view's contents. Useful for pre-populating with a
    /// known test sample.
    func setText(_ text: String) {
        textView.string = text
    }

    @objc private func runTapped() {
        onRun?(textView.string)
    }

    @objc private func cleanTapped() {
        textView.string = ""
    }

    /// LSUIElement apps have no main menu, so the standard Edit-menu
    /// keyboard shortcuts (⌘C / ⌘V / ⌘X / ⌘A / ⌘Z / ⌘⇧Z) never reach the
    /// text view through the usual menu-broadcast path. Intercept them
    /// here and route to the responder chain manually.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let isShift = event.modifierFlags.contains(.shift)
        let key = event.charactersIgnoringModifiers ?? ""
        let action: Selector?
        switch key {
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z":
            if isShift { undoManager?.redo() } else { undoManager?.undo() }
            return true
        default:  action = nil
        }
        if let action = action,
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
#endif
