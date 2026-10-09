import AppKit
import UniformTypeIdentifiers

/// The three Figma Widget Input layouts share one data model and one submission path.
/// The selected image is always the first image sent to the Worker.
final class WidgetInputPanel: NSPanel, NSTextViewDelegate {
    var onSubmit: ((WidgetTaskInput) -> Void)?
    var onDismiss: (() -> Void)?

    private enum Layout {
        case imageText, imageMask, multipleImages

        var width: CGFloat {
            switch self {
            case .imageText: 854
            case .imageMask: 1054
            case .multipleImages: 1066
            }
        }
    }

    private let capabilities: WidgetInputCapabilities
    private let layout: Layout
    private let initialURL: URL
    private let initialImage: NSImage?
    private var mediaURLs: [URL]
    private var maskURL: URL?
    private var maskEditor: WidgetMaskEditorPanel?
    private var restoredFrame: NSRect?
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: 16)
    private let body = NSView()
    private let imageSection = NSView()
    private let promptField = NSView()
    private let promptView = NSTextView()
    private let promptPlaceholder = NSTextField(labelWithString: "Describe what the Widget should do…".localized)
    private let maskStatus = NSTextField(labelWithString: "No mask selected".localized)
    private let maskPreview = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let runButton = PanelButton(title: "Run Widget".localized, target: nil, action: nil)

    init(widgetName: String, sourceURL: URL, sourceImage: NSImage?,
         capabilities: WidgetInputCapabilities) {
        self.capabilities = capabilities
        self.initialURL = sourceURL
        self.initialImage = sourceImage
        self.mediaURLs = [sourceURL]
        layout = capabilities.maxImages > 1 ? .multipleImages
            : capabilities.acceptsMask ? .imageMask : .imageText
        let size = NSSize(width: layout.width, height: 788)
        super.init(contentRect: NSRect(origin: .zero, size: size),
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
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = container
        let frost = designRoot
        frost.frame = container.bounds
        frost.layer?.masksToBounds = true
        frost.layer?.borderWidth = 1
        frost.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        container.addSubview(frost)

        let titlebar = NSView(frame: NSRect(x: 0, y: 740, width: layout.width, height: 48))
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        frost.addSubview(titlebar)
        addTrafficLight(to: titlebar, x: 24, color: NSColor(srgbRed: 237/255, green: 106/255, blue: 94/255, alpha: 1), action: #selector(cancelTapped))
        addTrafficLight(to: titlebar, x: 44, color: NSColor(srgbRed: 244/255, green: 191/255, blue: 79/255, alpha: 1), action: #selector(minimizeTapped))
        addTrafficLight(to: titlebar, x: 64, color: NSColor(srgbRed: 97/255, green: 197/255, blue: 84/255, alpha: 1), action: #selector(zoomTapped))
        let windowTitle = label("Widget · \(widgetName)", size: 14, weight: .semibold,
                                color: PanelStyle.textPrimary)
        windowTitle.alignment = .center
        windowTitle.frame = NSRect(x: 100, y: 15, width: layout.width - 200, height: 18)
        titlebar.addSubview(windowTitle)

        body.frame = NSRect(x: 0, y: 0, width: layout.width, height: 740)
        body.wantsLayer = true
        body.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        frost.addSubview(body)
        let title = label(layout == .multipleImages
                          ? (capabilities.acceptsPrompt ? "Images and prompt" : "Images").localized
                          : layout == .imageMask
                          ? (capabilities.acceptsPrompt ? "Image, prompt and mask" : "Image and mask").localized
                          : "Image and prompt".localized,
                          size: 24, weight: .semibold, color: PanelStyle.textPrimary)
        title.frame = NSRect(x: 32, y: 677, width: layout.width - 64, height: 30)
        body.addSubview(title)
        let subtitle = label(layout == .multipleImages
                             ? (capabilities.minImages == 2 && capabilities.maxImages == 2
                                ? "Use two images. The first image is the base.".localized
                                : "Use up to four images. The first image is the base.".localized)
                             : layout == .imageMask
                             ? (capabilities.acceptsPrompt
                                ? "Choose the image, describe the edit, then add a mask."
                                : "Choose an image, then mark the area to change.").localized
                             : "The prompt tells the Widget what to make or change.".localized,
                             size: 12, color: PanelStyle.textSecondary)
        subtitle.frame = NSRect(x: 32, y: 660, width: layout.width - 64, height: 16)
        body.addSubview(subtitle)
        divider(x: 32, y: 645, width: layout.width - 64, in: body)

        imageSection.frame = NSRect(x: 0, y: 0, width: layout.width, height: 645)
        body.addSubview(imageSection)
        renderImages()

        switch layout {
        case .imageText:
            configurePrompt(x: 32, labelY: 228, width: 790, fieldY: 102, height: 117)
        case .imageMask:
            configurePrompt(x: 526, labelY: 608, width: 496, fieldY: 459, height: 145)
            configureMask()
        case .multipleImages:
            configurePrompt(x: 32, labelY: 252, width: 1002, fieldY: 109, height: 134)
        }

        errorLabel.font = PanelStyle.inspectFont(ofSize: 11)
        errorLabel.textColor = PanelStyle.failure
        errorLabel.frame = NSRect(x: 32, y: 75, width: layout.width - 280, height: 16)
        body.addSubview(errorLabel)

        let cancel = actionButton("Cancel".localized, x: layout.width - 390, y: 33,
                                  width: 140, action: #selector(cancelTapped))
        body.addSubview(cancel)
        runButton.target = self
        runButton.action = #selector(runTapped)
        runButton.normalBackground = PanelStyle.accent
        runButton.hoverBackground = PanelStyle.accentHover
        runButton.titleColor = PanelStyle.accentInk
        runButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        runButton.layer?.borderWidth = 0
        runButton.frame = NSRect(x: layout.width - 238, y: 33, width: 206, height: 36)
        body.addSubview(runButton)
        updateRunState()
    }

    private func configurePrompt(x: CGFloat, labelY: CGFloat, width: CGFloat,
                                 fieldY: CGFloat, height: CGFloat) {
        let enabled = capabilities.acceptsPrompt
        let caption = label("PROMPT", size: 11, weight: .semibold,
                            color: enabled ? PanelStyle.textSecondary : PanelStyle.textTertiary)
        caption.frame = NSRect(x: x, y: labelY, width: width, height: 15)
        body.addSubview(caption)
        promptField.frame = NSRect(x: x, y: fieldY, width: width, height: height)
        promptField.wantsLayer = true
        promptField.layer?.cornerRadius = 9
        promptField.layer?.backgroundColor = PanelStyle.resolvedCG(
            enabled ? PanelStyle.inspectCanvas : PanelStyle.inspectChrome)
        promptField.layer?.borderWidth = 1
        promptField.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        body.addSubview(promptField)
        let scroll = NSScrollView(frame: promptField.bounds.insetBy(dx: 17, dy: 13))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        promptView.frame = scroll.contentView.bounds
        promptView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        promptView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
        promptView.isVerticallyResizable = true
        promptView.isHorizontallyResizable = false
        promptView.autoresizingMask = [.width]
        promptView.textContainer?.widthTracksTextView = true
        promptView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                         height: CGFloat.greatestFiniteMagnitude)
        promptView.font = PanelStyle.inspectFont(ofSize: 13)
        promptView.textColor = enabled ? PanelStyle.textPrimary : PanelStyle.textTertiary
        promptView.isEditable = enabled
        promptView.isSelectable = enabled
        promptView.isRichText = false
        promptView.drawsBackground = false
        promptView.textContainerInset = NSSize(width: 0, height: 0)
        promptView.delegate = self
        promptView.string = enabled ? "" : "Prompt unavailable for this Widget".localized
        scroll.documentView = promptView
        promptField.addSubview(scroll)
        promptPlaceholder.font = PanelStyle.inspectFont(ofSize: 13)
        promptPlaceholder.textColor = PanelStyle.textTertiary
        promptPlaceholder.frame = NSRect(x: 19, y: height - 36, width: width - 38, height: 18)
        promptPlaceholder.isHidden = !enabled
        promptField.addSubview(promptPlaceholder)
    }

    private func configureMask() {
        let caption = label("MASK", size: 11, weight: .semibold,
                            color: PanelStyle.textSecondary)
        caption.frame = NSRect(x: 526, y: 407, width: 496, height: 15)
        body.addSubview(caption)
        let field = NSView(frame: NSRect(x: 526, y: 175, width: 496, height: 223))
        field.wantsLayer = true
        field.layer?.cornerRadius = 9
        field.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        field.layer?.borderWidth = 1
        field.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        body.addSubview(field)
        maskPreview.frame = NSRect(x: 17, y: 61, width: 169, height: 145)
        maskPreview.imageScaling = .scaleProportionallyUpOrDown
        maskPreview.wantsLayer = true
        maskPreview.layer?.cornerRadius = 8
        maskPreview.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        maskPreview.layer?.borderWidth = 1
        maskPreview.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        field.addSubview(maskPreview)
        let description = label("Select the area to change".localized, size: 13,
                                weight: .medium, color: PanelStyle.textPrimary)
        description.frame = NSRect(x: 204, y: 177, width: 274, height: 18)
        field.addSubview(description)
        maskStatus.font = PanelStyle.inspectFont(ofSize: 11)
        maskStatus.textColor = PanelStyle.textSecondary
        maskStatus.lineBreakMode = .byTruncatingMiddle
        maskStatus.frame = NSRect(x: 204, y: 150, width: 274, height: 16)
        field.addSubview(maskStatus)
        field.addSubview(actionButton("Upload mask".localized, x: 17, y: 9,
                                      width: 220, action: #selector(uploadMaskTapped)))
        field.addSubview(actionButton("Draw mask".localized, x: 254, y: 9,
                                      width: 225, action: #selector(drawMaskTapped)))
    }

    private func renderImages() {
        imageSection.subviews.forEach { $0.removeFromSuperview() }
        switch layout {
        case .imageText, .imageMask:
            let wide = layout == .imageText
            let imageFrame = NSRect(x: 32, y: wide ? 288 : 139,
                                    width: wide ? 790 : 470,
                                    height: wide ? 339 : 488)
            addImagePreview(mediaURLs[0], frame: imageFrame, to: imageSection)
            let name = label(mediaURLs[0].lastPathComponent, size: 12,
                             color: PanelStyle.textSecondary)
            name.frame = NSRect(x: 32, y: wide ? 260 : 110,
                                width: imageFrame.width, height: 17)
            imageSection.addSubview(name)
            imageSection.addSubview(actionButton("Change image".localized,
                                                 x: 32, y: 33, width: 150,
                                                 action: #selector(changeImageTapped)))
        case .multipleImages:
            let title = label("IMAGES", size: 11, weight: .semibold,
                              color: PanelStyle.textSecondary)
            title.frame = NSRect(x: 32, y: 609, width: 300, height: 15)
            imageSection.addSubview(title)
            countLabel.stringValue = "\(mediaURLs.count) / \(capabilities.maxImages)"
            countLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
            countLabel.textColor = mediaURLs.count == capabilities.maxImages ? PanelStyle.accent : PanelStyle.textPrimary
            countLabel.alignment = .right
            countLabel.frame = NSRect(x: 956, y: 609, width: 76, height: 17)
            imageSection.addSubview(countLabel)
            for (index, url) in mediaURLs.enumerated() {
                let x = CGFloat(32 + index * 254)
                let tile = NSView(frame: NSRect(x: x, y: 298, width: 238, height: 296))
                tile.wantsLayer = true
                tile.layer?.cornerRadius = 10
                tile.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
                tile.layer?.borderWidth = 1
                tile.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
                imageSection.addSubview(tile)
                addImagePreview(url, frame: NSRect(x: 8, y: 64, width: 222, height: 224), to: tile)
                if index == 0 {
                    let badge = label("BASE", size: 10, weight: .semibold,
                                      color: PanelStyle.accent)
                    badge.alignment = .center
                    badge.frame = NSRect(x: 18, y: 258, width: 56, height: 18)
                    badge.wantsLayer = true
                    badge.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
                    badge.layer?.cornerRadius = 6
                    tile.addSubview(badge)
                }
                let remove = actionButton("×", x: 194, y: 252, width: 28,
                                          action: #selector(removeImageTapped))
                remove.tag = index
                remove.isEnabled = mediaURLs.count > 1
                tile.addSubview(remove)
                let file = label(url.lastPathComponent, size: 12,
                                 weight: .medium, color: PanelStyle.textPrimary)
                file.lineBreakMode = .byTruncatingMiddle
                file.frame = NSRect(x: 12, y: 32, width: 214, height: 17)
                tile.addSubview(file)
                let order = label("IMAGE \(index + 1)", size: 10,
                                  color: PanelStyle.textTertiary)
                order.frame = NSRect(x: 12, y: 11, width: 214, height: 14)
                tile.addSubview(order)
            }
            if mediaURLs.count < capabilities.maxImages {
                let add = actionButton("＋  Add image".localized,
                                       x: CGFloat(32 + mediaURLs.count * 254), y: 298,
                                       width: 238, action: #selector(addImagesTapped))
                add.frame.size.height = 296
                imageSection.addSubview(add)
            }
            let hint = label(capabilities.maxImages == 2
                             ? "This Widget requires exactly two images.".localized
                             : mediaURLs.count == 4
                             ? "4 images maximum · remove one to add another".localized
                             : "Images are sent from left to right · up to 4".localized,
                             size: 11, color: PanelStyle.textSecondary)
            hint.frame = NSRect(x: 32, y: 278, width: 900, height: 15)
            imageSection.addSubview(hint)
        }
    }

    private func addImagePreview(_ url: URL, frame: NSRect, to parent: NSView) {
        let preview = NSImageView(frame: frame)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        parent.addSubview(preview)
        if url == initialURL, let initialImage { preview.image = initialImage; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async { [weak preview] in preview?.image = image }
        }
    }

    private func label(_ value: String, size: CGFloat,
                       weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let result = NSTextField(labelWithString: value)
        result.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        result.textColor = color
        return result
    }

    private func divider(x: CGFloat, y: CGFloat, width: CGFloat, in view: NSView) {
        let line = NSView(frame: NSRect(x: x, y: y, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        view.addSubview(line)
    }

    private func actionButton(_ title: String, x: CGFloat, y: CGFloat,
                              width: CGFloat, action: Selector) -> PanelButton {
        let result = PanelButton(title: title, target: self, action: action)
        result.normalBackground = PanelStyle.inspectToolbar
        result.hoverBackground = PanelStyle.inspectLine
        result.titleColor = PanelStyle.textPrimary
        result.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        result.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        result.frame = NSRect(x: x, y: y, width: width, height: 36)
        return result
    }

    private func addTrafficLight(to parent: NSView, x: CGFloat,
                                 color: NSColor, action: Selector) {
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
        parent.addSubview(button)
    }

    func textDidChange(_ notification: Notification) {
        promptPlaceholder.isHidden = !capabilities.acceptsPrompt || !promptView.string.isEmpty
    }

    private func updateRunState() {
        runButton.isEnabled = mediaURLs.count >= capabilities.minImages &&
            mediaURLs.count <= capabilities.maxImages &&
            (!capabilities.acceptsMask || maskURL != nil)
    }

    func present(over parentWindow: NSWindow) {
        setFrame(ScreenManager.shared.contentFrame(for: frame.size), display: true)
        fitDesignRoot()
        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    private func fitDesignRoot() {
        let design = NSSize(width: layout.width, height: 788)
        let available = contentView?.bounds.size ?? design
        let scale = min(available.width / design.width, available.height / design.height)
        designRoot.frame = NSRect(x: (available.width - design.width * scale) / 2,
                                  y: (available.height - design.height * scale) / 2,
                                  width: design.width * scale,
                                  height: design.height * scale)
        designRoot.bounds = NSRect(origin: .zero, size: design)
    }

    override func close() {
        maskEditor?.close()
        maskEditor = nil
        parent?.removeChildWindow(self)
        orderOut(nil)
        let callback = onDismiss
        onDismiss = nil
        onSubmit = nil
        callback?()
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

    @objc private func runTapped() {
        guard runButton.isEnabled else { return }
        let input = WidgetTaskInput(mediaURLs: mediaURLs,
                                    prompt: capabilities.acceptsPrompt
                                        ? promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
                                        : nil,
                                    maskURL: maskURL,
                                    usesMultipleImages: layout == .multipleImages)
        let submit = onSubmit
        close()
        submit?(input)
    }

    @objc private func changeImageTapped() { selectImages(replacing: true) }
    @objc private func addImagesTapped() { selectImages(replacing: false) }

    private func selectImages(replacing: Bool) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = !replacing
        picker.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self else { return }
            if replacing {
                guard let first = picker.urls.first else { return }
                self.mediaURLs = [first]
                self.maskURL = nil
                self.maskStatus.stringValue = "No mask selected".localized
                self.maskPreview.image = nil
            } else {
                let available = max(0, self.capabilities.maxImages - self.mediaURLs.count)
                let additions = picker.urls.filter { !self.mediaURLs.contains($0) }
                self.mediaURLs.append(contentsOf: additions.prefix(available))
                self.errorLabel.stringValue = additions.count > available
                    ? (self.capabilities.maxImages == 2
                       ? "This Widget accepts at most two images.".localized
                       : "A Widget accepts at most four images.".localized) : ""
            }
            self.renderImages()
            self.updateRunState()
        }
    }

    @objc private func removeImageTapped(_ sender: NSButton) {
        guard mediaURLs.count > 1, mediaURLs.indices.contains(sender.tag) else { return }
        mediaURLs.remove(at: sender.tag)
        maskURL = nil
        maskStatus.stringValue = "No mask selected".localized
        maskPreview.image = nil
        renderImages()
        updateRunState()
    }

    @objc private func uploadMaskTapped() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self, let url = picker.urls.first else { return }
            self.maskURL = url
            self.maskStatus.stringValue = url.lastPathComponent
            self.loadMaskPreview(from: url)
            self.updateRunState()
        }
    }

    @objc private func drawMaskTapped() {
        guard let source = imageSection.subviews.compactMap({ $0 as? NSImageView }).first?.image else {
            errorLabel.stringValue = "The source image is still loading.".localized
            return
        }
        let editor = WidgetMaskEditorPanel(sourceImage: source)
        editor.onUse = { [weak self] url in
            self?.maskURL = url
            self?.maskStatus.stringValue = url.lastPathComponent
            self?.loadMaskPreview(from: url)
            self?.updateRunState()
        }
        maskEditor = editor
        editor.present(over: self)
    }

    private func loadMaskPreview(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async { [weak self] in
                guard self?.maskURL == url else { return }
                self?.maskPreview.image = image
            }
        }
    }
}

/// Draws an editable mask over the source image and exports a transparent PNG
/// whose white pixels are the selected area.
private final class WidgetMaskCanvas: NSView {
    private struct Stroke {
        var points: [CGPoint]
        let erases: Bool
        let widthFraction: CGFloat
    }

    let sourceImage: NSImage
    var erases = false
    var brushSize: CGFloat = 32
    private var strokes: [Stroke] = []

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        layer?.cornerRadius = 9
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var imageRect: CGRect {
        let available = bounds.insetBy(dx: 10, dy: 10)
        guard sourceImage.size.width > 0, sourceImage.size.height > 0 else { return available }
        let scale = min(available.width / sourceImage.size.width,
                        available.height / sourceImage.size.height)
        let size = NSSize(width: sourceImage.size.width * scale,
                          height: sourceImage.size.height * scale)
        return NSRect(x: available.midX - size.width / 2,
                      y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let target = imageRect
        sourceImage.draw(in: target)
        if let mask = Self.renderMask(strokes: strokes,
                                      width: max(1, Int(target.width)),
                                      height: max(1, Int(target.height)),
                                      color: PanelStyle.accent.cgColor) {
            NSImage(cgImage: mask, size: target.size)
                .draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.55)
        }
        PanelStyle.inspectLine.setStroke()
        NSBezierPath(roundedRect: target, xRadius: 8, yRadius: 8).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        let normalized = normalize(point)
        strokes.append(Stroke(points: [normalized], erases: erases,
                              widthFraction: brushSize / max(1, sourceImage.size.width)))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !strokes.isEmpty else { return }
        let rect = imageRect
        let point = convert(event.locationInWindow, from: nil)
        let clamped = CGPoint(x: max(rect.minX, min(point.x, rect.maxX)),
                              y: max(rect.minY, min(point.y, rect.maxY)))
        strokes[strokes.count - 1].points.append(normalize(clamped))
        needsDisplay = true
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: (point.x - rect.minX) / max(1, rect.width),
                       y: (point.y - rect.minY) / max(1, rect.height))
    }

    func undo() { if !strokes.isEmpty { strokes.removeLast(); needsDisplay = true } }
    func clear() { strokes.removeAll(); needsDisplay = true }
    var hasPaint: Bool { strokes.contains { !$0.erases } }

    private static func renderMask(strokes: [Stroke], width: Int, height: Int,
                                   color: CGColor) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            context.setBlendMode(stroke.erases ? .clear : .normal)
            context.setStrokeColor(color)
            context.setFillColor(color)
            let radius = max(1, stroke.widthFraction * CGFloat(width) / 2)
            context.setLineWidth(radius * 2)
            let start = CGPoint(x: first.x * CGFloat(width), y: first.y * CGFloat(height))
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(x: start.x - radius, y: start.y - radius,
                                               width: radius * 2, height: radius * 2))
            } else {
                context.beginPath()
                context.move(to: start)
                for point in stroke.points.dropFirst() {
                    context.addLine(to: CGPoint(x: point.x * CGFloat(width),
                                                y: point.y * CGFloat(height)))
                }
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    func maskExporter() -> (() -> Data?)? {
        let bitmap = sourceImage.representations.compactMap { $0 as? NSBitmapImageRep }.first
        let width = bitmap?.pixelsWide ?? Int(sourceImage.size.width)
        let height = bitmap?.pixelsHigh ?? Int(sourceImage.size.height)
        guard width > 0, height > 0 else { return nil }
        let snapshot = strokes
        let white = NSColor.white.cgColor
        return {
            guard let mask = Self.renderMask(strokes: snapshot,
                                             width: width, height: height,
                                             color: white) else { return nil }
            return NSBitmapImageRep(cgImage: mask).representation(using: .png, properties: [:])
        }
    }
}

final class WidgetMaskEditorPanel: NSPanel {
    var onUse: ((URL) -> Void)?
    private let canvas: WidgetMaskCanvas
    private let sizeLabel = NSTextField(labelWithString: "32 px")
    private let errorLabel = NSTextField(labelWithString: "")
    private let useButton = PanelButton(title: "Use mask".localized, target: nil, action: nil)
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: 16)
    private var restoredFrame: NSRect?

    init(sourceImage: NSImage) {
        canvas = WidgetMaskCanvas(sourceImage: sourceImage)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1210, height: 760),
                   styleMask: [.borderless, .closable, .miniaturizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func buildUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1210, height: 760))
        contentView = container
        let root = designRoot
        root.frame = container.bounds
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        container.addSubview(root)
        for (x, color, action) in [
            (24.0, NSColor(srgbRed: 237/255, green: 106/255, blue: 94/255, alpha: 1), #selector(cancelTapped)),
            (44.0, NSColor(srgbRed: 244/255, green: 191/255, blue: 79/255, alpha: 1), #selector(minimizeTapped)),
            (64.0, NSColor(srgbRed: 97/255, green: 197/255, blue: 84/255, alpha: 1), #selector(zoomTapped))
        ] {
            let button = NSButton(frame: NSRect(x: x - 6, y: 729, width: 24, height: 24))
            button.isBordered = false
            button.wantsLayer = true
            let dot = CALayer()
            dot.frame = NSRect(x: 6, y: 6, width: 12, height: 12)
            dot.backgroundColor = color.cgColor
            dot.cornerRadius = 6
            button.layer?.addSublayer(dot)
            button.target = self
            button.action = action
            root.addSubview(button)
        }
        let title = label("Draw mask".localized, 24, .semibold, PanelStyle.textPrimary)
        title.frame = NSRect(x: 120, y: 705, width: 600, height: 32)
        root.addSubview(title)
        let help = label("Paint the area the Widget should change.".localized,
                         12, .regular, PanelStyle.textSecondary)
        help.frame = NSRect(x: 32, y: 682, width: 800, height: 16)
        root.addSubview(help)
        canvas.frame = NSRect(x: 32, y: 113, width: 811, height: 537)
        root.addSubview(canvas)
        let tools = NSView(frame: NSRect(x: 877, y: 113, width: 301, height: 537))
        tools.wantsLayer = true
        tools.layer?.cornerRadius = 9
        tools.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        tools.layer?.borderWidth = 1
        tools.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.addSubview(tools)
        let heading = label("TOOLS", 11, .semibold, PanelStyle.textTertiary)
        heading.frame = NSRect(x: 20, y: 498, width: 261, height: 15)
        tools.addSubview(heading)
        tools.addSubview(button("Brush".localized, x: 20, y: 441, width: 124,
                                action: #selector(brushTapped)))
        tools.addSubview(button("Erase".localized, x: 157, y: 441, width: 124,
                                action: #selector(eraseTapped)))
        let brushLabel = label("BRUSH SIZE", 11, .semibold, PanelStyle.textTertiary)
        brushLabel.frame = NSRect(x: 20, y: 395, width: 261, height: 15)
        tools.addSubview(brushLabel)
        let slider = NSSlider(frame: NSRect(x: 20, y: 357, width: 261, height: 24))
        slider.minValue = 8
        slider.maxValue = 128
        slider.doubleValue = 32
        slider.target = self
        slider.action = #selector(sizeChanged(_:))
        tools.addSubview(slider)
        sizeLabel.font = PanelStyle.inspectFont(ofSize: 11)
        sizeLabel.textColor = PanelStyle.textSecondary
        sizeLabel.frame = NSRect(x: 20, y: 333, width: 261, height: 15)
        tools.addSubview(sizeLabel)
        tools.addSubview(button("Undo".localized, x: 20, y: 269, width: 124,
                                action: #selector(undoTapped)))
        tools.addSubview(button("Clear mask".localized, x: 157, y: 269, width: 124,
                                action: #selector(clearTapped)))
        let guide = label("Orange shows the selected area.".localized,
                          12, .regular, PanelStyle.textSecondary)
        guide.frame = NSRect(x: 20, y: 220, width: 261, height: 30)
        tools.addSubview(guide)
        errorLabel.font = PanelStyle.inspectFont(ofSize: 11)
        errorLabel.textColor = PanelStyle.failure
        errorLabel.frame = NSRect(x: 32, y: 75, width: 700, height: 16)
        root.addSubview(errorLabel)
        root.addSubview(button("Cancel".localized, x: 902, y: 32, width: 124,
                               action: #selector(cancelTapped)))
        useButton.target = self
        useButton.action = #selector(useTapped)
        useButton.normalBackground = PanelStyle.accent
        useButton.hoverBackground = PanelStyle.accentHover
        useButton.titleColor = PanelStyle.accentInk
        useButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        useButton.layer?.borderWidth = 0
        useButton.frame = NSRect(x: 1038, y: 32, width: 140, height: 36)
        root.addSubview(useButton)
    }

    private func label(_ value: String, _ size: CGFloat,
                       _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func button(_ title: String, x: CGFloat, y: CGFloat,
                        width: CGFloat, action: Selector) -> PanelButton {
        let button = PanelButton(title: title, target: self, action: action)
        button.normalBackground = PanelStyle.inspectToolbar
        button.hoverBackground = PanelStyle.inspectLine
        button.titleColor = PanelStyle.textPrimary
        button.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        button.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        button.frame = NSRect(x: x, y: y, width: width, height: 36)
        return button
    }

    func present(over parentWindow: NSWindow) {
        setFrame(ScreenManager.shared.contentFrame(for: frame.size), display: true)
        fitDesignRoot()
        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    private func fitDesignRoot() {
        let design = NSSize(width: 1210, height: 760)
        let available = contentView?.bounds.size ?? design
        let scale = min(available.width / design.width, available.height / design.height)
        designRoot.frame = NSRect(x: (available.width - design.width * scale) / 2,
                                  y: (available.height - design.height * scale) / 2,
                                  width: design.width * scale,
                                  height: design.height * scale)
        designRoot.bounds = NSRect(origin: .zero, size: design)
    }

    override func close() {
        parent?.removeChildWindow(self)
        orderOut(nil)
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
    @objc private func brushTapped() { canvas.erases = false }
    @objc private func eraseTapped() { canvas.erases = true }
    @objc private func undoTapped() { canvas.undo() }
    @objc private func clearTapped() { canvas.clear() }
    @objc private func sizeChanged(_ sender: NSSlider) {
        canvas.brushSize = CGFloat(sender.doubleValue)
        sizeLabel.stringValue = "\(Int(sender.doubleValue)) px"
    }

    @objc private func useTapped() {
        guard canvas.hasPaint else {
            errorLabel.stringValue = "Draw a mask before using it.".localized
            return
        }
        guard let export = canvas.maskExporter() else {
            errorLabel.stringValue = WidgetMaskError.exportFailed.localizedDescription
            return
        }
        useButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let data = export() else { throw WidgetMaskError.exportFailed }
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Glance/Widget Masks", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("mask-\(UUID().uuidString).png")
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.onUse?(url)
                    self.close()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorLabel.stringValue = error.localizedDescription
                    self?.useButton.isEnabled = true
                }
            }
        }
    }
}

private enum WidgetMaskError: LocalizedError {
    case exportFailed
    var errorDescription: String? { "Could not export the mask PNG.".localized }
}
