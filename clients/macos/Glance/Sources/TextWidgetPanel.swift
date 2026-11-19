import AppKit
import UniformTypeIdentifiers

/// Runs a Widget whose command takes only text (for example an X post link),
/// in the 静 Shizuka language of the other Widget inputs. One window carries the
/// whole run: input, price, progress, the result in ~/Downloads/Glance, or the
/// failure with its true credit status. The input is kept until the user edits it.
final class TextWidgetPanel: NSPanel, NSTextViewDelegate {
    /// One panel per Widget, so a second "Run" brings the open one forward.
    private static var open: [String: TextWidgetPanel] = [:]

    /// Installed Widgets that take only text, as a group for the image and
    /// video action menus: they need no media, so they are always runnable.
    static func menuEntries() -> [ActionMenuEntry] {
        let widgets = WidgetRegistry.shared.available.filter(\.hasTextOnlyCommand)
        guard !widgets.isEmpty else { return [] }
        var entries: [ActionMenuEntry] = [.header("Text input".localized)]
        for widget in widgets {
            let commands = widget.localizedCommands.filter(\.isTextOnly)
            func entry(_ command: WidgetCommand) -> ActionMenuEntry {
                ActionMenuEntry(title: commands.count == 1 ? widget.displayName : command.name,
                                creditCost: widget.taskCreditCost,
                                action: { present(widget: widget, command: command) })
            }
            entries.append(commands.count == 1 ? entry(commands[0])
                : ActionMenuEntry(title: widget.displayName, creditCost: widget.taskCreditCost, submenu: commands.map(entry)))
        }
        return entries
    }

    static func present(widget: WidgetManifest, command: WidgetCommand) {
        if let panel = open[widget.id] {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = TextWidgetPanel(widget: widget, command: command)
        open[widget.id] = panel
        panel.setFrame(ScreenManager.shared.contentFrame(for: panel.frame.size), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(panel.field.textView)
    }

    private enum Layout {
        static let size = NSSize(width: 560, height: 640)
        static let x: CGFloat = 48
        static let width: CGFloat = 464
        static let fieldTop: CGFloat = 250
        static let fieldHeight: CGFloat = 112
        static let statusTop: CGFloat = 404
        static let costTop: CGFloat = 528
        static let actionsTop: CGFloat = 588
    }

    private let widget: WidgetManifest
    private let command: WidgetCommand
    private let maxLength: Int?
    private let root = FlippedRootView()
    private let field: WidgetPromptField
    private let counter = WidgetInputTextView(frame: .zero)
    private lazy var pasteButton = TextWidgetLinkButton(title: "Paste".localized) { [weak self] in self?.pasteTapped() }

    private let statusDot = NSView()
    private let statusTitle = WidgetInputTextView(frame: .zero)
    private let statusValue = WidgetInputTextView(frame: .zero)
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let statusDetail = WidgetInputTextView(frame: .zero)
    private let creditsLine = WidgetInputTextView(frame: .zero)
    /// Figma W1 (Ready): where the run happens, shown until a task exists.
    private let idleNote = WidgetInputTextView(frame: .zero)
    /// Figma W1: shortcut hint beside Close.
    private let shortcutHint = WidgetInputTextView(frame: .zero)

    private lazy var closeButton = WidgetInputStyle.button("Close".localized, primary: false, target: self, action: #selector(closeTapped))
    private lazy var runButton = WidgetInputStyle.button("Run".localized, primary: true, target: self, action: #selector(runTapped))
    private lazy var cancelTaskButton = WidgetInputStyle.button("Cancel".localized, primary: false, target: self, action: #selector(cancelTaskTapped))
    private lazy var revealButton = WidgetInputStyle.button("Reveal in Finder".localized, primary: false, target: self, action: #selector(revealTapped))
    private lazy var openButton = WidgetInputStyle.button("Open in Inspect".localized, primary: true, target: self, action: #selector(openTapped))
    private lazy var retryButton = WidgetInputStyle.button("Try again".localized, primary: true, target: self, action: #selector(retryTapped))

    /// The run this window follows. The record appears at the click (before the
    /// price check answers), so it is matched by its text and start time.
    private var trackedID: UUID?
    private var pendingText: String?
    private var submittedAt = Date.distantPast
    private var observer: NSObjectProtocol?

    private init(widget: WidgetManifest, command: WidgetCommand) {
        self.widget = widget
        self.command = command
        let localized = widget.localizedCommands.first { $0.id == command.id } ?? command
        let promptSchema = Self.promptSchema(command)
        maxLength = promptSchema.maxLength
        field = WidgetPromptField(frame: NSRect(x: Layout.x, y: Layout.fieldTop, width: Layout.width, height: Layout.fieldHeight),
                                  enabled: true)
        super.init(contentRect: NSRect(origin: .zero, size: Layout.size),
                   styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        appearance = PanelStyle.windowAppearance
        title = widget.displayName

        root.frame = NSRect(origin: .zero, size: Layout.size)
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(WidgetInputStyle.lineStrong)
        contentView = root
        buildChrome()
        buildHeader(localized: localized)
        buildInput(placeholder: promptSchema.placeholder ?? localized.description)
        buildStatus()
        WidgetInputStyle.addCostRowFlipped(to: root, x: Layout.x, width: Layout.width, y: Layout.costTop,
            cost: widget.taskCreditCost == 0 ? "Free of charge".localized : widget.creditCostLabel)
        for button in [closeButton, runButton, cancelTaskButton, revealButton, openButton, retryButton] { root.addSubview(button) }

        observer = NotificationCenter.default.addObserver(forName: WidgetTaskManager.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        Self.open[widget.id] = nil
        super.close()
    }

    override func cancelOperation(_ sender: Any?) { close() }

    /// ⌘↵ runs, like the other Widget inputs.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
            if runButton.isEnabled, !runButton.isHidden { runTapped() } else if retryButton.isEnabled, !retryButton.isHidden { retryTapped() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Build

    private func buildChrome() {
        for (index, (color, action)) in [
            (NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), #selector(closeTapped)),
            (NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), #selector(minimizeTapped)),
            (NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), #selector(minimizeTapped))
        ].enumerated() {
            let button = TrafficLightButton(color: color, target: self, action: action)
            button.frame = NSRect(x: 20 + CGFloat(index) * 20, y: 16, width: 12, height: 12)
            root.addSubview(button)
        }
        let title = text(widget.displayName, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                         color: PanelStyle.textSecondary, frame: NSRect(x: 100, y: 14, width: Layout.size.width - 200, height: 16))
        title.alignment = .center
    }

    private func buildHeader(localized: WidgetCommand) {
        let outputs = Set(command.outputs).sorted().map { $0.capitalized.localized }.joined(separator: ", ")
        let eyebrow = text("\("Widget".localized)  ·  \("Text".localized) → \(outputs)".uppercased(),
                           font: PanelStyle.monoFont(ofSize: 11), color: PanelStyle.textTertiary,
                           frame: NSRect(x: Layout.x, y: 76, width: Layout.width, height: 14))
        eyebrow.kern = 0.66   // Figma 6%
        text(localized.name, font: PanelStyle.titleFont(ofSize: 28), color: PanelStyle.textPrimary,
             frame: NSRect(x: Layout.x, y: 98, width: Layout.width, height: 38))
        text(localized.description, font: PanelStyle.inspectFont(ofSize: 13), color: PanelStyle.textSecondary,
             frame: NSRect(x: Layout.x, y: 144, width: Layout.width, height: 63), lines: 3, lineHeight: 21)
    }

    private func buildInput(placeholder: String) {
        text("Input".localized, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary,
             frame: NSRect(x: Layout.x, y: 228, width: 200, height: 15))
        counter.font = PanelStyle.monoFont(ofSize: 11)
        counter.textColor = PanelStyle.textTertiary
        counter.alignment = .right
        counter.frame = NSRect(x: Layout.x + Layout.width - 140, y: 228, width: 140, height: 14)
        root.addSubview(counter)
        field.setPlaceholder(placeholder)
        field.textView.delegate = self
        root.addSubview(field)
        pasteButton.frame = NSRect(x: Layout.x, y: Layout.fieldTop + Layout.fieldHeight + 10, width: pasteButton.fittingWidth, height: 18)
        root.addSubview(pasteButton)
    }

    private func buildStatus() {
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        statusDot.frame = NSRect(x: Layout.x, y: Layout.statusTop + 5, width: 6, height: 6)
        root.addSubview(statusDot)
        statusTitle.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        statusTitle.textColor = PanelStyle.textPrimary
        statusTitle.frame = NSRect(x: Layout.x + 14, y: Layout.statusTop, width: Layout.width - 120, height: 16)
        root.addSubview(statusTitle)
        statusValue.font = PanelStyle.monoFont(ofSize: 11)
        statusValue.textColor = PanelStyle.textTertiary
        statusValue.alignment = .right
        statusValue.frame = NSRect(x: Layout.x + Layout.width - 100, y: Layout.statusTop + 1, width: 100, height: 14)
        root.addSubview(statusValue)
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surfaceElevated)
        progressTrack.layer?.cornerRadius = 1
        progressTrack.frame = NSRect(x: Layout.x, y: Layout.statusTop + 26, width: Layout.width, height: 2)
        root.addSubview(progressTrack)
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.textPrimary)
        progressFill.layer?.cornerRadius = 1
        progressTrack.addSubview(progressFill)
        statusDetail.font = PanelStyle.inspectFont(ofSize: 12)
        statusDetail.textColor = PanelStyle.textSecondary
        statusDetail.maximumNumberOfLines = 3
        statusDetail.lineBreakMode = .byWordWrapping
        statusDetail.lineHeight = 18
        statusDetail.frame = NSRect(x: Layout.x, y: Layout.statusTop + 40, width: Layout.width, height: 54)
        root.addSubview(statusDetail)
        creditsLine.font = PanelStyle.inspectFont(ofSize: 12)
        creditsLine.frame = NSRect(x: Layout.x, y: Layout.statusTop + 98, width: Layout.width, height: 15)
        root.addSubview(creditsLine)
        idleNote.string = "Runs on Glance’s servers. Results are saved to ~/Downloads/Glance and listed in Task Center.".localized
        idleNote.font = PanelStyle.inspectFont(ofSize: 12)
        idleNote.textColor = PanelStyle.textTertiary
        idleNote.maximumNumberOfLines = 2
        idleNote.lineBreakMode = .byWordWrapping
        idleNote.lineHeight = 18
        idleNote.frame = NSRect(x: Layout.x, y: Layout.statusTop, width: Layout.width, height: 40)
        root.addSubview(idleNote)
        shortcutHint.string = "⌘↵ \("Run".localized)   esc \("Close".localized)"
        shortcutHint.font = PanelStyle.monoFont(ofSize: 11)
        shortcutHint.textColor = Peek.text4
        shortcutHint.frame = NSRect(x: Layout.x + WidgetInputStyle.buttonWidth("Close".localized) + 16,
                                    y: Layout.actionsTop + 8, width: 180, height: 16)
        root.addSubview(shortcutHint)
    }

    @discardableResult
    private func text(_ value: String, font: NSFont, color: NSColor, frame: NSRect,
                      lines: Int = 1, lineHeight: CGFloat? = nil) -> WidgetInputTextView {
        let view = WidgetInputStyle.text(value, font: font, color: color, frame: frame, lines: lines, lineHeight: lineHeight)
        if lines > 1 { view.lineBreakMode = .byWordWrapping }
        root.addSubview(view)
        return view
    }

    /// The `prompt` property's description and length limit, when the schema gives them.
    private static func promptSchema(_ command: WidgetCommand) -> (placeholder: String?, maxLength: Int?) {
        let properties: [String: JSONValue]
        if case .object(let value)? = command.parameterSchema["properties"] { properties = value } else { properties = [:] }
        guard case .object(let prompt)? = properties["prompt"] else { return (nil, nil) }
        var placeholder: String?
        if case .string(let value)? = prompt["description"], !value.isEmpty { placeholder = value }
        var maxLength: Int?
        if case .number(let value)? = prompt["maxLength"], value.isFinite, value > 0 { maxLength = Int(value) }
        return (placeholder, maxLength)
    }

    // MARK: - State

    private var trackedRecord: WidgetTaskRecord? {
        trackedID.flatMap { id in WidgetTaskManager.shared.records.first { $0.id == id } }
    }

    private var inputText: String { field.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refresh() {
        if trackedID == nil, let pending = pendingText {
            trackedID = WidgetTaskManager.shared.records.first {
                $0.isTextInput && $0.widgetID == widget.id && $0.commandID == command.id
                    && $0.input?.prompt == pending && $0.createdAt >= submittedAt.addingTimeInterval(-1)
            }?.id
            // Sign-in, top-up or the price check is still in front of the run.
            if trackedID == nil, Date().timeIntervalSince(submittedAt) > 600 { pendingText = nil }
        } else if trackedID != nil, trackedRecord == nil {
            // The price check was dismissed or the record was removed: nothing ran.
            trackedID = nil
            pendingText = nil
        }

        let count = field.text.count
        counter.string = maxLength.map { "\(count) / \($0)" } ?? ""
        counter.textColor = maxLength.map { count > $0 } == true ? PanelStyle.failure : PanelStyle.textTertiary
        let validInput = !inputText.isEmpty && (maxLength.map { count <= $0 } ?? true)

        guard let record = trackedRecord else {
            // No run yet (or sign-in / top-up still open): Run stays available.
            setStatusVisible(false)
            layoutActions(right: [runButton])
            setEnabled(runButton, validInput)
            return
        }
        setStatusVisible(true)
        let outputs = Self.outputFiles(record)
        if record.phase.isActive {
            let title: String
            switch record.phase {
            case .uploading: title = "Preparing…".localized
            case .submitting: title = "Submitting…".localized
            case .downloading: title = "Downloading result…".localized
            default: title = "Running…".localized
            }
            showStatus(dot: PanelStyle.info, title: title,
                       value: record.progress > 0 ? "\(record.progress)%" : "",
                       progress: CGFloat(min(100, max(0, record.progress))) / 100,
                       detail: record.queueText ?? "You can close this window. The task keeps running in Task Center.".localized,
                       credits: record.billingStatusText, creditsColor: PanelStyle.textSecondary)
            layoutActions(right: WidgetTaskManager.shared.canCancel(record) ? [cancelTaskButton] : [])
        } else if record.phase == .completed {
            let folder = record.output.map { $0.hasDirectoryPath || Self.isDirectory($0) ? $0 : $0.deletingLastPathComponent() }
            let place = folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
            showStatus(dot: PanelStyle.success, title: "Widget completed".localized,
                       value: outputs.isEmpty ? "" : String(format: "%d files".localized, outputs.count),
                       progress: nil, detail: String(format: "Saved to %@".localized, place),
                       credits: record.billingStatusText, creditsColor: PanelStyle.textSecondary)
            let media = outputs.filter(Self.isMedia)
            layoutActions(right: media.isEmpty ? [revealButton] : [revealButton, openButton])
        } else {
            let cancelled = record.phase == .cancelled
            let reason = record.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = cancelled ? "You cancelled this task.".localized
                : (reason?.isEmpty == false ? reason! : "The task stopped without reporting a reason.".localized)
            let refunded = (record.refundedCredits ?? 0) > 0
            showStatus(dot: cancelled ? PanelStyle.textTertiary : PanelStyle.failure,
                       title: (cancelled ? "Task cancelled" : record.phase == .expired ? "Expired" : "Task failed").localized,
                       value: "", progress: nil, detail: detail, credits: record.billingStatusText,
                       creditsColor: refunded ? PanelStyle.success
                           : record.settlementOutcome != nil ? PanelStyle.info : PanelStyle.textSecondary)
            layoutActions(right: [retryButton])
            setEnabled(retryButton, validInput)
        }
    }

    private func setStatusVisible(_ visible: Bool) {
        for view in [statusDot, statusTitle, statusValue, progressTrack, statusDetail, creditsLine] { view.isHidden = !visible }
        idleNote.isHidden = visible
        shortcutHint.isHidden = visible
    }

    private func showStatus(dot: NSColor, title: String, value: String, progress: CGFloat?,
                            detail: String, credits: String?, creditsColor: NSColor) {
        statusDot.layer?.backgroundColor = PanelStyle.resolvedCG(dot)
        statusTitle.string = title
        statusValue.string = value
        progressTrack.isHidden = progress == nil
        progressFill.frame = NSRect(x: 0, y: 0, width: Layout.width * (progress ?? 0), height: 2)
        statusDetail.string = detail
        creditsLine.string = credits ?? ""
        creditsLine.textColor = creditsColor
        creditsLine.isHidden = credits == nil
    }

    /// Close at the left; the state's actions right-aligned, primary rightmost.
    private func layoutActions(right buttons: [PanelButton]) {
        for button in [runButton, cancelTaskButton, revealButton, openButton, retryButton] {
            button.isHidden = !buttons.contains(button)
        }
        let closeWidth = WidgetInputStyle.buttonWidth("Close".localized)
        closeButton.frame = NSRect(x: Layout.x, y: Layout.actionsTop, width: closeWidth, height: 32)
        var right = Layout.x + Layout.width
        for button in buttons.reversed() {
            let width = WidgetInputStyle.buttonWidth(button.title)
            right -= width
            button.frame = NSRect(x: right, y: Layout.actionsTop, width: width, height: 32)
            right -= 12
        }
    }

    private func setEnabled(_ button: PanelButton, _ enabled: Bool) {
        button.isEnabled = enabled
        let color = button.titleColor
        button.titleColor = color   // repaint the disabled tint
    }

    // MARK: - Results

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Files the run saved: the folder's contents for several outputs, else the one file.
    private static func outputFiles(_ record: WidgetTaskRecord) -> [URL] {
        guard let output = record.output else { return [] }
        guard isDirectory(output) else {
            return FileManager.default.fileExists(atPath: output.path) ? [output] : []
        }
        let items = (try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    // MARK: - Actions

    func textDidChange(_ notification: Notification) {
        // Editing the text after a finished run starts a fresh one.
        if let record = trackedRecord, !record.phase.isActive, record.input?.prompt != inputText {
            trackedID = nil
            pendingText = nil
        }
        refresh()
    }

    private func pasteTapped() {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { NSSound.beep(); return }
        field.textView.string = text
        field.textView.didChangeText()
        makeFirstResponder(field.textView)
    }

    @objc private func runTapped() {
        let value = inputText
        guard !value.isEmpty, trackedRecord?.phase.isActive != true else { return }
        guard let current = WidgetRegistry.shared.available.first(where: { $0.id == widget.id }),
              let runCommand = current.commands.first(where: { $0.id == command.id }) else {
            showStatus(dot: PanelStyle.failure, title: "Task failed".localized, value: "", progress: nil,
                       detail: "This Widget is no longer available.".localized, credits: "Not charged".localized,
                       creditsColor: PanelStyle.textSecondary)
            setStatusVisible(true)
            return
        }
        trackedID = nil
        pendingText = value
        submittedAt = Date()
        WidgetTaskManager.shared.startText(widget: current, command: runCommand, text: value, over: self)
        refresh()
    }

    @objc private func retryTapped() {
        if let record = trackedRecord, record.input?.prompt == inputText {
            trackedID = nil
            pendingText = inputText
            submittedAt = Date()
            WidgetTaskManager.shared.retry(record.id, over: self)
            refresh()
        } else {
            runTapped()
        }
    }

    @objc private func cancelTaskTapped() {
        guard let id = trackedID else { return }
        WidgetTaskManager.shared.cancel(id)
    }

    @objc private func revealTapped() {
        guard let record = trackedRecord else { return }
        let files = Self.outputFiles(record)
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
        else if let output = record.output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }

    @objc private func openTapped() {
        guard let record = trackedRecord else { return }
        let media = Self.outputFiles(record).filter(Self.isMedia)
        guard !media.isEmpty else { return }
        (NSApp.delegate as? AppDelegate)?.openMediaFromHome(media)
    }

    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
}

/// Top-origin root so the frames above read as drawn.
private final class FlippedRootView: NSView {
    override var isFlipped: Bool { true }
}

/// Quiet text action under the field: 12 pt text/2, text/1 on hover.
private final class TextWidgetLinkButton: NSControl {
    private let label = WidgetInputTextView(frame: .zero)
    private let onPress: () -> Void
    private var hovering = false { didSet { label.textColor = hovering ? PanelStyle.textPrimary : PanelStyle.textSecondary } }

    var fittingWidth: CGFloat { WidgetInputStyle.textWidth(label.string, font: label.font) + 2 }

    init(title: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        label.string = title
        label.font = PanelStyle.inspectFont(ofSize: 12)
        label.textColor = PanelStyle.textSecondary
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); label.frame = bounds }
    override func mouseDown(with event: NSEvent) { onPress() }
    override func accessibilityPerformPress() -> Bool { onPress(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}
