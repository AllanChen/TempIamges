import AppKit
import Highlightr

/// Shared loading indicator used by image, document, and web previews.
/// The three wireframe modules follow the same calm 2.04-second cycle as the
/// reference animation, while staying resolution-independent in Core Animation.
final class ModularImageLoadingView: NSView {
    static let preferredSize = NSSize(width: 104, height: 128)

    private let moduleLayers = (0..<3).map { _ in CAShapeLayer() }
    private var isLoading = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for moduleLayer in moduleLayers {
            moduleLayer.fillColor = NSColor.clear.cgColor
            moduleLayer.strokeColor = PanelStyle.resolvedCG(PanelStyle.textPrimary.withAlphaComponent(0.58))
            moduleLayer.lineWidth = 1
            moduleLayer.lineCap = .round
            moduleLayer.lineJoin = .round
            moduleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(moduleLayer)
        }
        configureGeometry()
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setLoading(_ loading: Bool) {
        guard loading != isLoading else { return }
        isLoading = loading
        isHidden = !loading
        loading ? startAnimating() : stopAnimating()
    }

    private func configureGeometry() {
        let path = CGMutablePath()
        let top = CGPoint(x: 19, y: 0)
        let upperRight = CGPoint(x: 38, y: 11)
        let lowerRight = CGPoint(x: 38, y: 33)
        let bottom = CGPoint(x: 19, y: 44)
        let lowerLeft = CGPoint(x: 0, y: 33)
        let upperLeft = CGPoint(x: 0, y: 11)
        let center = CGPoint(x: 19, y: 22)
        path.move(to: top)
        path.addLines(between: [upperRight, lowerRight, bottom, lowerLeft, upperLeft, top])
        path.move(to: top)
        path.addLines(between: [center, bottom])
        path.move(to: upperLeft)
        path.addLines(between: [center, upperRight])

        let restingPositions = [CGPoint(x: 52, y: 22), CGPoint(x: 52, y: 64), CGPoint(x: 62, y: 106)]
        for (moduleLayer, position) in zip(moduleLayers, restingPositions) {
            moduleLayer.bounds = CGRect(x: 0, y: 0, width: 38, height: 44)
            moduleLayer.position = position
            moduleLayer.path = path
        }
    }

    private func startAnimating() {
        stopAnimating()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let positions: [[CGPoint]] = [
            [CGPoint(x: 52, y: 22), CGPoint(x: 52, y: 64), CGPoint(x: 62, y: 106)],
            [CGPoint(x: 34, y: 50), CGPoint(x: 70, y: 50), CGPoint(x: 52, y: 82)],
            [CGPoint(x: 52, y: 22), CGPoint(x: 34, y: 78), CGPoint(x: 70, y: 78)],
            [CGPoint(x: 34, y: 22), CGPoint(x: 70, y: 50), CGPoint(x: 52, y: 92)],
            [CGPoint(x: 52, y: 22), CGPoint(x: 52, y: 64), CGPoint(x: 62, y: 106)],
        ]
        let keyTimes: [NSNumber] = [0, 0.25, 0.5, 0.75, 1]
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        for (index, moduleLayer) in moduleLayers.enumerated() {
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = positions.map { NSValue(point: $0[index]) }
            movement.keyTimes = keyTimes
            movement.timingFunctions = Array(repeating: timing, count: keyTimes.count - 1)
            movement.duration = 2.04
            movement.repeatCount = .infinity
            movement.isRemovedOnCompletion = false
            moduleLayer.add(movement, forKey: "glance.modularLoading")
        }
    }

    private func stopAnimating() {
        moduleLayers.forEach { $0.removeAnimation(forKey: "glance.modularLoading") }
    }
}

/// Shared visual design tokens for Glance's floating panels and content
/// windows. Centralises the frosted-dark-glass palette, type scale, and
/// frosted-base builder so PreviewPanel, ContentPanel and ContentViewerWindow
/// speak one design language instead of each rolling their own colours and
/// fonts. Neutral darkroom surfaces frame the content, while warm gold is
/// reserved for small, meaningful interaction cues.
enum PanelStyle {

    // MARK: - Palette

    /// Deepest image/background plane — Quiet Darkroom `#101113`.
    static let canvas = NSColor(srgbRed: 16 / 255, green: 17 / 255, blue: 19 / 255, alpha: 1)
    /// Primary chrome plane — `#17191C`.
    static let surface = NSColor(srgbRed: 23 / 255, green: 25 / 255, blue: 28 / 255, alpha: 1)
    /// Raised controls and cards — `#202329`.
    static let overlay = NSColor(srgbRed: 32 / 255, green: 35 / 255, blue: 41 / 255, alpha: 1)

    /// Warm off-white primary text — `#F2F0EB`.
    static let textPrimary = NSColor(srgbRed: 242 / 255, green: 240 / 255, blue: 235 / 255, alpha: 1)
    /// Secondary / supporting text — `#A7A8AA`.
    static let textSecondary = NSColor(srgbRed: 167 / 255, green: 168 / 255, blue: 170 / 255, alpha: 1)
    /// Tertiary text (timestamps, counts, hints).
    static let textTertiary = NSColor(srgbRed: 119 / 255, green: 122 / 255, blue: 126 / 255, alpha: 1)
    /// Sparse focus/interaction cue — `#E1B982`.
    static let warmCue = NSColor(srgbRed: 225 / 255, green: 185 / 255, blue: 130 / 255, alpha: 1)

    /// Hairline that defines a bar edge / separator on the frost.
    static let hairline       = textPrimary.withAlphaComponent(0.10)
    /// Translucent fill for a top/bottom bar sitting on the frost.
    static let barFill        = overlay.withAlphaComponent(0.72)
    /// Translucent fill for an inline control (button, field) on the frost.
    static let controlFill    = textPrimary.withAlphaComponent(0.09)
    /// Hover/active state of `controlFill`.
    static let controlFillHi  = textPrimary.withAlphaComponent(0.16)
    /// Translucent card fill for grouped controls / overlays.
    static let glassCard      = overlay.withAlphaComponent(0.76)

    /// Always-dark neutral canvas behind images — the image needs a dark frame
    /// to read against, even on the frosted base.
    static let imageCanvas    = canvas

    static let accent         = warmCue

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
    /// a canvas tint sublayer biases the frost toward the palette so it reads
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
        tint.backgroundColor = canvas.withAlphaComponent(0.58).cgColor
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
