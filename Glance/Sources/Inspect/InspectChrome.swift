import AppKit

/// Floating capsule with three text segments (Focus / Side by Side / Slider),
/// anchored to the canvas' top-left corner (spec `.canvas-mode`).
final class CanvasModeSwitcher: NSView {
    var onSelect: ((Int) -> Void)?

    private let buttons: [NSButton]
    private var activeIndex = 0
    private static func titles() -> [String] {
        ["Focus".localized, "Compare".localized, "Slider".localized]
    }

    override init(frame frameRect: NSRect) {
        buttons = Self.titles().enumerated().map { index, title in
            PanelStyle.makeSegmentButton(title: title, target: nil, action: nil)
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        for (index, button) in buttons.enumerated() {
            if let button = button as? PanelButton {
                button.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
            }
            button.tag = index
            button.target = self
            button.action = #selector(segmentTapped(_:))
            addSubview(button)
        }
        setActive(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize {
        NSSize(width: 318, height: 38)
    }

    override func layout() {
        super.layout()
        let designWidths: [CGFloat] = [96, 112, 94]
        let scale = bounds.width / 318
        var x: CGFloat = 0
        for (button, designWidth) in zip(buttons, designWidths) {
            let width = designWidth * scale
            if let button = button as? PanelButton {
                button.titleFont = PanelStyle.inspectFont(ofSize: 12 * scale, weight: .medium)
                button.layer?.cornerRadius = 8 * scale
                button.layer?.borderWidth = max(1, scale)
            }
            button.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + 8 * scale
        }
    }

    @objc private func segmentTapped(_ sender: NSButton) {
        onSelect?(sender.tag)
    }

    func setActive(_ index: Int) {
        activeIndex = index
        for (i, button) in buttons.enumerated() {
            PanelStyle.setSegmentActive(button, active: i == index)
        }
    }

    func setFocusEnabled(_ enabled: Bool) { buttons[0].isEnabled = enabled }
    func setCompareEnabled(_ enabled: Bool) {
        buttons[1].isEnabled = enabled
        buttons[2].isEnabled = enabled
    }

    func reloadTitles() {
        for (button, title) in zip(buttons, Self.titles()) {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                             .foregroundColor: PanelStyle.textSecondary]
            )
            button.setAccessibilityLabel(title)
        }
        // Reapply selected styling because attributedTitle resets the visible
        // text color until the next mode transition.
        setActive(activeIndex)
        needsLayout = true
    }
}

/// Non-blocking task toast pinned to the canvas' bottom-left corner
/// (spec `.task-toast`): spinner + task name + reassurance copy.
final class TaskToastView: NSView {
    private let spinner = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(NSColor(srgbRed: 27 / 255, green: 29 / 255, blue: 32 / 255, alpha: 1))
        layer?.cornerRadius = PanelStyle.cornerMedium
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.accent.cgColor

        spinner.wantsLayer = true
        spinner.layer?.backgroundColor = PanelStyle.resolvedCG(
            NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1)
        )
        spinner.layer?.cornerRadius = 15
        addSubview(spinner)

        titleLabel.font = PanelStyle.inspectFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = PanelStyle.inspectFont(ofSize: 11)
        subtitleLabel.textColor = PanelStyle.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let scale = min(bounds.width / 460, bounds.height / 76)
        layer?.cornerRadius = 12 * scale
        layer?.borderWidth = max(1, scale)
        spinner.layer?.cornerRadius = 15 * scale
        titleLabel.font = PanelStyle.inspectFont(ofSize: 14 * scale, weight: .semibold)
        subtitleLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        spinner.frame = NSRect(x: 20 * scale, y: 23 * scale, width: 30 * scale, height: 30 * scale)
        titleLabel.frame = NSRect(x: 66 * scale, y: 41 * scale,
                                  width: bounds.width - 86 * scale, height: 17 * scale)
        subtitleLabel.frame = NSRect(x: 66 * scale, y: 21 * scale,
                                     width: bounds.width - 86 * scale, height: 13 * scale)
    }

    func show(title: String, subtitle: String) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        if isHidden {
            isHidden = false
            alphaValue = 0
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard !isHidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.isHidden = true
        }
    }
}

final class InspectNonHitTestingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Figma V3's transparent drag region keeps native dragging without drawing a
/// second chrome band above the image.
final class FigmaInspectTitlebar: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

final class FigmaTrafficLightButton: NSControl {
    private let dot = CALayer()

    init(color: NSColor, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        dot.backgroundColor = PanelStyle.resolvedCG(color)
        dot.cornerRadius = 6
        dot.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dot.shadowOpacity = 1
        dot.shadowOffset = CGSize(width: 0, height: -1)
        dot.shadowRadius = 1.5
        layer?.addSublayer(dot)
        self.target = target
        self.action = action
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func layout() {
        super.layout()
        dot.frame = CGRect(x: (bounds.width - 12) / 2, y: (bounds.height - 12) / 2,
                           width: 12, height: 12)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        sendAction(action, to: target)
    }
}

final class InspectIdentityBar: NSVisualEffectView {
    private let tintLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.masksToBounds = true
        // Frosted translucency comes from the effect view; the sublayer only
        // biases it darker. Square corners.
        tintLayer.backgroundColor = PanelStyle.canvas.withAlphaComponent(0.62).cgColor
        layer?.addSublayer(tintLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    /// Double-click on the toolbar/identity bar zooms the window in and out,
    /// matching the standard macOS title-bar double-click behavior that the
    /// hidden title bar cannot provide.
    override func mouseDown(with event: NSEvent) {
        let now = event.timestamp
        let isDoubleClick = event.clickCount == 2
            || (now - lastMouseDownTimestamp) < NSEvent.doubleClickInterval
        lastMouseDownTimestamp = isDoubleClick ? -.infinity : now
        if isDoubleClick {
            window?.zoom(nil)
            return
        }
        super.mouseDown(with: event)
    }

    private var lastMouseDownTimestamp: TimeInterval = -.infinity
}

final class InspectToolbarButton: NSButton {
    var isActive = false { didSet { updateAppearance() } }
    var usesFigmaStyle = false { didSet { updateAppearance() } }
    var isBorderlessFigmaTile = false { didSet { updateAppearance() } }

    /// The glyph point size. The toolbar drives this from the tile size so the
    /// icon always fills the same proportion of its 38pt tile (18/38) as the
    /// Figma reference, at any window/image size. Centered via `.imageOnly`.
    private var symbolPointSize: CGFloat = 18
    private var currentSymbolName: String = ""
    private var designIconName: String?

    private var glyphConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .light)
    }

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        toolTip = tooltip
        isBordered = false
        bezelStyle = .recessed
        contentTintColor = PanelStyle.textPrimary
        wantsLayer = true
        layer?.cornerRadius = 5
        currentSymbolName = symbol
        setSymbol(symbol)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Swap the icon while keeping the shared symbol configuration. Use this
    /// instead of assigning `image` directly so dynamically swapped icons
    /// (play/pause, mute) match the rest of the toolbar.
    func setSymbol(_ name: String) {
        currentSymbolName = name
        designIconName = nil
        let raw = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)
        image = raw?.withSymbolConfiguration(glyphConfiguration)
    }

    /// Use the vector exported by the Glance Figma design for the floating toolbar.
    func setDesignIcon(_ name: String) {
        designIconName = name
        updateDesignIconSize()
        updateAppearance()
    }

    private func updateDesignIconSize() {
        guard let designIconName,
              let icon = NSImage(named: NSImage.Name(designIconName))?.copy() as? NSImage else { return }
        icon.isTemplate = true
        icon.size = NSSize(width: symbolPointSize, height: symbolPointSize)
        image = icon
    }

    /// Resize the glyph so it scales with its tile. No-op if unchanged, so it's
    /// cheap to call from every layout pass.
    func setSymbolPointSize(_ size: CGFloat) {
        let clamped = max(8, size)
        guard abs(clamped - symbolPointSize) > 0.5 else { return }
        symbolPointSize = clamped
        if designIconName == nil {
            setSymbol(currentSymbolName)
        } else {
            updateDesignIconSize()
        }
    }

    func updateTooltip(_ tooltip: String) {
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func mouseDown(with event: NSEvent) {
        if usesFigmaStyle { ActionMenuPanel.animateMoreButtonPress(self) }
        super.mouseDown(with: event)
    }

    private func updateAppearance() {
        if usesFigmaStyle {
            let idleFill = NSColor(srgbRed: 29 / 255, green: 30 / 255, blue: 34 / 255, alpha: 0.72)
            let activeFill = NSColor(srgbRed: 52 / 255, green: 37 / 255, blue: 31 / 255, alpha: 0.96)
            layer?.backgroundColor = PanelStyle.resolvedCG(
                isActive ? activeFill : idleFill
            )
            layer?.borderWidth = isBorderlessFigmaTile ? 0 : 1
            layer?.borderColor = PanelStyle.resolvedCG(
                isActive ? PanelStyle.accent.withAlphaComponent(0.78) : NSColor.white.withAlphaComponent(0.12)
            )
            let idleTint = designIconName == nil
                ? PanelStyle.textPrimary
                : NSColor(srgbRed: 243 / 255, green: 243 / 255, blue: 243 / 255, alpha: 1)
            contentTintColor = isEnabled
                ? (isActive ? PanelStyle.accent : idleTint)
                : PanelStyle.textTertiary
            alphaValue = isEnabled ? 1 : 0.45
            return
        }
        // Native-style selected tile: a filled rounded square, using Glance's
        // warm theme accent instead of the system blue selection color.
        layer?.backgroundColor = isActive
            ? PanelStyle.warmCue.withAlphaComponent(0.90).cgColor
            : NSColor.clear.cgColor
        // Dim disabled compare buttons so the user can see they are inactive
        // for a single image, instead of looking tappable but doing nothing.
        let activeTint = isActive ? PanelStyle.canvas : PanelStyle.textPrimary
        contentTintColor = isEnabled ? activeTint : PanelStyle.textTertiary
        alphaValue = isEnabled ? 1 : 0.5
    }
}
