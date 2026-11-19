import AppKit
import AVFoundation

/// Where Peek Mini attaches: the selection's screen rect when the source app
/// reports one, otherwise the pointer. Rects are AppKit global coordinates.
struct PeekMiniAnchor {
    var selection: NSRect?
    var pointer: NSPoint

    /// `axSelection` is the AX bounds of the selection: global, top-left origin.
    init(axSelection: CGRect?, pointer: NSPoint) {
        self.pointer = pointer
        guard let r = axSelection, let primary = NSScreen.screens.first else {
            selection = nil
            return
        }
        let rect = NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
        // Some apps report a zero or off-screen rect; those fall back to the pointer.
        selection = NSScreen.screens.contains { $0.frame.intersects(rect) } ? rect : nil
    }
}

/// Figma `Peek · Mini` (P1–P3): a 304 pt card beside the selected text that
/// previews the image or video a hotkey Peek found. ↵ hands off to the full
/// Inspect; esc, a click elsewhere, or another app taking focus closes it.
final class PeekMiniPanel: NSPanel {
    var onInspect: ((_ infos: [MediaInfo], _ focusedIndex: Int) -> Void)?
    /// ↵ on a failure card: rerun the same selection.
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// Fires once per `show`: true on the first item that loads, false when all fail.
    var onLoadFinished: ((_ succeeded: Bool, _ paths: [DetectedPath]) -> Void)?

    // Figma geometry: card 304 wide, 7 pt content inset, 290 pt rows.
    private enum Metric {
        static let width: CGFloat = 304
        static let inset: CGFloat = 7
        static let row: CGFloat = 290
        static let infoHeight: CGFloat = 50
        static let keysHeight: CGFloat = 32
        static let stateHeight: CGFloat = 132
        static let mediaMin: CGFloat = 140
        static let mediaMax: CGFloat = 228
        /// Transparent margin around the card so its drop shadow isn't clipped.
        static let shadowMargin: CGFloat = 48
        static let gap: CGFloat = 8
        static let screenEdge: CGFloat = 12
    }

    private enum Content {
        case idle
        case loading(name: String, meta: String)
        case failure(name: String, meta: String, title: String, message: String, retryTitle: String?)
        case media
    }

    private let loader: ImageLoader
    private let shadowView = NSView()
    private let blur = NSVisualEffectView()
    private let card = MiniFlippedView()
    private var content: Content = .idle
    private var anchor = PeekMiniAnchor(axSelection: nil, pointer: .zero)
    private var paths: [DetectedPath] = []
    private var infos: [MediaInfo] = []
    private var loaded: [LoadedMedia?] = []
    private var failed: Set<Int> = []
    private var focused = 0
    private var generation = 0
    private var videoCodecs: [URL: String] = [:]
    private var videoThumbnails: [URL: NSImage] = [:]
    private var mouseMonitor: Any?
    private var copyButton: PeekIconButton?

    private var player: AVPlayer?
    private var playerURL: URL?
    private var timeObserver: Any?
    private var loopObserver: NSObjectProtocol?
    private weak var scrubFill: CALayer?

    init(imageLoader: ImageLoader) {
        loader = imageLoader
        super.init(contentRect: NSRect(x: 0, y: 0, width: Metric.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = PanelStyle.windowAppearance

        let root = NSView()
        root.wantsLayer = true
        contentView = root

        shadowView.wantsLayer = true
        shadowView.layer?.shadowColor = PanelStyle.isLight
            ? NSColor(srgbRed: 0.2, green: 0.18, blue: 0.12, alpha: 1).cgColor : NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = PanelStyle.isLight ? 0.16 : 0.45
        shadowView.layer?.shadowRadius = 20   // Figma blur 40
        shadowView.layer?.shadowOffset = NSSize(width: 0, height: -16)
        root.addSubview(shadowView)

        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = PanelStyle.vibrantAppearance
        blur.maskImage = PanelStyle.roundedMask(radius: PanelStyle.Radius.window)
        root.addSubview(blur)

        card.wantsLayer = true
        card.layer?.cornerRadius = PanelStyle.Radius.window
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = PanelStyle.themed(PanelStyle.Sumi.ink1, PanelStyle.Washi.ink1)
            .withAlphaComponent(0.96).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Peek.lineStrong.cgColor
        root.addSubview(card)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Showing

    func showLoading(name: String, meta: String, anchor: PeekMiniAnchor) {
        resetMedia()
        self.anchor = anchor
        content = .loading(name: name, meta: meta)
        render()
        present()
    }

    func showFailure(name: String, meta: String, title: String, message: String,
                     retryTitle: String?, anchor: PeekMiniAnchor? = nil) {
        resetMedia()
        if let anchor { self.anchor = anchor }
        content = .failure(name: name, meta: meta, title: title, message: message, retryTitle: retryTitle)
        render()
        present()
    }

    /// Loads `paths` (images and/or videos) and shows them as they arrive.
    func show(paths: [DetectedPath], infos: [MediaInfo], anchor: PeekMiniAnchor) {
        guard !infos.isEmpty else { return }
        resetMedia()
        let token = generation
        self.anchor = anchor
        self.paths = paths
        self.infos = infos
        loaded = Array(repeating: nil, count: infos.count)
        content = .media
        render()
        present()

        var reported = false
        loader.loadMedia(from: paths, onProgress: { [weak self] index, media in
            guard let self, token == self.generation, index < self.loaded.count else { return }
            if let media {
                self.loaded[index] = media
                if case .video(let url, _, _) = media {
                    self.probeCodec(url, token: token)
                    if self.infos.count > 1 { self.loadVideoThumbnail(url, token: token) }
                }
                if !reported {
                    reported = true
                    self.onLoadFinished?(true, paths)
                }
            } else {
                self.failed.insert(index)
            }
            self.render()
        }, onComplete: { [weak self] in
            guard let self, token == self.generation else { return }
            guard !reported else { return }
            reported = true
            let info = self.infos.first
            self.showFailure(name: info?.filename ?? "", meta: info.map(Self.location(of:)) ?? "",
                             title: "Can't open this file".localized,
                             message: self.failureMessage?(info?.url) ?? "",
                             retryTitle: "Try again".localized)
            self.onLoadFinished?(false, paths)
        })
    }

    /// Supplies the explanation for a file that exists but couldn't be read.
    var failureMessage: ((URL?) -> String)?

    private func present() {
        if !isVisible {
            orderFrontRegardless()
            installMouseMonitor()
        }
        makeKey()
    }

    func dismiss() {
        guard isVisible else { return }
        resetMedia()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        orderOut(nil)
        onDismiss?()
    }

    override func resignKey() {
        super.resignKey()
        // Another app or window took focus: the card has done its job.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            self.dismiss()
        }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func resetMedia() {
        generation &+= 1
        content = .idle
        stopPlayer()
        paths = []
        infos = []
        loaded = []
        failed = []
        videoThumbnails = [:]
        focused = 0
        copyButton = nil
    }

    // MARK: - Keys

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53: dismiss()
        case 36, 76: primaryAction()
        case 49 where isSingleVideo: togglePlayback()
        case 123 where infos.count > 1: moveFocus(-1)
        case 124 where infos.count > 1: moveFocus(1)
        case 8 where flags == .command: copyFocused()
        default:
            if flags.contains(.command) {
                super.keyDown(with: event)
            } else {
                // Typing means the user moved on; don't swallow keys into a stale card.
                dismiss()
            }
        }
    }

    private var isSingleVideo: Bool {
        if case .media = content, infos.count == 1, infos[0].kind == .video { return true }
        return false
    }

    private func primaryAction() {
        switch content {
        case .idle, .loading: break
        case .failure(_, _, _, _, let retry):
            guard retry != nil else { return }
            onRetry?()
        case .media:
            let infos = loaded.enumerated().map { $0.element?.info ?? self.infos[$0.offset] }
            let index = focused
            dismiss()
            onInspect?(infos, index)
        }
    }

    private func moveFocus(_ delta: Int) {
        focused = (focused + delta + infos.count) % infos.count
        render()
    }

    // MARK: - Actions

    @objc private func copyFocused() {
        guard case .media = content, infos.indices.contains(focused) else { return }
        let info = loaded[focused]?.info ?? infos[focused]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if case .image(let image, _) = loaded[focused] {
            pasteboard.writeObjects([image])
        } else if info.isLocal {
            pasteboard.writeObjects([info.url as NSURL])
        } else {
            pasteboard.setString(info.url.absoluteString, forType: .string)
        }
        copyButton?.setSymbol("checkmark", description: "Copied".localized)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton?.setSymbol("doc.on.doc", description: "Copy".localized)
        }
    }

    @objc private func revealFocused() {
        guard infos.indices.contains(focused) else { return }
        let info = infos[focused]
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.rate != 0 { player.pause() } else { player.play() }
        render()
    }

    // MARK: - Layout

    private func render() {
        card.subviews.forEach { $0.removeFromSuperview() }
        scrubFill = nil
        copyButton = nil
        var y = Metric.inset
        let x = Metric.inset

        switch content {
        case .idle: return
        case .loading(let name, let meta):
            card.addSubview(stateBox(y: y, loading: true, title: "", message: ""))
            y += Metric.stateHeight
            addInfo(y: y, name: name, meta: meta, buttons: false)
            addKeys(y: y + Metric.infoHeight, keys: [("esc", "Close".localized)])

        case .failure(let name, let meta, let title, let message, let retry):
            card.addSubview(stateBox(y: y, loading: false, title: title, message: message))
            y += Metric.stateHeight
            addInfo(y: y, name: name, meta: meta, buttons: false)
            var keys: [(String, String)] = []
            if let retry { keys.append(("↵", retry)) }
            keys.append(("esc", "Close".localized))
            addKeys(y: y + Metric.infoHeight, keys: keys)

        case .media where infos.count == 1:
            let info = loaded[0]?.info ?? infos[0]
            guard let media = loaded[0] else {
                card.addSubview(stateBox(y: y, loading: true, title: "", message: ""))
                y += Metric.stateHeight
                addInfo(y: y, name: info.filename, meta: Self.location(of: info), buttons: false)
                addKeys(y: y + Metric.infoHeight, keys: [("esc", "Close".localized)])
                break
            }
            let height = Self.mediaHeight(for: media.naturalSize)
            let view = MiniMediaView(frame: NSRect(x: x, y: y, width: Metric.row, height: height), radius: 8)
            view.onClick = { [weak self] in self?.primaryAction() }
            card.addSubview(view)
            if case .image(let image, _) = media {
                view.image = image
            } else if case .video(let url, _, _) = media {
                attachPlayer(url: url, to: view, duration: info.duration)
            }
            y += height
            addInfo(y: y, name: info.filename, meta: meta(for: info), buttons: true)
            let keys: [(String, String)] = info.kind == .video
                ? [("space", ((player?.rate ?? 0) != 0 ? "Pause" : "Play").localized),
                   ("↵", "Open in Inspect".localized), ("esc", "Close".localized)]
                : [("↵", "Open in Inspect".localized), ("⌘C", "Copy".localized), ("esc", "Close".localized)]
            addKeys(y: y + Metric.infoHeight, keys: keys)

        case .media:
            y += addThumbnails(y: y)
            let (name, meta) = multiTitle()
            addInfo(y: y, name: name, meta: meta, buttons: true)
            addKeys(y: y + Metric.infoHeight, keys: [("↵", "Inspect all".localized),
                                                     ("← →", "Choose".localized),
                                                     ("esc", "Close".localized)])
        }

        let height = card.subviews.map(\.frame.maxY).max().map { $0 + 1 } ?? 200
        place(cardSize: NSSize(width: Metric.width, height: height))
    }

    private func place(cardSize: NSSize) {
        let cardFrame = Self.cardFrame(size: cardSize, anchor: anchor)
        let m = Metric.shadowMargin
        setFrame(cardFrame.insetBy(dx: -m, dy: -m), display: true)
        let local = NSRect(x: m, y: m, width: cardSize.width, height: cardSize.height)
        shadowView.frame = local
        shadowView.layer?.shadowPath = CGPath(roundedRect: shadowView.bounds,
                                              cornerWidth: PanelStyle.Radius.window,
                                              cornerHeight: PanelStyle.Radius.window, transform: nil)
        blur.frame = local
        card.frame = local
    }

    /// Figma P3: below the selection (8 pt gap), above it when there's no room,
    /// shifted to stay 12 pt inside the screen, never over the selection when
    /// either side fits. Without selection bounds, beside the pointer.
    static func cardFrame(size: NSSize, anchor: PeekMiniAnchor) -> NSRect {
        let gap = Metric.gap
        func visible(containing point: NSPoint) -> NSRect {
            let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
            return (screen?.visibleFrame ?? NSRect(origin: point, size: size))
                .insetBy(dx: Metric.screenEdge, dy: Metric.screenEdge)
        }
        func clampX(_ x: CGFloat, _ area: NSRect) -> CGFloat {
            max(area.minX, min(x, area.maxX - size.width))
        }
        func clampY(_ y: CGFloat, _ area: NSRect) -> CGFloat {
            max(area.minY, min(y, area.maxY - size.height))
        }

        if let selection = anchor.selection {
            let area = visible(containing: NSPoint(x: selection.maxX - 1, y: selection.midY))
            // Starts just before the selection's end, where the reader's eye is;
            // short selections line up with their left edge.
            let x = clampX(max(selection.minX, selection.maxX - 40), area)
            let below = selection.minY - gap - size.height
            let above = selection.maxY + gap
            let y: CGFloat
            if below >= area.minY {
                y = below
            } else if above + size.height <= area.maxY {
                y = above
            } else {
                // Neither side fits: use the roomier side and stay on screen.
                y = clampY(selection.minY - area.minY >= area.maxY - selection.maxY ? below : above, area)
            }
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        let p = anchor.pointer
        let area = visible(containing: p)
        var x = p.x + 16
        if x + size.width > area.maxX { x = p.x - 16 - size.width }
        var y = p.y - 16 - size.height
        if y < area.minY { y = p.y + 16 }
        return NSRect(x: clampX(x, area), y: clampY(y, area), width: size.width, height: size.height)
    }

    private static func mediaHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return Metric.mediaMax }
        return min(Metric.mediaMax, max(Metric.mediaMin, (Metric.row * size.height / size.width).rounded()))
    }

    // MARK: - Pieces

    /// `state` frame: 132 pt ink/0 plate with the loading bar or the failure note.
    private func stateBox(y: CGFloat, loading: Bool, title: String, message: String) -> NSView {
        let box = MiniFlippedView(frame: NSRect(x: Metric.inset, y: y, width: Metric.row, height: Metric.stateHeight))
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.backgroundColor = PanelStyle.canvas.cgColor
        let w = Metric.row
        if loading {
            let track = CALayer()
            // The box is flipped, so sublayer y counts from the top like Figma.
            track.frame = CGRect(x: (w - 96) / 2, y: 53.5, width: 96, height: 2)
            track.cornerRadius = 1
            track.backgroundColor = Peek.track.cgColor
            track.masksToBounds = true
            let bar = CALayer()
            bar.frame = CGRect(x: 0, y: 0, width: 36, height: 2)
            bar.backgroundColor = PanelStyle.textSecondary.cgColor
            track.addSublayer(bar)
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = -18
            slide.toValue = 96 + 18
            slide.duration = 1.1
            slide.repeatCount = .infinity
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(slide, forKey: "slide")
            box.layer?.addSublayer(track)
            box.addSubview(MiniText(frame: NSRect(x: 0, y: 63.5, width: w, height: 15),
                                    text: "Preparing preview".localized,
                                    font: .systemFont(ofSize: 12), color: PanelStyle.textSecondary,
                                    alignment: .center))
        } else {
            let dot = NSView(frame: NSRect(x: (w - 6) / 2, y: 31.5, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = PanelStyle.failure.cgColor
            box.addSubview(dot)
            box.addSubview(MiniText(frame: NSRect(x: 0, y: 45.5, width: w, height: 15), text: title,
                                    font: .systemFont(ofSize: 12), color: PanelStyle.textPrimary,
                                    alignment: .center))
            box.addSubview(MiniText(frame: NSRect(x: 28, y: 68.5, width: 236, height: 48), text: message,
                                    font: .systemFont(ofSize: 11), color: PanelStyle.textTertiary,
                                    alignment: .center, lineHeight: 16, wraps: true))
        }
        return box
    }

    /// `info` frame: name (13 medium) and mono meta, plus Copy / Reveal buttons.
    private func addInfo(y: CGFloat, name: String, meta: String, buttons: Bool) {
        let x = Metric.inset
        let textWidth: CGFloat = buttons ? 216 : 280
        card.addSubview(MiniText(frame: NSRect(x: x + 8, y: y + 10, width: textWidth, height: 16), text: name,
                                 font: .systemFont(ofSize: 13, weight: .medium), color: PanelStyle.textPrimary))
        card.addSubview(MiniText(frame: NSRect(x: x + 8, y: y + 29, width: textWidth, height: 13), text: meta,
                                 font: PanelStyle.monoFont(ofSize: 10), color: PanelStyle.textTertiary))
        guard buttons else { return }
        let copy = PeekIconButton(symbol: "doc.on.doc", tooltip: "Copy".localized,
                                  target: self, action: #selector(copyFocused))
        copy.frame = NSRect(x: x + 228, y: y + 12, width: 28, height: 28)
        card.addSubview(copy)
        copyButton = copy
        let reveal = PeekIconButton(symbol: "folder", tooltip: "Reveal in Finder".localized,
                                    target: self, action: #selector(revealFocused))
        reveal.frame = NSRect(x: x + 260, y: y + 12, width: 28, height: 28)
        reveal.isEnabled = infos.indices.contains(focused) && infos[focused].isLocal
        reveal.isHidden = !reveal.isEnabled
        card.addSubview(reveal)
    }

    /// `keys` frame: hairline on top, groups 14 pt apart, key (mono 10) + label (11).
    private func addKeys(y: CGFloat, keys: [(String, String)]) {
        let x = Metric.inset
        let hair = NSView(frame: NSRect(x: x, y: y, width: Metric.row, height: 1))
        hair.wantsLayer = true
        hair.layer?.backgroundColor = Peek.lineHair.cgColor
        card.addSubview(hair)
        let keyFont = PanelStyle.monoFont(ofSize: 10)
        let labelFont = NSFont.systemFont(ofSize: 11)
        var cursor = x + 8
        for (key, label) in keys {
            let keyWidth = ceil((key as NSString).size(withAttributes: [.font: keyFont]).width)
            let labelWidth = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
            card.addSubview(MiniText(frame: NSRect(x: cursor, y: y + 9, width: keyWidth, height: 13),
                                     text: key, font: keyFont, color: PanelStyle.textSecondary))
            card.addSubview(MiniText(frame: NSRect(x: cursor + keyWidth + 5, y: y + 9, width: labelWidth, height: 13),
                                     text: label, font: labelFont, color: PanelStyle.textTertiary))
            cursor += keyWidth + 5 + labelWidth + 14
        }
        // The card's 1 pt bottom padding sits under this 32 pt row.
        let end = NSView(frame: NSRect(x: x, y: y + Metric.keysHeight, width: 1, height: 0))
        card.addSubview(end)
    }

    /// The six-image Figma card has two rows of three 94⅔ × 123 pt thumbnails.
    private func addThumbnails(y: CGFloat) -> CGFloat {
        let pageSize = 6
        let start = focused / pageSize * pageSize
        let visibleCount = min(pageSize, infos.count - start)
        let columns = min(3, infos.count)
        let gap: CGFloat = 4
        let gridWidth = columns == 3 ? CGFloat(292) : Metric.row
        let width = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = width * 1.3
        let end = start + visibleCount
        for slot in 0..<visibleCount {
            let index = start + slot
            let frame = NSRect(x: Metric.inset + CGFloat(slot % columns) * (width + gap),
                               y: y + CGFloat(slot / columns) * (height + gap), width: width, height: height)
            let tile = MiniMediaView(frame: frame, radius: 6)
            switch loaded[index] {
            case .image(let image, _): tile.image = image
            case .video(let url, _, _): tile.image = videoThumbnails[url]
            default: tile.showsPlaceholder(failed: failed.contains(index))
            }
            tile.selected = index == focused
            tile.onClick = { [weak self] in
                guard let self else { return }
                if self.focused == index { self.primaryAction() } else { self.focused = index; self.render() }
            }
            if index == end - 1 && end < infos.count {
                let label = "+\(infos.count - end)"
                let font = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
                let badgeWidth = max(30, ceil((label as NSString).size(withAttributes: [.font: font]).width) + 12)
                let badge = MiniMediaView(frame: NSRect(x: width - badgeWidth - 5, y: 5,
                                                        width: badgeWidth, height: 20), radius: 10)
                badge.layer?.backgroundColor = NSColor(white: 0.09, alpha: 0.84).cgColor
                badge.addSubview(MiniText(frame: badge.bounds.insetBy(dx: 0, dy: 2), text: label,
                                          font: font, color: .white, alignment: .center))
                badge.onClick = { [weak self] in
                    self?.focused = end
                    self?.render()
                }
                tile.addSubview(badge)
            }
            card.addSubview(tile)
        }
        return infos.count > 3 ? height * 2 + gap : height
    }

    private func multiTitle() -> (String, String) {
        let names = Set(infos.map(\.filename))
        if names.count == 1, let name = names.first {
            let folders = infos.map(Self.location(of:))
            var meta = folders.prefix(2).joined(separator: "  ·  ")
            if folders.count > 2 { meta += "  ·  +\(folders.count - 2)" }
            return (String(format: "%d files named %@".localized, infos.count, name), meta)
        }
        let info = infos[focused]
        return (info.filename, String(format: "%1$d of %2$d".localized, focused + 1, infos.count)
                + "  ·  " + Self.location(of: info))
    }

    private func meta(for info: MediaInfo) -> String {
        var parts: [String] = []
        if let d = info.dimensions, d.width > 0 { parts.append("\(Int(d.width)) × \(Int(d.height))") }
        if info.kind == .video {
            parts.append(videoCodecs[info.url] ?? info.formatName)
            if let duration = info.duration { parts.append(Self.timecode(duration)) }
        } else {
            if !info.formatName.isEmpty { parts.append(info.formatName) }
            if let size = info.fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            } else if !info.isLocal, let host = info.url.host {
                parts.append(host)
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    /// `~/Downloads/Glance` for local files, the host for remote ones.
    static func location(of info: MediaInfo) -> String {
        guard info.isLocal else { return info.url.host ?? info.url.absoluteString }
        if let hint = info.disambiguationHint { return hint }
        let parent = info.url.deletingLastPathComponent().path
        let home = UserHome.path
        if parent == home { return "~" }
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }

    private static func timecode(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func loadVideoThumbnail(_ url: URL, token: Int) {
        loader.loadVideoThumbnail(from: url) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, token == self.generation, let image else { return }
                self.videoThumbnails[url] = image
                self.render()
            }
        }
    }

    private func probeCodec(_ url: URL, token: Int) {
        guard videoCodecs[url] == nil else { return }
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            guard let track = asset.tracks(withMediaType: .video).first,
                  let raw = track.formatDescriptions.first else { return }
            let description = raw as! CMFormatDescription
            let fourCC = CMFormatDescriptionGetMediaSubType(description)
            let name: String?
            switch fourCC {
            case kCMVideoCodecType_H264: name = "H.264"
            case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: name = "HEVC"
            case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
                 kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
                 kCMVideoCodecType_AppleProRes4444: name = "ProRes"
            case kCMVideoCodecType_VP9: name = "VP9"
            default: name = nil
            }
            guard let name else { return }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.videoCodecs[url] = name
                self.render()
            }
        }
    }

    // MARK: - Video

    /// Muted inline playback with the Figma duration badge and 2 pt scrubber.
    private func attachPlayer(url: URL, to view: MiniMediaView, duration: TimeInterval?) {
        if playerURL != url {
            stopPlayer()
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .none
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10),
                                                          queue: .main) { [weak self] time in
                self?.updateScrubber(time: time)
            }
            self.player = player
            playerURL = url
            player.play()
        }
        guard let player else { return }
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)

        // MiniMediaView is bottom-origin (AVPlayerLayer under a flipped layer tree
        // can draw upside down), so the scrubber sits at y 0 and the badge 10 pt up.
        let w = view.bounds.width
        let track = CALayer()
        track.frame = CGRect(x: 0, y: 0, width: w, height: 2)
        track.backgroundColor = Peek.track.cgColor
        view.layer?.addSublayer(track)
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: 0, height: 2)
        fill.backgroundColor = PanelStyle.textPrimary.cgColor
        view.layer?.addSublayer(fill)
        scrubFill = fill
        updateScrubber(time: player.currentTime())

        if let duration {
            let font = PanelStyle.monoFont(ofSize: 10)
            let text = Self.timecode(duration)
            let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let badge = MiniFlippedView(frame: NSRect(x: 8, y: 10, width: 22 + textWidth + 7, height: 21))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.backgroundColor = PanelStyle.canvas.withAlphaComponent(0.7).cgColor
            let icon = NSImageView(frame: NSRect(x: 7, y: 5.5, width: 10, height: 10))
            icon.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .regular))
            icon.contentTintColor = PanelStyle.textPrimary
            badge.addSubview(icon)
            badge.addSubview(MiniText(frame: NSRect(x: 22, y: 4, width: textWidth, height: 13), text: text,
                                      font: font, color: PanelStyle.textPrimary))
            view.addSubview(badge)
        }
    }

    private func updateScrubber(time: CMTime) {
        guard let fill = scrubFill, let item = player?.currentItem else { return }
        let total = CMTimeGetSeconds(item.duration)
        guard total.isFinite, total > 0, let width = fill.superlayer?.bounds.width else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame.size.width = width * CGFloat(min(1, max(0, CMTimeGetSeconds(time) / total)))
        CATransaction.commit()
    }

    private func stopPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        timeObserver = nil
        loopObserver = nil
        player?.pause()
        player = nil
        playerURL = nil
    }
}

// MARK: - Views

private final class MiniFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Text drawn into an exact Figma frame: no cell padding, top-aligned.
private final class MiniText: NSView {
    private let attributed: NSAttributedString

    init(frame: NSRect, text: String, font: NSFont, color: NSColor,
         alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil, wraps: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ])
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        attributed.draw(with: bounds, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Rounded, aspect-filled media plate. Click to act; `selected` draws the ring.
private final class MiniMediaView: NSView {
    var onClick: (() -> Void)?
    var image: NSImage? {
        didSet { layer?.contents = image }
    }
    var selected = false {
        didSet {
            layer?.borderWidth = selected ? 1.5 : 0
            layer?.borderColor = PanelStyle.textPrimary.cgColor
        }
    }

    init(frame: NSRect, radius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.backgroundColor = PanelStyle.canvas.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showsPlaceholder(failed: Bool) {
        let icon = NSImageView(frame: NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2,
                                             width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: failed ? "exclamationmark.triangle" : "photo",
                             accessibilityDescription: nil)
        icon.contentTintColor = failed ? PanelStyle.failure : Peek.text4
        addSubview(icon)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
