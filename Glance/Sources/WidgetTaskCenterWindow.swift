import AppKit

/// Task Center, built from the Figma "Task Center Redesign" board.
///
/// Two kinds of action, one place each:
///  - list actions (refresh, search, filters, clear finished) live in the list;
///  - task actions live in a single group at the top right of the detail and
///    change with the selected task's state. No toolbar band, no Info button.
final class WidgetTaskCenterWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    private static let designSize = NSSize(width: 1554, height: 1012)

    // Flipped so frames can be written with the board's top-left coordinates.
    private let root = FlippedDocView()
    private let titlebar = TaskCenterTitlebar()
    private let titleLabel = TaskPassthroughLabel(labelWithString: "Task Center".localized)
    private let countLabel = TaskPassthroughLabel(labelWithString: "")
    private lazy var closeButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))

    // List column: list-level actions only.
    private let sidebar = FlippedDocView()
    private let sidebarTitle = NSTextField(labelWithString: "Tasks".localized)
    private let sidebarEdge = NSView()
    private lazy var refreshButton = TaskGhostButton(icon: "TaskIconRefresh", tooltip: "Refresh".localized, tint: PanelStyle.textPrimary) { [weak self] in self?.refreshTapped() }
    private lazy var clearButton = TaskGhostButton(icon: "HistoryClear", tooltip: "Clear Finished".localized, tint: PanelStyle.failure, danger: true) { [weak self] in self?.clearAll() }
    private let searchBox = TaskSearchBox()
    private let pills = TaskPillBar(titles: ["All".localized, "Running".localized, "Done".localized, "Failed".localized])
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyListTitle = TaskPassthroughLabel(labelWithString: "")
    private let emptyListHint = TaskPassthroughLabel(labelWithString: "")

    // Detail column: one action group, then previews, timeline and properties.
    private let detail = FlippedDocView()
    private let detailTitle = NSTextField(labelWithString: "Select a task".localized)
    private let detailStatus = NSTextField(labelWithString: "")
    private lazy var showSourceButton = TaskActionButton(label: "Show Source".localized, icon: "HistoryFocus", style: .ghost) { [weak self] in self?.showSource() }
    private lazy var cancelButton = TaskActionButton(label: "Cancel".localized, icon: "TaskIconCancel", style: .danger) { [weak self] in self?.cancelSelected() }
    private lazy var inspectButton = TaskActionButton(label: "Show in Image Inspect".localized, icon: "HistoryFocus", style: .ghost) { [weak self] in self?.showInInspect() }
    private lazy var copyURLButton = TaskActionButton(label: "Copy URL".localized, icon: "ToastCopy", style: .ghost) { [weak self] in self?.copyResultURL() }
    private lazy var revealButton = TaskActionButton(label: "Reveal in Finder".localized, icon: "HistoryFolder", style: .ghost) { [weak self] in self?.revealSelected() }
    private lazy var retryButton = TaskActionButton(label: "Retry".localized, icon: "TaskIconRetry", style: .primary) { [weak self] in self?.retrySelected() }
    private lazy var removeButton = TaskActionButton(label: nil, icon: "HistoryClear", style: .danger, tooltip: "Remove Record".localized) { [weak self] in self?.removeSelected() }
    private let actionSeparator = NSView()
    /// Visible actions left to right; nil is the separator.
    private var actionOrder: [NSView] = []
    private let sourcePreview = TaskPreviewView(title: "Source".localized)
    private let resultPreview = TaskPreviewView(title: "Waiting for result".localized)
    private let timelinePanel = FlippedDocView()
    private let timelineTitle = NSTextField(labelWithString: "Timeline".localized)
    private var timelineRows: [TaskTimelineRow] = []
    private let propertiesPanel = FlippedDocView()
    private let propertiesTitle = NSTextField(labelWithString: "Task Details".localized)
    private var propertyKeys: [NSTextField] = []
    private var propertyValues: [NSTextField] = []
    private var propertyDividers: [NSView] = []
    private let emptyDetail = HistoryEmptyView()
    private let toast = InspectToastWindow()

    private var visibleRecords: [WidgetTaskRecord] = []
    private var allRecords: [WidgetTaskRecord] = []

    init() {
        let frame = Self.initialFrame()
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Tasks".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = HistoryStyle.background
        minSize = NSSize(width: 900, height: 586)
        contentAspectRatio = Self.designSize
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI()
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(tasksChanged), name: WidgetTaskManager.didChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private static func initialFrame() -> NSRect {
        let location = NSEvent.mouseLocation
        guard let screen = ScreenManager.shared.screenForMouseLocation(location) ?? NSScreen.main else {
            return NSRect(origin: location, size: designSize)
        }
        let visible = screen.visibleFrame
        let scale = min(1, visible.width / designSize.width, visible.height / designSize.height)
        return ScreenManager.shared.centerFrame(
            for: NSSize(width: designSize.width * scale, height: designSize.height * scale),
            on: screen
        )
    }

    private func buildUI() {
        contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        root.layer?.masksToBounds = true

        configureLabel(titleLabel, size: 13, color: PanelStyle.textPrimary, weight: .semibold, alignment: .center)
        configureLabel(countLabel, size: 11, color: PanelStyle.textTertiary, weight: .regular, alignment: .center)
        titlebar.addSubview(titleLabel)
        titlebar.addSubview(countLabel)
        // Traffic lights go on top of the (full-width, centered) title labels so
        // clicks land on the buttons instead of the label / drag surface.
        titlebar.addSubview(closeButton)
        titlebar.addSubview(minimizeButton)
        titlebar.addSubview(zoomButton)
        root.addSubview(titlebar)

        // List column.
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = HistoryStyle.hex(0x0E0F13).cgColor
        sidebarEdge.wantsLayer = true
        sidebarEdge.layer?.backgroundColor = HistoryStyle.hairline.cgColor
        sidebar.addSubview(sidebarEdge)
        configureLabel(sidebarTitle, size: 17, color: PanelStyle.textPrimary, weight: .semibold)
        sidebar.addSubview(sidebarTitle)
        sidebar.addSubview(refreshButton)
        sidebar.addSubview(clearButton)
        searchBox.onChange = { [weak self] in self?.refresh() }
        sidebar.addSubview(searchBox)
        pills.onSelect = { [weak self] index in
            self?.pills.selectedSegment = index
            self?.refresh()
        }
        sidebar.addSubview(pills)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Task"))
        column.width = 332
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 82
        table.intercellSpacing = NSSize(width: 0, height: 10)
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = false
        table.focusRingType = .none
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(selectionChanged)
        table.doubleAction = #selector(openSelected)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        sidebar.addSubview(scroll)
        configureLabel(emptyListTitle, size: 14, color: PanelStyle.textSecondary, weight: .medium, alignment: .center)
        configureLabel(emptyListHint, size: 12, color: PanelStyle.textTertiary, alignment: .center)
        emptyListHint.maximumNumberOfLines = 2
        emptyListHint.lineBreakMode = .byWordWrapping
        sidebar.addSubview(emptyListTitle)
        sidebar.addSubview(emptyListHint)
        root.addSubview(sidebar)

        // Detail column.
        detail.wantsLayer = true
        detail.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        configureLabel(detailTitle, size: 18, color: PanelStyle.textPrimary, weight: .semibold)
        configureLabel(detailStatus, size: 12, color: PanelStyle.accent, weight: .medium)
        detail.addSubview(detailTitle)
        detail.addSubview(detailStatus)
        actionSeparator.wantsLayer = true
        actionSeparator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        for view in [showSourceButton, cancelButton, inspectButton, copyURLButton, revealButton, retryButton, removeButton, actionSeparator] as [NSView] {
            view.isHidden = true
            detail.addSubview(view)
        }
        detail.addSubview(sourcePreview)
        detail.addSubview(resultPreview)
        let panelColor = HistoryStyle.hex(0x101115)
        configurePanel(timelinePanel, color: panelColor, radius: 12)
        configureLabel(timelineTitle, size: 13, color: PanelStyle.textPrimary, weight: .semibold)
        timelinePanel.addSubview(timelineTitle)
        let timelineSpecs = [
            ("Task submitted".localized, "Client uploaded the source image".localized),
            ("Worker claimed".localized, "GPU worker".localized),
            ("Processing".localized, "Polling every 2 seconds".localized),
            ("Download result".localized, "Waiting for output file".localized)
        ]
        for (index, spec) in timelineSpecs.enumerated() {
            let row = TaskTimelineRow(title: spec.0, detail: spec.1, showsConnector: index < timelineSpecs.count - 1)
            timelinePanel.addSubview(row)
            timelineRows.append(row)
        }
        detail.addSubview(timelinePanel)
        configurePanel(propertiesPanel, color: panelColor, radius: 12)
        configureLabel(propertiesTitle, size: 13, color: PanelStyle.textPrimary, weight: .semibold)
        propertiesPanel.addSubview(propertiesTitle)
        for key in ["Widget", "Input", "Worker", "Progress", "Polling", "Failure reason"] {
            let keyLabel = NSTextField(labelWithString: key.localized)
            let valueLabel = NSTextField(labelWithString: "—")
            configureLabel(keyLabel, size: 13, color: PanelStyle.textTertiary, weight: .medium)
            configureLabel(valueLabel, size: 13, color: PanelStyle.textPrimary)
            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            propertiesPanel.addSubview(keyLabel)
            propertiesPanel.addSubview(valueLabel)
            propertiesPanel.addSubview(divider)
            propertyKeys.append(keyLabel)
            propertyValues.append(valueLabel)
            propertyDividers.append(divider)
        }
        detail.addSubview(propertiesPanel)
        detail.addSubview(emptyDetail)
        root.addSubview(detail)
        layoutContent()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        guard width > 0, height > 0 else { return }
        let sx = width / Self.designSize.width, sy = height / Self.designSize.height
        let scale = min(sx, sy)
        root.layer?.cornerRadius = 16 * scale
        root.layer?.borderWidth = max(1, scale)

        // Title bar: 52 pt, traffic lights at y 18, title 13 pt at y 12, subtitle 11 pt at y 31.
        titlebar.frame = NSRect(x: 0, y: 0, width: width, height: 52 * sy)
        [closeButton, minimizeButton, zoomButton].enumerated().forEach { index, button in
            button.frame = NSRect(x: (20 + CGFloat(index) * 20) * sx, y: 18 * sy, width: 12 * sx, height: 12 * sy)
            button.layer?.cornerRadius = 6 * scale
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        countLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        titleLabel.frame = NSRect(x: 0, y: 12 * sy, width: width, height: 16 * sy)
        countLabel.frame = NSRect(x: 0, y: 31 * sy, width: width, height: 14 * sy)

        let columnH = height - 52 * sy
        sidebar.frame = NSRect(x: 0, y: 52 * sy, width: 360 * sx, height: columnH)
        detail.frame = NSRect(x: 360 * sx, y: 52 * sy, width: width - 360 * sx, height: columnH)

        // List column (design 360 × 960).
        func s(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
        }
        sidebarEdge.frame = s(359, 0, 1, 960)
        sidebarTitle.font = PanelStyle.inspectFont(ofSize: 17 * scale, weight: .semibold)
        sidebarTitle.frame = s(24, 22, 200, 21)
        for button in [refreshButton, clearButton] { button.uiScale = scale }
        refreshButton.frame = s(360 - 24 - 32 * 2 - 8, 16, 32, 32)
        clearButton.frame = s(360 - 24 - 32, 16, 32, 32)
        searchBox.uiScale = scale
        searchBox.frame = s(24, 68, 312, 36)
        pills.uiScale = scale
        pills.frame = s(24, 118, 312, 30)
        scroll.frame = s(14, 166, 332, 960 - 166 - 12)
        scroll.borderType = .noBorder
        scroll.layoutSubtreeIfNeeded()
        let tableWidth = max(1, scroll.contentSize.width)
        if let column = table.tableColumns.first {
            // Widen the limits before the width: setting a width above the old
            // maxWidth is clamped, which froze the rows at their first size.
            column.resizingMask = .autoresizingMask
            column.minWidth = 1
            column.maxWidth = .greatestFiniteMagnitude
            column.width = tableWidth
            column.minWidth = tableWidth
            column.maxWidth = tableWidth
        }
        table.rowHeight = 82 * sy
        table.intercellSpacing = NSSize(width: 0, height: 10 * sy)
        table.frame.size.width = tableWidth
        table.tile()
        emptyListTitle.font = PanelStyle.inspectFont(ofSize: 14 * scale, weight: .medium)
        emptyListHint.font = PanelStyle.inspectFont(ofSize: 12 * scale)
        emptyListTitle.frame = s(0, 300, 360, 18)
        emptyListHint.frame = s(40, 328, 280, 34)

        // Detail column (design 1194 × 960).
        detailTitle.font = PanelStyle.inspectFont(ofSize: 18 * scale, weight: .semibold)
        detailStatus.font = PanelStyle.inspectFont(ofSize: 12 * scale, weight: .medium)
        detailTitle.frame = s(32, 26, 600, 22)
        detailStatus.frame = s(32, 54, 700, 15)
        // The one action group, built from the right edge so it stays aligned
        // whichever buttons this state needs.
        var x: CGFloat = 1194 - 32
        for view in actionOrder.reversed() {
            if view === actionSeparator {
                x -= 13
                actionSeparator.frame = s(x + 6, 30, 1, 24)
            } else if let button = view as? TaskActionButton {
                button.uiScale = scale
                x -= button.designWidth
                button.frame = s(x, 24, button.designWidth, 36)
                x -= 8
            }
        }
        sourcePreview.frame = s(32, 100, 556, 360)
        resultPreview.frame = s(606, 100, 556, 360)
        timelinePanel.frame = s(32, 490, 556, 400)
        propertiesPanel.frame = s(606, 490, 556, 400)
        for panel in [timelinePanel, propertiesPanel] { panel.layer?.cornerRadius = 12 * scale }
        func inPanel(_ parent: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
        }
        timelineTitle.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        timelineTitle.frame = inPanel(timelinePanel, 24, 20, 200, 16)
        // Board rows (215:5970) start every 72 pt from y 60; each row frame also
        // holds the current-step halo (2 pt above) and the connector below.
        for (index, row) in timelineRows.enumerated() {
            row.frame = inPanel(timelinePanel, 0, CGFloat(58 + index * 72), 556, TaskTimelineRow.designHeight)
        }
        propertiesTitle.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        propertiesTitle.frame = inPanel(propertiesPanel, 24, 20, 300, 16)
        // Board rows (215:5992): key at 36, value at 174 (220 wide), 38 pt pitch,
        // a 362 pt divider 30 pt below each row.
        for index in propertyKeys.indices {
            let y = CGFloat(60 + index * 38)
            propertyKeys[index].font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
            propertyValues[index].font = PanelStyle.inspectFont(ofSize: 13 * scale)
            propertyKeys[index].frame = inPanel(propertiesPanel, 36, y, 130, 16)
            propertyValues[index].frame = inPanel(propertiesPanel, 174, y, 220, 16)
            propertyDividers[index].frame = inPanel(propertiesPanel, 36, y + 30, 362, max(1, scale))
        }
        // HistoryEmptyView puts its tile at (height / 2 - 120); the board (215:6302)
        // wants it at 340 of 960, so the view gets 40 pt less height.
        emptyDetail.frame = NSRect(x: 0, y: 0, width: detail.bounds.width, height: max(0, detail.bounds.height - 40 * sy))
        clearButton.isEnabled = allRecords.contains { !$0.phase.isActive }
    }

    private func configurePanel(_ view: NSView, color: NSColor, radius: CGFloat = 0) {
        view.wantsLayer = true
        view.layer?.backgroundColor = PanelStyle.resolvedCG(color)
        view.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        view.layer?.borderWidth = 1
        view.layer?.cornerRadius = radius
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat, color: NSColor,
                                weight: NSFont.Weight = .regular,
                                alignment: NSTextAlignment = .left) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    func refresh() {
        allRecords = WidgetTaskManager.shared.records
        let records = allRecords
        let query = searchBox.query
        let filtered: [WidgetTaskRecord]
        switch pills.selectedSegment {
        case 1: filtered = records.filter { $0.phase.isActive }
        case 2: filtered = records.filter { $0.phase == .completed }
        case 3: filtered = records.filter { $0.phase.isFailure }
        default: filtered = records
        }
        visibleRecords = query.isEmpty ? filtered : filtered.filter {
            $0.widgetName.localizedCaseInsensitiveContains(query) ||
            $0.commandName.localizedCaseInsensitiveContains(query) ||
            ($0.source?.lastPathComponent.localizedCaseInsensitiveContains(query) ?? false)
        }
        pills.counts = [records.count,
                        records.filter { $0.phase.isActive }.count,
                        records.filter { $0.phase == .completed }.count,
                        records.filter { $0.phase.isFailure }.count]
        let running = WidgetTaskManager.shared.activeCount
        countLabel.stringValue = records.isEmpty
            ? String(format: "%d tasks".localized, 0)
            : String(format: "%d tasks  •  %d running".localized, records.count, running)
        let selectedID = selected?.id
        table.reloadData()
        if let selectedID, let row = visibleRecords.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !visibleRecords.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateEmptyStates()
        updateDetail(selected)
        layoutContent()
    }

    /// The list and the detail each explain themselves when there is nothing to show.
    private func updateEmptyStates() {
        let none = visibleRecords.isEmpty
        scroll.isHidden = none
        emptyListTitle.isHidden = !none
        emptyListHint.isHidden = !none
        if none {
            let noTasks = allRecords.isEmpty
            emptyListTitle.stringValue = noTasks ? "No tasks yet".localized : "No matching tasks".localized
            emptyListHint.stringValue = noTasks ? "Run a Widget on an image and it will show up here.".localized
                                                : "Try a different search or filter.".localized
        }
        emptyDetail.isHidden = !none
        if none {
            emptyDetail.configure(icon: "TaskIconTasks", heading: "Select a task".localized,
                                  detail: "Its progress, result and timeline appear here.".localized)
        }
        for view in [detailTitle, detailStatus, sourcePreview, resultPreview, timelinePanel, propertiesPanel] as [NSView] {
            view.isHidden = none
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRecords.count }

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("TaskCenterCell")

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = visibleRecords[row]
        let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil) as? TaskCenterCellView)
            ?? TaskCenterCellView()
        cell.identifier = Self.cellIdentifier
        cell.configure(record: record, selected: row == table.selectedRow)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TaskCenterRowView()
    }

    private var previousSelectedRow = -1

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetail(selected)
        // Only the rows whose highlight changed need a new cell; reloading every
        // row re-decoded every visible thumbnail and made selection stutter.
        var rows = IndexSet()
        for row in [previousSelectedRow, table.selectedRow] where visibleRecords.indices.contains(row) { rows.insert(row) }
        previousSelectedRow = table.selectedRow
        table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
    }

    private var selected: WidgetTaskRecord? {
        let row = table.selectedRow
        return visibleRecords.indices.contains(row) ? visibleRecords[row] : nil
    }

    private var selectedOutputExists: Bool {
        selected?.output.map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    private func returnsText(_ record: WidgetTaskRecord) -> Bool {
        if record.outputTypes?.contains("text") == true { return true }
        if let output = record.output,
           ["txt", "text", "md", "markdown"].contains(output.pathExtension.lowercased()) {
            return true
        }
        guard let widget = WidgetRegistry.shared.installed.first(where: { $0.id == record.widgetID }),
              let command = widget.commands.first(where: { $0.id == record.commandID }) else { return false }
        return command.outputs.contains("text")
    }

    private func updateDetail(_ record: WidgetTaskRecord?) {
        guard let record else {
            detailTitle.stringValue = "Select a task".localized
            detailStatus.stringValue = ""
            sourcePreview.caption = nil
            sourcePreview.configure(url: nil, waiting: false)
            resultPreview.configure(url: nil, waiting: true, displaysText: false)
            timelineRows.enumerated().forEach { $0.element.configure(state: $0.offset == 0 ? .pending : .disabled, time: "") }
            propertyValues.forEach { $0.stringValue = "—" }
            setActions([])
            return
        }
        detailTitle.stringValue = record.commandName
        detailStatus.stringValue = String(format: "Task %@  •  %@".localized, String(record.id.uuidString.prefix(4).uppercased()), stateText(record))
        detailStatus.textColor = record.phase.isActive ? PanelStyle.accent
            : (record.phase.isFailure ? PanelStyle.failure
               : (record.phase == .cancelled ? PanelStyle.textSecondary : PanelStyle.success))
        sourcePreview.caption = String(format: "Source · %@".localized, record.source?.lastPathComponent ?? "Media".localized)
        sourcePreview.configure(url: record.source, waiting: false)
        let failed = record.phase.isFailure
        let stopped = failed || record.phase == .cancelled
        let failureReason = record.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = (failureReason?.isEmpty == false ? failureReason : nil)
            ?? "The task stopped without reporting a reason.".localized
        resultPreview.showsResultPill = false
        if record.phase.isActive {
            resultPreview.showRunning(detail: record.widgetName)
        } else if stopped {
            resultPreview.showFailure(title: (record.phase == .cancelled ? "Task cancelled" : "Task failed").localized,
                                      reason: record.phase == .cancelled ? "You cancelled this task.".localized : reasonText)
        } else if resultPreview.isShowingRunning {
            // Board frame 7: the chip says "Done ✓" for 1.6 s, then the result.
            let elapsed = Self.durationText(record.updatedAt.timeIntervalSince(record.createdAt))
            resultPreview.finishRunning(detail: "\(record.widgetName) · \(elapsed)") { [weak self] in
                guard let self, let current = self.selected, current.id == record.id else { return }
                self.showResult(current)
            }
        } else {
            showResult(record)
        }

        // Timeline: finished steps are green, the live step amber, a failed step red.
        let phaseIndex: Int
        switch record.phase {
        case .uploading, .submitting: phaseIndex = 0
        case .processing: phaseIndex = 2
        case .downloading: phaseIndex = 3
        case .completed: phaseIndex = 4
        case .failed, .interrupted, .cancelled, .expired: phaseIndex = 2
        }
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        for index in timelineRows.indices {
            var state: TaskTimelineRow.State = index < phaseIndex ? .complete : (index == phaseIndex ? .current : .pending)
            var time = index == phaseIndex ? "Now".localized : ""
            var detail: String?
            if index == 0 { time = clock.string(from: record.createdAt) }
            if stopped && index == phaseIndex {
                state = failed ? .failed : .disabled
                time = clock.string(from: record.updatedAt)
                detail = record.phase == .cancelled ? "Cancelled".localized : reasonText
            }
            if stopped && index > phaseIndex { detail = "Skipped".localized; time = "—" }
            if record.phase == .completed && index == 2 {
                detail = String(format: "Finished in %@".localized, Self.durationText(record.updatedAt.timeIntervalSince(record.createdAt)))
            }
            if record.phase == .completed && index == 3 {
                detail = "Saved next to the source".localized
                time = clock.string(from: record.updatedAt)
            }
            timelineRows[index].configure(state: state, time: time, detail: detail)
        }

        // Properties follow the state: live tasks poll, finished ones report a
        // duration and a file, stopped ones say where and why.
        let rows: [(String, String, NSColor)]
        let worker = record.remoteTaskID == nil ? "—" : "Remote"
        if record.phase.isActive {
            rows = [("Widget", record.widgetName, PanelStyle.textPrimary), ("Input", record.source?.lastPathComponent ?? "Media", PanelStyle.textPrimary),
                    ("Worker", worker, PanelStyle.textPrimary), ("Progress", "\(record.progress)%", PanelStyle.textPrimary),
                    ("Polling", "2 seconds".localized, PanelStyle.textPrimary)]
        } else if stopped {
            rows = [("Widget", record.widgetName, PanelStyle.textPrimary), ("Input", record.source?.lastPathComponent ?? "Media", PanelStyle.textPrimary),
                    ("Worker", worker, PanelStyle.textPrimary),
                    ("Progress", String(format: "Stopped at %d%%".localized, record.progress), PanelStyle.textPrimary),
                    ("Error", record.phase == .cancelled ? "Cancelled".localized : reasonText, record.phase == .cancelled ? PanelStyle.textPrimary : PanelStyle.failure)]
        } else {
            rows = [("Widget", record.widgetName, PanelStyle.textPrimary), ("Input", record.source?.lastPathComponent ?? "Media", PanelStyle.textPrimary),
                    ("Worker", worker, PanelStyle.textPrimary),
                    ("Duration", Self.durationText(record.updatedAt.timeIntervalSince(record.createdAt)), PanelStyle.textPrimary),
                    ("Result", record.output?.lastPathComponent ?? "—", PanelStyle.textPrimary)]
        }
        for index in propertyKeys.indices {
            let hidden = index >= rows.count
            propertyKeys[index].isHidden = hidden
            propertyValues[index].isHidden = hidden
            guard !hidden else { continue }
            propertyKeys[index].stringValue = rows[index].0.localized
            propertyValues[index].stringValue = rows[index].1
            propertyValues[index].textColor = rows[index].2
            propertyValues[index].toolTip = rows[index].1
        }
        copyURLButton.isEnabled = true

        // The single action group for this state.
        let sourceExists = record.source.map { !$0.isFileURL || FileManager.default.fileExists(atPath: $0.path) } == true
        if record.phase.isActive {
            setActions([sourceExists ? showSourceButton : nil, cancelButton].compactMap { $0 })
        } else if record.phase == .completed && selectedOutputExists {
            var items: [NSView] = []
            if !returnsText(record) { items.append(inspectButton) }
            if record.copyableMediaResultURL != nil { items.append(copyURLButton) }
            items.append(revealButton)
            items.append(actionSeparator)
            items.append(removeButton)
            setActions(items)
        } else {
            setActions([retryButton, actionSeparator, removeButton])
        }
    }

    private func showResult(_ record: WidgetTaskRecord) {
        resultPreview.showsResultPill = !returnsText(record)
        resultPreview.configure(url: record.output, waiting: record.phase != .completed,
                                displaysText: returnsText(record))
    }

    /// "12.4 s" under a minute, "2 min 5 s" above.
    private static func durationText(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        if value < 60 { return String(format: "%.1f s", value) }
        return String(format: "%d min %d s", Int(value) / 60, Int(value) % 60)
    }

    private func setActions(_ items: [NSView]) {
        let all: [NSView] = [showSourceButton, cancelButton, inspectButton, copyURLButton, revealButton, retryButton, removeButton, actionSeparator]
        for view in all { view.isHidden = !items.contains { $0 === view } }
        actionOrder = items
        layoutContent()
    }

    private func stateText(_ record: WidgetTaskRecord) -> String {
        if let queued = record.queueText { return queued }
        switch record.phase {
        case .processing: return record.progress > 0 ? "\(record.progress)%" : "Processing".localized
        case .uploading: return "Uploading".localized
        case .submitting: return "Submitting".localized
        case .downloading: return "Downloading".localized
        case .completed: return "Completed".localized
        case .failed: return "Failed".localized
        case .interrupted: return "Interrupted".localized
        case .cancelled: return "Cancelled".localized
        case .expired: return "Expired".localized
        }
    }

    @objc private func tasksChanged() { refresh() }
    @objc private func selectionChanged() { updateDetail(selected) }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    private func refreshTapped() { refresh() }

    private func showInInspect() {
        guard let url = selected?.output, FileManager.default.fileExists(atPath: url.path) else { return }
        (NSApp.delegate as? AppDelegate)?.openTaskOutputInInspect(url)
    }

    private func showSource() {
        guard let url = selected?.source else { return }
        (NSApp.delegate as? AppDelegate)?.openTaskOutputInInspect(url)
    }

    @objc private func openSelected() {
        if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    private func revealSelected() {
        if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func copyResultURL() {
        guard let record = selected, let storedURL = record.copyableMediaResultURL else { return }
        guard let taskID = record.remoteTaskID else {
            copyURLToPasteboard(storedURL)
            return
        }
        copyURLButton.isEnabled = false
        WidgetTaskClient.shared.fetchResultURL(taskID: taskID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.selected?.id == record.id else { return }
                self.copyURLButton.isEnabled = true
                switch result {
                case .success(let url): self.copyURLToPasteboard(url.absoluteString)
                case .failure:
                    if let url = URL(string: storedURL),
                       url.host != "api.glance.mcreator.ai" {
                        self.copyURLToPasteboard(storedURL)
                    } else {
                        self.toast.show(message: "Could not refresh result URL".localized, kind: .error, over: self)
                    }
                }
            }
        }
    }

    private func copyURLToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        toast.show(message: "Result URL copied".localized, kind: .info, over: self)
    }

    private func retrySelected() { if let id = selected?.id { WidgetTaskManager.shared.retry(id) } }
    private func removeSelected() { if let id = selected?.id { WidgetTaskManager.shared.remove(id) } }
    private func cancelSelected() { if let id = selected?.id { WidgetTaskManager.shared.cancel(id) } }

    private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear finished task history?".localized
        alert.informativeText = "Downloaded files will not be deleted.".localized
        alert.addButton(withTitle: "Clear".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn { WidgetTaskManager.shared.clear() }
        }
    }
}

/// A title label that never intercepts mouse events, so the centered title can
/// span the full titlebar width without blocking the traffic lights or the
/// drag surface underneath it.
private final class TaskPassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class TaskCenterTitlebar: NSView {
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { event.clickCount == 2 ? window?.zoom(nil) : window?.performDrag(with: event) }
}

private final class TaskCenterCellView: NSTableCellView {
    /// Thumbnail tile: aspect-fill layer contents, as the board's full-bleed artwork.
    private let preview = NSView()
    private let placeholder = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stateBadge = NSView()
    private let stateLabel = PanelCenteredTextView()
    private let runningScrim = NSView()
    private let runningPeeker = PeekerView()
    /// Which thumbnail request this cell is waiting for; a reused cell ignores
    /// results that arrive for the record it used to show.
    private var thumbnailToken = UUID()
    /// 56 pt tile at 2× Retina.
    private static let thumbnailPixelSize = 112
    private var isSelectedRow = false
    private var isHovering = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 9; layer?.borderWidth = 1; layer?.masksToBounds = true
        preview.wantsLayer = true; preview.layer?.cornerRadius = 7; preview.layer?.masksToBounds = true; preview.layer?.borderWidth = 1; preview.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        preview.layer?.contentsGravity = .resizeAspectFill
        preview.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.contentTintColor = PanelStyle.textTertiary
        preview.addSubview(placeholder)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold); titleLabel.textColor = PanelStyle.textPrimary
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11); detailLabel.textColor = PanelStyle.textTertiary
        stateBadge.wantsLayer = true; stateBadge.layer?.cornerRadius = 6; stateBadge.layer?.masksToBounds = true
        stateLabel.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
        stateBadge.addSubview(stateLabel)
        [preview, titleLabel, detailLabel, stateBadge].forEach(addSubview)
        runningScrim.wantsLayer = true
        runningScrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        runningScrim.layer?.cornerRadius = 7
        runningScrim.isHidden = true
        runningPeeker.isHidden = true
        addSubview(runningScrim)
        addSubview(runningPeeker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(record: WidgetTaskRecord, selected: Bool) {
        isSelectedRow = selected
        applyBackground()
        layer?.borderColor = PanelStyle.resolvedCG(selected ? PanelStyle.accent.withAlphaComponent(0.42) : PanelStyle.inspectLine)
        // A running task shows the peeker over the thumbnail instead of a glyph.
        placeholder.image = record.phase.isActive ? nil : NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        let candidates = [record.output, record.source].compactMap { $0 }.filter(\.isFileURL)
        let token = UUID()
        thumbnailToken = token
        if let hit = candidates.lazy.compactMap({ MediaThumbnailCache.shared.cached(for: $0, maxPixelSize: Self.thumbnailPixelSize) }).first {
            setThumbnail(hit)
        } else {
            setThumbnail(nil)
            loadThumbnail(candidates, token: token)
        }
        titleLabel.stringValue = record.commandName
        detailLabel.stringValue = "\(relativeDate(record.createdAt))  •  \(record.source?.lastPathComponent ?? "Media")"
        let color: NSColor = record.phase.isActive ? PanelStyle.accent : (record.phase.isFailure ? PanelStyle.failure : (record.phase == .cancelled ? PanelStyle.textSecondary : PanelStyle.success))
        runningScrim.isHidden = !record.phase.isActive
        runningPeeker.isHidden = !record.phase.isActive
        stateLabel.string = taskState(record)
        stateLabel.textColor = color
        stateBadge.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        setAccessibilityLabel("\(record.commandName), \(stateLabel.string)")
    }

    private func setThumbnail(_ image: NSImage?) {
        preview.layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        placeholder.isHidden = image != nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let sx = bounds.width / 332
        let sy = bounds.height / 82
        let scale = min(sx, sy)
        layer?.cornerRadius = 9 * scale
        layer?.borderWidth = max(1, scale)
        preview.layer?.cornerRadius = 7 * scale
        preview.layer?.borderWidth = max(1, scale)
        stateBadge.layer?.cornerRadius = 6 * scale
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        stateLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale, weight: .semibold)
        preview.frame = NSRect(x: 12 * sx, y: 13 * sy, width: 56 * sx, height: 56 * sy)
        placeholder.frame = preview.bounds.insetBy(dx: 16 * scale, dy: 16 * scale)
        // Text stops 8 pt before the state badge (x 250) so long file names truncate
        // instead of running under it.
        titleLabel.frame = NSRect(x: 82 * sx, y: 17 * sy, width: 160 * sx, height: 17 * sy)
        detailLabel.frame = NSRect(x: 82 * sx, y: 43 * sy, width: 160 * sx, height: 14 * sy)
        stateBadge.frame = NSRect(x: 250 * sx, y: 28 * sy, width: 70 * sx, height: 26 * sy)
        stateLabel.frame = stateBadge.bounds.insetBy(dx: 2 * sx, dy: 0)
        runningScrim.frame = preview.frame
        runningScrim.layer?.cornerRadius = 7 * scale
        runningPeeker.frame = NSRect(x: 24 * sx, y: 24 * sy, width: 32 * sx, height: 32 * sy)
    }

    private func applyBackground() {
        let base = isSelectedRow
            ? NSColor(srgbRed: 36 / 255, green: 34 / 255, blue: 41 / 255, alpha: 1)
            : PanelStyle.inspectChrome
        // Hover reads as a lighter row, never as strong as selection.
        let color = isHovering && !isSelectedRow ? PanelStyle.hoverTinted(base) : base
        layer?.backgroundColor = PanelStyle.resolvedCG(color)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { isHovering = true; applyBackground() }
    override func mouseExited(with event: NSEvent) { isHovering = false; applyBackground() }

    /// Try the result first, then the source; stop at the first file that previews.
    private func loadThumbnail(_ candidates: [URL], token: UUID) {
        guard let url = candidates.first else { return }
        MediaThumbnailCache.shared.load(url, maxPixelSize: Self.thumbnailPixelSize) { [weak self] image in
            guard let self, self.thumbnailToken == token else { return }
            if let image { self.setThumbnail(image) }
            else { self.loadThumbnail(Array(candidates.dropFirst()), token: token) }
        }
    }

    private func taskState(_ record: WidgetTaskRecord) -> String {
        if let queued = record.queueText { return queued }
        // The badge names the state (board: "Running…"); the percentage lives in the detail.
        switch record.phase {
        case .processing: return "Running…".localized
        case .uploading: return "Uploading".localized
        case .submitting: return "Submitting".localized
        case .downloading: return "Downloading".localized
        case .completed: return "Done".localized
        case .failed: return "Failed".localized
        case .interrupted: return "Interrupted".localized
        case .cancelled: return "Cancelled".localized
        case .expired: return "Expired".localized
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private final class TaskCenterRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        // Selection is rendered by TaskCenterCellView using Glance's warm
        // neutral surface and accent hairline. Never draw AppKit blue.
    }

    override var isEmphasized: Bool {
        get { false }
        set { }
    }

    override func drawSeparator(in dirtyRect: NSRect) { }
}

private final class TaskPreviewView: NSView {
    private let imageView = NSImageView()
    private let waitingLabel: NSTextField
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private var loadGeneration = UUID()
    private let runningChip = TaskRunningChip()
    private let failureBadge = TaskFailureBadge()
    private let failureTitle = NSTextField(labelWithString: "")
    private let failureReason = NSTextField(wrappingLabelWithString: "")
    private let resultPill = TaskResultPill()
    private let captionLabel = NSTextField(labelWithString: "")
    /// Shows the "Result" pill over a finished result image.
    var showsResultPill = false
    /// "Source · input.png" over the bottom-left of the image (board 215:5953).
    var caption: String? { didSet { captionLabel.stringValue = caption ?? ""; needsLayout = true } }
    /// True while the running chip (working or "Done") is on screen.
    var isShowingRunning: Bool { !runningChip.isHidden }
    private var doneWork: DispatchWorkItem?

    init(title: String) {
        waitingLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        layer?.borderWidth = 1
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        addSubview(imageView)
        captionLabel.font = PanelStyle.inspectFont(ofSize: 11, weight: .medium)
        captionLabel.textColor = HistoryStyle.hex(0xF3F3F3)
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.maximumNumberOfLines = 1
        captionLabel.isHidden = true
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.scrollerStyle = .overlay
        textScroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = PanelStyle.inspectFont(ofSize: 13)
        textView.textColor = PanelStyle.textPrimary
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textScroll.documentView = textView
        textScroll.isHidden = true
        addSubview(textScroll)
        waitingLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        waitingLabel.textColor = PanelStyle.textTertiary
        waitingLabel.alignment = .center
        addSubview(waitingLabel)
        runningChip.isHidden = true
        addSubview(runningChip)
        failureBadge.isHidden = true
        addSubview(failureBadge)
        failureTitle.font = PanelStyle.inspectFont(ofSize: 16, weight: .semibold)
        failureTitle.textColor = PanelStyle.textPrimary
        failureTitle.alignment = .center
        failureReason.font = PanelStyle.inspectFont(ofSize: 12)
        failureReason.textColor = PanelStyle.textSecondary
        failureReason.alignment = .center
        failureReason.maximumNumberOfLines = 3
        [failureTitle, failureReason].forEach { $0.isHidden = true; addSubview($0) }
        resultPill.isHidden = true
        addSubview(resultPill)
        addSubview(captionLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func resetModes() {
        doneWork?.cancel()
        doneWork = nil
        runningChip.isHidden = true
        captionLabel.isHidden = true
        failureBadge.isHidden = true
        failureTitle.isHidden = true
        failureReason.isHidden = true
        resultPill.isHidden = true
    }

    /// A running task: the peeker chip instead of a "waiting" label.
    func showRunning(detail: String) {
        loadGeneration = UUID()
        imageView.image = nil
        textScroll.isHidden = true
        waitingLabel.isHidden = true
        resetModes()
        runningChip.showRunning(detail: detail)
        runningChip.isHidden = false
        needsLayout = true
    }

    /// The task finished while the chip was up: show board frame 7 ("Done ✓",
    /// `detail` = "Remove Background · 12.4 s"), hold 1.6 s, then `completion`.
    /// Later calls while the hold runs keep the first completion.
    func finishRunning(detail: String, completion: @escaping () -> Void) {
        guard isShowingRunning else { completion(); return }
        if runningChip.isDone { return }
        runningChip.showDone(detail: detail)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.doneWork != nil else { return }
            self.doneWork = nil
            completion()
        }
        doneWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    /// A failed or cancelled task: a red badge, the outcome and the reason.
    func showFailure(title: String, reason: String) {
        loadGeneration = UUID()
        imageView.image = nil
        textScroll.isHidden = true
        waitingLabel.isHidden = true
        resetModes()
        failureTitle.stringValue = title
        failureReason.stringValue = reason
        failureBadge.isHidden = false
        failureTitle.isHidden = false
        failureReason.isHidden = false
        needsLayout = true
    }

    func configure(url: URL?, waiting: Bool, displaysText: Bool = false) {
        loadGeneration = UUID()
        let generation = loadGeneration
        resetModes()
        imageView.image = nil
        textView.string = ""
        textScroll.isHidden = true
        waitingLabel.isHidden = false
        waitingLabel.stringValue = waiting ? "Waiting for result".localized : "Preview unavailable".localized
        guard let url else { return }
        if displaysText {
            waitingLabel.stringValue = "Loading text…".localized
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try Self.readTextResult(at: url) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    switch result {
                    case .success(let text):
                        self.textView.string = text.isEmpty ? "No text returned".localized : text
                        self.textScroll.isHidden = false
                        self.waitingLabel.isHidden = true
                        self.layoutTextView()
                        self.textView.scrollToBeginningOfDocument(nil)
                    case .failure:
                        self.waitingLabel.stringValue = "Unable to read text result".localized
                    }
                }
            }
            return
        }
        guard url.isFileURL else { return }
        waitingLabel.stringValue = "Loading preview…".localized
        // The pane is at most a few hundred points wide; 1600 px keeps Retina
        // sharp without decoding the full-size result on the main thread.
        MediaThumbnailCache.shared.load(url, maxPixelSize: 1600) { [weak self] image in
            guard let self, self.loadGeneration == generation else { return }
            if let image {
                self.imageView.image = image
                self.waitingLabel.isHidden = true
                self.resultPill.isHidden = !self.showsResultPill
                self.captionLabel.isHidden = self.caption == nil
            } else {
                self.waitingLabel.stringValue = waiting ? "Waiting for result".localized : "Preview unavailable".localized
            }
        }
    }

    private static func readTextResult(at url: URL) throws -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let files = try FileManager.default.contentsOfDirectory(at: url,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            guard let textURL = files.first(where: {
                ["txt", "text", "md", "markdown"].contains($0.pathExtension.lowercased())
            }) else { throw CocoaError(.fileReadUnsupportedScheme) }
            return try String(contentsOf: textURL, encoding: .utf8)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    override func layout() {
        super.layout()
        // Everything follows the 556 × 360 board, scaled with the pane. Board
        // y values are top-origin; this view is not flipped, so y = height - (top + h).
        let k = bounds.width / 556
        imageView.frame = NSRect(x: 12 * k, y: 12 * k, width: bounds.width - 24 * k, height: bounds.height - 24 * k)
        imageView.layer?.cornerRadius = 8 * k
        textScroll.frame = bounds.insetBy(dx: 12 * k, dy: 12 * k)
        waitingLabel.frame = NSRect(x: 20, y: bounds.midY - 9, width: bounds.width - 40, height: 18)
        captionLabel.font = PanelStyle.inspectFont(ofSize: 11 * k, weight: .medium)
        captionLabel.frame = NSRect(x: 18 * k, y: bounds.height - (322 + 14) * k, width: 300 * k, height: 14 * k)
        let chipWidth = 360 * k
        runningChip.frame = NSRect(x: (bounds.width - chipWidth) / 2, y: (bounds.height - 76 * k) / 2, width: chipWidth, height: 76 * k)
        failureBadge.frame = NSRect(x: (bounds.width - 56 * k) / 2, y: bounds.height - (112 + 56) * k, width: 56 * k, height: 56 * k)
        failureTitle.font = PanelStyle.inspectFont(ofSize: 16 * k, weight: .semibold)
        failureReason.font = PanelStyle.inspectFont(ofSize: 12 * k)
        failureTitle.frame = NSRect(x: 0, y: bounds.height - (188 + 20) * k, width: bounds.width, height: 20 * k)
        failureReason.frame = NSRect(x: 78 * k, y: bounds.height - (218 + 46) * k, width: bounds.width - 156 * k, height: 46 * k)
        // Board pill: 58 wide — dot at 10, label at 22. Wider only if the label needs it.
        let pillWidth = max(58, 22 + HistoryStyle.width("Result".localized, size: 11, weight: .semibold) + 4) * k
        resultPill.frame = NSRect(x: 24 * k, y: bounds.height - (24 + 22) * k, width: pillWidth, height: 22 * k)
        resultPill.uiScale = k
        layoutTextView()
    }

    private func layoutTextView() {
        let size = textScroll.contentSize
        guard size.width > 0, let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        textContainer.containerSize = NSSize(width: size.width,
                                             height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: size.width, height: max(1, size.height))
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            + textView.textContainerInset.height * 2
        textView.frame.size.height = max(size.height, usedHeight)
    }
}

private final class TaskTimelineRow: NSView {
    enum State { case complete, current, pending, disabled, failed }
    /// Board row box: halo top (y − 2) to connector bottom (y + 70), 72 pt pitch.
    static let designHeight: CGFloat = 74
    private let mark = NSView(), halo = NSView(), connector = NSView()
    private let titleLabel: NSTextField, detailLabel: NSTextField
    private let timeLabel = NSTextField(labelWithString: "")
    private let defaultDetail: String
    private let showsConnector: Bool
    override var isFlipped: Bool { true }

    init(title: String, detail: String, showsConnector: Bool) {
        self.showsConnector = showsConnector
        defaultDetail = detail
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        super.init(frame: .zero)
        mark.wantsLayer = true
        halo.wantsLayer = true
        connector.wantsLayer = true
        connector.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        addSubview(connector); addSubview(halo); addSubview(mark)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = PanelStyle.textPrimary
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11)
        detailLabel.textColor = PanelStyle.textTertiary
        timeLabel.font = PanelStyle.inspectFont(ofSize: 11)
        timeLabel.textColor = PanelStyle.textTertiary
        timeLabel.alignment = .right
        for label in [titleLabel, detailLabel, timeLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `detail` replaces the default description for this state (nil restores it).
    func configure(state: State, time: String, detail: String? = nil) {
        let color: NSColor
        switch state {
        case .complete: color = PanelStyle.success
        case .current: color = PanelStyle.accent
        case .failed: color = PanelStyle.failure
        case .pending, .disabled: color = PanelStyle.textTertiary
        }
        mark.layer?.backgroundColor = color.cgColor
        halo.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        halo.isHidden = !(state == .current || state == .failed)
        timeLabel.stringValue = time
        detailLabel.stringValue = detail ?? defaultDetail
    }

    override func layout() {
        super.layout()
        // Board (row origin y): halo (23, y − 2) 24, mark (28, y + 3) 14,
        // title (58, y) 13 pt, detail (58, y + 22) 11 pt, time (430, y + 3) 110
        // wide right-aligned, connector (34, y + 18) 1 × 52. This box starts at y − 2.
        let sx = bounds.width / 556, sy = bounds.height / Self.designHeight
        let scale = min(sx, sy)
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
        }
        halo.frame = r(23, 0, 24, 24); halo.layer?.cornerRadius = 12 * scale
        mark.frame = r(28, 5, 14, 14); mark.layer?.cornerRadius = 7 * scale
        connector.isHidden = !showsConnector
        connector.frame = NSRect(x: 34 * sx, y: 20 * sy, width: max(1, scale), height: 52 * sy)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        timeLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        titleLabel.frame = r(58, 2, 360, 16)
        detailLabel.frame = r(58, 24, 360, 14)
        timeLabel.frame = r(430, 5, 110, 14)
    }
}

/// Red circle with a warning glyph (failed / cancelled result pane).
private final class TaskFailureBadge: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        PanelStyle.failure.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let side = bounds.width * 0.5
        HistoryStyle.drawIcon("ToastWarning", color: PanelStyle.failure,
                              in: CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side))
    }
}

/// "● Result" pill on a finished result image.
private final class TaskResultPill: NSView {
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11 * s, yRadius: 11 * s)
        HistoryStyle.overlayFill.withAlphaComponent(0.8).setFill(); path.fill()
        HistoryStyle.accent.withAlphaComponent(0.5).setStroke(); path.lineWidth = max(1, s); path.stroke()
        HistoryStyle.accent.setFill()
        NSBezierPath(ovalIn: CGRect(x: 10 * s, y: 8 * s, width: 6 * s, height: 6 * s)).fill()
        HistoryStyle.draw("Result".localized, in: CGRect(x: 22 * s, y: 4 * s, width: bounds.width - 24 * s, height: 14 * s),
                          size: 11 * s, weight: .semibold, color: HistoryStyle.accent)
    }
}

// MARK: - Redesign controls

/// 32 × 32 list-level icon button (refresh, clear finished).
private final class TaskGhostButton: NSView {
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    private let icon: String
    private let tint: NSColor
    private let danger: Bool
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String, tint: NSColor, danger: Bool = false, onClick: @escaping () -> Void) {
        self.icon = icon; self.tint = tint; self.danger = danger; self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick() } }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10 * s, yRadius: 10 * s)
        NSColor.white.withAlphaComponent(hovering ? 0.09 : 0.05).setFill(); path.fill()
        (danger ? PanelStyle.failure.withAlphaComponent(0.32) : NSColor.white.withAlphaComponent(0.08)).setStroke()
        path.lineWidth = max(1, s); path.stroke()
        HistoryStyle.drawIcon(icon, color: tint, in: CGRect(x: 8 * s, y: 8 * s, width: 16 * s, height: 16 * s))
    }
}

/// Task-level action in the detail header: ghost, primary (amber) or danger.
/// Icon + label, or icon only (label nil).
private final class TaskActionButton: NSView {
    enum Style { case ghost, primary, danger }
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    private let label: String?
    private let icon: String
    private let style: Style
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Width on the 1554-wide board.
    var designWidth: CGFloat {
        guard let label else { return 36 }
        return 14 + 16 + 8 + HistoryStyle.width(label, size: 12, weight: style == .primary ? .semibold : .medium) + 14
    }

    init(label: String?, icon: String, style: Style, tooltip: String? = nil, onClick: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.style = style; self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tooltip ?? label
        setAccessibilityLabel(tooltip ?? label ?? "")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick() } }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12 * s, yRadius: 12 * s)
        let tint: NSColor
        switch style {
        case .primary:
            (hovering ? PanelStyle.accentHover : PanelStyle.warmCue).setFill(); path.fill()
            tint = PanelStyle.accentInk
        case .danger:
            PanelStyle.failure.withAlphaComponent(hovering ? 0.14 : 0.08).setFill(); path.fill()
            PanelStyle.failure.withAlphaComponent(0.32).setStroke(); path.lineWidth = max(1, s); path.stroke()
            tint = PanelStyle.failure
        case .ghost:
            NSColor.white.withAlphaComponent(hovering ? 0.09 : 0.05).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.08).setStroke(); path.lineWidth = max(1, s); path.stroke()
            tint = PanelStyle.textPrimary
        }
        if let label {
            HistoryStyle.drawIcon(icon, color: tint, in: CGRect(x: 14 * s, y: 10 * s, width: 16 * s, height: 16 * s))
            HistoryStyle.draw(label, in: CGRect(x: 38 * s, y: 10 * s, width: bounds.width - 52 * s, height: 16 * s), size: 12 * s,
                              weight: style == .primary ? .semibold : .medium, color: tint)
        } else {
            HistoryStyle.drawIcon(icon, color: tint, in: CGRect(x: 10 * s, y: 10 * s, width: 16 * s, height: 16 * s))
        }
    }
}

/// 312 × 36 search field, always visible in the list header.
private final class TaskSearchBox: NSView, NSTextFieldDelegate {
    var uiScale: CGFloat = 1 { didSet { needsLayout = true; needsDisplay = true } }
    var onChange: (() -> Void)?
    private let field = HistoryTextField()
    private var focused = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var query: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = HistoryStyle.text
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.onFocusChange = { [weak self] in self?.focused = $0 }
        addSubview(field)
        updatePlaceholder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updatePlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: "Search tasks".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 13), .foregroundColor: HistoryStyle.muted])
    }

    private var clearRect: CGRect {
        let s = uiScale
        return CGRect(x: bounds.width - 10 * s - 18 * s, y: 9 * s, width: 18 * s, height: 18 * s)
    }

    override func layout() {
        super.layout()
        let s = uiScale
        field.font = PanelStyle.inspectFont(ofSize: 13 * s)
        field.frame = CGRect(x: 38 * s, y: (bounds.height - 18 * s) / 2, width: bounds.width - 38 * s - 34 * s, height: 18 * s)
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12 * s, yRadius: 12 * s)
        HistoryStyle.field.setFill(); path.fill()
        (focused ? HistoryStyle.accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.10)).setStroke()
        path.lineWidth = max(1, s); path.stroke()
        HistoryStyle.drawIcon("HistorySearch", color: focused ? HistoryStyle.accent : HistoryStyle.muted,
                              in: CGRect(x: 12 * s, y: 9 * s, width: 18 * s, height: 18 * s))
        if !field.stringValue.isEmpty {
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: clearRect).fill()
            HistoryStyle.drawIcon("HistoryClose", color: HistoryStyle.secondary,
                                  in: clearRect.insetBy(dx: 4 * s, dy: 4 * s))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !field.stringValue.isEmpty, clearRect.insetBy(dx: -4, dy: -4).contains(point) { clear(); return }
        window?.makeFirstResponder(field)
    }

    private func clear() {
        field.stringValue = ""
        needsDisplay = true
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        needsDisplay = true
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if field.stringValue.isEmpty { window?.makeFirstResponder(nil) } else { clear() }
        return true
    }
}

/// All / Running / Done / Failed with counts, as pills.
private final class TaskPillBar: NSView {
    var onSelect: ((Int) -> Void)?
    var selectedSegment = 0 { didSet { needsDisplay = true } }
    var counts: [Int] = [0, 0, 0, 0] { didSet { needsDisplay = true } }
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    private let titles: [String]
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func pillRects() -> [CGRect] {
        let s = uiScale
        var x: CGFloat = 0
        return titles.indices.map { index in
            let active = index == selectedSegment
            let w = (12 + HistoryStyle.width(titles[index], size: 12, weight: active ? .semibold : .medium) + 6
                     + HistoryStyle.width(String(counts[index]), size: 12) + 12) * s
            defer { x += w + 8 * s }
            return CGRect(x: x, y: 0, width: w, height: 30 * s)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        for (index, rect) in pillRects().enumerated() {
            let active = index == selectedSegment
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 15 * s, yRadius: 15 * s)
            (active ? HistoryStyle.chipActiveFill : NSColor.white.withAlphaComponent(0.05)).setFill(); path.fill()
            (active ? HistoryStyle.accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.08)).setStroke()
            path.lineWidth = max(1, s); path.stroke()
            let weight: NSFont.Weight = active ? .semibold : .medium
            let labelW = HistoryStyle.width(titles[index], size: 12 * s, weight: weight)
            HistoryStyle.draw(titles[index], in: CGRect(x: rect.minX + 12 * s, y: 7 * s, width: labelW + 2, height: 16 * s), size: 12 * s,
                              weight: weight, color: active ? HistoryStyle.accent : HistoryStyle.secondary)
            HistoryStyle.draw(String(counts[index]), in: CGRect(x: rect.minX + 12 * s + labelW + 6 * s, y: 7 * s, width: 50, height: 16 * s), size: 12 * s,
                              color: active ? HistoryStyle.accent : HistoryStyle.muted)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = pillRects().firstIndex(where: { $0.contains(point) }) { onSelect?(index) }
    }
}
