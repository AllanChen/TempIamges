import AppKit
import Highlightr

/// Shared visual design tokens for Glance's floating panels and content
/// windows. Centralises the frosted-dark-glass palette, type scale, and
/// frosted-base builder so PreviewPanel, ContentPanel and ContentViewerWindow
/// speak one design language instead of each rolling their own colours and
/// fonts.
///
/// The whole chrome commits to an on-glass dark palette regardless of the
/// system theme — fills are translucent white so the frost reads through them,
/// text is white / dimmed-white.
enum PanelStyle {

    // MARK: - Palette

    /// Primary text on the dark frost.
    static let textPrimary    = NSColor.white
    /// Secondary / supporting text (paths, metadata).
    static let textSecondary  = NSColor(white: 1, alpha: 0.62)
    /// Tertiary text (timestamps, counts, hints).
    static let textTertiary   = NSColor(white: 1, alpha: 0.42)

    /// Hairline that defines a bar edge / separator on the frost.
    static let hairline       = NSColor(white: 1, alpha: 0.10)
    /// Translucent fill for a top/bottom bar sitting on the frost.
    static let barFill        = NSColor(white: 1, alpha: 0.05)
    /// Translucent fill for an inline control (button, field) on the frost.
    static let controlFill    = NSColor(white: 1, alpha: 0.10)
    /// Hover/active state of `controlFill`.
    static let controlFillHi  = NSColor(white: 1, alpha: 0.18)
    /// Translucent card fill for grouped controls / overlays.
    static let glassCard      = NSColor(white: 1, alpha: 0.07)

    /// Always-dark neutral canvas behind images — the image needs a dark frame
    /// to read against, even on the frosted base.
    static let imageCanvas    = NSColor(white: 0.03, alpha: 1)

    static let accent         = NSColor.systemBlue

    // MARK: - Type scale

    /// Window / section title.
    static var title: NSFont    { .systemFont(ofSize: 15, weight: .semibold) }
    /// Filenames, primary one-line labels.
    static var headline: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    /// Default body text.
    static var body: NSFont     { .systemFont(ofSize: 13, weight: .regular) }
    /// Control labels, address/path fields.
    static var label: NSFont    { .systemFont(ofSize: 12, weight: .medium) }
    /// Secondary metadata, captions, counts.
    static var caption: NSFont  { .systemFont(ofSize: 11, weight: .regular) }

    // MARK: - Appearance helpers

    /// Resolve a (possibly dynamic) NSColor to a CGColor against the app's
    /// current effective appearance. `layer.backgroundColor` stores a snapshot
    /// CGColor, so without forcing the right appearance a semantic NSColor reads
    /// `NSAppearance.currentDrawing` at the call site (usually default Aqua),
    /// ignoring our theme override.
    static func resolvedCG(_ color: NSColor) -> CGColor {
        var resolved: CGColor!
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    /// A within-window dark frosted material, for the top/bottom bars of a
    /// content window. Translucent so the content scrolling beneath shows
    /// through, biased dark via the vibrant-dark appearance.
    static func makeBarBlur() -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.material = .headerView
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        return blur
    }

    /// A dark, semi-transparent frosted base for a borderless panel.
    /// `.hudWindow` + vibrant-dark gives the translucent black "磨砂" material;
    /// a black tint sublayer biases the frost toward black so it reads
    /// consistently over bright wallpapers.
    static func makeFrostedBase(cornerRadius: CGFloat) -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true

        let tint = CALayer()
        tint.backgroundColor = NSColor(white: 0, alpha: 0.30).cgColor
        tint.cornerRadius = cornerRadius
        tint.frame = blur.bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(tint)
        return blur
    }

    /// Theme name (a highlight.js theme bundled with Highlightr) used for the
    /// editable code view — a dark theme whose background sits close to the
    /// panel's dark base.
    static let codeTheme = "tomorrow-night"

    /// Build an editable, syntax-highlighting code text view backed by
    /// Highlightr's `CodeAttributedString`. Highlighting re-runs automatically
    /// as the user types. Set the file's language afterwards via
    /// `(textView.textStorage as? CodeAttributedString)?.language`.
    static func makeCodeTextView() -> NSTextView {
        let storage = CodeAttributedString()
        storage.highlightr.setTheme(to: codeTheme)
        storage.highlightr.theme.codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.allowsUndo = true
        // Keep rich text on so highlight colours render, but disable the
        // "smart" substitutions that would corrupt source code.
        tv.isRichText = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        // The designated initializer (frame:textContainer:) leaves min/maxSize at
        // the frame size (.zero), which pins the text view's height and makes the
        // bottom of long files unreachable in the scroll view. Restore the
        // unbounded growth the convenience NSTextView(frame:) initializer gives.
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        // Built-in find-bar support: ⌘F inline find; ⌘G / ⌘⇧G cycle matches.
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.drawsBackground = true
        tv.backgroundColor = storage.highlightr.theme.themeBackgroundColor
        tv.insertionPointColor = .white
        return tv
    }

    /// A uniform borderless SF Symbol icon button for the toolbars — white
    /// glyph, no bezel, tooltip carries the label. Mirrors PreviewPanel's
    /// `makeIconButton` so the chrome shares one button style.
    static func makeIconButton(symbol: String, tooltip: String,
                               target: AnyObject?, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.contentTintColor = textPrimary
        btn.toolTip = tooltip
        btn.target = target
        btn.action = action
        return btn
    }

    /// Add a 1px hairline separator along one edge of `bar`. Returns the
    /// separator view so callers can re-tint it on theme change.
    @discardableResult
    static func addHairline(to bar: NSView, edge: NSRectEdge) -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = hairline.cgColor
        switch edge {
        case .minY:
            sep.frame = NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1)
            sep.autoresizingMask = [.width]
        case .maxY:
            sep.frame = NSRect(x: 0, y: bar.bounds.height - 1, width: bar.bounds.width, height: 1)
            sep.autoresizingMask = [.width, .minYMargin]
        default:
            sep.frame = NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1)
            sep.autoresizingMask = [.width]
        }
        bar.addSubview(sep)
        return sep
    }
}
