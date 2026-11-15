import AppKit
import UniformTypeIdentifiers

/// Collects an optional prompt and up to four ordered video inputs, on the
/// Shizuka input board (see `WidgetInputStyle`): the videos on the stage, the
/// prompt and actions in the form.
final class WidgetVideoInputPanel: NSPanel {
    var onSubmit: ((WidgetTaskInput) -> Void)?
    var onDismiss: (() -> Void)?

    private let capabilities: WidgetInputCapabilities
    private let costText: String?
    private var mediaURLs: [URL]
    private var restoredFrame: NSRect?
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: PanelStyle.Radius.window)
    private var videoList = NSView()
    private let countLabel = WidgetInputTextView(frame: .zero)
    private var promptField: WidgetPromptField?
    private let addButton = WidgetInputStyle.button("Add video".localized, primary: false, target: nil, action: nil)

    /// `costText` is the Widget's configured price as the catalog states it
    /// (for example `creditCostLabel`); the Cost row is shown only when given.
    init(widgetName: String, sourceURL: URL, capabilities: WidgetInputCapabilities, costText: String? = nil) {
        self.capabilities = capabilities
        self.costText = costText
        mediaURLs = [sourceURL]
        super.init(contentRect: NSRect(origin: .zero, size: WidgetInputStyle.board),
                   styleMask: [.borderless, .closable, .miniaturizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI(widgetName: widgetName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func buildUI(widgetName: String) {
        let container = NSView(frame: NSRect(origin: .zero, size: WidgetInputStyle.board))
        contentView = container
        let root = designRoot
        root.frame = container.bounds
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(WidgetInputStyle.lineStrong)
        container.addSubview(root)
        videoList = WidgetInputStyle.buildChrome(in: root, title: widgetName, target: self,
                                                 close: #selector(cancelTapped),
                                                 minimize: #selector(minimizeTapped),
                                                 zoom: #selector(zoomTapped))

        var kinds = [(capabilities.maxVideos > 1 ? "Videos" : "Video").localized]
        if capabilities.acceptsPrompt { kinds.append("Prompt".localized) }
        WidgetInputStyle.addHeader(to: root, eyebrow: "\("Widget".localized)  ·  \(kinds.joined(separator: " + "))",
                                   title: widgetName,
                                   description: (capabilities.maxVideos > 1
                                                 ? "Use up to four videos. The first video is the base."
                                                 : "Select the video to process.").localized)

        WidgetInputStyle.addSectionLabel(to: root, "Prompt".localized, y: 232)
        let field = WidgetPromptField(frame: WidgetInputStyle.frame(WidgetInputStyle.formX, 255,
                                                                    WidgetInputStyle.formWidth, 148),
                                      enabled: capabilities.acceptsPrompt)
        root.addSubview(field)
        promptField = field
        if let costText { WidgetInputStyle.addCostRow(to: root, cost: costText, y: 720) }

        addButton.target = self
        addButton.action = #selector(addVideoTapped)
        let run = WidgetInputStyle.button("Run Widget".localized, primary: true,
                                          target: self, action: #selector(runTapped))
        WidgetInputStyle.addActions(to: root,
                                    cancel: WidgetInputStyle.button("Cancel".localized, primary: false,
                                                                    target: self, action: #selector(cancelTapped)),
                                    run: run, runTitle: "Run Widget".localized)
        renderVideos()
    }

    /// Stage list: 48 pt rows across the board image column (x 120, 760 wide)
    /// from y 116, each with its order, file name and a hairline; "Add video"
    /// and the count follow the last row.
    private func renderVideos() {
        videoList.subviews.forEach { $0.removeFromSuperview() }
        let stage = WidgetInputStyle.stage
        func stageFrame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            WidgetInputStyle.frame(x, y - stage.minY, width, height, in: stage.height)
        }
        var y: CGFloat = 116
        for (index, url) in mediaURLs.enumerated() {
            videoList.addSubview(WidgetInputStyle.text("\(index + 1)", font: PanelStyle.monoFont(ofSize: 11),
                                                       color: PanelStyle.textTertiary, frame: stageFrame(120, y + 17, 20, 14)))
            let trailing: CGFloat = index > 0 ? 40 : 0
            let name = WidgetInputStyle.text(url.lastPathComponent, font: PanelStyle.inspectFont(ofSize: 13),
                                             color: PanelStyle.textPrimary,
                                             frame: stageFrame(148, y + 16, 760 - 28 - 60 - trailing, 16))
            name.lineBreakMode = .byTruncatingMiddle
            name.toolTip = url.lastPathComponent
            videoList.addSubview(name)
            if index == 0 {
                let base = WidgetInputStyle.text("Base".localized, font: PanelStyle.inspectFont(ofSize: 11),
                                                 color: PanelStyle.textTertiary, frame: stageFrame(820, y + 17, 60, 13))
                base.alignment = .right
                videoList.addSubview(base)
            } else {
                let remove = WidgetInputStyle.button("×", primary: false, target: self,
                                                     action: #selector(removeVideoTapped(_:)))
                remove.setAccessibilityLabel("Remove".localized)
                remove.toolTip = "Remove".localized
                remove.tag = index
                remove.frame = stageFrame(852, y + 10, 28, 28)
                videoList.addSubview(remove)
            }
            let rule = NSView(frame: stageFrame(120, y + 47, 760, 1))
            rule.wantsLayer = true
            rule.layer?.backgroundColor = PanelStyle.resolvedCG(WidgetInputStyle.line)
            videoList.addSubview(rule)
            y += 48
        }
        addButton.frame = stageFrame(120, y + 16, WidgetInputStyle.buttonWidth("Add video".localized), 32)
        addButton.isHidden = capabilities.maxVideos == 1
        addButton.isEnabled = mediaURLs.count < capabilities.maxVideos
        videoList.addSubview(addButton)
        countLabel.string = "\(mediaURLs.count) / \(capabilities.maxVideos)"
        countLabel.font = PanelStyle.monoFont(ofSize: 11)
        countLabel.textColor = PanelStyle.textTertiary
        countLabel.alignment = .right
        countLabel.frame = stageFrame(680, y + 25, 200, 14)
        videoList.addSubview(countLabel)
    }

    func present(over parentWindow: NSWindow) {
        setFrame(ScreenManager.shared.contentFrame(for: WidgetInputStyle.board), display: true)
        fitDesignRoot()
        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    private func fitDesignRoot() { WidgetInputStyle.fit(designRoot, in: contentView) }

    override func close() {
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        orderOut(nil)
        let callback = onDismiss
        onDismiss = nil
        onSubmit = nil
        callback?()
    }

    @objc private func addVideoTapped() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.movie]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self else { return }
            let available = self.capabilities.maxVideos - self.mediaURLs.count
            let additions = picker.urls.filter { !self.mediaURLs.contains($0) }
            self.mediaURLs.append(contentsOf: additions.prefix(max(0, available)))
            self.renderVideos()
        }
    }

    @objc private func removeVideoTapped(_ sender: NSButton) {
        guard mediaURLs.indices.contains(sender.tag), sender.tag > 0 else { return }
        mediaURLs.remove(at: sender.tag)
        renderVideos()
    }

    @objc private func runTapped() {
        let input = WidgetTaskInput(mediaURLs: mediaURLs,
                                    prompt: capabilities.acceptsPrompt
                                        ? (promptField?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                        : nil,
                                    maskURL: nil,
                                    usesMultipleVideos: capabilities.maxVideos > 1)
        let submit = onSubmit
        close()
        submit?(input)
    }

    @objc private func cancelTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() {
        if let restoredFrame {
            setFrame(restoredFrame, display: true)
            self.restoredFrame = nil
        } else if let screen = screen ?? NSScreen.main {
            restoredFrame = frame
            setFrame(screen.visibleFrame, display: true)
        }
        fitDesignRoot()
    }
}
