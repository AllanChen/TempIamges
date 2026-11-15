import AppKit
import UniformTypeIdentifiers

/// Shizuka chrome shared by the Widget input windows (Figma `10 · Widget Input /
/// Image + Prompt`, `29 · Draw Mask`, `30 · Multi-image`): a 1440 × 900 board with
/// an ink/0 stage (0, 44, 1000 × 856), a hairline at x 1000 and a 360 pt form
/// at x 1040. Frames are written in Figma's top-origin coordinates and converted
/// to AppKit's bottom-origin frames by `frame(_:_:_:_:in:)`.
enum WidgetInputStyle {
    static let board = NSSize(width: 1440, height: 900)
    static let stage = NSRect(x: 0, y: 44, width: 1000, height: 856)
    static let formX: CGFloat = 1040
    static let formWidth: CGFloat = 360
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let lineStrong = PanelStyle.themed(PanelStyle.Sumi.lineStrong, PanelStyle.Washi.lineStrong)
    static let ink3 = PanelStyle.themed(PanelStyle.Sumi.ink3, PanelStyle.Washi.ink3)
    /// The mask paint colour, unchanged: the accent in Sumi, vermilion in Washi.
    static let maskColor = PanelStyle.themed(PanelStyle.accent, PanelStyle.Washi.shu)

    /// A Figma top-origin rect inside a parent of `height`, as an AppKit frame.
    static func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                      in parentHeight: CGFloat = board.height) -> NSRect {
        NSRect(x: x, y: parentHeight - y - height, width: width, height: height)
    }

    static func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    /// Window planes, traffic lights, the centred title and the stage/form hairline.
    /// Returns the stage view; the form is drawn straight onto `root`.
    @discardableResult
    static func buildChrome(in root: NSView, title: String, target: AnyObject,
                            close: Selector, minimize: Selector, zoom: Selector) -> NSView {
        let plane = NSView(frame: NSRect(origin: .zero, size: board))
        plane.wantsLayer = true
        plane.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        root.addSubview(plane)
        let stageView = NSView(frame: frame(stage.minX, stage.minY, stage.width, stage.height))
        stageView.wantsLayer = true
        stageView.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.canvas)
        root.addSubview(stageView)
        let divider = NSView(frame: frame(stage.maxX, stage.minY, 1, stage.height))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(line)
        root.addSubview(divider)
        for (index, (color, action)) in [
            (NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), close),
            (NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), minimize),
            (NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), zoom)
        ].enumerated() {
            let button = TrafficLightButton(color: color, target: target, action: action)
            button.frame = frame(20 + CGFloat(index) * 20, 16, 12, 12)
            root.addSubview(button)
        }
        if !title.isEmpty {
            let titleView = text(title, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                                 color: PanelStyle.textSecondary, frame: frame(100, 14, board.width - 200, 16))
            titleView.alignment = .center
            root.addSubview(titleView)
        }
        return stageView
    }

    static func text(_ value: String, font: NSFont, color: NSColor, frame: NSRect,
                     lines: Int = 1, lineHeight: CGFloat? = nil) -> WidgetInputTextView {
        let view = WidgetInputTextView(frame: frame)
        view.string = value
        view.font = font
        view.textColor = color
        view.maximumNumberOfLines = lines
        view.lineHeight = lineHeight
        return view
    }

    /// Form header: mono eyebrow (y 84), Mincho title (y 108, 38 tall) and a
    /// two-line description (y 154).
    static func addHeader(to root: NSView, eyebrow: String, title: String, description: String) {
        let eyebrowView = text(eyebrow.uppercased(), font: PanelStyle.monoFont(ofSize: 11),
                               color: PanelStyle.textTertiary, frame: frame(formX, 84, formWidth, 14))
        eyebrowView.kern = 1.2
        root.addSubview(eyebrowView)
        root.addSubview(text(title, font: PanelStyle.titleFont(ofSize: 30), color: PanelStyle.textPrimary,
                             frame: frame(formX, 108, formWidth, 38)))
        root.addSubview(text(description, font: PanelStyle.inspectFont(ofSize: 13), color: PanelStyle.textSecondary,
                             frame: frame(formX, 154, formWidth, 42), lines: 2, lineHeight: 21))
    }

    /// Section label (12, text/3) with an optional mono status at the right.
    @discardableResult
    static func addSectionLabel(to root: NSView, _ title: String, y: CGFloat,
                                status: WidgetInputTextView? = nil) -> WidgetInputTextView {
        root.addSubview(text(title, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary,
                             frame: frame(formX, y, 200, 15)))
        if let status {
            status.font = PanelStyle.monoFont(ofSize: 11)
            status.textColor = PanelStyle.textTertiary
            status.alignment = .right
            status.frame = frame(formX + formWidth - 140, y, 140, 14)
            root.addSubview(status)
        }
        return status ?? WidgetInputTextView(frame: .zero)
    }

    /// Board "cost" row: hairlines above and below, "Cost" at the left, the
    /// Widget's configured price in mono at the right.
    static func addCostRow(to root: NSView, cost: String, y: CGFloat) {
        for lineY in [y, y + 35] {
            let rule = NSView(frame: frame(formX, lineY, formWidth, 1))
            rule.wantsLayer = true
            rule.layer?.backgroundColor = PanelStyle.resolvedCG(line)
            root.addSubview(rule)
        }
        root.addSubview(text("Cost".localized, font: PanelStyle.inspectFont(ofSize: 13),
                             color: PanelStyle.textTertiary, frame: frame(formX, y + 10, 120, 16)))
        let value = text(cost, font: PanelStyle.monoFont(ofSize: 13), color: PanelStyle.textPrimary,
                         frame: frame(formX + 120, y + 10, formWidth - 120, 16))
        value.alignment = .right
        root.addSubview(value)
    }

    /// Board "Button": 32 pt, radius 6, label 13 medium. Primary is the accent
    /// fill with accent ink; quiet is a strong hairline with text/1.
    static func button(_ title: String, primary: Bool, target: AnyObject?, action: Selector?) -> PanelButton {
        let button = PanelButton(title: title, target: target, action: action)
        button.normalBackground = primary ? PanelStyle.accent : .clear
        button.hoverBackground = primary ? PanelStyle.accentHover : PanelStyle.rowHover
        button.titleColor = primary ? PanelStyle.accentInk : PanelStyle.textPrimary
        button.titleFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        button.layer?.cornerRadius = PanelStyle.Radius.control
        button.layer?.borderWidth = primary ? 0 : 1
        button.layer?.borderColor = PanelStyle.resolvedCG(lineStrong)
        return button
    }

    static func buttonWidth(_ title: String) -> CGFloat {
        textWidth(title, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium)) + 32
    }

    /// Board "actions" (y 836): Cancel at the form's left edge, the run action at its right.
    static func addActions(to root: NSView, cancel: PanelButton, run: PanelButton, runTitle: String) {
        let cancelWidth = buttonWidth("Cancel".localized)
        cancel.frame = frame(formX, 836, cancelWidth, 32)
        root.addSubview(cancel)
        let runWidth = min(formWidth - cancelWidth - 16, buttonWidth(runTitle))
        run.frame = frame(formX + formWidth - runWidth, 836, runWidth, 32)
        root.addSubview(run)
    }

    /// Scale the 1440 × 900 board to fit the window, centred.
    static func fit(_ root: NSView, in contentView: NSView?) {
        let available = contentView?.bounds.size ?? board
        let scale = min(available.width / board.width, available.height / board.height)
        root.frame = NSRect(x: (available.width - board.width * scale) / 2,
                            y: (available.height - board.height * scale) / 2,
                            width: board.width * scale, height: board.height * scale)
        root.bounds = NSRect(origin: .zero, size: board)
    }

    /// "3024 × 4032   JPEG   6.8 MB", read off the main thread.
    static func loadImageDetails(_ url: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var parts: [String] = []
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                parts.append("\(width) × \(height)")
            }
            if !url.pathExtension.isEmpty { parts.append(url.pathExtension.uppercased()) }
            if let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
            let details = parts.joined(separator: "   ")
            DispatchQueue.main.async { completion(details) }
        }
    }
}

/// A read-only Figma text frame. Draws into its own bounds so NSTextField cell
/// padding never moves the specified position or wrapping width.
final class WidgetInputTextView: NSView {
    var string = "" { didSet { setAccessibilityLabel(string); needsDisplay = true } }
    var font = PanelStyle.inspectFont(ofSize: 13) { didSet { needsDisplay = true } }
    var textColor = PanelStyle.textPrimary { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var lineBreakMode: NSLineBreakMode = .byTruncatingTail { didSet { needsDisplay = true } }
    var maximumNumberOfLines = 1 { didSet { needsDisplay = true } }
    var lineHeight: CGFloat? { didSet { needsDisplay = true } }
    var kern: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = maximumNumberOfLines == 1 ? lineBreakMode : .byWordWrapping
        if let lineHeight { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight }
        let text = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph, .kern: kern])
        var rect = bounds
        if maximumNumberOfLines > 0 {
            let line = lineHeight ?? NSLayoutManager().defaultLineHeight(for: font)
            rect.size.height = min(rect.height, line * CGFloat(maximumNumberOfLines))
        }
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

/// Board "prompt field" (360 × 148, radius 6): ink/0 with a strong hairline,
/// text 14 inset (14, 12), placeholder in text/3. Disabled when the Widget
/// takes no prompt, showing why in place of the text.
final class WidgetPromptField: NSView {
    let textView = NSTextView()
    private let placeholder = WidgetInputTextView(frame: .zero)
    private let isEnabled: Bool
    var text: String { textView.string }

    init(frame frameRect: NSRect, enabled: Bool) {
        isEnabled = enabled
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.backgroundColor = PanelStyle.resolvedCG(enabled ? PanelStyle.canvas : PanelStyle.surface)
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(WidgetInputStyle.lineStrong)
        let inset = NSRect(x: 14, y: 12, width: frameRect.width - 20, height: frameRect.height - 24)
        let scroll = NSScrollView(frame: inset)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: scroll)
        scroll.borderType = .noBorder
        textView.frame = scroll.contentView.bounds
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width - 6,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        paragraph.maximumLineHeight = 22
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: PanelStyle.inspectFont(ofSize: 14), .paragraphStyle: paragraph,
                                     .foregroundColor: enabled ? PanelStyle.textPrimary : PanelStyle.textTertiary]
        textView.font = PanelStyle.inspectFont(ofSize: 14)
        textView.textColor = enabled ? PanelStyle.textPrimary : PanelStyle.textTertiary
        textView.insertionPointColor = PanelStyle.contrast
        textView.isEditable = enabled
        textView.isSelectable = enabled
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        scroll.documentView = textView
        addSubview(scroll)
        placeholder.font = PanelStyle.inspectFont(ofSize: 14)
        placeholder.textColor = PanelStyle.textTertiary
        placeholder.lineHeight = 22
        placeholder.frame = NSRect(x: 14, y: frameRect.height - 12 - 22, width: frameRect.width - 28, height: 22)
        addSubview(placeholder)
        if enabled {
            placeholder.string = "Describe what the Widget should do…".localized
            NotificationCenter.default.addObserver(self, selector: #selector(textChanged),
                                                   name: NSText.didChangeNotification, object: textView)
        } else {
            placeholder.string = "Prompt unavailable for this Widget".localized
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func textChanged() { placeholder.isHidden = !textView.string.isEmpty }
}

/// The three Figma Widget Input layouts share one data model and one submission path.
/// The selected image is always the first image sent to the Worker.
final class WidgetInputPanel: NSPanel, NSTextViewDelegate {
    var onSubmit: ((WidgetTaskInput) -> Void)?
    var onDismiss: (() -> Void)?

    private enum Layout { case imageText, imageMask, multipleImages }

    private let capabilities: WidgetInputCapabilities
    private let layout: Layout
    private let initialURL: URL
    private let initialImage: NSImage?
    private let costText: String?
    private var mediaURLs: [URL]
    private var maskURL: URL?
    private var maskEditor: WidgetMaskEditorPanel?
    private var restoredFrame: NSRect?
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: PanelStyle.Radius.window)
    private var imageSection = NSView()
    private var sourcePreview: NSImageView?
    private var promptField: WidgetPromptField?
    /// The static hint under the mask description (Figma "Mask Hint"); the stage shows what was drawn.
    private let maskStatus = WidgetInputTextView(frame: .zero)
    private let maskState = WidgetInputTextView(frame: .zero)
    /// The drawn mask, laid over the stage image in the mask colour.
    private let maskPreview = NSImageView()
    private let countLabel = WidgetInputTextView(frame: .zero)
    private let errorLabel = WidgetInputTextView(frame: .zero)
    private let runButton = WidgetInputStyle.button("Run Widget".localized, primary: true, target: nil, action: nil)

    /// `costText` is the Widget's configured price as the catalog states it
    /// (for example `creditCostLabel`); the Cost row is shown only when given.
    init(widgetName: String, sourceURL: URL, sourceImage: NSImage?,
         capabilities: WidgetInputCapabilities, costText: String? = nil) {
        self.capabilities = capabilities
        self.initialURL = sourceURL
        self.initialImage = sourceImage
        self.costText = costText
        self.mediaURLs = [sourceURL]
        layout = capabilities.maxImages > 1 ? .multipleImages
            : capabilities.acceptsMask ? .imageMask : .imageText
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
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = container
        let root = designRoot
        root.frame = container.bounds
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(WidgetInputStyle.lineStrong)
        container.addSubview(root)
        imageSection = WidgetInputStyle.buildChrome(in: root, title: widgetName, target: self,
                                                    close: #selector(cancelTapped),
                                                    minimize: #selector(minimizeTapped),
                                                    zoom: #selector(zoomTapped))

        var kinds = [(layout == .multipleImages ? "Images" : "Image").localized]
        if capabilities.acceptsPrompt { kinds.append("Prompt".localized) }
        if layout == .imageMask { kinds.append("Mask".localized) }
        let description = layout == .multipleImages
            ? (capabilities.minImages == 2 && capabilities.maxImages == 2
               ? "Use two images. The first image is the base.".localized
               : "Use up to four images. The first image is the base.".localized)
            : layout == .imageMask
            ? (capabilities.acceptsPrompt
               ? "Choose the image, describe the edit, then draw the mask."
               : "Choose an image, then draw the area to change.").localized
            : "The prompt tells the Widget what to make or change.".localized
        WidgetInputStyle.addHeader(to: root, eyebrow: "\("Widget".localized)  ·  \(kinds.joined(separator: " + "))",
                                   title: widgetName, description: description)
        renderImages()

        // Board form: section label at y 232, field at y 255 (148 tall).
        // A mask Widget without a prompt shows no prompt field at all (not even a disabled one).
        if layout != .imageMask || capabilities.acceptsPrompt {
            WidgetInputStyle.addSectionLabel(to: root, "Prompt".localized, y: 232)
            let field = WidgetPromptField(frame: WidgetInputStyle.frame(WidgetInputStyle.formX, 255,
                                                                        WidgetInputStyle.formWidth, 148),
                                          enabled: capabilities.acceptsPrompt)
            root.addSubview(field)
            promptField = field
        }
        if layout == .imageMask { configureMask(in: root) }
        if let costText { WidgetInputStyle.addCostRow(to: root, cost: costText, y: 720) }

        errorLabel.font = PanelStyle.inspectFont(ofSize: 12)
        errorLabel.textColor = PanelStyle.failure
        errorLabel.maximumNumberOfLines = 2
        errorLabel.frame = WidgetInputStyle.frame(WidgetInputStyle.formX, 790, WidgetInputStyle.formWidth, 32)
        root.addSubview(errorLabel)

        runButton.target = self
        runButton.action = #selector(runTapped)
        WidgetInputStyle.addActions(to: root,
                                    cancel: WidgetInputStyle.button("Cancel".localized, primary: false,
                                                                    target: self, action: #selector(cancelTapped)),
                                    run: runButton, runTitle: "Run Widget".localized)
        updateRunState()
    }

    /// Mask section under the prompt (or in its place): label with the drawn
    /// state, what to do, a hint, and the one "Draw mask" action. The drawn
    /// mask itself is shown over the stage image.
    private func configureMask(in root: NSView) {
        let top: CGFloat = capabilities.acceptsPrompt ? 427 : 232
        let x = WidgetInputStyle.formX, width = WidgetInputStyle.formWidth
        WidgetInputStyle.addSectionLabel(to: root, "Mask".localized, y: top, status: maskState)
        root.addSubview(WidgetInputStyle.text("Select the area to change".localized,
                                              font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                                              color: PanelStyle.textPrimary,
                                              frame: WidgetInputStyle.frame(x, top + 25, width, 18)))
        maskStatus.string = "Paint it on the image.".localized
        maskStatus.font = PanelStyle.inspectFont(ofSize: 12)
        maskStatus.textColor = PanelStyle.textTertiary
        maskStatus.frame = WidgetInputStyle.frame(x, top + 46, width, 16)
        root.addSubview(maskStatus)
        let draw = WidgetInputStyle.button("Draw mask".localized, primary: false,
                                           target: self, action: #selector(drawMaskTapped))
        draw.frame = WidgetInputStyle.frame(x, top + 74, width, 32)
        root.addSubview(draw)
        maskPreview.imageScaling = .scaleAxesIndependently
        maskPreview.alphaValue = 0.55
        updateMaskState()
    }

    private func updateMaskState() {
        maskState.string = maskURL == nil ? "" : "Drawn".localized
    }

    /// The image being edited, as the editor will draw on it.
    private var currentSourceImage: NSImage? {
        sourcePreview?.image ?? (mediaURLs.first == initialURL ? initialImage : nil)
    }

    /// The mask overlay takes the shape the image has on the stage (aspect-fit
    /// inside the image frame), so the drawn area lines up with the picture.
    private func fitMaskPreview() {
        guard layout == .imageMask, let sourcePreview else { return }
        let area = sourcePreview.frame
        guard let size = currentSourceImage?.size, size.width > 0, size.height > 0 else {
            maskPreview.frame = area
            return
        }
        let scale = min(area.width / size.width, area.height / size.height)
        let width = (size.width * scale).rounded()
        let height = (size.height * scale).rounded()
        maskPreview.frame = NSRect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(),
                                   width: width, height: height)
    }

    /// The drawn mask (white on transparent) recoloured in the mask colour.
    private func tintedMask(_ mask: NSImage) -> NSImage {
        NSImage(size: mask.size, flipped: false) { rect in
            mask.draw(in: rect)
            WidgetInputStyle.maskColor.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    /// Stage coordinates: Figma y minus the 44 pt title strip, inside the 856 pt stage.
    private func stageFrame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        WidgetInputStyle.frame(x, y - WidgetInputStyle.stage.minY, width, height,
                               in: WidgetInputStyle.stage.height)
    }

    private func renderImages() {
        imageSection.subviews.forEach { $0.removeFromSuperview() }
        sourcePreview = nil
        switch layout {
        case .imageText, .imageMask:
            // Board "image" (120, 116, 760 × 570), meta at y 706, "Change image" right-aligned at y 698.
            let url = mediaURLs[0]
            let preview = NSImageView(frame: stageFrame(120, 116, 760, 570))
            preview.imageScaling = .scaleProportionallyUpOrDown
            imageSection.addSubview(preview)
            sourcePreview = preview
            loadPreview(url, into: preview)
            if layout == .imageMask {
                imageSection.addSubview(maskPreview)
                fitMaskPreview()
            }
            let nameFont = PanelStyle.inspectFont(ofSize: 13)
            let changeWidth = WidgetInputStyle.buttonWidth("Change image".localized)
            let nameWidth = min(WidgetInputStyle.textWidth(url.lastPathComponent, font: nameFont), 760 - changeWidth - 220)
            let name = WidgetInputStyle.text(url.lastPathComponent, font: nameFont, color: PanelStyle.textPrimary,
                                             frame: stageFrame(120, 706, nameWidth, 16))
            name.lineBreakMode = .byTruncatingMiddle
            imageSection.addSubview(name)
            let details = WidgetInputStyle.text("", font: PanelStyle.monoFont(ofSize: 11), color: PanelStyle.textTertiary,
                                                frame: stageFrame(120 + nameWidth + 16, 707, 760 - nameWidth - 16 - changeWidth - 16, 14))
            imageSection.addSubview(details)
            WidgetInputStyle.loadImageDetails(url) { [weak self, weak details] text in
                guard self?.mediaURLs.first == url else { return }
                details?.string = text
            }
            let change = WidgetInputStyle.button("Change image".localized, primary: false,
                                                 target: self, action: #selector(changeImageTapped))
            change.frame = stageFrame(880 - changeWidth, 698, changeWidth, 32)
            imageSection.addSubview(change)
        case .multipleImages:
            // Board "inputs" at (84, 244): 196 × 262 tiles every 212 pt, a caption row 10 pt below.
            for (index, url) in mediaURLs.enumerated() {
                let x = 84 + CGFloat(index) * 212
                let tile = WidgetInputImageTile(frame: stageFrame(x, 244, 196, 262))
                tile.showsBaseOutline = index == 0
                imageSection.addSubview(tile)
                loadTileImage(url, into: tile)
                if mediaURLs.count > 1 {
                    let remove = WidgetInputRemoveButton(frame: NSRect(x: 166, y: 262 - 8 - 22, width: 22, height: 22))
                    remove.target = self
                    remove.action = #selector(removeImageTapped)
                    remove.tag = index
                    tile.addSubview(remove)
                }
                imageSection.addSubview(WidgetInputStyle.text("\(index + 1)", font: PanelStyle.monoFont(ofSize: 11),
                                                              color: PanelStyle.textTertiary,
                                                              frame: stageFrame(x, 516, 12, 14)))
                let file = WidgetInputStyle.text(url.lastPathComponent, font: PanelStyle.inspectFont(ofSize: 12),
                                                 color: PanelStyle.textPrimary,
                                                 frame: stageFrame(x + 15, 516, index == 0 ? 140 : 181, 15))
                file.lineBreakMode = .byTruncatingMiddle
                file.toolTip = url.lastPathComponent
                imageSection.addSubview(file)
                if index == 0 {
                    let base = WidgetInputStyle.text("Base".localized, font: PanelStyle.inspectFont(ofSize: 11),
                                                     color: PanelStyle.textTertiary, frame: stageFrame(x + 150, 516, 46, 13))
                    base.alignment = .right
                    imageSection.addSubview(base)
                }
            }
            if mediaURLs.count < capabilities.maxImages {
                let x = 84 + CGFloat(mediaURLs.count) * 212
                let add = WidgetInputAddTile(frame: stageFrame(x, 244, 196, 41), title: "Add image".localized)
                add.target = self
                add.action = #selector(addImagesTapped)
                imageSection.addSubview(add)
                imageSection.addSubview(WidgetInputStyle.text("\(mediaURLs.count + 1)", font: PanelStyle.monoFont(ofSize: 11),
                                                              color: PanelStyle.textTertiary,
                                                              frame: stageFrame(x, 295, 12, 14)))
                if mediaURLs.count >= capabilities.minImages {
                    imageSection.addSubview(WidgetInputStyle.text("Optional".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                                                  color: PanelStyle.textTertiary,
                                                                  frame: stageFrame(x + 15, 295, 181, 15)))
                }
            }
            let hint = WidgetInputStyle.text(capabilities.maxImages == 2
                                             ? "This Widget requires exactly two images.".localized
                                             : mediaURLs.count == 4
                                             ? "4 images maximum · remove one to add another".localized
                                             : "Images are sent from left to right · up to 4".localized,
                                             font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary,
                                             frame: stageFrame(84, 559, 600, 15))
            imageSection.addSubview(hint)
            countLabel.string = "\(mediaURLs.count) / \(capabilities.maxImages)"
            countLabel.font = PanelStyle.monoFont(ofSize: 11)
            countLabel.textColor = mediaURLs.count == capabilities.maxImages ? PanelStyle.textPrimary : PanelStyle.textTertiary
            countLabel.alignment = .right
            countLabel.frame = stageFrame(716, 559, 200, 14)
            imageSection.addSubview(countLabel)
        }
    }

    private func loadPreview(_ url: URL, into preview: NSImageView) {
        if url == initialURL, let initialImage { preview.image = initialImage; return }
        DispatchQueue.global(qos: .userInitiated).async { [weak preview, weak self] in
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async { [weak preview, weak self] in
                preview?.image = image
                self?.fitMaskPreview()
            }
        }
    }

    private func loadTileImage(_ url: URL, into tile: WidgetInputImageTile) {
        if url == initialURL, let initialImage { tile.image = initialImage; return }
        DispatchQueue.global(qos: .userInitiated).async { [weak tile] in
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async { [weak tile] in tile?.image = image }
        }
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

    private func fitDesignRoot() { WidgetInputStyle.fit(designRoot, in: contentView) }

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
                                        ? (promptField?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
                self.maskPreview.image = nil
                self.updateMaskState()
            } else {
                let available = max(0, self.capabilities.maxImages - self.mediaURLs.count)
                let additions = picker.urls.filter { !self.mediaURLs.contains($0) }
                self.mediaURLs.append(contentsOf: additions.prefix(available))
                self.errorLabel.string = additions.count > available
                    ? (self.capabilities.maxImages == 2
                       ? "This Widget accepts at most two images.".localized
                       : "A Widget accepts at most four images.".localized) : ""
            }
            self.renderImages()
            self.fitMaskPreview()
            self.updateRunState()
        }
    }

    @objc private func removeImageTapped(_ sender: NSButton) {
        guard mediaURLs.count > 1, mediaURLs.indices.contains(sender.tag) else { return }
        mediaURLs.remove(at: sender.tag)
        maskURL = nil
        maskPreview.image = nil
        updateMaskState()
        renderImages()
        updateRunState()
    }

    @objc private func drawMaskTapped() {
        guard let source = sourcePreview?.image else {
            errorLabel.string = "The source image is still loading.".localized
            return
        }
        let editor = WidgetMaskEditorPanel(sourceImage: source)
        editor.onUse = { [weak self] url in
            self?.maskURL = url
            self?.updateMaskState()
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
                guard let self, self.maskURL == url else { return }
                self.fitMaskPreview()
                self.maskPreview.image = image.map { self.tintedMask($0) }
            }
        }
    }
}

/// Board multi-image tile: the picture aspect-filled at radius 3; the base
/// image carries a 1 pt text/1 outline.
private final class WidgetInputImageTile: NSView {
    var image: NSImage? { didSet { imageLayer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) } }
    var showsBaseOutline = false { didSet { layer?.borderWidth = showsBaseOutline ? 1 : 0 } }
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.thumb
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.resolvedCG(WidgetInputStyle.ink3)
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.textPrimary)
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}

/// 22 pt round remove control drawn over a photo: black plate, white cross.
final class WidgetInputRemoveButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        imagePosition = .noImage
        toolTip = "Remove".localized
        setAccessibilityLabel("Remove".localized)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(isHighlighted ? 0.85 : 0.7).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        HistoryStyle.icon("HistoryClose", color: .white, size: 12)?
            .draw(in: NSRect(x: (bounds.width - 12) / 2, y: (bounds.height - 12) / 2, width: 12, height: 12))
    }
}

/// Board "Add image": a dashed strong hairline, a plus glyph and the label.
final class WidgetInputAddTile: NSControl {
    private let title: String
    private var hovering = false { didSet { needsDisplay = true } }

    init(frame frameRect: NSRect, title: String) {
        self.title = title
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { sendAction(action, to: target) } }
    override func accessibilityPerformPress() -> Bool { sendAction(action, to: target) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: PanelStyle.Radius.thumb, yRadius: PanelStyle.Radius.thumb)
        if hovering { PanelStyle.rowHover.setFill(); path.fill() }
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.lineWidth = 1
        WidgetInputStyle.lineStrong.setStroke()
        path.stroke()
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            let tinted = NSImage(size: plus.size, flipped: false) { rect in
                plus.draw(in: rect)
                PanelStyle.textSecondary.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (bounds.width - plus.size.width) / 2, y: 1 + (16 - plus.size.height) / 2,
                                   width: plus.size.width, height: plus.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(string: title, attributes: [
            .font: PanelStyle.inspectFont(ofSize: 12), .foregroundColor: PanelStyle.textSecondary,
            .paragraphStyle: paragraph
        ]).draw(with: NSRect(x: 0, y: 25, width: bounds.width, height: 15), options: [.usesLineFragmentOrigin])
    }
}

/// Draws an editable mask over the source image and exports a transparent PNG
/// whose white pixels are the selected area.
private final class WidgetMaskCanvas: NSView {
    private struct Stroke {
        var points: [CGPoint]
        let widthFraction: CGFloat
    }

    let sourceImage: NSImage
    var brushSize: CGFloat = 32 { didSet { updateBrushCursor() } }
    private var strokes: [Stroke] = []
    /// The pointer over the image is a circle the size of the brush (not a crosshair); the system cursor is blank there.
    private let brushCursor = CAShapeLayer()
    private var hoverPoint: CGPoint?
    private static let blankCursor = NSCursor(
        image: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true },
        hotSpot: NSPoint(x: 8, y: 8))

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
        super.init(frame: .zero)
        wantsLayer = true
        brushCursor.fillColor = nil
        brushCursor.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        brushCursor.lineWidth = 1.5
        brushCursor.shadowColor = NSColor.black.cgColor
        brushCursor.shadowOpacity = 0.55
        brushCursor.shadowRadius = 2
        brushCursor.shadowOffset = .zero
        brushCursor.isHidden = true
        layer?.addSublayer(brushCursor)
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
                                      color: WidgetInputStyle.maskColor.cgColor) {
            NSImage(cgImage: mask, size: target.size)
                .draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.55)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        let normalized = normalize(point)
        // The brush is sized in on-screen points, as a fraction of the displayed image width, so it
        // looks the same for a 600 px and a 6000 px photo; the export scales it to the source pixels.
        strokes.append(Stroke(points: [normalized],
                              widthFraction: brushSize / max(1, imageRect.width)))
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: Self.blankCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { moveBrushCursor(to: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { moveBrushCursor(to: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hoverPoint = nil; updateBrushCursor() }

    private func moveBrushCursor(to point: CGPoint) {
        hoverPoint = imageRect.contains(point) ? point : nil
        updateBrushCursor()
    }

    private func updateBrushCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hoverPoint {
            let diameter = brushSize
            brushCursor.path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2,
                                                        width: diameter, height: diameter), transform: nil)
            brushCursor.position = hoverPoint
            brushCursor.isHidden = false
        } else {
            brushCursor.isHidden = true
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !strokes.isEmpty else { return }
        let rect = imageRect
        let point = convert(event.locationInWindow, from: nil)
        let clamped = CGPoint(x: max(rect.minX, min(point.x, rect.maxX)),
                              y: max(rect.minY, min(point.y, rect.maxY)))
        strokes[strokes.count - 1].points.append(normalize(clamped))
        moveBrushCursor(to: point)
        needsDisplay = true
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: (point.x - rect.minX) / max(1, rect.width),
                       y: (point.y - rect.minY) / max(1, rect.height))
    }

    func undo() { if !strokes.isEmpty { strokes.removeLast(); needsDisplay = true } }
    func clear() { strokes.removeAll(); needsDisplay = true }
    /// True only when some painted pixels survive the erase strokes.
    var hasPaint: Bool {
        guard !strokes.isEmpty else { return false }
        let rect = imageRect
        let width = 128
        let height = max(1, Int((CGFloat(width) * rect.height / max(1, rect.width)).rounded()))
        guard let mask = Self.renderMask(strokes: strokes, width: width, height: height,
                                         color: NSColor.white.cgColor),
              let data = mask.dataProvider?.data as Data? else { return false }
        // RGBA, premultiplied: every fourth byte is alpha.
        return stride(from: 3, to: data.count, by: 4).contains { data[$0] > 0 }
    }

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

/// Board "Size" slider (Figma 29): a 2 pt strong-hairline track filled in
/// text/1 up to a 14 pt knob.
private final class WidgetMaskSizeSlider: NSControl {
    var minValue: Double = 8
    var maxValue: Double = 128
    var value: Double = 32 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Brush size".localized)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var fraction: CGFloat { CGFloat((value - minValue) / max(1, maxValue - minValue)) }

    override func draw(_ dirtyRect: NSRect) {
        let travel = bounds.width - 14
        let knobX = travel * fraction
        WidgetInputStyle.lineStrong.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 2), xRadius: 1, yRadius: 1).fill()
        PanelStyle.textPrimary.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: bounds.midY - 1, width: knobX + 7, height: 2), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: bounds.midY - 7, width: 14, height: 14)).fill()
    }

    override func mouseDown(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }

    private func track(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x - 7
        set(minValue + Double(min(1, max(0, x / max(1, bounds.width - 14)))) * (maxValue - minValue))
    }

    private func set(_ newValue: Double) {
        let clamped = min(maxValue, max(minValue, newValue.rounded()))
        guard clamped != value else { return }
        value = clamped
        sendAction(action, to: target)
    }

    override func accessibilityValue() -> Any? { NSNumber(value: value) }
    override func accessibilityPerformIncrement() -> Bool { set(value + 8); return true }
    override func accessibilityPerformDecrement() -> Bool { set(value - 8); return true }
}

/// A text-only action (Figma 29 "Undo", "Clear mask"): 12 pt text/2, text/1 on hover.
private final class WidgetInputTextButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        NSAttributedString(string: title, attributes: [
            .font: PanelStyle.inspectFont(ofSize: 12),
            .foregroundColor: hovering || isHighlighted ? PanelStyle.textPrimary : PanelStyle.textSecondary
        ]).draw(with: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
    override var isFlipped: Bool { true }
}

/// Figma `29 · Widget Input / Draw Mask`: the image on the stage with the brush,
/// the mask tools in the form. Exports the same white-on-transparent PNG.
final class WidgetMaskEditorPanel: NSPanel {
    var onUse: ((URL) -> Void)?
    private let canvas: WidgetMaskCanvas
    private let slider = WidgetMaskSizeSlider(frame: .zero)
    private let sizeLabel = WidgetInputTextView(frame: .zero)
    private let errorLabel = WidgetInputTextView(frame: .zero)
    private let useButton = WidgetInputStyle.button("Use mask".localized, primary: true, target: nil, action: nil)
    private let designRoot = PanelStyle.makeFrostedBase(cornerRadius: PanelStyle.Radius.window)
    private var restoredFrame: NSRect?

    init(sourceImage: NSImage) {
        canvas = WidgetMaskCanvas(sourceImage: sourceImage)
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
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func buildUI() {
        let container = NSView(frame: NSRect(origin: .zero, size: WidgetInputStyle.board))
        contentView = container
        let root = designRoot
        root.frame = container.bounds
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(WidgetInputStyle.lineStrong)
        container.addSubview(root)
        WidgetInputStyle.buildChrome(in: root, title: "", target: self, close: #selector(cancelTapped),
                                     minimize: #selector(minimizeTapped), zoom: #selector(zoomTapped))
        WidgetInputStyle.addHeader(to: root, eyebrow: "\("Widget".localized)  ·  \("Mask".localized)",
                                   title: "Draw mask".localized,
                                   description: "Paint the area the Widget should change.".localized)
        // Board "image" (120, 116, 760 × 570); the canvas keeps its 10 pt inset around the picture.
        canvas.frame = WidgetInputStyle.frame(110, 106, 780, 590)
        root.addSubview(canvas)

        let x = WidgetInputStyle.formX, width = WidgetInputStyle.formWidth
        WidgetInputStyle.addSectionLabel(to: root, "Mask".localized, y: 232)
        // Board "tool": a 31 pt ink/2 track holding the selected Brush (ink/3). There is no
        // eraser (Undo and Clear mask cover mistakes), so Brush spans the track.
        let track = NSView(frame: WidgetInputStyle.frame(x, 255, width, 31))
        track.wantsLayer = true
        track.layer?.cornerRadius = PanelStyle.Radius.control
        track.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.overlay)
        root.addSubview(track)
        let brush = NSView(frame: NSRect(x: 2, y: 2, width: width - 4, height: 27))
        brush.wantsLayer = true
        brush.layer?.cornerRadius = PanelStyle.Radius.control - 1
        brush.layer?.backgroundColor = PanelStyle.resolvedCG(WidgetInputStyle.ink3)
        track.addSubview(brush)
        let brushTitle = PanelCenteredTextView(frame: brush.bounds)
        brushTitle.string = "Brush".localized
        brushTitle.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        brushTitle.textColor = PanelStyle.textPrimary
        brush.addSubview(brushTitle)

        root.addSubview(WidgetInputStyle.text("Size".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                              color: PanelStyle.textTertiary, frame: WidgetInputStyle.frame(x, 300, 30, 15)))
        slider.frame = WidgetInputStyle.frame(x + 34, 300.5, 270, 14)
        slider.target = self
        slider.action = #selector(sizeChanged(_:))
        root.addSubview(slider)
        sizeLabel.string = "32 px"
        sizeLabel.font = PanelStyle.monoFont(ofSize: 11)
        sizeLabel.textColor = PanelStyle.textSecondary
        sizeLabel.alignment = .right
        sizeLabel.frame = WidgetInputStyle.frame(x + width - 50, 300.5, 50, 14)
        root.addSubview(sizeLabel)

        let undoTitle = "Undo".localized
        let undoWidth = WidgetInputStyle.textWidth(undoTitle, font: PanelStyle.inspectFont(ofSize: 12)) + 2
        let undo = WidgetInputTextButton(title: undoTitle, target: self, action: #selector(undoTapped))
        undo.frame = WidgetInputStyle.frame(x, 329, undoWidth, 15)
        root.addSubview(undo)
        let clearTitle = "Clear mask".localized
        let clear = WidgetInputTextButton(title: clearTitle, target: self, action: #selector(clearTapped))
        clear.frame = WidgetInputStyle.frame(x + undoWidth + 16, 329,
                                             WidgetInputStyle.textWidth(clearTitle, font: PanelStyle.inspectFont(ofSize: 12)) + 2, 15)
        root.addSubview(clear)

        let swatch = NSView(frame: WidgetInputStyle.frame(x, 360.5, 10, 10))
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 2
        swatch.layer?.backgroundColor = PanelStyle.resolvedCG(WidgetInputStyle.maskColor)
        root.addSubview(swatch)
        root.addSubview(WidgetInputStyle.text("The highlighted area will be changed.".localized,
                                              font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary,
                                              frame: WidgetInputStyle.frame(x + 18, 358, width - 18, 15)))

        errorLabel.font = PanelStyle.inspectFont(ofSize: 12)
        errorLabel.textColor = PanelStyle.failure
        errorLabel.maximumNumberOfLines = 2
        errorLabel.frame = WidgetInputStyle.frame(x, 790, width, 32)
        root.addSubview(errorLabel)
        useButton.target = self
        useButton.action = #selector(useTapped)
        WidgetInputStyle.addActions(to: root,
                                    cancel: WidgetInputStyle.button("Cancel".localized, primary: false,
                                                                    target: self, action: #selector(cancelTapped)),
                                    run: useButton, runTitle: "Use mask".localized)
    }

    func present(over parentWindow: NSWindow) {
        setFrame(ScreenManager.shared.contentFrame(for: frame.size), display: true)
        fitDesignRoot()
        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    private func fitDesignRoot() { WidgetInputStyle.fit(designRoot, in: contentView) }

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
    @objc private func undoTapped() { canvas.undo() }
    @objc private func clearTapped() { canvas.clear() }
    @objc private func sizeChanged(_ sender: WidgetMaskSizeSlider) {
        canvas.brushSize = CGFloat(sender.value)
        sizeLabel.string = "\(Int(sender.value)) px"
    }

    @objc private func useTapped() {
        guard canvas.hasPaint else {
            errorLabel.string = "Draw a mask before using it.".localized
            return
        }
        guard let export = canvas.maskExporter() else {
            errorLabel.string = WidgetMaskError.exportFailed.localizedDescription
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
                    self?.errorLabel.string = error.localizedDescription
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
