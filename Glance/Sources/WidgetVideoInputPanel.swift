import AppKit
import UniformTypeIdentifiers

/// Collects an optional prompt and up to four ordered video inputs.
final class WidgetVideoInputPanel: NSPanel {
    var onSubmit: ((WidgetTaskInput) -> Void)?
    var onDismiss: (() -> Void)?

    private let capabilities: WidgetInputCapabilities
    private var mediaURLs: [URL]
    private var restoredFrame: NSRect?
    private let designSize = NSSize(width: 760, height: 600)
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: 16)
    private let videoList = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private let promptView = NSTextView()
    private let promptPlaceholder = NSTextField(labelWithString: "Describe what the Widget should do…".localized)
    private let addButton = PanelButton(title: "Add video".localized, target: nil, action: nil)

    init(widgetName: String, sourceURL: URL, capabilities: WidgetInputCapabilities) {
        self.capabilities = capabilities
        mediaURLs = [sourceURL]
        super.init(contentRect: NSRect(origin: .zero, size: designSize),
                   styleMask: [.borderless, .closable, .miniaturizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI(widgetName: widgetName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func buildUI(widgetName: String) {
        let container = NSView(frame: NSRect(origin: .zero, size: designSize))
        contentView = container
        designRoot.frame = container.bounds
        designRoot.layer?.masksToBounds = true
        designRoot.layer?.borderWidth = 1
        designRoot.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        container.addSubview(designRoot)

        let titlebar = NSView(frame: NSRect(x: 0, y: 552, width: 760, height: 48))
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        designRoot.addSubview(titlebar)
        for (x, color, action) in [
            (24.0, NSColor(srgbRed: 237/255, green: 106/255, blue: 94/255, alpha: 1), #selector(cancelTapped)),
            (44.0, NSColor(srgbRed: 244/255, green: 191/255, blue: 79/255, alpha: 1), #selector(minimizeTapped)),
            (64.0, NSColor(srgbRed: 97/255, green: 197/255, blue: 84/255, alpha: 1), #selector(zoomTapped))
        ] {
            let button = NSButton(frame: NSRect(x: x - 6, y: 12, width: 24, height: 24))
            button.isBordered = false
            button.wantsLayer = true
            let dot = CALayer()
            dot.frame = NSRect(x: 6, y: 6, width: 12, height: 12)
            dot.backgroundColor = color.cgColor
            dot.cornerRadius = 6
            button.layer?.addSublayer(dot)
            button.target = self
            button.action = action
            titlebar.addSubview(button)
        }
        let windowTitle = label("Widget · \(widgetName)", size: 14, weight: .semibold)
        windowTitle.alignment = .center
        windowTitle.frame = NSRect(x: 100, y: 15, width: 560, height: 18)
        titlebar.addSubview(windowTitle)

        let headingText = capabilities.maxVideos > 1
            ? (capabilities.acceptsPrompt ? "Videos and prompt" : "Videos")
            : (capabilities.acceptsPrompt ? "Video and prompt" : "Video")
        let heading = label(headingText.localized, size: 24, weight: .semibold)
        heading.frame = NSRect(x: 32, y: 497, width: 696, height: 30)
        designRoot.addSubview(heading)
        let help = label((capabilities.maxVideos > 1
                          ? "Use up to four videos. The first video is the base."
                          : "Select the video to process.").localized,
                         size: 12, color: PanelStyle.textSecondary)
        help.frame = NSRect(x: 32, y: 474, width: 696, height: 18)
        designRoot.addSubview(help)

        videoList.frame = NSRect(x: 32, y: 255, width: 696, height: 205)
        videoList.wantsLayer = true
        videoList.layer?.cornerRadius = 9
        videoList.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        videoList.layer?.borderWidth = 1
        videoList.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        designRoot.addSubview(videoList)
        countLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        countLabel.textColor = PanelStyle.textSecondary
        countLabel.alignment = .right
        countLabel.frame = NSRect(x: 600, y: 224, width: 128, height: 18)
        designRoot.addSubview(countLabel)
        configureButton(addButton, title: "Add video".localized,
                        frame: NSRect(x: 32, y: 212, width: 148, height: 34),
                        action: #selector(addVideoTapped))
        designRoot.addSubview(addButton)

        let promptLabel = label("PROMPT", size: 11, weight: .semibold,
                                color: capabilities.acceptsPrompt
                                    ? PanelStyle.textSecondary : PanelStyle.textTertiary)
        promptLabel.frame = NSRect(x: 32, y: 185, width: 696, height: 15)
        designRoot.addSubview(promptLabel)
        let promptFrame = NSView(frame: NSRect(x: 32, y: 83, width: 696, height: 94))
        promptFrame.wantsLayer = true
        promptFrame.layer?.cornerRadius = 9
        promptFrame.layer?.backgroundColor = PanelStyle.resolvedCG(
            capabilities.acceptsPrompt ? PanelStyle.inspectCanvas : PanelStyle.inspectChrome)
        promptFrame.layer?.borderWidth = 1
        promptFrame.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        designRoot.addSubview(promptFrame)
        if capabilities.acceptsPrompt {
            let scroll = NSScrollView(frame: promptFrame.bounds.insetBy(dx: 14, dy: 10))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .noBorder
            promptView.frame = scroll.contentView.bounds
            promptView.isVerticallyResizable = true
            promptView.isHorizontallyResizable = false
            promptView.autoresizingMask = [.width]
            promptView.textContainer?.widthTracksTextView = true
            promptView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                             height: CGFloat.greatestFiniteMagnitude)
            promptView.font = PanelStyle.inspectFont(ofSize: 13)
            promptView.textColor = PanelStyle.textPrimary
            promptView.isRichText = false
            promptView.drawsBackground = false
            scroll.documentView = promptView
            promptFrame.addSubview(scroll)
            promptPlaceholder.font = PanelStyle.inspectFont(ofSize: 13)
            promptPlaceholder.textColor = PanelStyle.textTertiary
            promptPlaceholder.frame = NSRect(x: 17, y: 61, width: 650, height: 18)
            promptFrame.addSubview(promptPlaceholder)
            NotificationCenter.default.addObserver(self, selector: #selector(promptChanged),
                name: NSText.didChangeNotification, object: promptView)
        } else {
            let disabled = label("Prompt unavailable for this Widget".localized,
                                 size: 13, color: PanelStyle.textTertiary)
            disabled.frame = NSRect(x: 17, y: 61, width: 650, height: 18)
            promptFrame.addSubview(disabled)
        }

        designRoot.addSubview(button("Cancel".localized,
            frame: NSRect(x: 394, y: 28, width: 140, height: 36), action: #selector(cancelTapped)))
        let run = button("Run Widget".localized,
            frame: NSRect(x: 546, y: 28, width: 182, height: 36), action: #selector(runTapped))
        run.normalBackground = PanelStyle.accent
        run.hoverBackground = PanelStyle.accentHover
        run.titleColor = PanelStyle.accentInk
        run.layer?.borderWidth = 0
        designRoot.addSubview(run)
        renderVideos()
    }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = PanelStyle.textPrimary) -> NSTextField {
        let view = NSTextField(labelWithString: value)
        view.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        view.textColor = color
        view.lineBreakMode = .byTruncatingMiddle
        return view
    }

    private func configureButton(_ button: PanelButton, title: String,
                                 frame: NSRect, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.normalBackground = PanelStyle.inspectToolbar
        button.hoverBackground = PanelStyle.inspectLine
        button.titleColor = PanelStyle.textPrimary
        button.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        button.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        button.frame = frame
    }

    private func button(_ title: String, frame: NSRect, action: Selector) -> PanelButton {
        let view = PanelButton(title: title, target: self, action: action)
        configureButton(view, title: title, frame: frame, action: action)
        return view
    }

    private func renderVideos() {
        videoList.subviews.forEach { $0.removeFromSuperview() }
        for (index, url) in mediaURLs.enumerated() {
            let y = CGFloat(154 - index * 47)
            let row = NSView(frame: NSRect(x: 12, y: y, width: 672, height: 40))
            row.wantsLayer = true
            row.layer?.cornerRadius = 7
            row.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
            videoList.addSubview(row)
            let number = label(index == 0 ? "BASE" : "\(index + 1)", size: 11,
                               weight: .semibold, color: PanelStyle.accent)
            number.frame = NSRect(x: 12, y: 12, width: 46, height: 15)
            row.addSubview(number)
            let name = label(url.lastPathComponent, size: 12)
            name.frame = NSRect(x: 62, y: 11, width: 546, height: 18)
            row.addSubview(name)
            if index > 0 {
                let remove = button("×", frame: NSRect(x: 625, y: 4, width: 36, height: 32),
                                    action: #selector(removeVideoTapped(_:)))
                remove.tag = index
                row.addSubview(remove)
            }
        }
        countLabel.stringValue = "\(mediaURLs.count) / \(capabilities.maxVideos)"
        addButton.isHidden = capabilities.maxVideos == 1
        addButton.isEnabled = mediaURLs.count < capabilities.maxVideos
    }

    func present(over parentWindow: NSWindow) {
        setFrame(ScreenManager.shared.contentFrame(for: designSize), display: true)
        fitDesignRoot()
        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    private func fitDesignRoot() {
        let available = contentView?.bounds.size ?? designSize
        let scale = min(available.width / designSize.width, available.height / designSize.height)
        designRoot.frame = NSRect(x: (available.width - designSize.width * scale) / 2,
                                  y: (available.height - designSize.height * scale) / 2,
                                  width: designSize.width * scale,
                                  height: designSize.height * scale)
        designRoot.bounds = NSRect(origin: .zero, size: designSize)
    }

    override func close() {
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        orderOut(nil)
        let callback = onDismiss
        onDismiss = nil
        onSubmit = nil
        callback?()
    }

    @objc private func promptChanged() {
        promptPlaceholder.isHidden = !promptView.string.isEmpty
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
                                        ? promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
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
