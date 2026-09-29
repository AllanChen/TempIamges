import AppKit
import Highlightr

/// The Focus Sweep loader from Glance Motion / 05. Shared by preview surfaces.
final class FocusSweepLoadingView: NSView {
    static let preferredSize = NSSize(width: 160, height: 173)

    private let focusArtwork = NSView(frame: NSRect(x: 0, y: 61, width: 160, height: 112))
    private let beam = NSView(frame: NSRect(x: 12, y: 76, width: 136, height: 16))
    private let scanLine = NSView(frame: NSRect(x: 12, y: 90, width: 136, height: 2))
    private let imageGlyph = NSImageView(frame: NSRect(x: 48, y: 35, width: 64, height: 42))
    private let corners: [NSImageView] = [
        NSImageView(frame: NSRect(x: 0, y: 94, width: 18, height: 18)),
        NSImageView(frame: NSRect(x: 142, y: 94, width: 18, height: 18)),
        NSImageView(frame: NSRect(x: 0, y: 0, width: 18, height: 18)),
        NSImageView(frame: NSRect(x: 142, y: 0, width: 18, height: 18))
    ]
    private let caption = NSTextField(labelWithString: "Preparing preview".localized)
    private var isLoading = false

    var showsCaption = true {
        didSet { caption.isHidden = !showsCaption }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusArtwork.wantsLayer = true
        addSubview(focusArtwork)

        let accent = NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 125 / 255, alpha: 1)
        for (view, radius) in [(beam, CGFloat(0)), (scanLine, CGFloat(1))] {
            view.wantsLayer = true
            view.layer?.backgroundColor = accent.cgColor
            view.layer?.cornerRadius = radius
            focusArtwork.addSubview(view)
        }
        for (view, name) in zip([imageGlyph] + corners,
                                ["FocusSweepImage", "FocusSweepCornerTL", "FocusSweepCornerTR",
                                 "FocusSweepCornerBL", "FocusSweepCornerBR"]) {
            view.image = NSImage(named: NSImage.Name(name))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            focusArtwork.addSubview(view)
        }
        caption.font = PanelStyle.inspectFont(ofSize: 14)
        caption.textColor = NSColor(srgbRed: 0.72, green: 0.69, blue: 0.67, alpha: 1)
        caption.alignment = .center
        caption.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
        caption.wantsLayer = true
        addSubview(caption)
        resetAppearance()
        setAccessibilityLabel("Preparing preview".localized)
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

    private var animatedLayers: [CALayer] {
        ([beam, scanLine, imageGlyph] + corners + [caption]).compactMap(\.layer)
    }

    private func startAnimating() {
        stopAnimating()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageGlyph.layer?.opacity = 0.92
            imageGlyph.layer?.transform = CATransform3DIdentity
            corners.forEach { $0.layer?.opacity = 0.9 }
            caption.layer?.opacity = 0.88
            CATransaction.commit()
            return
        }

        // Figma's three-cycle 6.12s timeline is three identical 2.04s sweeps.
        for (view, peak) in [(beam, 0.09), (scanLine, 0.82)] {
            animate(view.layer, "opacity", [0, 0.18, 1.58, 1.84, 2.04],
                    [0, peak, peak, 0, 0])
            // The last millisecond is an invisible step back to the top.
            animate(view.layer, "transform.translation.y", [0, 0.18, 1.58, 1.84, 2.039, 2.04],
                    [0, 0, -72, -80, -80, 0])
        }
        animate(imageGlyph.layer, "opacity", [0, 0.55, 1.2, 1.72, 2.04],
                [0.28, 0.4, 0.92, 0.55, 0.28])
        animate(imageGlyph.layer, "transform.scale", [0, 1.2, 2.04], [0.94, 1.02, 0.94])
        animate(caption.layer, "opacity", [0, 1.02, 2.04], [0.55, 0.88, 0.55])

        for (index, view) in corners.enumerated() {
            guard let layer = view.layer else { continue }
            let x: CGFloat = index.isMultiple(of: 2) ? 4 : -4
            let y: CGFloat = index < 2 ? -4 : 4
            let origin = layer.position
            let times: [Double] = [0, 0.35, 0.52, 1.45, 2.04]
            let positions = [origin,
                             CGPoint(x: origin.x + x * 1.1, y: origin.y + y * 1.1),
                             CGPoint(x: origin.x + x, y: origin.y + y),
                             CGPoint(x: origin.x + x, y: origin.y + y), origin]
            let movement = keyframes("position", times, positions.map { NSValue(point: $0) })
            layer.add(movement, forKey: "focusSweep.position")
            animate(layer, "opacity", [0, 0.52, 1.45, 2.04], [0.55, 0.9, 0.9, 0.55])
        }
    }

    private func stopAnimating() {
        animatedLayers.forEach { $0.removeAllAnimations() }
        resetAppearance()
    }

    private func resetAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beam.layer?.opacity = 0
        scanLine.layer?.opacity = 0
        imageGlyph.layer?.opacity = 0.28
        imageGlyph.layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        corners.forEach { $0.layer?.opacity = 0.55 }
        caption.layer?.opacity = 0.55
        CATransaction.commit()
    }

    private func animate(_ layer: CALayer?, _ path: String, _ seconds: [Double], _ values: [Double]) {
        guard let layer else { return }
        layer.add(keyframes(path, seconds, values.map { NSNumber(value: $0) }), forKey: "focusSweep.\(path)")
    }

    private func keyframes(_ path: String, _ seconds: [Double], _ values: [Any]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = seconds.map { NSNumber(value: $0 / 2.04) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                          count: seconds.count - 1)
        animation.duration = 2.04
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}

/// Shared animated failure artwork used wherever a preview cannot be loaded.
/// The GIF is bundled so AppKit can advance only the airplane and skull layers
/// while the rest of the frosted-black composition remains static.
final class LoadFailedAnimationView: NSImageView {
    static let preferredSize = NSSize(width: 170, height: 170)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        animates = true
        imageAlignment = .alignCenter
        isEditable = false
        image = Self.loadImage()
        setAccessibilityLabel("Load failed".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func loadImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "LoadFailed", withExtension: "gif") else {
            Logger.error("LoadFailed.gif is missing from the app bundle")
            return nil
        }
        return NSImage(contentsOf: url)
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

    /// Deepest image/background plane — Quiet Darkroom `#09090B`.
    static let canvas = NSColor(srgbRed: 9 / 255, green: 9 / 255, blue: 11 / 255, alpha: 1)
    /// Primary chrome plane — `#111114`.
    static let surface = NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1)
    /// Raised controls and cards — `#17171C`.
    static let overlay = NSColor(srgbRed: 23 / 255, green: 23 / 255, blue: 28 / 255, alpha: 1)
    /// Toolbar chrome plane, one step below `surface` — `#0D0D10`.
    static let chrome = NSColor(srgbRed: 13 / 255, green: 13 / 255, blue: 16 / 255, alpha: 1)
    /// Elevated surface for floating menus and cards — `#201F25`.
    static let surfaceElevated = NSColor(srgbRed: 32 / 255, green: 31 / 255, blue: 37 / 255, alpha: 1)
    /// Image Inspect Figma palette. Kept separate so other Glance windows can
    /// migrate independently without inheriting the denser inspector chrome.
    static let inspectBackground = NSColor(srgbRed: 6 / 255, green: 7 / 255, blue: 10 / 255, alpha: 1)
    static let inspectChrome = NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
    static let inspectToolbar = NSColor(srgbRed: 44 / 255, green: 45 / 255, blue: 49 / 255, alpha: 1)
    static let inspectCanvas = NSColor(srgbRed: 9 / 255, green: 10 / 255, blue: 13 / 255, alpha: 1)
    static let inspectStatus = NSColor(srgbRed: 26 / 255, green: 27 / 255, blue: 32 / 255, alpha: 1)
    static let inspectLine = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1)
    /// Semantic alias matching the V2 spec: raised surface (`overlay`).
    static var surfaceRaised: NSColor { overlay }

    /// Warm off-white primary text — `#F3EEE8`.
    static let textPrimary = NSColor(srgbRed: 243 / 255, green: 238 / 255, blue: 232 / 255, alpha: 1)
    /// Secondary / supporting text — `#AAA4A0`.
    static let textSecondary = NSColor(srgbRed: 170 / 255, green: 164 / 255, blue: 160 / 255, alpha: 1)
    /// Tertiary text (timestamps, counts, hints).
    static let textTertiary = NSColor(srgbRed: 114 / 255, green: 109 / 255, blue: 105 / 255, alpha: 1)
    /// Warm apricot interaction cue, the only brand accent — `#E8A87C`.
    static let warmCue = NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 124 / 255, alpha: 1)
    /// Dark ink drawn on top of `accent` fills (primary buttons) — `#21130D`.
    static let accentInk = NSColor(srgbRed: 33 / 255, green: 19 / 255, blue: 13 / 255, alpha: 1)
    /// Accent hover fill — `#F0B58E`.
    static let accentHover = NSColor(srgbRed: 240 / 255, green: 181 / 255, blue: 142 / 255, alpha: 1)
    /// Subtle accent tint for selected/active backgrounds.
    static let accentSubtleFill = warmCue.withAlphaComponent(0.12)
    /// Subtle accent tint for selected/active borders.
    static let accentSubtleBorder = warmCue.withAlphaComponent(0.35)

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
    /// Semantic colours shared by task, Widget, and validation states.
    static let success        = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 1)
    static let failure        = NSColor(srgbRed: 241 / 255, green: 139 / 255, blue: 134 / 255, alpha: 1)
    static let info           = NSColor(srgbRed: 169 / 255, green: 197 / 255, blue: 239 / 255, alpha: 1)
    /// Alias matching the V2 spec vocabulary.
    static var danger: NSColor { failure }
    static let cornerSmall: CGFloat = 8
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 16
    static let spacing: CGFloat = 8

    // MARK: - Workbench geometry (V2 spec)

    /// Height of a content window's custom title bar.
    static let titlebarHeight: CGFloat = 44
    /// Height of the workbench toolbar below the title bar.
    static let toolbarHeight: CGFloat = 48
    /// Width of the collapsible right inspector.
    static let inspectorWidth: CGFloat = 280
    /// Height of the bottom filmstrip.
    static let filmstripHeight: CGFloat = 92
    /// Height of the bottom status bar.
    static let statusbarHeight: CGFloat = 26
    /// Minimum hit-target height for ordinary controls.
    static let controlHeight: CGFloat = 32

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

    /// Fonts used by the Figma-authored Image Inspect frame. Inter is bundled
    /// under Resources/Fonts so AppKit and Figma use the same glyph metrics.
    static func inspectFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name: String
        if weight >= .semibold { name = "Inter-SemiBold" }
        else if weight >= .medium { name = "Inter-Medium" }
        else { name = "Inter-Regular" }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

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

    // MARK: - V2 control factories

    /// Primary call-to-action: warm apricot fill, dark ink label, 8pt corner,
    /// 32pt minimum height. Mirrors the HTML spec's `.primary-btn`.
    static func makePrimaryButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let btn = PanelButton(title: title, target: target, action: action)
        btn.normalBackground = accent
        btn.hoverBackground = accentHover
        btn.titleColor = accentInk
        btn.titleFont = .systemFont(ofSize: 13, weight: .semibold)
        btn.setAccessibilityLabel(title)
        return btn
    }

    /// Quiet secondary action: hairline border over a faint control fill.
    /// Mirrors the HTML spec's `.quiet-btn`.
    static func makeQuietButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let btn = PanelButton(title: title, target: target, action: action)
        btn.normalBackground = controlFill
        btn.hoverBackground = controlFillHi
        btn.titleColor = textPrimary
        btn.titleFont = label
        btn.setAccessibilityLabel(title)
        return btn
    }

    /// Destructive action: same chrome as quiet, but the label reads danger.
    static func makeDangerButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let btn = makeQuietButton(title: title, target: target, action: action)
        btn.titleColor = danger
        return btn
    }

    /// A small text segment for the floating mode switcher (专注/并排/滑杆).
    /// Toggle its selected look with `setSegmentActive(_:active:)`.
    static func makeSegmentButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let btn = PanelButton(title: title, target: target, action: action)
        btn.normalBackground = .clear
        btn.hoverBackground = controlFill
        btn.titleColor = textSecondary
        btn.titleFont = caption
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        btn.setAccessibilityLabel(title)
        return btn
    }

    /// Apply/remove the active look of a segment button (accent tint + text).
    static func setSegmentActive(_ button: NSButton, active: Bool) {
        guard let btn = button as? PanelButton else { return }
        btn.normalBackground = inspectToolbar
        btn.titleColor = active ? accent : textSecondary
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = resolvedCG(active ? accent.withAlphaComponent(0.58) : inspectLine)
        btn.setAccessibilitySelected(active)
    }

    /// A 6pt semantic status dot (task polling, live states).
    static func makeStatusDot(color: NSColor) -> NSView {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = resolvedCG(color)
        return dot
    }

    /// A 36×20 toggle switch in the V2 style (warm apricot when on).
    static func makeSwitch(target: AnyObject?, action: Selector?, on: Bool = false) -> GlanceSwitch {
        let sw = GlanceSwitch()
        sw.isOn = on
        sw.target = target
        sw.action = action
        return sw
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
        case .minX:
            sep.frame = NSRect(x: 0, y: 0, width: 1, height: bar.bounds.height)
            sep.autoresizingMask = [.height]
        case .maxX:
            sep.frame = NSRect(x: bar.bounds.width - 1, y: 0, width: 1, height: bar.bounds.height)
            sep.autoresizingMask = [.height, .minXMargin]
        default:
            sep.frame = NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1)
            sep.autoresizingMask = [.width]
        }
        bar.addSubview(sep)
        return sep
    }
}

/// Layer-backed text button used by the V2 control factories. Draws its own
/// rounded background so normal/hover/disabled states stay on the darkroom
/// palette instead of AppKit's system button face.
final class PanelButton: NSButton {
    var normalBackground: NSColor = PanelStyle.controlFill { didSet { refresh() } }
    var hoverBackground: NSColor = PanelStyle.controlFillHi
    var titleColor: NSColor = PanelStyle.textPrimary { didSet { refresh() } }
    var titleFont: NSFont = PanelStyle.label { didSet { refresh() } }

    private var hovering = false
    private var tracking: NSTrackingArea?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        bezelStyle = .recessed
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.cornerSmall
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.hairline.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: PanelStyle.label, .foregroundColor: PanelStyle.textPrimary]
        )
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 24
        size.height = max(size.height, PanelStyle.controlHeight)
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let base = (hovering && isEnabled) ? hoverBackground : normalBackground
        layer?.backgroundColor = PanelStyle.resolvedCG(isEnabled ? base : base.withAlphaComponent(0.5))
        let color = isEnabled ? titleColor : titleColor.withAlphaComponent(0.45)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: titleFont, .foregroundColor: color]
        )
    }
}

/// 36×20 toggle switch in the V2 style: warm apricot track with a dark knob
/// when on, raised-surface track with a secondary-text knob when off.
final class GlanceSwitch: NSControl {
    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            animateKnob()
        }
    }

    private let knob = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 8
        addSubview(knob)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 20) }

    override func layout() {
        super.layout()
        let knobX: CGFloat = isOn ? 18 : 2
        knob.frame = NSRect(x: knobX, y: 2, width: 16, height: 16)
        layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.accent : PanelStyle.surfaceElevated)
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.accentInk : PanelStyle.textSecondary)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func setAccessibilityValue(_ value: Any?) {
        if let on = value as? Bool { isOn = on }
    }

    override func accessibilityValue() -> Any? { isOn }

    private func animateKnob() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            self.layout()
        }
    }
}
