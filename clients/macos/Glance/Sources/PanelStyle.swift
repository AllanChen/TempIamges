import AppKit
import CoreText
import Highlightr
import WebKit

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

        let accent = PanelStyle.themed(NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 125 / 255, alpha: 1), PanelStyle.Washi.text1)
        for (view, radius) in [(beam, CGFloat(0)), (scanLine, CGFloat(1))] {
            view.wantsLayer = true
            view.layer?.backgroundColor = accent.cgColor
            view.layer?.cornerRadius = radius
            focusArtwork.addSubview(view)
        }
        for (view, name) in zip([imageGlyph] + corners,
                                ["FocusSweepImage", "FocusSweepCornerTL", "FocusSweepCornerTR",
                                 "FocusSweepCornerBL", "FocusSweepCornerBR"]) {
            view.image = PanelStyle.washiTinted(NSImage(named: NSImage.Name(name)), PanelStyle.Washi.text3)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            focusArtwork.addSubview(view)
        }
        caption.font = PanelStyle.inspectFont(ofSize: 14)
        caption.textColor = PanelStyle.themed(NSColor(srgbRed: 0.72, green: 0.69, blue: 0.67, alpha: 1), PanelStyle.Washi.text2)
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

    /// Apply Glance's shared scrollbar without changing a scroll view's content or scroll behavior.
    /// Call after setting hasVerticalScroller / hasHorizontalScroller.
    static func styleScrollers(in scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if scrollView.hasVerticalScroller {
            scrollView.verticalScroller = GlanceScroller()
        }
        if scrollView.hasHorizontalScroller {
            scrollView.horizontalScroller = GlanceScroller()
        }
    }

    /// Style scrollbars inside Glance-owned WebKit documents, including nested
    /// code blocks. The 12px lane leaves a centered 3px track and 4px thumb.
    static func styleWebScrollbars(in configuration: WKWebViewConfiguration) {
        let track = isLight ? "rgba(213,209,198,.8)" : "rgba(52,53,58,.8)"
        let thumb = isLight ? "rgba(141,137,127,1)" : "rgba(232,168,124,.86)"
        let thumbActive = isLight ? "#5C5952" : "#E8A87C"
        let script = WKUserScript(source: """
            (() => {
              if (document.getElementById('glance-scrollbar-style')) return;
              const style = document.createElement('style');
              style.id = 'glance-scrollbar-style';
              style.textContent = `
                ::-webkit-scrollbar { width: 12px; height: 12px; }
                ::-webkit-scrollbar-track:vertical {
                  background: linear-gradient(to right, transparent 4.5px, \(track) 4.5px,
                    \(track) 7.5px, transparent 7.5px);
                }
                ::-webkit-scrollbar-track:horizontal {
                  background: linear-gradient(to bottom, transparent 4.5px, \(track) 4.5px,
                    \(track) 7.5px, transparent 7.5px);
                }
                ::-webkit-scrollbar-thumb {
                  background: \(thumb); border: 4px solid transparent;
                  border-radius: 6px; background-clip: padding-box;
                }
                ::-webkit-scrollbar-thumb:hover, ::-webkit-scrollbar-thumb:active {
                  background-color: \(thumbActive);
                }
                ::-webkit-scrollbar-corner { background: transparent; }
              `;
              (document.head || document.documentElement).appendChild(style);
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(script)
    }

    // MARK: - Theme

    /// True when Glance runs the Washi (light) theme. Resolved once at launch
    /// from the Theme preference — `.system` follows macOS — so every token and
    /// every snapshot `cgColor` agrees for the whole session. Changing the theme
    /// asks for a relaunch (see PreferencesWindow).
    static let isLight: Bool = {
        switch Preferences.shared.theme {
        case .light: return true
        case .dark: return false
        case .system: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != "Dark"
        }
    }()

    /// Pick the dark (Sumi, the shipped palette) or light (Washi) value.
    static func themed(_ dark: NSColor, _ light: NSColor) -> NSColor { isLight ? light : dark }

    /// Window appearance for system controls, menus and text fields.
    static var windowAppearance: NSAppearance? { NSAppearance(named: isLight ? .aqua : .darkAqua) }
    /// Vibrant appearance for frosted NSVisualEffectViews.
    static var vibrantAppearance: NSAppearance? { NSAppearance(named: isLight ? .vibrantLight : .vibrantDark) }

    static func hex(_ value: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    /// Washi paper and ink — the `Glance · Shizuka` Figma light palette.
    enum Washi {
        static let ink0 = PanelStyle.hex(0xEFEDE6)
        static let ink1 = PanelStyle.hex(0xFAF9F5)
        static let ink2 = PanelStyle.hex(0xF3F1EB)
        static let ink3 = PanelStyle.hex(0xEAE7DF)
        static let ink4 = PanelStyle.hex(0xDDD9CF)
        static let line = PanelStyle.hex(0xE7E4DC)
        static let lineStrong = PanelStyle.hex(0xD5D1C6)
        static let text1 = PanelStyle.hex(0x1C1B19)
        static let text2 = PanelStyle.hex(0x5C5952)
        static let text3 = PanelStyle.hex(0x8D897F)
        static let text4 = PanelStyle.hex(0xB6B2A8)
        static let shu = PanelStyle.hex(0xB5462E)
        static let moss = PanelStyle.hex(0x5D7046)
        static let ai = PanelStyle.hex(0x476780)
    }

    /// Sumi ink — the `Glance · Shizuka` Figma dark palette.
    enum Sumi {
        static let ink0 = PanelStyle.hex(0x0F0F0E)
        static let ink1 = PanelStyle.hex(0x151514)
        static let ink2 = PanelStyle.hex(0x1B1B1A)
        static let ink3 = PanelStyle.hex(0x242422)
        static let ink4 = PanelStyle.hex(0x2E2E2B)
        static let line = PanelStyle.hex(0x262624)
        static let lineStrong = PanelStyle.hex(0x34342F)
        static let text1 = PanelStyle.hex(0xEAE7E0)
        static let text2 = PanelStyle.hex(0xA19D94)
        static let text3 = PanelStyle.hex(0x6B6862)
        static let text4 = PanelStyle.hex(0x47453F)
        static let shu = PanelStyle.hex(0xC65A40)
        static let moss = PanelStyle.hex(0x8C9C72)
        static let ai = PanelStyle.hex(0x6F8AA0)
    }

    /// Recolour a full-colour asset (drawn for Sumi) as a flat glyph for Washi.
    /// Returns the original image in the dark theme.
    static func washiTinted(_ image: NSImage?, _ color: NSColor) -> NSImage? {
        guard isLight, let image else { return image }
        return NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// The colour UI tints are mixed from: white over Sumi, ink over Washi.
    /// Use for hairlines, hover washes and translucent control fills on chrome;
    /// keep literal white/black for marks drawn over photos and video.
    static let contrast = themed(Sumi.text1, Washi.text1)

    // MARK: - Palette

    /// Deepest plane, behind images — ink/0.
    static let canvas = themed(Sumi.ink0, Washi.ink0)
    /// Primary window plane — ink/1.
    static let surface = themed(Sumi.ink1, Washi.ink1)
    /// Fields and quiet fills — ink/2.
    static let overlay = themed(Sumi.ink2, Washi.ink2)
    /// Bar chrome plane — ink/2.
    static let chrome = themed(Sumi.ink2, Washi.ink2)
    /// Selected rows and active tools — ink/4.
    static let surfaceElevated = themed(Sumi.ink4, Washi.ink4)
    /// Image Inspect Figma palette. Kept separate so other Glance windows can
    /// migrate independently without inheriting the denser inspector chrome.
    static let inspectBackground = themed(Sumi.ink0, Washi.ink0)
    static let inspectChrome = themed(Sumi.ink1, Washi.ink1)
    static let inspectToolbar = themed(Sumi.ink3, Washi.ink3)
    static let inspectCanvas = themed(Sumi.ink0, Washi.ink0)
    static let inspectStatus = themed(Sumi.ink2, Washi.ink2)
    static let inspectLine = themed(Sumi.lineStrong, Washi.lineStrong)
    /// Semantic alias matching the V2 spec: raised surface (`overlay`).
    static var surfaceRaised: NSColor { overlay }

    /// Primary text — text/1.
    static let textPrimary = themed(Sumi.text1, Washi.text1)
    /// Secondary text — text/2.
    static let textSecondary = themed(Sumi.text2, Washi.text2)
    /// Tertiary text (timestamps, counts, hints) — text/3.
    static let textTertiary = themed(Sumi.text3, Washi.text3)
    /// Interaction cue: primary buttons, selection outlines. Paper on Sumi,
    /// ink on Washi; vermilion (`failure`) is reserved for marks.
    static let warmCue = themed(Sumi.text1, Washi.text1)
    /// `Glance / Scrollbar System` track and thumb tokens.
    static let scrollbarTrack = inspectLine.withAlphaComponent(0.8)
    static let scrollbarThumb = themed(Sumi.text3, Washi.text3)
    static let scrollbarThumbActive = themed(Sumi.text2, Washi.text2)
    /// Text drawn on top of `accent` fills (primary buttons).
    static let accentInk = themed(Sumi.ink0, Washi.ink1)
    /// Accent hover fill.
    static let accentHover = themed(PanelStyle.hex(0xFFFFFF), PanelStyle.hex(0x3A3833))
    /// Subtle accent tint for selected/active backgrounds.
    static let accentSubtleFill = warmCue.withAlphaComponent(isLight ? 0.06 : 0.12)
    /// Subtle accent tint for selected/active borders.
    static let accentSubtleBorder = warmCue.withAlphaComponent(isLight ? 0.25 : 0.35)

    /// Hairline that defines a bar edge / separator on the frost.
    static let hairline       = textPrimary.withAlphaComponent(0.10)
    /// Pointer-over tint for list rows and cards (History, Task Center): a
    /// touch of light over the darkroom surface, well below selection.
    static let rowHover       = textPrimary.withAlphaComponent(isLight ? 0.04 : 0.06)
    /// `base` with the hover tint laid over it, for opaque layer backgrounds.
    static func hoverTinted(_ base: NSColor) -> NSColor {
        base.blended(withFraction: isLight ? 0.04 : 0.06, of: textPrimary) ?? base
    }
    /// Translucent fill for a top/bottom bar sitting on the frost.
    static let barFill        = overlay.withAlphaComponent(isLight ? 0.86 : 0.72)
    /// Translucent fill for an inline control (button, field) on the frost.
    static let controlFill    = textPrimary.withAlphaComponent(isLight ? 0.06 : 0.09)
    /// Hover/active state of `controlFill`.
    static let controlFillHi  = textPrimary.withAlphaComponent(isLight ? 0.11 : 0.16)
    /// Translucent card fill for grouped controls / overlays.
    static let glassCard      = overlay.withAlphaComponent(isLight ? 0.90 : 0.76)

    /// Neutral canvas behind images — darkroom black in Sumi, warm paper in Washi.
    static let imageCanvas    = canvas

    static let accent         = warmCue
    /// Colours baked into exported and captured images. Fixed, so a file looks
    /// the same whichever theme produced it.
    static let exportCanvas = NSColor(srgbRed: 9 / 255, green: 9 / 255, blue: 11 / 255, alpha: 1)
    static let exportDivider = NSColor(srgbRed: 243 / 255, green: 238 / 255, blue: 232 / 255, alpha: 0.82)
    /// Compare divider drawn over photos in the viewer.
    static let imageDivider = themed(textPrimary.withAlphaComponent(0.82), NSColor.white.withAlphaComponent(0.9))
    /// Semantic colours shared by task, Widget, and validation states.
    static let success        = themed(Sumi.moss, Washi.moss)
    static let failure        = themed(Sumi.shu, Washi.shu)
    static let info           = themed(Sumi.ai, Washi.ai)
    /// Alias matching the V2 spec vocabulary.
    static var danger: NSColor { failure }
    static let cornerSmall: CGFloat = 8
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 16
    static let spacing: CGFloat = 8

    // MARK: - Shizuka type and space (Figma `00 · Foundations`)

    /// Mincho display face for window and section titles only. Figma uses
    /// Shippori Mincho; macOS ships Hiragino Mincho, the closest available.
    static func titleFont(ofSize size: CGFloat) -> NSFont {
        NSFont(name: "HiraMinProN-W3", size: size) ?? .systemFont(ofSize: size, weight: .regular)
    }
    /// Metadata face: dimensions, sizes, counts, timestamps, shortcuts.
    /// Figma uses Geist Mono; SF Mono is the system equivalent.
    static func monoFont(ofSize size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    /// Spacing scale. Group with space, not boxes (間).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let ma: CGFloat = 56
    }
    /// Corner radii: thumbnails 3, controls 6, windows and popovers 12.
    enum Radius {
        static let thumb: CGFloat = 3
        static let control: CGFloat = 6
        static let window: CGFloat = 12
    }

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
        blur.appearance = vibrantAppearance
        return blur
    }

    /// Resizable rounded-rect mask for a `.behindWindow` NSVisualEffectView. The
    /// window server composites that blur itself and ignores layer corner
    /// masking, so without this mask a rounded borderless panel shows a square
    /// plate and a square shadow. Cap insets keep the corners fixed at any size.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
        blur.appearance = vibrantAppearance
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
    static let codeTheme = isLight ? "github" : "tomorrow-night"

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
        tv.insertionPointColor = contrast
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

/// The shared 3 pt track and 4 pt warm thumb. NSScroller retains native
/// wheel, trackpad, thumb dragging, accessibility, and overlay fade behavior.
final class GlanceScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat { 12 }

    private var hovering = false { didSet { needsDisplay = true } }
    private var dragging = false { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func trackKnob(with event: NSEvent) {
        dragging = true
        super.trackKnob(with: event)
        dragging = false
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        drawPill(in: slotRect, thickness: 3, color: PanelStyle.scrollbarTrack)
    }

    override func drawKnob() {
        drawPill(in: rect(for: .knob), thickness: 4,
                 color: hovering || dragging ? PanelStyle.scrollbarThumbActive : PanelStyle.scrollbarThumb)
    }

    private func drawPill(in rect: NSRect, thickness: CGFloat, color: NSColor) {
        guard !rect.isEmpty else { return }
        let pill: NSRect
        if bounds.width < bounds.height {
            pill = NSRect(x: rect.midX - thickness / 2, y: rect.minY,
                          width: thickness, height: rect.height)
        } else {
            pill = NSRect(x: rect.minX, y: rect.midY - thickness / 2,
                          width: rect.width, height: thickness)
        }
        color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: thickness / 2,
                     yRadius: thickness / 2).fill()
    }
}

/// The same Figma scrollbar for scroll surfaces that manage their own offset
/// (for example, Home's thumbnail row and Widget Market's virtual catalog).
final class GlanceScrollIndicator: NSView {
    enum Axis { case horizontal, vertical }

    var onSeek: ((CGFloat) -> Void)?
    private let axis: Axis
    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    private var contentLength: CGFloat = 0
    private var viewportLength: CGFloat = 0
    private var offset: CGFloat = 0
    private var dragAnchor: CGFloat = 0
    private var hovering = false { didSet { updateThumbColor() } }
    private var dragging = false { didSet { updateThumbColor() } }
    private var hoverArea: NSTrackingArea?

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = PanelStyle.resolvedCG(PanelStyle.scrollbarTrack)
        trackLayer.cornerRadius = 1.5
        thumbLayer.cornerRadius = 2
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(thumbLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        updateThumbColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    func update(contentLength: CGFloat, viewportLength: CGFloat, offset: CGFloat) {
        self.contentLength = contentLength
        self.viewportLength = viewportLength
        self.offset = offset
        isHidden = viewportLength <= 0 || contentLength <= viewportLength + 1
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let length = axis == .horizontal ? bounds.width : bounds.height
        let thumbLength = min(length, max(axis == .horizontal ? 28 : 34,
                                          length * viewportLength / max(contentLength, 1)))
        let overflow = max(0, contentLength - viewportLength)
        let travel = max(0, length - thumbLength)
        let position = overflow > 0 ? min(1, max(0, offset / overflow)) * travel : 0
        if axis == .horizontal {
            trackLayer.frame = NSRect(x: 0, y: (bounds.height - 3) / 2,
                                      width: length, height: 3)
            thumbLayer.frame = NSRect(x: position, y: (bounds.height - 4) / 2,
                                      width: thumbLength, height: 4)
        } else {
            trackLayer.frame = NSRect(x: (bounds.width - 3) / 2, y: 0,
                                      width: 3, height: length)
            thumbLayer.frame = NSRect(x: (bounds.width - 4) / 2, y: position,
                                      width: 4, height: thumbLength)
        }
    }

    override func mouseDown(with event: NSEvent) {
        layoutSubtreeIfNeeded()
        dragging = true
        let point = convert(event.locationInWindow, from: nil)
        let thumb = thumbLayer.frame
        let coordinate = axis == .horizontal ? point.x : point.y
        let thumbStart = axis == .horizontal ? thumb.minX : thumb.minY
        let thumbLength = axis == .horizontal ? thumb.width : thumb.height
        dragAnchor = thumb.contains(point) ? coordinate - thumbStart : thumbLength / 2
        seek(at: coordinate)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        seek(at: axis == .horizontal ? point.x : point.y)
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func accessibilityValue() -> Any? {
        NSNumber(value: Double(min(1, max(0, offset / max(1, contentLength - viewportLength)))))
    }

    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }

    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber else { return }
        onSeek?(min(1, max(0, CGFloat(number.doubleValue))))
    }

    private func seek(at coordinate: CGFloat) {
        let thumbLength = axis == .horizontal ? thumbLayer.frame.width : thumbLayer.frame.height
        let length = axis == .horizontal ? bounds.width : bounds.height
        let travel = length - thumbLength
        guard travel > 0 else { return }
        onSeek?(min(1, max(0, (coordinate - dragAnchor) / travel)))
    }

    private func updateThumbColor() {
        thumbLayer.backgroundColor = PanelStyle.resolvedCG(
            hovering || dragging ? PanelStyle.scrollbarThumbActive : PanelStyle.scrollbarThumb)
    }
}

/// Draws the actual glyph bounds at the center of a fixed Figma text frame.
/// NSTextField's cell padding otherwise shifts short labels and badge counts.
final class PanelCenteredTextView: NSView {
    var string = "" { didSet { setAccessibilityLabel(string); needsDisplay = true } }
    var font = PanelStyle.inspectFont(ofSize: 11) { didSet { needsDisplay = true } }
    var textColor = PanelStyle.contrast { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .center { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !string.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let text = NSAttributedString(string: string,
                                      attributes: [.font: font, .foregroundColor: textColor])
        let line = CTLineCreateWithAttributedString(text)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…",
                                                                         attributes: [.font: font, .foregroundColor: textColor]))
        let displayed = CTLineCreateTruncatedLine(line, Double(bounds.width), .end, token) ?? line
        let ink = CTLineGetImageBounds(displayed, nil)
        guard !ink.isNull, !ink.isEmpty else { return }

        context.saveGState()
        if isFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.clip(to: bounds)
        context.textMatrix = .identity
        let x: CGFloat
        switch alignment {
        case .left, .natural: x = bounds.minX - ink.minX
        case .right: x = bounds.maxX - ink.maxX
        default: x = bounds.midX - ink.midX
        }
        context.textPosition = CGPoint(x: x, y: bounds.midY - ink.midY)
        CTLineDraw(displayed, context)
        context.restoreGState()
    }
}

private final class PanelCenteredButtonCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let textHeight = min(frame.height, ceil(title.size().height))
        let centered = NSRect(x: frame.minX, y: frame.midY - textHeight / 2,
                              width: frame.width, height: textHeight)
        return super.drawTitle(title, withFrame: centered, in: controlView)
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
        cell = PanelCenteredButtonCell(textCell: title)
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
