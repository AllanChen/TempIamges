import AppKit

private enum Tone {
    static let background = NSColor(calibratedWhite: 0.035, alpha: 1)
    static let chrome = NSColor(calibratedWhite: 0.055, alpha: 1)
    static let surface = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let raised = NSColor(calibratedWhite: 0.105, alpha: 1)
    static let line = NSColor(calibratedWhite: 1, alpha: 0.10)
    static let lineStrong = NSColor(calibratedWhite: 1, alpha: 0.18)
    static let text = NSColor(calibratedWhite: 0.94, alpha: 1)
    static let secondary = NSColor(calibratedWhite: 0.70, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.48, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.91, green: 0.66, blue: 0.49, alpha: 1)
    static let accentSoft = NSColor(calibratedRed: 0.91, green: 0.66, blue: 0.49, alpha: 0.14)
    static let accentInk = NSColor(calibratedRed: 0.12, green: 0.07, blue: 0.04, alpha: 1)
    static let success = NSColor(calibratedRed: 0.56, green: 0.81, blue: 0.68, alpha: 1)
    static let danger = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.52, alpha: 1)
    static let info = NSColor(calibratedRed: 0.66, green: 0.77, blue: 0.94, alpha: 1)
}

private enum Type {
    static let title = NSFont.systemFont(ofSize: 17, weight: .semibold)
    static let heading = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let small = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let tiny = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
}

private func label(_ value: String, font: NSFont = Type.body, color: NSColor = Tone.text) -> NSTextField {
    let item = NSTextField(labelWithString: value)
    item.font = font
    item.textColor = color
    item.lineBreakMode = .byTruncatingTail
    return item
}

private func button(_ title: String, primary: Bool = false, width: CGFloat? = nil) -> NSButton {
    let item = NSButton(title: title, target: nil, action: nil)
    item.font = Type.small
    item.bezelStyle = .rounded
    item.controlSize = .regular
    item.contentTintColor = primary ? Tone.accentInk : Tone.text
    item.wantsLayer = true
    item.layer?.cornerRadius = 7
    item.layer?.backgroundColor = (primary ? Tone.accent : Tone.raised).cgColor
    item.layer?.borderColor = Tone.line.cgColor
    item.layer?.borderWidth = primary ? 0 : 1
    if let width { item.widthAnchor.constraint(equalToConstant: width).isActive = true }
    return item
}

private func stack(_ views: [NSView], axis: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 8, distribution: NSStackView.Distribution = .fill) -> NSStackView {
    let item = NSStackView(views: views)
    item.orientation = axis
    item.spacing = spacing
    item.distribution = distribution
    item.translatesAutoresizingMaskIntoConstraints = false
    return item
}

private func divider() -> NSView {
    let item = NSView()
    item.wantsLayer = true
    item.layer?.backgroundColor = Tone.line.cgColor
    item.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return item
}

private final class FrostedView: NSVisualEffectView {
    init(material: NSVisualEffectView.Material = .underWindowBackground) {
        super.init(frame: .zero)
        self.material = material
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Tone.line.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class TrafficLights: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: CGFloat(index) * 18, y: 5, width: 11, height: 11)).fill()
        }
    }
}

private final class ArtworkView: NSView {
    private var image: NSImage?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        if let url = URL(string: "https://rh-images.xiaoyaoyou.com/609023cda18564cc1e0ec2589c98987a/2026-09-06/ccf23759bffa3fbed3474a1f758a3e58.jpg") {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    DispatchQueue.main.async { self?.image = image; self?.needsDisplay = true }
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let bounds = dirtyRect
        if let image {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            return
        }
        let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.20, alpha: 1), NSColor(calibratedRed: 0.58, green: 0.40, blue: 0.32, alpha: 1), NSColor(calibratedRed: 0.15, green: 0.22, blue: 0.18, alpha: 1)])
        gradient?.draw(in: bounds, angle: 135)
        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: bounds.midY * 0.72)); path.line(to: NSPoint(x: bounds.maxX, y: bounds.midY * 1.28)); path.lineWidth = 1; path.stroke()
    }
}

private final class PreviewRootView: NSView {
    private let picker = NSSegmentedControl(labels: ["快速预览", "图片", "视频", "内容", "任务", "Market", "Web", "Base64", "历史", "设置", "权限"], trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSView()
    private let subtitle = NSTextField(labelWithString: "原生 AppKit 预览，不连接生产数据")
    private var currentScreen = 1
    private var screenView: NSView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Tone.background.cgColor
        picker.selectedSegment = currentScreen
        picker.target = self
        picker.action = #selector(screenChanged)
        picker.segmentStyle = .texturedRounded
        picker.controlSize = .small
        picker.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = Type.tiny; subtitle.textColor = Tone.muted
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        let brand = label("GLANCE / NATIVE UI PREVIEW", font: Type.tiny, color: Tone.accent)
        brand.translatesAutoresizingMaskIntoConstraints = false
        let top = FrostedView(material: .hudWindow)
        top.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(brand); top.addSubview(picker); top.addSubview(subtitle)
        addSubview(top); addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 18), top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22), top.heightAnchor.constraint(equalToConstant: 48),
            brand.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 14), brand.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            subtitle.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -14), subtitle.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            picker.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 28), picker.trailingAnchor.constraint(lessThanOrEqualTo: subtitle.leadingAnchor, constant: -18), picker.centerYAnchor.constraint(equalTo: top.centerYAnchor), picker.heightAnchor.constraint(equalToConstant: 26),
            content.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 16), content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22)
        ])
        showScreen(index: currentScreen)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func screenChanged() { showScreen(index: picker.selectedSegment) }

    private func showScreen(index: Int) {
        currentScreen = index
        screenView?.removeFromSuperview()
        let view: NSView
        switch index {
        case 0: view = QuickPreviewScreen()
        case 1: view = ImageInspectScreen()
        case 2: view = VideoInspectScreen()
        case 3: view = DocumentScreen()
        case 4: view = TaskCenterScreen()
        case 5: view = MarketScreen()
        case 6: view = WebStateScreen()
        case 7: view = Base64Screen()
        case 8: view = HistoryScreen()
        case 9: view = PreferencesScreen()
        default: view = OnboardingScreen()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor), view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        screenView = view
    }
}

private class WindowFrame: NSView {
    let body = NSView()
    let title = NSTextField(labelWithString: "")
    init(title value: String, bodyColor: NSColor = Tone.surface) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Tone.surface.cgColor; layer?.cornerRadius = 15; layer?.borderWidth = 1; layer?.borderColor = Tone.lineStrong.cgColor
        let bar = NSView(); bar.wantsLayer = true; bar.layer?.backgroundColor = Tone.chrome.cgColor; bar.translatesAutoresizingMaskIntoConstraints = false
        let lights = TrafficLights(); lights.translatesAutoresizingMaskIntoConstraints = false
        title.stringValue = value; title.font = Type.small; title.textColor = Tone.text; title.alignment = .center; title.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(lights); bar.addSubview(title); addSubview(bar)
        body.wantsLayer = true; body.layer?.backgroundColor = bodyColor.cgColor; body.translatesAutoresizingMaskIntoConstraints = false; addSubview(body)
        NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 42), lights.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14), lights.centerYAnchor.constraint(equalTo: bar.centerYAnchor), lights.widthAnchor.constraint(equalToConstant: 34), lights.heightAnchor.constraint(equalToConstant: 20), title.centerXAnchor.constraint(equalTo: bar.centerXAnchor), title.centerYAnchor.constraint(equalTo: bar.centerYAnchor), body.topAnchor.constraint(equalTo: bar.bottomAnchor), body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor), body.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class ImageInspectScreen: NSView {
    private let status = label("", font: Type.small, color: Tone.secondary)
    private let thumbStrip = NSStackView()
    private let taskButton = button("任务", width: 50)
    private let runButton = button("运行 Remove BG", primary: true, width: 124)
    private let inspector = FrostedView(material: .underWindowBackground)
    init() {
        super.init(frame: .zero)
        let frame = WindowFrame(title: "Image Inspect")
        addSubview(frame); frame.translatesAutoresizingMaskIntoConstraints = false
        let close = button("×", width: 30); let direction = button("↻", width: 30); let fit = button("适应窗口", width: 72); let minus = button("−", width: 30); let plus = button("+", width: 30)
        direction.toolTip = "方向菜单: 向左旋转、向右旋转、左右翻转、上下翻转"
        taskButton.toolTip = "任务中心"
        runButton.target = self; runButton.action = #selector(runWidget)
        let left = stack([close, direction, fit], axis: .horizontal, spacing: 6); let zoom = stack([minus, label("100%", font: Type.tiny, color: Tone.secondary), plus], axis: .horizontal, spacing: 6); let right = stack([taskButton, button("W", width: 30), runButton], axis: .horizontal, spacing: 6)
        let toolbar = stack([left, zoom, right], axis: .horizontal, spacing: 8, distribution: .fillEqually); toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let canvas = FrostedView(material: .underWindowBackground); let mode = NSSegmentedControl(labels: ["专注", "并排", "滑杆"], trackingMode: .selectOne, target: nil, action: nil); mode.selectedSegment = 0; mode.segmentStyle = .texturedRounded; mode.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(mode)
        let artwork = ArtworkView(frame: .zero); artwork.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(artwork)
        NSLayoutConstraint.activate([mode.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 12), mode.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 12), mode.heightAnchor.constraint(equalToConstant: 26), artwork.centerXAnchor.constraint(equalTo: canvas.centerXAnchor), artwork.centerYAnchor.constraint(equalTo: canvas.centerYAnchor), artwork.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, multiplier: 0.70), artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 0.68)])
        inspector.addSubview(makeInspector()); NSLayoutConstraint.activate([inspector.subviews[0].leadingAnchor.constraint(equalTo: inspector.leadingAnchor, constant: 14), inspector.subviews[0].trailingAnchor.constraint(equalTo: inspector.trailingAnchor, constant: -14), inspector.subviews[0].topAnchor.constraint(equalTo: inspector.topAnchor, constant: 14), inspector.subviews[0].bottomAnchor.constraint(lessThanOrEqualTo: inspector.bottomAnchor, constant: -14)])
        let middle = NSStackView(views: [canvas, inspector]); middle.orientation = .horizontal; middle.spacing = 0; middle.distribution = .fill; middle.translatesAutoresizingMaskIntoConstraints = false; canvas.setContentHuggingPriority(.defaultLow, for: .horizontal); inspector.widthAnchor.constraint(equalToConstant: 278).isActive = true
        for color in [Tone.raised, Tone.raised, Tone.raised] { let tile = ArtworkView(frame: .zero); tile.wantsLayer = true; tile.layer?.backgroundColor = color.cgColor; tile.translatesAutoresizingMaskIntoConstraints = false; tile.widthAnchor.constraint(equalToConstant: 68).isActive = true; tile.heightAnchor.constraint(equalToConstant: 62).isActive = true; thumbStrip.addArrangedSubview(tile) }
        let add = button("+", width: 40); thumbStrip.addArrangedSubview(add); thumbStrip.orientation = .horizontal; thumbStrip.spacing = 8; thumbStrip.translatesAutoresizingMaskIntoConstraints = false
        status.stringValue = "3840 × 2560   JPEG   6.8 MB"; status.translatesAutoresizingMaskIntoConstraints = false
        let bottom = NSView(); bottom.wantsLayer = true; bottom.layer?.backgroundColor = Tone.chrome.cgColor; bottom.translatesAutoresizingMaskIntoConstraints = false; bottom.addSubview(thumbStrip); bottom.addSubview(status); NSLayoutConstraint.activate([thumbStrip.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 12), thumbStrip.centerYAnchor.constraint(equalTo: bottom.centerYAnchor), status.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -12), status.centerYAnchor.constraint(equalTo: bottom.centerYAnchor)])
        let work = NSStackView(views: [toolbar, middle, bottom]); work.orientation = NSUserInterfaceLayoutOrientation.vertical; work.spacing = 0; work.translatesAutoresizingMaskIntoConstraints = false; toolbar.heightAnchor.constraint(equalToConstant: 48).isActive = true; bottom.heightAnchor.constraint(equalToConstant: 86).isActive = true
        frame.body.addSubview(work); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), work.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), work.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), work.topAnchor.constraint(equalTo: frame.body.topAnchor), work.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor)])
        taskButton.target = self
    }
    required init?(coder: NSCoder) { fatalError() }
    private func makeInspector() -> NSView { let title = label("图片信息", font: Type.heading); let rows = [("名称", "ccf23759...jpg"), ("尺寸", "3840 × 2560"), ("格式", "JPEG · RGB"), ("大小", "6.8 MB"), ("来源", "rh-images.xiaoyaoyou.com/...")].map { row($0.0, $0.1) }; let widgetTitle = label("WIDGET", font: Type.tiny, color: Tone.muted); let column = stack([title, divider(), label("文件", font: Type.tiny, color: Tone.muted)] + rows + [widgetTitle, button("Remove Background"), button("Upscale")], spacing: 9); return column }
    private func row(_ key: String, _ value: String) -> NSView { let left = label(key, font: Type.small, color: Tone.muted); let right = label(value, font: Type.small, color: Tone.secondary); right.alignment = .right; let row = NSStackView(views: [left, right]); row.orientation = .horizontal; row.distribution = .fill; right.setContentHuggingPriority(.defaultHigh, for: .horizontal); return row }
    @objc private func runWidget() { runButton.title = "处理中"; taskButton.title = "任务 •"; status.stringValue = "1 个任务正在轮询 · 源图保持可查看"; DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.runButton.title = "运行 Remove BG"; self?.taskButton.title = "任务"; self?.status.stringValue = "3840 × 2560   JPEG   6.8 MB   ·   结果已插入右侧" } }
}

private final class VideoInspectScreen: NSView {
    init() {
        super.init(frame: .zero); let frame = WindowFrame(title: "Video Inspect"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame)
        let toolbar = stack([stack([button("×", width: 30), button("截取当前帧", width: 92)], axis: .horizontal, spacing: 6), NSSegmentedControl(labels: ["专注", "比较"], trackingMode: .selectOne, target: nil, action: nil), stack([button("W", width: 30)], axis: .horizontal)], axis: .horizontal, spacing: 8, distribution: .fillEqually); toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10); toolbar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let video = FrostedView(material: .underWindowBackground); let artwork = ArtworkView(frame: .zero); artwork.translatesAutoresizingMaskIntoConstraints = false; video.addSubview(artwork); let play = button("▶", width: 44); play.font = NSFont.systemFont(ofSize: 16); play.translatesAutoresizingMaskIntoConstraints = false; video.addSubview(play); NSLayoutConstraint.activate([artwork.centerXAnchor.constraint(equalTo: video.centerXAnchor), artwork.centerYAnchor.constraint(equalTo: video.centerYAnchor), artwork.widthAnchor.constraint(equalTo: video.widthAnchor, multiplier: 0.78), artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 0.56), play.centerXAnchor.constraint(equalTo: artwork.centerXAnchor), play.centerYAnchor.constraint(equalTo: artwork.centerYAnchor)])
        let info = FrostedView(); info.addSubview(stack([label("视频信息", font: Type.heading), divider(), row("尺寸", "3840 × 2160"), row("时长", "01:42"), row("编码", "H.265"), row("帧率", "30 fps"), row("音频", "AAC · 48 kHz")], spacing: 12)); let body = NSStackView(views: [video, info]); body.orientation = .horizontal; body.spacing = 0; info.widthAnchor.constraint(equalToConstant: 278).isActive = true; body.translatesAutoresizingMaskIntoConstraints = false
        let bottom = label("01:42     ━━━━━━━━━━━━━━━     空格 播放或暂停", font: Type.tiny, color: Tone.muted); bottom.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(toolbar); frame.body.addSubview(body); frame.body.addSubview(bottom); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), toolbar.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), toolbar.topAnchor.constraint(equalTo: frame.body.topAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), body.topAnchor.constraint(equalTo: toolbar.bottomAnchor), body.bottomAnchor.constraint(equalTo: bottom.topAnchor), bottom.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 12), bottom.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor, constant: -8), bottom.heightAnchor.constraint(equalToConstant: 18)])
    }
    required init?(coder: NSCoder) { fatalError() }
    private func row(_ key: String, _ value: String) -> NSView { let a = label(key, font: Type.small, color: Tone.muted); let b = label(value, font: Type.small, color: Tone.secondary); b.alignment = .right; let r = NSStackView(views: [a, b]); r.orientation = .horizontal; r.distribution = .fill; return r }
}

private final class DocumentScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "Content Viewer"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let code = label("# Widget Worker\n\n该文件进入内容查看器，不显示媒体方向、缩放和比较按钮。\n\n```python\ndef process(task):\n    return {\"status\": \"completed\"}\n```", font: Type.tiny, color: Tone.secondary); code.maximumNumberOfLines = 0; code.lineBreakMode = .byWordWrapping; let text = FrostedView(); text.addSubview(code); code.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([code.leadingAnchor.constraint(equalTo: text.leadingAnchor, constant: 22), code.trailingAnchor.constraint(equalTo: text.trailingAnchor, constant: -22), code.topAnchor.constraint(equalTo: text.topAnchor, constant: 22)]); let info = FrostedView(); let infoStack = stack([label("内容信息", font: Type.heading), divider(), row("类型", "Markdown"), row("编码", "UTF-8"), row("行数", "18"), label("右侧内容框固定 3:4", font: Type.small, color: Tone.muted)], spacing: 12); info.addSubview(infoStack); infoStack.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([infoStack.leadingAnchor.constraint(equalTo: info.leadingAnchor, constant: 18), infoStack.trailingAnchor.constraint(equalTo: info.trailingAnchor, constant: -18), infoStack.topAnchor.constraint(equalTo: info.topAnchor, constant: 18)]); let body = NSStackView(views: [text, info]); body.orientation = .horizontal; body.spacing = 0; info.widthAnchor.constraint(equalToConstant: 278).isActive = true; body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), body.topAnchor.constraint(equalTo: frame.body.topAnchor), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func row(_ key: String, _ value: String) -> NSView { let a = label(key, font: Type.small, color: Tone.muted); let b = label(value, font: Type.small, color: Tone.secondary); b.alignment = .right; let r = NSStackView(views: [a, b]); r.orientation = .horizontal; return r }
}

private final class QuickPreviewScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "Glance Preview"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let grid = NSGridView(views: [[tile("input.png"), tile("portrait.jpg")], [tile("README.md"), tile("clip.mov")]]); grid.rowSpacing = 8; grid.columnSpacing = 8; grid.translatesAutoresizingMaskIntoConstraints = false; let text = label("当前选择\n\n/Users/mac/Desktop/project/input.png\nhttps://temp.himarts.com/result.png\nREADME.md\nclip.mov\n\n检测到 2 张图片、1 个视频和 1 个文档。\n\n按 Return 打开检查工作台。", font: Type.small, color: Tone.secondary); text.maximumNumberOfLines = 0; let info = FrostedView(); info.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: info.leadingAnchor, constant: 18), text.trailingAnchor.constraint(equalTo: info.trailingAnchor, constant: -18), text.topAnchor.constraint(equalTo: info.topAnchor, constant: 20)]); let body = NSStackView(views: [grid, info]); body.orientation = .horizontal; body.spacing = 12; info.widthAnchor.constraint(equalToConstant: 320).isActive = true; body.translatesAutoresizingMaskIntoConstraints = false; let actions = stack([label("4 个项目 · 混合内容", font: Type.tiny, color: Tone.muted), button("打开所选内容", primary: true, width: 110)], axis: .horizontal, spacing: 10); actions.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12); actions.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); frame.body.addSubview(actions); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 14), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor, constant: -14), body.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 14), body.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -14), actions.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), actions.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), actions.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor), actions.heightAnchor.constraint(equalToConstant: 52)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func tile(_ text: String) -> NSView { let item = FrostedView(); let art = ArtworkView(frame: .zero); art.translatesAutoresizingMaskIntoConstraints = false; item.addSubview(art); let name = label(text, font: Type.tiny, color: Tone.text); name.translatesAutoresizingMaskIntoConstraints = false; item.addSubview(name); NSLayoutConstraint.activate([art.leadingAnchor.constraint(equalTo: item.leadingAnchor), art.trailingAnchor.constraint(equalTo: item.trailingAnchor), art.topAnchor.constraint(equalTo: item.topAnchor), art.bottomAnchor.constraint(equalTo: item.bottomAnchor), name.leadingAnchor.constraint(equalTo: item.leadingAnchor, constant: 9), name.bottomAnchor.constraint(equalTo: item.bottomAnchor, constant: -8)]); return item }
}

private final class TaskCenterScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "任务中心"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let list = FrostedView(); let rows = [("Remove Background", "处理中", Tone.accent), ("Upscale 2×", "已完成", Tone.success), ("Image Caption", "失败", Tone.danger)].map { taskRow($0.0, $0.1, $0.2) }; let listStack = stack([label("任务", font: Type.heading), label("本机提交和正在轮询的 Widget 任务", font: Type.tiny, color: Tone.muted), divider()] + rows, spacing: 10); list.addSubview(listStack); listStack.translatesAutoresizingMaskIntoConstraints = false; let detail = FrostedView(); let detailStack = stack([label("Remove Background", font: Type.heading), label("任务 81C4 · 处理中", font: Type.small, color: Tone.secondary), divider(), stack([preview("源图"), preview("等待结果")], axis: .horizontal, spacing: 10), label("任务已提交       14:32:06\nWorker 已领取     14:32:08\n正在处理         现在\n等待结果回传", font: Type.small, color: Tone.secondary)], spacing: 14); detail.addSubview(detailStack); detailStack.translatesAutoresizingMaskIntoConstraints = false; list.widthAnchor.constraint(equalToConstant: 312).isActive = true; let body = NSStackView(views: [list, detail]); body.orientation = .horizontal; body.spacing = 0; body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor), body.topAnchor.constraint(equalTo: frame.body.topAnchor), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor), listStack.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 14), listStack.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -14), listStack.topAnchor.constraint(equalTo: list.topAnchor, constant: 16), detailStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 20), detailStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -20), detailStack.topAnchor.constraint(equalTo: detail.topAnchor, constant: 18)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func taskRow(_ name: String, _ state: String, _ color: NSColor) -> NSView { let a = label(name, font: Type.small); let b = label(state, font: Type.tiny, color: color); let r = NSStackView(views: [a, b]); r.orientation = .horizontal; r.distribution = .fill; b.setContentHuggingPriority(.required, for: .horizontal); return r }
    private func preview(_ title: String) -> NSView { let view = FrostedView(); let art = ArtworkView(frame: .zero); art.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(art); let text = label(title, font: Type.tiny, color: Tone.secondary); text.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(text); NSLayoutConstraint.activate([art.leadingAnchor.constraint(equalTo: view.leadingAnchor), art.trailingAnchor.constraint(equalTo: view.trailingAnchor), art.topAnchor.constraint(equalTo: view.topAnchor), art.heightAnchor.constraint(equalToConstant: 130), text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9), text.topAnchor.constraint(equalTo: art.bottomAnchor, constant: 8), view.bottomAnchor.constraint(equalTo: text.bottomAnchor, constant: 10)]); return view }
}

private final class MarketScreen: NSView {
    private let install = button("卸载", width: 82)
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "Widget Market"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let cards = [widget("R", "Remove Background", "已安装"), widget("2×", "Upscale 2×", "云端"), widget("C", "Image Caption", "已安装"), widget("B", "Base64 Toolkit", "云端")]; let grid = NSGridView(views: [[cards[0], cards[1]], [cards[2], cards[3]]]); grid.rowSpacing = 10; grid.columnSpacing = 10; grid.translatesAutoresizingMaskIntoConstraints = false; let left = stack([stack([label("Widget Market", font: Type.heading), button("⌕ 搜索", width: 92)], axis: .horizontal, spacing: 8), grid], spacing: 16); let detail = FrostedView(); let detailStack = stack([label("R", font: NSFont.systemFont(ofSize: 24, weight: .bold), color: Tone.accent), label("Remove Background", font: Type.title), label("已安装", font: Type.tiny, color: Tone.success), divider(), label("自动抠出主体并生成透明背景 PNG。任务完成后，结果会插入源图右侧。", font: Type.small, color: Tone.secondary), label("支持 PNG 和 JPEG\n单 command 直接显示在一级菜单", font: Type.small, color: Tone.muted), install], spacing: 14); detail.addSubview(detailStack); detailStack.translatesAutoresizingMaskIntoConstraints = false; install.target = self; install.action = #selector(toggleInstall); detail.widthAnchor.constraint(equalToConstant: 340).isActive = true; let body = NSStackView(views: [left, detail]); body.orientation = .horizontal; body.spacing = 16; body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 18), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor, constant: -18), body.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 18), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor, constant: -18), detailStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 20), detailStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -20), detailStack.topAnchor.constraint(equalTo: detail.topAnchor, constant: 20)]) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func toggleInstall() { install.title = install.title == "卸载" ? "安装" : "卸载" }
    private func widget(_ icon: String, _ title: String, _ status: String) -> NSView { let card = FrostedView(); let top = stack([label(icon, font: Type.heading, color: Tone.accent), label(status, font: Type.tiny, color: status == "已安装" ? Tone.success : Tone.accent)], axis: .horizontal, spacing: 8); let content = stack([top, label(title, font: Type.heading), label("云端处理，结果回到当前工作台", font: Type.tiny, color: Tone.muted)], spacing: 9); card.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)]); return card }
}

private final class WebStateScreen: NSView {
    private let content = NSStackView(); init() { super.init(frame: .zero); let frame = WindowFrame(title: "Widget Result"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let tabs = NSSegmentedControl(labels: ["加载", "完成", "错误"], trackingMode: .selectOne, target: nil, action: nil); tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(changeState); tabs.translatesAutoresizingMaskIntoConstraints = false; content.orientation = .vertical; content.alignment = .centerX; content.spacing = 12; content.translatesAutoresizingMaskIntoConstraints = false; content.addArrangedSubview(label("◌", font: NSFont.systemFont(ofSize: 38), color: Tone.accent)); content.addArrangedSubview(label("正在打开 Widget", font: Type.title)); content.addArrangedSubview(label("透明深色磨砂容器，复用项目现有 Loading。", font: Type.small, color: Tone.secondary)); let card = FrostedView(); card.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([content.centerXAnchor.constraint(equalTo: card.centerXAnchor), content.centerYAnchor.constraint(equalTo: card.centerYAnchor), content.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: -50)]); frame.body.addSubview(tabs); frame.body.addSubview(card); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), tabs.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 18), tabs.centerXAnchor.constraint(equalTo: frame.body.centerXAnchor), card.centerXAnchor.constraint(equalTo: frame.body.centerXAnchor), card.centerYAnchor.constraint(equalTo: frame.body.centerYAnchor, constant: 16), card.widthAnchor.constraint(equalToConstant: 500), card.heightAnchor.constraint(equalToConstant: 310)]) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func changeState(_ sender: NSSegmentedControl) { content.arrangedSubviews.forEach { $0.removeFromSuperview() }; let states = [("◌", "正在打开 Widget", "透明深色磨砂容器，复用项目现有 Loading。", Tone.accent), ("✓", "处理完成", "结果已加入图片检查工作台，位于源图右侧。", Tone.success), ("!", "Widget 无法加载", "网络请求超时。可以重新加载，当前输入不会丢失。", Tone.danger)]; let state = states[sender.selectedSegment]; content.addArrangedSubview(label(state.0, font: NSFont.systemFont(ofSize: 38), color: state.3)); content.addArrangedSubview(label(state.1, font: Type.title)); content.addArrangedSubview(label(state.2, font: Type.small, color: Tone.secondary)); if sender.selectedSegment > 0 { content.addArrangedSubview(button(sender.selectedSegment == 1 ? "查看结果" : "重新加载", primary: sender.selectedSegment == 1, width: 100)) } }
}

private final class Base64Screen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "Base64 Toolkit"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let title = label("Base64 转图片", font: Type.title); let hint = label("粘贴完整 Data URL 或纯 Base64 字符串。", font: Type.small, color: Tone.secondary); let area = NSTextView(); area.font = Type.tiny; area.textColor = Tone.text; area.backgroundColor = Tone.background; area.string = "data:image/png;base64,..."; area.wantsLayer = true; area.layer?.cornerRadius = 8; area.layer?.borderColor = Tone.line.cgColor; area.layer?.borderWidth = 1; let scroll = NSScrollView(); scroll.documentView = area; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false; let main = stack([title, hint, label("Base64 内容", font: Type.tiny, color: Tone.muted), scroll, stack([label("支持 PNG、JPEG、WebP 和 GIF", font: Type.tiny, color: Tone.muted), button("解码并显示", primary: true, width: 110)], axis: .horizontal, spacing: 8)], spacing: 10); let result = FrostedView(); result.addSubview(stack([label("结果预览", font: Type.heading), label("等待输入", font: Type.small, color: Tone.muted)], spacing: 14)); let body = NSStackView(views: [main, result]); body.orientation = .horizontal; body.spacing = 16; result.widthAnchor.constraint(equalToConstant: 300).isActive = true; body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 22), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor, constant: -22), body.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 22), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor, constant: -22), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250)]) }
    required init?(coder: NSCoder) { fatalError() }
}

private final class HistoryScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "预览历史"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let header = stack([stack([label("今天", font: Type.heading), label("8 个项目", font: Type.tiny, color: Tone.muted)], spacing: 4), button("⌕ 搜索", width: 88)], axis: .horizontal, spacing: 10); let grid = NSGridView(views: stride(from: 0, to: 8, by: 2).map { _ in [historyTile(), historyTile()] }); grid.rowSpacing = 10; grid.columnSpacing = 10; grid.translatesAutoresizingMaskIntoConstraints = false; let body = stack([header, grid], spacing: 16); body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 18), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor, constant: -18), body.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 18), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor, constant: -18)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func historyTile() -> NSView { let view = ArtworkView(frame: .zero); view.heightAnchor.constraint(equalToConstant: 130).isActive = true; return view }
}

private final class PreferencesScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "Glance 偏好设置"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let nav = FrostedView(); nav.widthAnchor.constraint(equalToConstant: 190).isActive = true; let navStack = stack([label("通用", font: Type.heading, color: Tone.accent), label("预览", font: Type.small, color: Tone.secondary), label("Widget", font: Type.small, color: Tone.secondary), label("隐私与权限", font: Type.small, color: Tone.secondary)], spacing: 16); nav.addSubview(navStack); navStack.translatesAutoresizingMaskIntoConstraints = false; let rows = [setting("登录时启动 Glance", "登录 macOS 后保持菜单栏可用"), setting("记住上次窗口位置", "在多显示器之间恢复工作台位置"), setting("界面语言", "简体中文"), setting("优先读取复制的图片", "同一剪贴板包含图片和 URL 时使用图片")]; let detail = stack([label("通用", font: Type.title), label("控制 Glance 的启动、语言和常用行为。", font: Type.small, color: Tone.secondary), divider()] + rows, spacing: 16); let body = NSStackView(views: [nav, detail]); body.orientation = .horizontal; body.spacing = 18; body.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(body); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), body.leadingAnchor.constraint(equalTo: frame.body.leadingAnchor, constant: 18), body.trailingAnchor.constraint(equalTo: frame.body.trailingAnchor, constant: -28), body.topAnchor.constraint(equalTo: frame.body.topAnchor, constant: 22), body.bottomAnchor.constraint(equalTo: frame.body.bottomAnchor, constant: -22), navStack.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 14), navStack.topAnchor.constraint(equalTo: nav.topAnchor, constant: 16)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func setting(_ title: String, _ detail: String) -> NSView { let a = stack([label(title, font: Type.small), label(detail, font: Type.tiny, color: Tone.muted)], spacing: 4); let toggle = button("●", width: 34); let row = NSStackView(views: [a, toggle]); row.orientation = .horizontal; row.distribution = .fill; toggle.setContentHuggingPriority(.required, for: .horizontal); return row }
}

private final class OnboardingScreen: NSView {
    init() { super.init(frame: .zero); let frame = WindowFrame(title: "欢迎使用 Glance"); frame.translatesAutoresizingMaskIntoConstraints = false; addSubview(frame); let title = label("先完成必要权限", font: Type.title); let desc = label("Glance 需要读取当前选择内容并响应快捷键。权限可以稍后修改。", font: Type.small, color: Tone.secondary); desc.maximumNumberOfLines = 2; let permissions = [permission("辅助功能", "读取当前选区并响应快捷键", "已允许"), permission("输入监听", "识别全局快捷键", "打开设置"), permission("完全磁盘访问", "预览受保护位置中的文件", "可选")]; let column = stack([label("GLANCE", font: Type.tiny, color: Tone.accent), title, desc] + permissions + [button("继续", primary: true)], spacing: 14); column.alignment = .centerX; column.translatesAutoresizingMaskIntoConstraints = false; frame.body.addSubview(column); NSLayoutConstraint.activate([frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor), frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(equalTo: bottomAnchor), column.centerXAnchor.constraint(equalTo: frame.body.centerXAnchor), column.centerYAnchor.constraint(equalTo: frame.body.centerYAnchor), column.widthAnchor.constraint(equalToConstant: 430)]) }
    required init?(coder: NSCoder) { fatalError() }
    private func permission(_ title: String, _ detail: String, _ action: String) -> NSView { let text = stack([label(title, font: Type.small), label(detail, font: Type.tiny, color: Tone.muted)], spacing: 3); let action = label(action, font: Type.tiny, color: action == "已允许" ? Tone.success : Tone.accent); let row = NSStackView(views: [label("•", font: Type.heading, color: Tone.accent), text, action]); row.orientation = .horizontal; row.spacing = 10; return row }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let root = PreviewRootView(frame: .zero)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Glance Native UI Preview"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = root
        window.center(); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)

    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
