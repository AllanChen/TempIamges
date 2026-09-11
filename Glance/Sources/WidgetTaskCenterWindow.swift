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
    private var visibleRecords: [WidgetTaskRecord] = []

    init() {
        super.init(contentRect: ScreenManager.shared.contentFrame(for: NSSize(width: 760, height: 560)), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        title = "Tasks".localized; minSize = NSSize(width: 560, height: 380); isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua); backgroundColor = PanelStyle.canvas
        buildUI(); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(tasksChanged), name: WidgetTaskManager.didChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        guard let content = contentView else { return }
        filter.selectedSegment = 0; filter.target = self; filter.action = #selector(filterChanged)
        filter.frame = NSRect(x: 18, y: content.bounds.height - 46, width: 360, height: 26); filter.autoresizingMask = [.maxXMargin, .minYMargin]
        content.addSubview(filter)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task")); column.title = "Task".localized; column.width = 700
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 58; table.delegate = self; table.dataSource = self
        table.doubleAction = #selector(openSelected); table.target = self
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = true; scroll.backgroundColor = PanelStyle.canvas
        scroll.frame = NSRect(x: 0, y: 52, width: content.bounds.width, height: content.bounds.height - 104); scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)
        let buttons = [openButton, revealButton, retryButton, removeButton, clearButton]
        let actions: [Selector] = [#selector(openSelected), #selector(revealSelected), #selector(retrySelected), #selector(removeSelected), #selector(clearAll)]
        var x: CGFloat = 18
        for (button, action) in zip(buttons, actions) { button.target = self; button.action = action; button.bezelStyle = .rounded; button.sizeToFit(); button.frame.origin = NSPoint(x: x, y: 14); content.addSubview(button); x += button.frame.width + 10 }
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
        let cell = NSTableCellView()
        let preview = NSImageView(frame: NSRect(x: 10, y: 8, width: 42, height: 42)); preview.imageScaling = .scaleProportionallyUpOrDown
        let previewURL = record.output.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? record.source
        preview.image = previewURL.flatMap { $0.isFileURL ? NSImage(contentsOf: $0) : nil }
            ?? NSImage(systemSymbolName: record.phase.isActive ? "hourglass" : "photo", accessibilityDescription: nil)
        cell.addSubview(preview)
        let label = NSTextField(labelWithString: summary(record)); label.frame = NSRect(x: 64, y: 7, width: max(100, table.bounds.width - 78), height: 44); label.autoresizingMask = [.width]; label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingTail; label.textColor = PanelStyle.textPrimary; cell.addSubview(label); cell.textField = label
        cell.setAccessibilityLabel(summary(record)); return cell
    }

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
    private func updateButtons() { let record = selected; let exists = record?.output.map { FileManager.default.fileExists(atPath: $0.path) } == true; openButton.isEnabled = exists; revealButton.isEnabled = exists; retryButton.isEnabled = record?.phase == .failed || record?.phase == .interrupted || (record?.phase == .completed && !exists); removeButton.isEnabled = record != nil && record?.phase.isActive == false; clearButton.isEnabled = WidgetTaskManager.shared.records.contains { !$0.phase.isActive } }
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
