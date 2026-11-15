import AppKit

// The peeker at work (Figma "Task Running Motion", node 215:6310): eyes glance
// left, centre, right and blink; the hands take turns lifting; three sparkles
// twinkle; the ellipsis counts 1 → 3; a highlight sweeps the track and fades
// before it wraps. Six 350 ms frames, ease in-out, one 2.1 s loop. Frame 7
// ("Done") holds 1.6 s before the result takes over. Reduce Motion shows
// frame 1 still, with only the ellipsis counting.

private enum PeekerMotion {
    static let duration: CFTimeInterval = 2.1
    static let doneHold: TimeInterval = 1.6
    static let doneTransition: CFTimeInterval = 0.4
    // One value per frame (board frames 1–6); the loop closes on frame 1.
    // Vertical values are in peeker units, positive = up (bottom-origin layers).
    static let eye: [CGFloat] = [-0.9, 0, 0.9, 0.9, 0, -0.9]
    static let blink: [CGFloat] = [1, 1, 1, 0.27, 1, 1]
    static let handL: [CGFloat] = [0, 0.7, 0, 0.7, 0, 0.7]
    static let handR: [CGFloat] = [0, 0, 0.7, 0, 0.7, 0]
    static let lift: [CGFloat] = [0, 0.3, 0, 0.3, 0, 0.3]
    static let sparks: [[(opacity: Float, scale: CGFloat)]] = [
        [(1, 0.6), (0.4, 0.5), (0.25, 0.4), (0.8, 0.8), (1, 1), (0.5, 0.6)],
        [(0.35, 0.4), (1, 1), (0.5, 0.6), (0.3, 0.4), (0.7, 0.7), (0.3, 0.4)],
        [(0.7, 0.5), (0.3, 0.4), (1, 1), (0.5, 0.5), (0.25, 0.4), (1, 1)]
    ]
    static let dots: [[CGFloat]] = [[1, 0.25, 0.25], [1, 1, 0.25], [1, 1, 1], [0.25, 1, 1], [0.25, 0.25, 1], [0.25, 0.25, 0.25]]
    // Shimmer: left edge on the 252 pt track per frame, and its opacity.
    static let shimmerX: [CGFloat] = [-90, 0, 90, 165, 240, 320]
    static let shimmerOpacity: [CGFloat] = [0, 1, 1, 1, 1, 0]
    // Frame 7: happy squint, both hands up, a small hop, every sparkle lit.
    enum Done {
        static let squint = CGSize(width: 2.4 / 2.2, height: 1.1 / 2.2)
        static let hands: CGFloat = 1.6
        static let lift: CGFloat = 0.6
        static let spark: (opacity: Float, scale: CGFloat) = (1, 1.15)
    }
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func animation(_ keyPath: String, _ values: [CGFloat], scale: CGFloat = 1) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (values + [values[0]]).map { $0 * scale }
        animation.keyTimes = (0...values.count).map { NSNumber(value: Double($0) / Double(values.count)) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count)
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Runs `body` as one eased 0.4 s change (the board's Smart Animate to "Done").
    static func transition(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(doneTransition)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }
}

/// The character, drawn from separate layers so each part can move.
final class PeekerView: NSView {
    /// Show the three sparkles around the character (chip size and up).
    var showsSparks = false { didSet { needsLayout = true } }
    /// Frame 7 of the board: the task finished. Set with `setDone`.
    private(set) var isDone = false
    private let head = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    private let hands = [CAShapeLayer(), CAShapeLayer()]
    private var sparkLayers: [CAShapeLayer] = []
    private let body = CALayer()
    private var animationState: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        body.masksToBounds = false
        layer?.addSublayer(body)
        for shape in [head, edge] + eyes + hands { body.addSublayer(shape) }
        head.fillColor = PanelStyle.textPrimary.cgColor
        edge.fillColor = PanelStyle.textPrimary.cgColor
        eyes.forEach { $0.fillColor = PanelStyle.themed(HistoryStyle.hex(0x161719), PanelStyle.Washi.ink1).cgColor }
        hands.forEach { $0.fillColor = PeekerPalette.hands.cgColor }
        for _ in 0..<3 {
            let spark = CAShapeLayer()
            spark.fillColor = PanelStyle.warmCue.cgColor
            spark.opacity = 0
            layer?.addSublayer(spark)
            sparkLayers.append(spark)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Switch between the working loop and the "Done" pose.
    func setDone(_ done: Bool, animated: Bool = true) {
        guard done != isDone else { return }
        isDone = done
        restartAnimations(animated: animated)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restartAnimations(animated: false)
    }
    override func viewDidHide() { super.viewDidHide(); restartAnimations(animated: false) }
    override func viewDidUnhide() { super.viewDidUnhide(); restartAnimations(animated: false) }

    private var unit: CGFloat { min(bounds.width, bounds.height) / 18 }

    override func layout() {
        super.layout()
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }
        let u = size / 18
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.frame = CGRect(x: 0, y: 0, width: size, height: size)
        // Figma coordinates are top-origin; the layer is bottom-origin.
        func y(_ top: CGFloat, _ height: CGFloat) -> CGFloat { size - (top + height) * u }
        func disc(_ cx: CGFloat, _ cy: CGFloat, _ d: CGFloat) -> CGRect { CGRect(x: (cx - d / 2) * u, y: y(cy - d / 2, d), width: d * u, height: d * u) }
        func circle(_ shape: CAShapeLayer, _ rect: CGRect) {
            shape.frame = rect
            shape.path = CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size), transform: nil)
        }
        circle(head, disc(9, 8, 11))
        let edgeRect = CGRect(x: 1.5 * u, y: y(12.25, 2.25), width: 15 * u, height: 2.25 * u)
        edge.frame = edgeRect
        edge.path = CGPath(roundedRect: CGRect(origin: .zero, size: edgeRect.size), cornerWidth: 1.125 * u, cornerHeight: 1.125 * u, transform: nil)
        circle(eyes[0], disc(6.8, 7.6, 2.2)); circle(eyes[1], disc(11.2, 7.6, 2.2))
        circle(hands[0], disc(5.2, 12.3, 3.2)); circle(hands[1], disc(12.8, 12.3, 3.2))
        // Sparkles sit around the character, as in the board.
        let anchors: [(CGFloat, CGFloat)] = [(1.045, -0.136), (-0.227, -0.18), (1.09, 0.77)]
        let sparkSize = 14 * size / 44
        for (index, spark) in sparkLayers.enumerated() {
            spark.isHidden = !showsSparks
            let cx = anchors[index].0 * size, cy = size - anchors[index].1 * size
            spark.frame = CGRect(x: cx - sparkSize / 2, y: cy - sparkSize / 2, width: sparkSize, height: sparkSize)
            spark.path = Self.starPath(in: CGRect(origin: .zero, size: spark.frame.size))
        }
        CATransaction.commit()
        restartAnimations(animated: false)
    }

    private static func starPath(in rect: CGRect) -> CGPath {
        let s = rect.width / 16
        let points: [(CGFloat, CGFloat)] = [(8, 0), (9.6, 6.4), (16, 8), (9.6, 9.6), (8, 16), (6.4, 9.6), (0, 8), (6.4, 6.4)]
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: point.0 * s, y: rect.height - point.1 * s)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    private func restartAnimations(animated: Bool) {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        let state = "\(unit)-\(isDone)-\(showsSparks)-\(PeekerMotion.reduced)"
        if visible, animationState == state { return }
        animationState = visible ? state : nil
        let all = [head, edge] + eyes + hands + sparkLayers
        all.forEach { $0.removeAllAnimations() }
        body.removeAllAnimations()
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        let u = unit
        if isDone {
            PeekerMotion.transition(animated: animated) {
                eyes.forEach { $0.transform = CATransform3DMakeScale(PeekerMotion.Done.squint.width, PeekerMotion.Done.squint.height, 1) }
                hands.forEach {
                    $0.transform = CATransform3DMakeTranslation(0, PeekerMotion.Done.hands * u, 0)
                    $0.fillColor = PanelStyle.success.cgColor
                }
                body.transform = CATransform3DMakeTranslation(0, PeekerMotion.Done.lift * u, 0)
                for spark in sparkLayers {
                    spark.opacity = showsSparks ? PeekerMotion.Done.spark.opacity : 0
                    spark.transform = CATransform3DMakeScale(PeekerMotion.Done.spark.scale, PeekerMotion.Done.spark.scale, 1)
                }
            }
            return
        }
        PeekerMotion.transition(animated: false) {
            hands.forEach { $0.fillColor = PeekerPalette.hands.cgColor; $0.transform = CATransform3DIdentity }
            body.transform = CATransform3DIdentity
            if PeekerMotion.reduced {
                // Frame 1, still: eyes left, sparkles at their frame-1 glow.
                eyes.forEach { $0.transform = CATransform3DMakeTranslation(PeekerMotion.eye[0] * u, 0, 0) }
                for (index, spark) in sparkLayers.enumerated() {
                    let frame = PeekerMotion.sparks[index][0]
                    spark.opacity = showsSparks ? frame.opacity : 0
                    spark.transform = CATransform3DMakeScale(frame.scale, frame.scale, 1)
                }
            } else {
                eyes.forEach { $0.transform = CATransform3DIdentity }
                sparkLayers.forEach { $0.transform = CATransform3DIdentity; $0.opacity = 0 }
            }
        }
        guard !PeekerMotion.reduced else { return }
        eyes.forEach {
            $0.add(PeekerMotion.animation("transform.translation.x", PeekerMotion.eye, scale: u), forKey: "glance")
            $0.add(PeekerMotion.animation("transform.scale.y", PeekerMotion.blink), forKey: "blink")
        }
        hands[0].add(PeekerMotion.animation("transform.translation.y", PeekerMotion.handL, scale: u), forKey: "lift")
        hands[1].add(PeekerMotion.animation("transform.translation.y", PeekerMotion.handR, scale: u), forKey: "lift")
        body.add(PeekerMotion.animation("transform.translation.y", PeekerMotion.lift, scale: u), forKey: "bob")
        guard showsSparks else { return }
        for (index, spark) in sparkLayers.enumerated() {
            let frames = PeekerMotion.sparks[index]
            spark.add(PeekerMotion.animation("opacity", frames.map { CGFloat($0.opacity) }), forKey: "twinkle")
            spark.add(PeekerMotion.animation("transform.scale", frames.map { $0.scale }), forKey: "pulse")
        }
    }
}

/// "Generating…" chip (board 360 × 76): the peeker, a counting ellipsis, the
/// widget name, and a highlight sweeping along a thin track. `showDone` turns
/// it into frame 7: "Done ✓", the track filled green, the peeker celebrating.
final class TaskRunningChip: NSView {
    enum Style { case full, compact }
    var style: Style = .full {
        didSet {
            guard style != oldValue else { return }
            needsLayout = true
            needsDisplay = true
        }
    }
    /// Placement uses the plain peeker; the Task Center motion study has sparks.
    var showsSparks: Bool {
        get { peeker.showsSparks }
        set { peeker.showsSparks = newValue }
    }
    private(set) var detail = ""
    private(set) var isDone = false
    private let peeker = PeekerView()
    private let track = CALayer()
    private let shimmer = CAGradientLayer()
    private let barFill = CALayer()
    private var dots: [CALayer] = []
    private var animationState: String?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        // Board: drop shadow 0 / 12, blur 32, black 45 %. Flipped view: negative
        // height casts downwards (see HistoryCardView).
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -12)
        peeker.showsSparks = true
        addSubview(peeker)
        track.backgroundColor = PanelStyle.contrast.withAlphaComponent(0.10).cgColor
        track.masksToBounds = true
        let accent = PanelStyle.warmCue
        shimmer.colors = [accent.withAlphaComponent(0).cgColor, accent.cgColor, accent.withAlphaComponent(0).cgColor]
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.opacity = 0
        track.addSublayer(shimmer)
        barFill.backgroundColor = PanelStyle.success.cgColor
        barFill.opacity = 0
        track.addSublayer(barFill)
        layer?.addSublayer(track)
        for _ in 0..<3 {
            let dot = CALayer()
            dot.backgroundColor = PanelStyle.textPrimary.cgColor
            layer?.addSublayer(dot)
            dots.append(dot)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Frames 1–6: "Generating…" for `detail` (the widget name).
    func showRunning(detail: String) {
        guard self.detail != detail || isDone else { return }
        self.detail = detail
        isDone = false
        peeker.setDone(false, animated: false)
        needsLayout = true
        needsDisplay = true
        restartAnimations()
    }

    /// Frame 7: "Done ✓" with `detail` ("Remove Background · 12.4 s").
    func showDone(detail: String) {
        self.detail = detail
        guard !isDone else { needsDisplay = true; return }
        isDone = true
        peeker.setDone(true)
        needsDisplay = true
        restartAnimations()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); restartAnimations() }
    override func viewDidHide() { super.viewDidHide(); restartAnimations() }
    override func viewDidUnhide() { super.viewDidUnhide(); restartAnimations() }

    private var compact: Bool { style == .compact }
    private var scale: CGFloat { bounds.width / (compact ? 240 : 360) }
    private var textX: CGFloat { compact ? 54 : 84 }
    private var textY: CGFloat { compact ? 8 : 14 }
    private var titleSize: CGFloat { compact ? 13 : 14 }
    private var title: String { (isDone ? "Done" : "Generating").localized }

    override func layout() {
        super.layout()
        let s = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowRadius = 16 * s
        layer?.shadowOffset = CGSize(width: 0, height: -12 * s)
        peeker.frame = compact
            ? CGRect(x: 10 * s, y: 8 * s, width: 32 * s, height: 32 * s)
            : CGRect(x: 16 * s, y: 16 * s, width: 44 * s, height: 44 * s)
        track.frame = CGRect(x: textX * s, y: (compact ? 32 : 60) * s,
                             width: (compact ? 164 : 252) * s, height: (compact ? 3 : 4) * s)
        track.cornerRadius = track.bounds.height / 2
        let shimmerWidth = (compact ? 59 : 91) * s
        shimmer.frame = CGRect(x: -shimmerWidth, y: 0, width: shimmerWidth, height: track.bounds.height)
        shimmer.cornerRadius = track.cornerRadius
        barFill.frame = track.bounds
        barFill.cornerRadius = track.cornerRadius
        // Board: "Generating" ends at 160, dots at 166 / 174 / 182 — a 6 pt gap.
        let titleWidth = HistoryStyle.width(title, size: titleSize * s, weight: .semibold)
        let dotsX = title == "Generating" ? (compact ? 124.0 : 166.0) * s : textX * s + titleWidth + 6 * s
        for (index, dot) in dots.enumerated() {
            let d: CGFloat = compact ? 3.5 : 4
            dot.frame = CGRect(x: dotsX + CGFloat(index) * (compact ? 7 : 8) * s,
                               y: (compact ? 19 : 26) * s, width: d * s, height: d * s)
            dot.cornerRadius = d * s / 2
        }
        CATransaction.commit()
        restartAnimations()
    }

    private func restartAnimations() {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        let state = "\(scale)-\(track.bounds.width)-\(compact)-\(isDone)-\(PeekerMotion.reduced)"
        if visible, animationState == state { return }
        animationState = visible ? state : nil
        shimmer.removeAllAnimations()
        dots.forEach { $0.removeAllAnimations() }
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        if isDone {
            PeekerMotion.transition(animated: true) {
                shimmer.opacity = 0
                barFill.opacity = 1
                dots.forEach { $0.opacity = 0 }
            }
            return
        }
        PeekerMotion.transition(animated: false) {
            barFill.opacity = 0
            shimmer.opacity = 0
            shimmer.transform = CATransform3DIdentity
            dots.forEach { $0.opacity = 1 }
        }
        // The ellipsis counts 1 → 3 and starts over; it keeps counting under
        // Reduce Motion (the board's "frame 1 static with the ellipsis only").
        for (index, dot) in dots.enumerated() {
            dot.add(PeekerMotion.animation("opacity", PeekerMotion.dots.map { $0[index] }), forKey: "count")
        }
        guard !PeekerMotion.reduced else { return }
        let s = track.bounds.width / 252
        // Highlight sweeps the track and fades out before it wraps.
        let offsets = PeekerMotion.shimmerX.map { $0 - PeekerMotion.shimmerX[0] }
        shimmer.add(PeekerMotion.animation("transform.translation.x", offsets, scale: s), forKey: "sweep")
        shimmer.add(PeekerMotion.animation("opacity", PeekerMotion.shimmerOpacity), forKey: "fade")
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = scale
        let radius = (compact ? 14.0 : 20.0) * s
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        PanelStyle.themed(HistoryStyle.hex(0x18191D, alpha: 0.96), PanelStyle.Washi.ink1.withAlphaComponent(0.96)).setFill(); path.fill()
        PanelStyle.contrast.withAlphaComponent(0.12).setStroke()
        path.lineWidth = max(1, s); path.stroke()
        let titleWidth = HistoryStyle.draw(title, in: CGRect(x: textX * s, y: textY * s, width: (compact ? 150 : 200) * s, height: 18 * s), size: titleSize * s,
                                           weight: .semibold, color: HistoryStyle.text)
        if isDone {
            // Board: check 16 pt, 8 pt after "Done".
            HistoryStyle.drawIcon("ToastCheck", color: PanelStyle.success,
                                  in: CGRect(x: textX * s + titleWidth + 8 * s, y: textY * s, width: 16 * s, height: 16 * s))
        }
        if !compact {
            HistoryStyle.draw(detail, in: CGRect(x: 84 * s, y: 36 * s, width: 250 * s, height: 16 * s), size: 12 * s,
                              color: HistoryStyle.secondary)
        }
    }
}

/// Figma 215:5628. Sizes stay fixed as the window resizes; placement uses
/// bottom-origin AppKit coordinates, above the actual visible filmstrip.
enum TaskRunningPlacement {
    static func chip(canvas: CGSize, stripTop: CGFloat, toolbarBottom: CGFloat)
        -> (style: TaskRunningChip.Style, frame: CGRect)? {
        guard canvas.width >= 360 else { return nil }
        let full = canvas.width >= 520 && canvas.height >= 360
        let size = full ? CGSize(width: 360, height: 76) : CGSize(width: 240, height: 48)
        let y = stripTop + (full ? 16 : 14)
        guard y + size.height + 14 <= toolbarBottom else { return nil }
        return (full ? .full : .compact,
                CGRect(x: (canvas.width - size.width) / 2, y: y, width: size.width, height: size.height))
    }
}

/// Tile-only overlay. It never changes the thumbnail's geometry or hit target.
final class TaskRunningTileOverlay: NSView {
    private let peeker = PeekerView()
    private let track = CALayer()
    private let shimmer = CAGradientLayer()
    private var animationState: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.themed(NSColor.black.withAlphaComponent(0.35), PanelStyle.Washi.ink1.withAlphaComponent(0.6)).cgColor
        layer?.masksToBounds = true
        addSubview(peeker)
        track.backgroundColor = PanelStyle.contrast.withAlphaComponent(0.1).cgColor
        track.cornerRadius = 1
        track.masksToBounds = true
        let accent = PanelStyle.warmCue
        shimmer.colors = [accent.withAlphaComponent(0).cgColor, accent.cgColor, accent.withAlphaComponent(0).cgColor]
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        track.addSublayer(shimmer)
        layer?.addSublayer(track)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAnimation() }
    override func viewDidHide() { super.viewDidHide(); refreshAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshAnimation() }
    override func layout() {
        super.layout()
        let size = max(16, (min(bounds.width, bounds.height) * 0.45).rounded())
        peeker.frame = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2 + 2, width: size, height: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = max(5, bounds.width * 0.12)
        track.frame = CGRect(x: 4, y: 5, width: max(0, bounds.width - 8), height: 2)
        let w = max(24, (track.bounds.width * 0.36).rounded())
        shimmer.frame = CGRect(x: -w, y: 0, width: w, height: 2)
        CATransaction.commit()
        refreshAnimation()
    }
    private func refreshAnimation() {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        let state = "\(bounds.size)-\(track.bounds.width)-\(PeekerMotion.reduced)"
        if visible, animationState == state { return }
        animationState = visible ? state : nil
        shimmer.removeAllAnimations()
        guard visible else { return }
        shimmer.opacity = PeekerMotion.reduced ? 0 : 1
        guard !PeekerMotion.reduced else { return }
        let distance = track.bounds.width + shimmer.bounds.width
        shimmer.add(PeekerMotion.animation("transform.translation.x", [0, distance * 0.2, distance * 0.4, distance * 0.6, distance * 0.8, distance]), forKey: "sweep")
        shimmer.add(PeekerMotion.animation("opacity", PeekerMotion.shimmerOpacity), forKey: "fade")
    }
}

/// A counting ellipsis for the Task Center's state badge, without a UI timer.
final class TaskRunningEllipsis: NSView {
    private let dots = [CALayer(), CALayer(), CALayer()]
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for dot in dots {
            dot.backgroundColor = PanelStyle.warmCue.cgColor
            layer?.addSublayer(dot)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let s = bounds.width / 10
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: CGFloat(i) * 4 * s, y: 0, width: 2 * s, height: 2 * s)
            dot.cornerRadius = s
        }
        refreshAnimation()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAnimation() }
    override func viewDidHide() { super.viewDidHide(); refreshAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshAnimation() }
    private func refreshAnimation() {
        for (i, dot) in dots.enumerated() {
            if window == nil || isHiddenOrHasHiddenAncestor { dot.removeAllAnimations() }
            else if dot.animation(forKey: "count") == nil {
                dot.add(PeekerMotion.animation("opacity", PeekerMotion.dots.map { $0[i] }), forKey: "count")
            }
        }
    }
}

/// The peeker's hands: warm cue on Sumi; on Washi a softer ink so they read
/// apart from the sumi head.
private enum PeekerPalette {
    static let hands = PanelStyle.themed(PanelStyle.warmCue, PanelStyle.Washi.text3)
}

// MARK: - Shizuka Widget running (Figma `32 · Image Inspect / Widget running`)

/// Laid over the image a Widget is processing: an ink/0 veil at 35 %, a soft
/// light sweep and a 2 pt progress rule along the image's foot. The image
/// stays inspectable; this view never takes clicks.
final class InspectRunningVeil: NSView {
    /// Task progress 0–100; nil or 0 shows only the track.
    var progress: Int? { didSet { if progress != oldValue { needsLayout = true } } }
    private let veil = CALayer()
    private let sweep = CAGradientLayer()
    private let track = CALayer()
    private let fill = CALayer()
    private var animationState: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        veil.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink0.withAlphaComponent(0.35))
        // A highlight drawn over the photo itself, so literal white is intended.
        sweep.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.08).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        track.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink4)
        fill.backgroundColor = PanelStyle.resolvedCG(InspectInk.text1)
        for sublayer in [veil, sweep, track, fill] { layer?.addSublayer(sublayer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAnimation() }
    override func viewDidHide() { super.viewDidHide(); refreshAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshAnimation() }

    private var sweepWidth: CGFloat { min(220, bounds.width * 0.45) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        veil.frame = bounds
        sweep.frame = CGRect(x: -sweepWidth, y: 0, width: sweepWidth, height: bounds.height)
        track.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 2)
        let fraction = CGFloat(min(100, max(0, progress ?? 0))) / 100
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: 2)
        CATransaction.commit()
        refreshAnimation()
    }

    private func refreshAnimation() {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        let state = "\(bounds.size)-\(PeekerMotion.reduced)"
        if visible, animationState == state { return }
        animationState = visible ? state : nil
        sweep.removeAllAnimations()
        sweep.isHidden = !visible || PeekerMotion.reduced
        guard visible, !PeekerMotion.reduced, bounds.width > 0 else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = bounds.width + sweepWidth
        move.duration = PeekerMotion.duration
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.repeatCount = .infinity
        sweep.add(move, forKey: "sweep")
    }
}

/// The task capsule near the foot of the processed image: an ai dot, the
/// Widget name (13 pt), progress in mono and a Cancel link.
final class InspectRunningPill: NSView {
    var onCancel: (() -> Void)?
    private var title = ""
    private var progressText: String?
    private let cancelButton = InspectTextButton(title: "Cancel".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                                 color: InspectInk.text2)
    private static let titleFont = PanelStyle.inspectFont(ofSize: 13)
    private static let progressFont = PanelStyle.monoFont(ofSize: 11)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        cancelButton.onPress = { [weak self] in self?.onCancel?() }
        addSubview(cancelButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === cancelButton ? hit : nil
    }

    func configure(title: String, progress: Int?, canCancel: Bool) {
        self.title = title
        progressText = progress.map { "\(min(99, max(0, $0)))%" }
        cancelButton.title = "Cancel".localized
        cancelButton.isHidden = !canCancel
        setAccessibilityLabel([title, progressText, "Task running".localized].compactMap { $0 }.joined(separator: ", "))
        needsLayout = true
        needsDisplay = true
    }

    /// Padding 14 × 8, a 6 pt dot and 8 pt gaps (Figma 26:1520).
    var preferredSize: NSSize {
        var width: CGFloat = 14 + 6 + 8 + InspectText.width(title, font: Self.titleFont)
        if let progressText { width += 8 + InspectText.width(progressText, font: Self.progressFont) }
        if !cancelButton.isHidden { width += 8 + cancelButton.preferredWidth }
        return NSSize(width: width + 14, height: 31)
    }

    override func layout() {
        super.layout()
        let width = cancelButton.preferredWidth
        cancelButton.frame = NSRect(x: bounds.width - 14 - width, y: 8, width: width, height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        InspectInk.ink1.withAlphaComponent(0.92).setFill()
        capsule.fill()
        InspectInk.lineStrong.setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        PanelStyle.info.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: (bounds.height - 6) / 2, width: 6, height: 6)).fill()
        let titleEnd = cancelButton.isHidden ? bounds.width - 14 : cancelButton.frame.minX - 8
        let progressWidth = progressText.map { InspectText.width($0, font: Self.progressFont) } ?? 0
        let titleWidth = max(0, titleEnd - 28 - (progressText == nil ? 0 : progressWidth + 8))
        InspectText.draw(title, in: NSRect(x: 28, y: 7, width: titleWidth, height: 16),
                         font: Self.titleFont, color: InspectInk.text1)
        if let progressText {
            InspectText.draw(progressText, in: NSRect(x: 28 + min(titleWidth, InspectText.width(title, font: Self.titleFont)) + 8,
                                                      y: 8.5, width: progressWidth, height: 14),
                             font: Self.progressFont, color: InspectInk.text3)
        }
    }
}

/// Filmstrip `running ring` (14 pt, ai): spins while a task has no progress
/// yet, and becomes a determinate arc once progress is reported.
final class InspectRunningRing: NSView {
    var progress: Int? { didSet { if progress != oldValue { needsLayout = true } } }
    private let backdrop = CAShapeLayer()
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var animationState: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A small disc and faint track keep the loader legible over any photo.
        backdrop.fillColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome.withAlphaComponent(0.86))
        layer?.addSublayer(backdrop)
        track.fillColor = nil
        track.strokeColor = PanelStyle.resolvedCG(PanelStyle.contrast.withAlphaComponent(0.18))
        layer?.addSublayer(track)
        arc.fillColor = nil
        arc.strokeColor = PanelStyle.resolvedCG(PanelStyle.info)
        arc.lineCap = .round
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAnimation() }
    override func viewDidHide() { super.viewDidHide(); refreshAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshAnimation() }

    private var determinate: Bool { (progress ?? 0) > 0 }

    override func layout() {
        super.layout()
        let size = min(bounds.width, bounds.height)
        let lineWidth = max(1, 1.4 * size / 20)
        let square = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = square
        backdrop.path = CGPath(ellipseIn: CGRect(origin: .zero, size: square.size), transform: nil)
        // The arc spins about its own centre, so it gets the same square frame.
        for ringLayer in [track, arc] {
            ringLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ringLayer.bounds = CGRect(origin: .zero, size: square.size)
            ringLayer.position = CGPoint(x: square.midX, y: square.midY)
            ringLayer.lineWidth = lineWidth
        }
        // Start at 12 o'clock and run clockwise in the bottom-origin layer; inset
        // inside the disc.
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size * 0.32
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: .pi / 2,
                    endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        track.path = path
        arc.path = path
        arc.strokeEnd = determinate ? CGFloat(min(100, progress ?? 0)) / 100 : 0.75
        CATransaction.commit()
        refreshAnimation()
    }

    private func refreshAnimation() {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        let spins = visible && !determinate && !PeekerMotion.reduced
        let state = "\(bounds.size)-\(spins)"
        if animationState == state { return }
        animationState = state
        arc.removeAnimation(forKey: "spin")
        guard spins else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * CGFloat.pi
        spin.duration = 1.2
        spin.repeatCount = .infinity
        arc.add(spin, forKey: "spin")
    }
}
