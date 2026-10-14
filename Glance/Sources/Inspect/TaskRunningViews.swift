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
        eyes.forEach { $0.fillColor = HistoryStyle.hex(0x161719).cgColor }
        hands.forEach { $0.fillColor = PanelStyle.warmCue.cgColor }
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
            hands.forEach { $0.fillColor = PanelStyle.warmCue.cgColor; $0.transform = CATransform3DIdentity }
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
    private(set) var detail = ""
    private(set) var isDone = false
    private let peeker = PeekerView()
    private let track = CALayer()
    private let shimmer = CAGradientLayer()
    private let barFill = CALayer()
    private var dots: [CALayer] = []

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
        track.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
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

    private var scale: CGFloat { bounds.width / 360 }
    private var title: String { (isDone ? "Done" : "Generating").localized }

    override func layout() {
        super.layout()
        let s = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowRadius = 16 * s
        layer?.shadowOffset = CGSize(width: 0, height: -12 * s)
        peeker.frame = CGRect(x: 16 * s, y: 16 * s, width: 44 * s, height: 44 * s)
        track.frame = CGRect(x: 84 * s, y: 60 * s, width: 252 * s, height: 4 * s)
        track.cornerRadius = 2 * s
        shimmer.frame = CGRect(x: -90 * s, y: 0, width: 90 * s, height: 4 * s)
        shimmer.cornerRadius = 2 * s
        barFill.frame = CGRect(x: 0, y: 0, width: 252 * s, height: 4 * s)
        barFill.cornerRadius = 2 * s
        // Board: "Generating" ends at 160, dots at 166 / 174 / 182 — a 6 pt gap.
        let titleWidth = HistoryStyle.width(title, size: 14 * s, weight: .semibold)
        for (index, dot) in dots.enumerated() {
            dot.frame = CGRect(x: 84 * s + titleWidth + 6 * s + CGFloat(index) * 8 * s, y: 26 * s, width: 4 * s, height: 4 * s)
            dot.cornerRadius = 2 * s
        }
        CATransaction.commit()
        restartAnimations()
    }

    private func restartAnimations() {
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
        let s = scale
        // Highlight sweeps the track and fades out before it wraps.
        let offsets = PeekerMotion.shimmerX.map { $0 - PeekerMotion.shimmerX[0] }
        shimmer.add(PeekerMotion.animation("transform.translation.x", offsets, scale: s), forKey: "sweep")
        shimmer.add(PeekerMotion.animation("opacity", PeekerMotion.shimmerOpacity), forKey: "fade")
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = scale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 20 * s, yRadius: 20 * s)
        HistoryStyle.hex(0x18191D, alpha: 0.96).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = max(1, s); path.stroke()
        let titleWidth = HistoryStyle.draw(title, in: CGRect(x: 84 * s, y: 14 * s, width: 200 * s, height: 18 * s), size: 14 * s,
                                           weight: .semibold, color: HistoryStyle.text)
        if isDone {
            // Board: check 16 pt, 8 pt after "Done".
            HistoryStyle.drawIcon("ToastCheck", color: PanelStyle.success,
                                  in: CGRect(x: 84 * s + titleWidth + 8 * s, y: 14 * s, width: 16 * s, height: 16 * s))
        }
        HistoryStyle.draw(detail, in: CGRect(x: 84 * s, y: 36 * s, width: 250 * s, height: 16 * s), size: 12 * s,
                          color: HistoryStyle.secondary)
    }
}
