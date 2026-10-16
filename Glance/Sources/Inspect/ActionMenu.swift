import AppKit

// MARK: - Themed action menu

/// One row in an ActionMenuPanel. `submenu` rows cascade to a child panel.
struct ActionMenuEntry {
    var title = ""
    var shortcut: String? = nil
    var creditCost: Int? = nil
    var showsDisclosure = false
    var isSeparator = false
    var enabled = true
    var requiresPro: Bool = false
    var submenu: [ActionMenuEntry]? = nil
    var action: (() -> Void)? = nil

    static func separator() -> ActionMenuEntry { ActionMenuEntry(isSeparator: true) }
}

/// Measure the real localized glyphs, with room for an independent cost badge.
/// Only Widget menus use this sizing; the other action menus retain their layout.
enum WidgetMenuMetrics {
    static let minimumWidth: CGFloat = 176
    static let maximumWidth: CGFloat = 360
    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 32

    static func costLabel(_ cost: Int) -> String {
        cost == 0 ? "Free of charge".localized : String(cost)
    }

    static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: PanelStyle.inspectFont(ofSize: size, weight: weight)]).size().width)
    }

    static func badgeWidth(_ cost: Int) -> CGFloat {
        let label = costLabel(cost)
        let specimenAdvance: CGFloat = label.unicodeScalars.allSatisfy(\.isASCII) ? 7 : 11
        let specimenWidth = ceil(CGFloat(label.count) * specimenAdvance) + 16
        return max(28, specimenWidth, textWidth(label, size: 11, weight: .semibold) + 16)
    }

    static func width(for entries: [ActionMenuEntry], heading: String, availableWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        let headerWidth = 32 + textWidth(heading, size: 11, weight: .medium) + 12
            + textWidth("pts/task".localized, size: 11)
        let rows = entries.filter { !$0.isSeparator }.map { entry -> CGFloat in
            let disclosure: CGFloat = entry.submenu != nil || entry.showsDisclosure ? 18 : 0
            if let cost = entry.creditCost {
                // Outer 6+6, inner 10+10, a 10pt gap, then the badge.
                return 42 + textWidth(entry.title, size: 13, weight: .medium) + badgeWidth(cost) + disclosure
            }
            return 32 + textWidth(entry.title, size: 12) + disclosure
        }
        return min(maximumWidth, max(0, availableWidth), max(minimumWidth, headerWidth, rows.max() ?? 0))
    }
}

/// Themed replacement for the system NSMenu behind the ⋯ button and image
/// right-clicks: frosted dark translucent chrome with warm-cue row
/// highlights (the system menu's blue selection and light-mode material
/// clash with the darkroom theme). Supports cascading Widget/command menus.
final class ActionMenuPanel: NSPanel {
    enum Style { case context, more }

    private static let menuWidth: CGFloat = 216
    private static let rowHeight: CGFloat = 26
    private static let separatorHeight: CGFloat = 9
    private static let padding: CGFloat = 6

    private let entries: [ActionMenuEntry]
    private let style: Style
    var onDismiss: (() -> Void)?
    private var rowViews: [ActionMenuRow] = []
    private var childPanel: ActionMenuPanel?
    private weak var parentPanel: ActionMenuPanel?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var submenuWorkItem: DispatchWorkItem?
    private var isDismissing = false

    init(entries: [ActionMenuEntry], style: Style = .context, widgetMenuHeading: String? = nil) {
        self.entries = entries
        self.style = style
        let compact = entries.contains { $0.creditCost != nil }
        let heading = widgetMenuHeading ?? "Installed".localized
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let width = compact ? WidgetMenuMetrics.width(for: entries, heading: heading,
            availableWidth: max(0, (cursorScreen?.visibleFrame.width ?? WidgetMenuMetrics.maximumWidth) - 8)) : Self.menuWidth
        let separatorHeight: CGFloat = compact ? 14 : Self.separatorHeight
        func rowHeight(_ entry: ActionMenuEntry) -> CGFloat {
            compact ? (entry.creditCost == nil ? 24 : WidgetMenuMetrics.rowHeight) : Self.rowHeight
        }
        var height = compact ? WidgetMenuMetrics.headerHeight + 5 : Self.padding * 2
        for entry in entries {
            height += entry.isSeparator ? separatorHeight : rowHeight(entry)
        }
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = compact || style == .context
        hidesOnDeactivate = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces]
        guard let content = contentView else { return }
        // Keep menu text in a normal compositing layer. Rendering labels on
        // top of NSVisualEffectView vibrancy makes them look soft/gray on
        // Retina displays, especially while the panel is animating.
        content.wantsLayer = true
        content.layer?.backgroundColor = compact ? PanelStyle.resolvedCG(PanelStyle.inspectChrome) : style == .more
            ? NSColor(srgbRed: 28 / 255, green: 29 / 255, blue: 33 / 255, alpha: 1).cgColor
            : PanelStyle.surface.cgColor
        content.layer?.cornerRadius = 10
        content.layer?.borderWidth = compact || style == .context ? 1 : 0
        if compact { content.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor }
        else if style == .context { content.layer?.borderColor = PanelStyle.hairline.cgColor }

        if compact {
            let header = WidgetMenuHeaderView(title: heading)
            header.frame = NSRect(x: 0, y: height - WidgetMenuMetrics.headerHeight, width: width, height: WidgetMenuMetrics.headerHeight)
            content.addSubview(header)
        }
        var y = height - (compact ? WidgetMenuMetrics.headerHeight : Self.padding)
        for entry in entries {
            if entry.isSeparator {
                let sepX: CGFloat = compact ? 12 : style == .more ? 13 : Self.padding + 6
                let sepWidth: CGFloat = compact ? width - 24 : style == .more ? 190 : Self.menuWidth - sepX * 2
                let sepY = compact ? y - 9 : y - Self.separatorHeight + (style == .more ? 5 : 4)
                let sep = NSView(frame: NSRect(x: sepX, y: sepY,
                                               width: sepWidth, height: 1))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = compact ? NSColor.white.withAlphaComponent(0.09).cgColor : style == .more
                    ? NSColor(srgbRed: 69 / 255, green: 71 / 255, blue: 77 / 255, alpha: 1).cgColor
                    : PanelStyle.hairline.cgColor
                content.addSubview(sep)
                y -= separatorHeight
                continue
            }
            let row = ActionMenuRow(entry: entry, usesMoreStyle: style == .more,
                                    usesWidgetMenuStyle: compact,
                                    frame: NSRect(x: Self.padding, y: y - rowHeight(entry),
                                                  width: width - Self.padding * 2,
                                                  height: rowHeight(entry)))
            row.onHover = { [weak self] hovered in self?.rowHovered(hovered) }
            row.onActivate = { [weak self] activated in self?.rowActivated(activated) }
            content.addSubview(row)
            rowViews.append(row)
            y -= rowHeight(entry)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func animateMoreButtonPress(_ button: NSView) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = button.layer else { return }
        // Figma's spring is exported as sampled linear() easing. Preserve its
        // overshoot for both the press (1 → .84) and release (.84 → 1).
        let spring: [Double] = [
            0, 0.03, 0.1077, 0.2165, 0.342, 0.4728, 0.6001, 0.7175, 0.8208,
            0.9077, 0.9776, 1.0307, 1.0684, 1.0925, 1.1051, 1.1084,
            1.1047, 1.096, 1.084, 1.0703, 1.0561, 1.0424, 1.0297, 1.0187,
            1.0094, 1.0019, 0.9963, 0.9923, 0.9898, 0.9885, 0.9882,
            0.9887, 0.9897, 0.991, 0.9925, 0.994, 0.9955, 0.9969,
            0.9981, 0.9991, 0.9998, 1.0004, 1.0009, 1.0011, 1.0012,
            1.0013, 1.0012, 1.0011, 1.001, 1.0008, 1.0006
        ]
        let segments: [(from: Double, to: Double, start: Double, end: Double)] = [
            (1, 0.84, 0, 0.16), (0.84, 1, 0.16, 0.38)
        ]
        var values: [NSNumber] = []
        var times: [NSNumber] = []
        for (segmentIndex, segment) in segments.enumerated() {
            for (index, progress) in spring.enumerated() where segmentIndex == 0 || index > 0 {
                let fraction = Double(index) / Double(spring.count - 1)
                values.append(NSNumber(value: segment.from + (segment.to - segment.from) * progress))
                times.append(NSNumber(value: (segment.start + (segment.end - segment.start) * fraction) / 0.38))
            }
        }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = values
        scale.keyTimes = times
        scale.calculationMode = .linear
        scale.duration = 0.38
        layer.add(scale, forKey: "glance.moreButtonPress")
    }

    private func animateEntrance() {
        guard style == .more,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = contentView?.layer else { return }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0, 1]
        opacity.keyTimes = [0, NSNumber(value: 0.16 / 0.42), 1]
        opacity.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                   CAMediaTimingFunction(name: .easeOut)]
        opacity.duration = 0.42
        let position = CABasicAnimation(keyPath: "transform.translation.y")
        position.fromValue = 8
        position.toValue = 0
        position.timingFunction = CAMediaTimingFunction(name: .easeOut)
        position.duration = 0.42
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.96
        scale.toValue = 1
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scale.duration = 0.42
        let group = CAAnimationGroup()
        group.animations = [opacity, position, scale]
        group.duration = 0.42
        layer.add(group, forKey: "glance.moreMenuEntrance")
    }

    /// Present top-left-anchored at a screen point, clamped on screen.
    func present(at screenPoint: NSPoint, parent: ActionMenuPanel? = nil) {
        parentPanel = parent
        let size = frame.size
        var origin = NSPoint(x: screenPoint.x, y: screenPoint.y - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX { origin.x = visible.maxX - size.width - 4 }
            origin.x = max(visible.minX + 4, origin.x)
            origin.y = min(max(visible.minY + 4, origin.y), visible.maxY - size.height - 4)
        }
        setFrameOrigin(origin)
        if parent == nil { installMonitors() }
        orderFront(nil)
    }

    /// Present below a toolbar control. `screenPoint` is the control's bottom
    /// edge in AppKit screen coordinates; unlike `present(at:)`, this does not
    /// interpret the point as the menu's top edge.
    func presentBelowToolbar(at screenPoint: NSPoint) {
        parentPanel = nil
        let size = frame.size
        let gap: CGFloat = 8
        // The menu drops down from the toolbar: its right edge aligns with the
        // toolbar's right edge and there is an 8pt gap between them.
        var origin = NSPoint(x: screenPoint.x - size.width,
                             y: screenPoint.y - gap - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX {
                // Keep the menu right-aligned with the toolbar when possible;
                // only pin to the screen edge when the toolbar is too close.
                origin.x = min(screenPoint.x - size.width, visible.maxX - size.width - 4)
            }
            origin.x = max(visible.minX + 4, origin.x)
            origin.y = min(max(visible.minY + 4, origin.y), visible.maxY - size.height - 4)
        }
        setFrameOrigin(origin)
        installMonitors()
        animateEntrance()
        orderFront(nil)
    }

    func dismissChain() {
        guard !isDismissing else { return }
        isDismissing = true
        let wasVisible = isVisible
        submenuWorkItem?.cancel()
        submenuWorkItem = nil
        childPanel?.dismissChain()
        childPanel = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        mouseMonitor = nil
        keyMonitor = nil
        resignObserver = nil
        if wasVisible, style == .more,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let layer = contentView?.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = 0.27
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = 0
            lift.toValue = 4
            lift.duration = 0.27
            lift.timingFunction = CAMediaTimingFunction(name: .easeIn)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            CATransaction.commit()
            layer.add(fade, forKey: "glance.moreMenuExitOpacity")
            layer.add(lift, forKey: "glance.moreMenuExitLift")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { [self] in
                orderOut(nil)
                onDismiss?()
            }
        } else {
            orderOut(nil)
            if wasVisible { onDismiss?() }
        }
    }

    private func dismissFromRoot() {
        var root = self
        while let parent = root.parentPanel { root = parent }
        root.dismissChain()
    }

    private func chainContains(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        var current: ActionMenuPanel? = self
        while let panel = current {
            if panel == window { return true }
            current = panel.childPanel
        }
        return false
    }

    /// Resolve the visible parent/child menu panel under a screen point.
    private func panel(atScreenPoint point: NSPoint) -> ActionMenuPanel? {
        if let child = childPanel, let hit = child.panel(atScreenPoint: point) { return hit }
        return frame.contains(point) ? self : nil
    }

    /// Dispatch a click directly from the root event monitor. Nonactivating
    /// panels do not reliably route the first click through the responder
    /// chain, so waiting for row mouseDown/mouseUp loses the action.
    private func activateRow(atScreenPoint point: NSPoint) {
        let windowPoint = convertFromScreen(NSRect(origin: point, size: .zero)).origin
        let contentPoint = contentView?.convert(windowPoint, from: nil) ?? windowPoint
        guard let row = rowViews.first(where: { $0.frame.contains(contentPoint) }) else { return }
        rowActivated(row)
    }

    private func installMonitors() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            if let panel = self.panel(atScreenPoint: point) {
                if event.type == .leftMouseDown { panel.activateRow(atScreenPoint: point) }
                return nil
            }
            self.dismissChain()
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc closes the menu before the window sees it
                self?.dismissChain()
                return nil
            }
            return event
        }
        // hidesOnDeactivate hides the panel visually; tear the chain down so
        // no hidden menu keeps swallowing clicks/Esc.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissChain()
        }
    }

    private func rowHovered(_ row: ActionMenuRow) {
        for other in rowViews where other !== row { other.setHighlighted(false) }
        row.setHighlighted(row.entry.enabled)
        submenuWorkItem?.cancel()
        if let submenu = row.entry.submenu, row.entry.enabled {
            // Slight delay matches system submenu hover behavior.
            let item = DispatchWorkItem { [weak self, weak row] in
                guard let self, let row, row.isHighlightedState else { return }
                self.openSubmenu(submenu, from: row)
            }
            submenuWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        } else {
            childPanel?.dismissChain()
            childPanel = nil
        }
    }

    private func rowActivated(_ row: ActionMenuRow) {
        guard row.entry.enabled else { return }
        if let submenu = row.entry.submenu {
            openSubmenu(submenu, from: row)
            return
        }
        guard let action = row.entry.action else { return }
        dismissFromRoot()
        action()
    }

    private func openSubmenu(_ entries: [ActionMenuEntry], from row: ActionMenuRow) {
        childPanel?.dismissChain()
        // Inherit the parent's look: the ⋯ menu is .more, the right-click menu .context.
        let child = ActionMenuPanel(entries: entries, style: style,
            widgetMenuHeading: row.entry.creditCost != nil ? row.entry.title : nil)
        childPanel = child
        let rowTopRight = row.convert(NSPoint(x: row.bounds.width, y: row.bounds.height), to: nil)
        let screenPoint = convertToScreen(NSRect(origin: rowTopRight, size: .zero)).origin
        // rowTopRight stops at the content padding (6pt before the panel
        // edge), so add padding + gap to guarantee no panel overlap.
        var point = NSPoint(x: screenPoint.x + Self.padding + 2,
                            y: screenPoint.y + Self.padding)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame,
           point.x + child.frame.width > visible.maxX {
            // No room on the right — cascade to the left of the parent.
            point.x = frame.minX - child.frame.width - 2
        }
        child.present(at: point, parent: self)
    }
}

/// A single shared unit label keeps per-row prices concise.
private final class WidgetMenuHeaderView: NSView {
    private let title: String
    override var isFlipped: Bool { true }
    init(title: String) { self.title = title; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let unit = "pts/task".localized
        let unitWidth = WidgetMenuMetrics.textWidth(unit, size: 11)
        HistoryStyle.draw(title, in: NSRect(x: 16, y: 10, width: max(0, bounds.width - 44 - unitWidth), height: 13),
                          size: 11, weight: .medium, color: PanelStyle.textSecondary)
        HistoryStyle.draw(unit, in: NSRect(x: bounds.width - 16 - unitWidth, y: 10, width: unitWidth, height: 13),
                          size: 11, color: PanelStyle.textSecondary, align: .right)
    }
}

/// One menu row: title (+ optional shortcut hint or submenu chevron),
/// warm-cue highlight with dark text for contrast.
final class ActionMenuRow: NSView {
    let entry: ActionMenuEntry
    private let usesMoreStyle: Bool
    private let usesWidgetMenuStyle: Bool
    var onHover: ((ActionMenuRow) -> Void)?
    var onActivate: ((ActionMenuRow) -> Void)?
    private(set) var isHighlightedState = false
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")
    private let lockIcon = NSImageView()
    private let creditBadge = NSView()
    private let creditLabel = PanelCenteredTextView()

    init(entry: ActionMenuEntry, usesMoreStyle: Bool, usesWidgetMenuStyle: Bool = false, frame: NSRect) {
        self.entry = entry
        self.usesMoreStyle = usesMoreStyle && !usesWidgetMenuStyle
        self.usesWidgetMenuStyle = usesWidgetMenuStyle
        super.init(frame: frame)
        wantsLayer = true
        if usesWidgetMenuStyle {
            layer?.cornerRadius = 5
            toolTip = entry.title
            setAccessibilityElement(true)
            setAccessibilityRole(.menuItem)
            setAccessibilityLabel(entry.title)
            setAccessibilityEnabled(entry.enabled)
            if let cost = entry.creditCost {
                creditBadge.wantsLayer = true
                creditBadge.layer?.cornerRadius = 5
                creditLabel.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
                creditLabel.string = WidgetMenuMetrics.costLabel(cost)
                creditBadge.addSubview(creditLabel)
                addSubview(creditBadge)
                setAccessibilityValue(cost == 0 ? "Free of charge".localized
                    : String(format: "%d points per task".localized, cost))
            }
            updateColors()
            return
        }
        layer?.cornerRadius = usesMoreStyle ? 6 : 5
        titleLabel.stringValue = entry.title
        titleLabel.font = usesMoreStyle ? PanelStyle.inspectFont(ofSize: 13)
                                        : NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        if let shortcut = entry.shortcut {
            shortcutLabel.stringValue = shortcut
            shortcutLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            shortcutLabel.alignment = .right
            addSubview(shortcutLabel)
        }
        if entry.submenu != nil {
            chevronLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            addSubview(chevronLabel)
        }
        if entry.requiresPro {
            lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Requires Pro".localized)
            lockIcon.contentTintColor = PanelStyle.textTertiary
            addSubview(lockIcon)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { usesWidgetMenuStyle }

    // Swallow all hits at the row level so the labels never consume events.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func layout() {
        super.layout()
        if usesWidgetMenuStyle {
            if let cost = entry.creditCost {
                let disclosure: CGFloat = entry.submenu == nil ? 0 : 18
                let width = WidgetMenuMetrics.badgeWidth(cost)
                creditBadge.frame = NSRect(x: bounds.width - 10 - disclosure - width, y: 4, width: width, height: 20)
                creditLabel.frame = creditBadge.bounds
            }
            return
        }
        // Center the labels vertically by their real line height — a
        // full-height text field draws its text on the baseline, not centered.
        let titleHeight = ceil(titleLabel.cell?.cellSize.height ?? bounds.height)
        let centeredY = (bounds.height - titleHeight) / 2
        titleLabel.frame = NSRect(x: 10, y: centeredY, width: bounds.width - 62, height: titleHeight)
        lockIcon.frame = NSRect(x: bounds.width - 70, y: (bounds.height - 12)/2, width: 12, height: 12)
        shortcutLabel.frame = NSRect(x: bounds.width - 52, y: centeredY, width: 40, height: titleHeight)
        chevronLabel.frame = NSRect(x: bounds.width - 20, y: centeredY, width: 12, height: titleHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard usesWidgetMenuStyle else { super.draw(dirtyRect); return }
        let hasDisclosure = entry.submenu != nil || entry.showsDisclosure
        let end = entry.creditCost != nil ? creditBadge.frame.minX - 10
            : bounds.width - (hasDisclosure ? 38 : 10)
        let color = !entry.enabled ? PanelStyle.textTertiary : isHighlightedState ? PanelStyle.accentInk
            : entry.creditCost == nil ? PanelStyle.textSecondary : PanelStyle.textPrimary
        HistoryStyle.draw(entry.title, in: NSRect(x: 10, y: entry.creditCost == nil ? 4 : 6,
            width: max(0, end - 10), height: entry.creditCost == nil ? 15 : 16),
            size: entry.creditCost == nil ? 12 : 13, weight: entry.creditCost == nil ? .regular : .medium,
            color: color)
        if hasDisclosure {
            HistoryStyle.drawIcon("WidgetMenuChevron", color: isHighlightedState ? PanelStyle.accentInk : PanelStyle.textTertiary,
                in: NSRect(x: bounds.width - (entry.creditCost == nil ? 24 : 22), y: (bounds.height - 12) / 2, width: 12, height: 12))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard entry.enabled else { return false }
        onActivate?(self)
        return true
    }

    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlightedState else { return }
        isHighlightedState = highlighted
        let color = usesMoreStyle
            ? NSColor(srgbRed: 61 / 255, green: 48 / 255, blue: 43 / 255,
                      alpha: highlighted ? 0.8 : 0).cgColor
            : (highlighted ? PanelStyle.warmCue.cgColor : NSColor.clear.cgColor)
        if usesMoreStyle, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let layer = layer {
            let transition = CABasicAnimation(keyPath: "backgroundColor")
            transition.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            transition.toValue = color
            transition.duration = highlighted ? 0.26 : 0.23
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(transition, forKey: "glance.moreRowHover")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color
        CATransaction.commit()
        updateColors()
    }

    private func updateColors() {
        if usesWidgetMenuStyle {
            alphaValue = entry.enabled ? 1 : 0.55
            if let cost = entry.creditCost {
                creditBadge.layer?.backgroundColor = PanelStyle.resolvedCG(isHighlightedState
                    ? PanelStyle.accentInk.withAlphaComponent(0.09)
                    : cost == 0 ? PanelStyle.success.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.06))
                creditLabel.textColor = isHighlightedState ? PanelStyle.accentInk : !entry.enabled ? PanelStyle.textTertiary
                    : cost == 0 ? PanelStyle.success : PanelStyle.textSecondary
            }
            needsDisplay = true
            return
        }
        let color: NSColor
        if !entry.enabled { color = PanelStyle.textTertiary }
        else if usesMoreStyle { color = NSColor(srgbRed: 237 / 255, green: 232 / 255,
                                               blue: 227 / 255, alpha: 1) }
        else if isHighlightedState { color = PanelStyle.canvas }
        else { color = PanelStyle.textPrimary }
        titleLabel.textColor = color
        shortcutLabel.textColor = isHighlightedState && entry.enabled
            ? PanelStyle.canvas.withAlphaComponent(0.72)
            : PanelStyle.textTertiary
        chevronLabel.textColor = color
        alphaValue = 1
    }

    override func mouseEntered(with event: NSEvent) { onHover?(self) }

    override func mouseDown(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?(self)
    }
}
