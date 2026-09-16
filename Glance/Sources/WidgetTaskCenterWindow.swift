import AppKit

final class WidgetTaskCenterWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    private let filter = NSSegmentedControl(labels: ["All".localized, "Running".localized, "Completed".localized, "Failed".localized], trackingMode: .selectOne, target: nil, action: nil)
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let openButton = NSButton(title: "Open".localized, target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal in Finder".localized, target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry".localized, target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Record".localized, target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear History".localized, target: nil, action: nil)
    private let detailPanel = NSView()
    private let detailTitle = NSTextField(labelWithString: "Select a task".localized)
    private let detailStatus = NSTextField(labelWithString: "")
    private let detailTimeline = NSTextField(wrappingLabelWithString: "")
    private var visibleRecords: [WidgetTaskRecord] = []

    init() {
        super.init(contentRect: ScreenManager.shared.contentFrame(for: NSSize(width: 760, height: 560)), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        title = "Tasks".localized; minSize = NSSize(width: 560, height: 380); isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua); isOpaque = false; backgroundColor = .clear
        buildUI(); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(tasksChanged), name: WidgetTaskManager.didChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        guard let content = contentView else { return }
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 14)
        frost.frame = content.bounds; frost.autoresizingMask = [.width, .height]
        content.addSubview(frost, positioned: .below, relativeTo: nil)
        content.wantsLayer = true
        content.layer?.backgroundColor = PanelStyle.canvas.withAlphaComponent(0.22).cgColor
        filter.selectedSegment = 0; filter.target = self; filter.action = #selector(filterChanged); filter.segmentStyle = .texturedRounded
        filter.controlSize = .small
        filter.frame = NSRect(x: 18, y: content.bounds.height - 46, width: 360, height: 28); filter.autoresizingMask = [.maxXMargin, .minYMargin]
        content.addSubview(filter)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task")); column.title = "Task".localized; column.width = 700
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 78; table.intercellSpacing = NSSize(width: 0, height: 8); table.delegate = self; table.dataSource = self
        table.doubleAction = #selector(openSelected); table.target = self
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.backgroundColor = .clear; scroll.contentView.backgroundColor = .clear
        table.backgroundColor = .clear
        scroll.frame = NSRect(x: 0, y: 52, width: content.bounds.width - 286, height: content.bounds.height - 104); scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)
        detailPanel.wantsLayer = true
        detailPanel.layer?.backgroundColor = PanelStyle.surface.withAlphaComponent(0.84).cgColor
        detailPanel.layer?.borderColor = PanelStyle.hairline.cgColor
        detailPanel.layer?.borderWidth = 1
        detailPanel.frame = NSRect(x: content.bounds.width - 286, y: 52, width: 268, height: content.bounds.height - 70)
        detailPanel.autoresizingMask = [.minXMargin, .height]
        content.addSubview(detailPanel)
        detailTitle.font = PanelStyle.title; detailTitle.textColor = PanelStyle.textPrimary
        detailTitle.frame = NSRect(x: 18, y: detailPanel.bounds.height - 38, width: 232, height: 22)
        detailTitle.autoresizingMask = [.width, .minYMargin]; detailPanel.addSubview(detailTitle)
        detailStatus.font = PanelStyle.caption; detailStatus.textColor = PanelStyle.warmCue
        detailStatus.frame = NSRect(x: 18, y: detailPanel.bounds.height - 64, width: 232, height: 18)
        detailStatus.autoresizingMask = [.width, .minYMargin]; detailPanel.addSubview(detailStatus)
        detailTimeline.font = PanelStyle.caption; detailTimeline.textColor = PanelStyle.textSecondary
        detailTimeline.frame = NSRect(x: 18, y: 30, width: 232, height: detailPanel.bounds.height - 112)
        detailTimeline.autoresizingMask = [.width, .height]; detailPanel.addSubview(detailTimeline)
        let buttons = [openButton, revealButton, retryButton, removeButton, clearButton]
        let actions: [Selector] = [#selector(openSelected), #selector(revealSelected), #selector(retrySelected), #selector(removeSelected), #selector(clearAll)]
        var x: CGFloat = 18
        for (button, action) in zip(buttons, actions) { button.target = self; button.action = action; button.bezelStyle = .rounded; button.contentTintColor = PanelStyle.textPrimary; button.sizeToFit(); button.frame.origin = NSPoint(x: x, y: 14); content.addSubview(button); x += button.frame.width + 10 }
        table.action = #selector(selectionChanged)
    }

    func refresh() {
        let records = WidgetTaskManager.shared.records
        switch filter.selectedSegment {
        case 1: visibleRecords = records.filter { $0.phase.isActive }
        case 2: visibleRecords = records.filter { $0.phase == .completed }
        case 3: visibleRecords = records.filter { $0.phase == .failed || $0.phase == .interrupted }
        default: visibleRecords = records
        }
        table.reloadData(); updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRecords.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = visibleRecords[row]
        let cell = NSTableCellView(); cell.wantsLayer = true
        cell.layer?.backgroundColor = PanelStyle.glassCard.cgColor
        cell.layer?.cornerRadius = PanelStyle.cornerMedium
        cell.layer?.borderWidth = 1
        cell.layer?.borderColor = PanelStyle.hairline.cgColor
        let preview = NSImageView(frame: NSRect(x: 12, y: 17, width: 44, height: 44)); preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true; preview.layer?.cornerRadius = 8; preview.layer?.masksToBounds = true
        let previewURL = record.output.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? record.source
        preview.image = previewURL.flatMap { $0.isFileURL ? NSImage(contentsOf: $0) : nil }
            ?? NSImage(systemSymbolName: record.phase.isActive ? "hourglass" : "photo", accessibilityDescription: nil)
        cell.addSubview(preview)
        let label = NSTextField(labelWithString: "\(record.widgetName)  ·  \(record.commandName)"); label.font = PanelStyle.headline; label.frame = NSRect(x: 72, y: 45, width: max(100, table.bounds.width - 180), height: 18); label.autoresizingMask = [.width]; label.textColor = PanelStyle.textPrimary; cell.addSubview(label); cell.textField = label
        let detail = NSTextField(labelWithString: detailText(record)); detail.font = PanelStyle.caption; detail.frame = NSRect(x: 72, y: 22, width: max(100, table.bounds.width - 180), height: 16); detail.autoresizingMask = [.width]; detail.textColor = PanelStyle.textSecondary; detail.lineBreakMode = .byTruncatingTail; cell.addSubview(detail)
        let pill = NSTextField(labelWithString: stateText(record)); pill.font = NSFont.systemFont(ofSize: 10, weight: .semibold); pill.alignment = .center; pill.textColor = stateColor(record); pill.frame = NSRect(x: table.bounds.width - 102, y: 35, width: 86, height: 20); pill.autoresizingMask = [.minXMargin]; pill.wantsLayer = true; pill.layer?.cornerRadius = 10; pill.layer?.backgroundColor = stateColor(record).withAlphaComponent(0.14).cgColor; cell.addSubview(pill)
        cell.setAccessibilityLabel(summary(record)); return cell
    }

    private func detailText(_ record: WidgetTaskRecord) -> String { "\(record.source?.lastPathComponent ?? "Media")  ·  \(DateFormatter.localizedString(from: record.createdAt, dateStyle: .short, timeStyle: .short))" }
    private func stateText(_ record: WidgetTaskRecord) -> String { switch record.phase { case .processing: return record.progress > 0 ? "\(record.progress)%" : "Processing".localized; case .uploading: return "Uploading".localized; case .submitting: return "Submitting".localized; case .downloading: return "Downloading".localized; case .completed: return "Completed".localized; case .failed: return "Failed".localized; case .interrupted: return "Interrupted".localized } }
    private func stateColor(_ record: WidgetTaskRecord) -> NSColor { record.phase.isActive ? PanelStyle.warmCue : (record.phase == .failed || record.phase == .interrupted ? PanelStyle.failure : PanelStyle.success) }

    private func summary(_ record: WidgetTaskRecord) -> String {
        let source = record.source?.lastPathComponent ?? "Media"
        let state: String
        switch record.phase {
        case .processing: state = record.progress > 0 ? "Processing \(record.progress)%" : "Processing…".localized
        case .uploading: state = "Uploading…".localized
        case .submitting: state = "Submitting…".localized
        case .downloading: state = "Downloading result…".localized
        case .completed: state = FileManager.default.fileExists(atPath: record.outputPath ?? "") ? "Completed".localized : "Missing File".localized
        case .failed: state = "Failed".localized
        case .interrupted: state = "Interrupted".localized
        }
        let time = DateFormatter.localizedString(from: record.createdAt, dateStyle: .short, timeStyle: .short)
        return "\(record.widgetName) · \(record.commandName)\n\(source)   —   \(state)   ·   \(time)"
    }

    private var selected: WidgetTaskRecord? { let row = table.selectedRow; return visibleRecords.indices.contains(row) ? visibleRecords[row] : nil }
    @objc private func tasksChanged() { refresh() }
    @objc private func filterChanged() { refresh() }
    @objc private func selectionChanged() { updateButtons() }
    private func updateButtons() { let record = selected; let exists = record?.output.map { FileManager.default.fileExists(atPath: $0.path) } == true; openButton.isEnabled = exists; revealButton.isEnabled = exists; retryButton.isEnabled = record?.phase == .failed || record?.phase == .interrupted || (record?.phase == .completed && !exists); removeButton.isEnabled = record != nil && record?.phase.isActive == false; clearButton.isEnabled = WidgetTaskManager.shared.records.contains { !$0.phase.isActive }; updateDetail(record) }
    private func updateDetail(_ record: WidgetTaskRecord?) {
        guard let record else {
            detailTitle.stringValue = "Select a task".localized
            detailStatus.stringValue = ""
            detailTimeline.stringValue = "Choose a task to inspect its progress and actions.".localized
            return
        }
        detailTitle.stringValue = record.widgetName
        detailStatus.stringValue = stateText(record)
        let source = record.source?.lastPathComponent ?? "Media"
        let output = record.output?.lastPathComponent ?? "Waiting for output".localized
        detailTimeline.stringValue = "\("Task submitted".localized)\n\(DateFormatter.localizedString(from: record.createdAt, dateStyle: .short, timeStyle: .short))\n\n\("Input".localized)\n\(source)\n\n\("Command".localized)\n\(record.commandName)\n\n\("Output".localized)\n\(output)\n\n\("Status".localized)\n\(record.errorMessage ?? stateText(record))"
    }
    @objc private func openSelected() { if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) } }
    @objc private func revealSelected() { if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func retrySelected() { if let id = selected?.id { WidgetTaskManager.shared.retry(id) } }
    @objc private func removeSelected() { if let id = selected?.id { WidgetTaskManager.shared.remove(id) } }
    @objc private func clearAll() {
        let alert = NSAlert(); alert.messageText = "Clear finished task history?".localized
        alert.informativeText = "Downloaded files will not be deleted.".localized
        alert.addButton(withTitle: "Clear".localized); alert.addButton(withTitle: "Cancel".localized)
        alert.beginSheetModal(for: self) { if $0 == .alertFirstButtonReturn { WidgetTaskManager.shared.clear() } }
    }
}
