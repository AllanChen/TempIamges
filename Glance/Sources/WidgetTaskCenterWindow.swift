import AppKit

final class WidgetTaskCenterWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static let designSize = NSSize(width: 1554, height: 1012)

    private let root = NSView()
    private let titlebar = TaskCenterTitlebar()
    private let titleLabel = TaskPassthroughLabel(labelWithString: "Task Center")
    private let countLabel = TaskPassthroughLabel(labelWithString: "")
    private lazy var closeButton = TaskTrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeButton = TaskTrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomButton = TaskTrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))

    private let toolbarBar = NSView()
    private lazy var refreshButton = makeIconButton("arrow.clockwise", "Refresh".localized, #selector(refreshTapped))
    private lazy var searchButton = makeIconButton("magnifyingglass", "Search".localized, #selector(searchTapped))
    private lazy var inspectButton = makeIconButton("photo", "Show in Image Inspect".localized, #selector(showInInspect))
    private lazy var clearButton = makeIconButton("trash", "Clear History".localized, #selector(clearAll), tint: PanelStyle.failure)
    private lazy var infoButton = makeIconButton("info.circle", "Task information".localized, #selector(toggleDetails))
    private lazy var revealButton = makeIconButton("folder", "Reveal in Finder".localized, #selector(revealSelected))
    private lazy var retryButton = makeIconButton("arrow.clockwise", "Retry".localized, #selector(retrySelected))
    private lazy var removeButton = makeIconButton("trash", "Remove Record".localized, #selector(removeSelected), tint: PanelStyle.failure)

    private let sidebar = NSView()
    private let sidebarTitle = NSTextField(labelWithString: "Tasks".localized)
    private let sidebarCaption = NSTextField(labelWithString: "Local and polling Widget tasks".localized)
    private let filter = TaskFilterBar(titles: ["All".localized, "Running".localized, "Completed".localized, "Failed".localized])
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    private let detail = NSView()
    private let detailTitle = NSTextField(labelWithString: "Select a task".localized)
    private let detailStatus = NSTextField(labelWithString: "")
    private let sourcePreview = TaskPreviewView(title: "Source".localized)
    private let resultPreview = TaskPreviewView(title: "Waiting for result".localized)
    private let timelinePanel = NSView()
    private let timelineTitle = NSTextField(labelWithString: "Timeline".localized)
    private var timelineRows: [TaskTimelineRow] = []
    private let propertiesPanel = NSView()
    private let propertiesTitle = NSTextField(labelWithString: "Task Details".localized)
    private var propertyKeys: [NSTextField] = []
    private var propertyValues: [NSTextField] = []

    private let statusbar = NSView()
    private let leftStatus = NSTextField(labelWithString: "")
    private let centerStatus = NSTextField(labelWithString: "Select a task to inspect details".localized)
    private let rightDot = NSView()
    private let rightStatus = NSTextField(labelWithString: "")

    private var visibleRecords: [WidgetTaskRecord] = []
    private var detailsVisible = true

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
        backgroundColor = PanelStyle.inspectBackground
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
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.masksToBounds = true

        configureLabel(titleLabel, size: 15, color: PanelStyle.textPrimary, weight: .semibold, alignment: .center)
        configureLabel(countLabel, size: 11, color: PanelStyle.textTertiary, weight: .regular, alignment: .center)
        titlebar.addSubview(titleLabel)
        titlebar.addSubview(countLabel)
        // Traffic lights go on top of the (full-width, centered) title labels so
        // clicks land on the buttons instead of the label / drag surface.
        titlebar.addSubview(closeButton)
        titlebar.addSubview(minimizeButton)
        titlebar.addSubview(zoomButton)
        root.addSubview(titlebar)

        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        toolbarBar.layer?.borderWidth = 1
        toolbarBar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        [refreshButton, searchButton, inspectButton, clearButton, infoButton].forEach(toolbarBar.addSubview)
        root.addSubview(toolbarBar)

        configurePanel(sidebar, color: NSColor(srgbRed: 17 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1))
        configureLabel(sidebarTitle, size: 17, color: PanelStyle.textPrimary, weight: .semibold)
        configureLabel(sidebarCaption, size: 11, color: PanelStyle.textTertiary)
        sidebar.addSubview(sidebarTitle)
        sidebar.addSubview(sidebarCaption)
        filter.selectedSegment = 0
        filter.onSelect = { [weak self] index in
            self?.filter.selectedSegment = index
            self?.refresh()
        }
        sidebar.addSubview(filter)
        searchField.placeholderString = "Search tasks".localized
        searchField.delegate = self
        searchField.isHidden = true
        sidebar.addSubview(searchField)
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
        root.addSubview(sidebar)

        configurePanel(detail, color: PanelStyle.inspectChrome)
        configureLabel(detailTitle, size: 18, color: PanelStyle.textPrimary, weight: .semibold)
        configureLabel(detailStatus, size: 12, color: PanelStyle.accent, weight: .medium)
        detail.addSubview(detailTitle)
        detail.addSubview(detailStatus)
        detail.addSubview(revealButton)
        detail.addSubview(retryButton)
        detail.addSubview(removeButton)
        detail.addSubview(sourcePreview)
        detail.addSubview(resultPreview)
        configurePanel(timelinePanel, color: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 1), radius: 10)
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
        configurePanel(propertiesPanel, color: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 1), radius: 10)
        configureLabel(propertiesTitle, size: 13, color: PanelStyle.textPrimary, weight: .semibold)
        propertiesPanel.addSubview(propertiesTitle)
        for key in ["Widget", "Input", "Worker", "Progress", "Polling"] {
            let keyLabel = NSTextField(labelWithString: key.localized)
            let valueLabel = NSTextField(labelWithString: "—")
            configureLabel(keyLabel, size: 11, color: PanelStyle.textTertiary, weight: .medium)
            configureLabel(valueLabel, size: 12, color: PanelStyle.textPrimary)
            propertiesPanel.addSubview(keyLabel)
            propertiesPanel.addSubview(valueLabel)
            propertyKeys.append(keyLabel)
            propertyValues.append(valueLabel)
        }
        detail.addSubview(propertiesPanel)
        root.addSubview(detail)

        configurePanel(statusbar, color: PanelStyle.inspectStatus)
        configureLabel(leftStatus, size: 12, color: PanelStyle.textSecondary)
        configureLabel(centerStatus, size: 12, color: PanelStyle.textSecondary, alignment: .center)
        configureLabel(rightStatus, size: 12, color: PanelStyle.accent, weight: .medium)
        rightDot.wantsLayer = true
        rightDot.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
        statusbar.addSubview(leftStatus)
        statusbar.addSubview(centerStatus)
        statusbar.addSubview(rightDot)
        statusbar.addSubview(rightStatus)
        root.addSubview(statusbar)
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
        titlebar.frame = NSRect(x: 0, y: height - 58 * sy, width: width, height: 58 * sy)
        [closeButton, minimizeButton, zoomButton].enumerated().forEach { index, button in
            button.frame = NSRect(x: (24 + CGFloat(index) * 20) * sx, y: 23 * sy, width: 12 * sx, height: 12 * sy)
            button.layer?.cornerRadius = 6 * scale
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 15 * sy, weight: .semibold)
        countLabel.font = PanelStyle.inspectFont(ofSize: 11 * sy)
        titleLabel.frame = NSRect(x: 0, y: 26 * sy, width: width, height: 18 * sy)
        countLabel.frame = NSRect(x: 0, y: 7 * sy, width: width, height: 13 * sy)

        toolbarBar.frame = NSRect(x: 0, y: height - 128 * sy, width: width, height: 70 * sy)
        toolbarBar.layer?.borderWidth = max(1, scale)
        func place(_ button: NSButton, _ x: CGFloat) {
            button.frame = NSRect(x: x * sx, y: 18 * sy, width: 38 * sx, height: 38 * sy)
            button.layer?.cornerRadius = 8 * scale
            button.layer?.borderWidth = max(1, scale)
        }
        place(refreshButton, 40); place(searchButton, 88)
        place(inspectButton, 1378); place(clearButton, 1426); place(infoButton, 1474)

        let statusH = 37 * sy
        statusbar.frame = NSRect(x: 0, y: 0, width: width, height: statusH)
        statusbar.layer?.borderWidth = max(1, scale)
        leftStatus.font = PanelStyle.inspectFont(ofSize: 12 * sy)
        centerStatus.font = PanelStyle.inspectFont(ofSize: 12 * sy)
        rightStatus.font = PanelStyle.inspectFont(ofSize: 12 * sy, weight: .medium)
        leftStatus.frame = NSRect(x: 38 * sx, y: 11 * sy, width: 420 * sx, height: 15 * sy)
        centerStatus.frame = NSRect(x: 0, y: 11 * sy, width: width, height: 15 * sy)
        rightDot.frame = NSRect(x: 1394 * sx, y: 14 * sy, width: 8 * sx, height: 8 * sy)
        rightDot.layer?.cornerRadius = 4 * scale
        rightStatus.frame = NSRect(x: 1414 * sx, y: 11 * sy, width: 120 * sx, height: 15 * sy)

        let contentY = statusH, contentH = height - 128 * sy - statusH
        sidebar.frame = NSRect(x: 0, y: contentY, width: 360 * sx, height: contentH)
        detail.frame = NSRect(x: 360 * sx, y: contentY, width: width - 360 * sx, height: contentH)
        sidebar.layer?.borderWidth = max(1, scale); detail.layer?.borderWidth = max(1, scale)
        func topRect(_ parent: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, designW: CGFloat = 360, designH: CGFloat = 847) -> NSRect {
            let px = parent.bounds.width / designW, py = parent.bounds.height / designH
            return NSRect(x: x * px, y: parent.bounds.height - (y + h) * py, width: w * px, height: h * py)
        }
        sidebarTitle.font = PanelStyle.inspectFont(ofSize: 17 * sy, weight: .semibold)
        sidebarCaption.font = PanelStyle.inspectFont(ofSize: 11 * sy)
        sidebarTitle.frame = topRect(sidebar, 24, 22, 300, 21)
        sidebarCaption.frame = topRect(sidebar, 24, 49, 312, 14)
        filter.frame = topRect(sidebar, 20, 82, 320, 38)
        searchField.frame = topRect(sidebar, 20, 82, 320, 38)
        scroll.frame = topRect(sidebar, 14, 140, 332, 690)
        scroll.borderType = .noBorder
        scroll.layoutSubtreeIfNeeded()
        let tableWidth = max(1, scroll.contentSize.width)
        if let column = table.tableColumns.first {
            column.resizingMask = .autoresizingMask
            column.width = tableWidth
            column.minWidth = tableWidth
            column.maxWidth = tableWidth
        }
        table.rowHeight = 82 * sy
        table.intercellSpacing = NSSize(width: 0, height: 10 * sy)
        table.frame.size.width = tableWidth

        let dx = detail.bounds.width / 1194, dy = detail.bounds.height / 847
        detailTitle.font = PanelStyle.inspectFont(ofSize: 18 * sy, weight: .semibold)
        detailStatus.font = PanelStyle.inspectFont(ofSize: 12 * sy, weight: .medium)
        detailTitle.frame = NSRect(x: 32 * dx, y: detail.bounds.height - 46 * dy, width: 500 * dx, height: 22 * dy)
        detailStatus.frame = NSRect(x: 32 * dx, y: detail.bounds.height - 69 * dy, width: 500 * dx, height: 15 * dy)
        revealButton.frame = NSRect(x: detail.bounds.width - 162 * dx, y: detail.bounds.height - 60 * dy, width: 38 * dx, height: 38 * dy)
        retryButton.frame = NSRect(x: detail.bounds.width - 114 * dx, y: detail.bounds.height - 60 * dy, width: 38 * dx, height: 38 * dy)
        removeButton.frame = NSRect(x: detail.bounds.width - 66 * dx, y: detail.bounds.height - 60 * dy, width: 38 * dx, height: 38 * dy)
        [revealButton, retryButton, removeButton].forEach {
            $0.layer?.cornerRadius = 8 * scale
            $0.layer?.borderWidth = max(1, scale)
        }
        inspectButton.isEnabled = selectedOutputExists
        clearButton.isEnabled = WidgetTaskManager.shared.records.contains { !$0.phase.isActive }
        sourcePreview.frame = NSRect(x: 32 * dx, y: detail.bounds.height - 408 * dy, width: 528 * dx, height: 304 * dy)
        resultPreview.frame = NSRect(x: 578 * dx, y: detail.bounds.height - 408 * dy, width: 528 * dx, height: 304 * dy)
        timelinePanel.frame = NSRect(x: 32 * dx, y: detail.bounds.height - 770 * dy, width: 560 * dx, height: 330 * dy)
        propertiesPanel.frame = NSRect(x: 612 * dx, y: detail.bounds.height - 770 * dy, width: 494 * dx, height: 330 * dy)
        timelineTitle.frame = NSRect(x: 24 * dx, y: timelinePanel.bounds.height - 39 * dy, width: 200 * dx, height: 16 * dy)
        let timelineY: [CGFloat] = [60, 132, 204, 276]
        for (row, y) in zip(timelineRows, timelineY) { row.frame = topRect(timelinePanel, 20, y, 520, 54, designW: 560, designH: 330) }
        propertiesTitle.frame = topRect(propertiesPanel, 24, 20, 300, 16, designW: 494, designH: 330)
        let propertyY: [CGFloat] = [60, 98, 136, 174, 212]
        for index in propertyKeys.indices {
            propertyKeys[index].frame = topRect(propertiesPanel, 24, propertyY[index], 120, 15, designW: 494, designH: 330)
            propertyValues[index].frame = topRect(propertiesPanel, 168, propertyY[index], 290, 15, designW: 494, designH: 330)
        }
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

    private func makeIconButton(_ symbol: String, _ tooltip: String, _ action: Selector,
                                tint: NSColor = PanelStyle.textPrimary) -> InspectToolbarButton {
        let button = InspectToolbarButton(symbol: symbol, tooltip: tooltip)
        button.target = self
        button.action = action
        button.usesFigmaStyle = true
        button.contentTintColor = tint
        return button
    }

    func refresh() {
        let records = WidgetTaskManager.shared.records
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [WidgetTaskRecord]
        switch filter.selectedSegment {
        case 1: filtered = records.filter { $0.phase.isActive }
        case 2: filtered = records.filter { $0.phase == .completed }
        case 3: filtered = records.filter { $0.phase == .failed || $0.phase == .interrupted }
        default: filtered = records
        }
        visibleRecords = query.isEmpty ? filtered : filtered.filter {
            $0.widgetName.localizedCaseInsensitiveContains(query) ||
            $0.commandName.localizedCaseInsensitiveContains(query) ||
            ($0.source?.lastPathComponent.localizedCaseInsensitiveContains(query) ?? false)
        }
        countLabel.stringValue = "\(records.count) tasks"
        leftStatus.stringValue = "\(records.count) tasks  •  \(WidgetTaskManager.shared.activeCount) running"
        rightDot.isHidden = WidgetTaskManager.shared.activeCount == 0
        rightStatus.isHidden = WidgetTaskManager.shared.activeCount == 0
        rightStatus.stringValue = "\(WidgetTaskManager.shared.activeCount) task" + (WidgetTaskManager.shared.activeCount == 1 ? " running" : "s running")
        let selectedID = selected?.id
        table.reloadData()
        if let selectedID, let row = visibleRecords.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !visibleRecords.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateDetail(selected)
        layoutContent()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRecords.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = visibleRecords[row]
        let cell = TaskCenterCellView()
        cell.configure(record: record, selected: row == table.selectedRow)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TaskCenterRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetail(selected)
        table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<visibleRecords.count), columnIndexes: IndexSet(integer: 0))
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    private var selected: WidgetTaskRecord? {
        let row = table.selectedRow
        return visibleRecords.indices.contains(row) ? visibleRecords[row] : nil
    }

    private var selectedOutputExists: Bool {
        selected?.output.map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    private func updateDetail(_ record: WidgetTaskRecord?) {
        guard let record else {
            detailTitle.stringValue = "Select a task".localized
            detailStatus.stringValue = ""
            sourcePreview.configure(url: nil, waiting: false)
            resultPreview.configure(url: nil, waiting: true)
            timelineRows.enumerated().forEach { $0.element.configure(state: $0.offset == 0 ? .pending : .disabled, time: "") }
            propertyValues.forEach { $0.stringValue = "—" }
            centerStatus.stringValue = "Select a task to inspect details".localized
            inspectButton.isEnabled = false
            revealButton.isEnabled = false
            retryButton.isEnabled = false
            removeButton.isEnabled = false
            return
        }
        detailTitle.stringValue = record.commandName
        detailStatus.stringValue = "Task \(record.id.uuidString.prefix(4).uppercased())  •  \(stateText(record))"
        sourcePreview.configure(url: record.source, waiting: false)
        resultPreview.configure(url: record.output, waiting: record.phase != .completed)
        let phaseIndex: Int
        switch record.phase {
        case .uploading, .submitting: phaseIndex = 0
        case .processing: phaseIndex = 2
        case .downloading: phaseIndex = 3
        case .completed: phaseIndex = 4
        case .failed, .interrupted: phaseIndex = 2
        }
        for index in timelineRows.indices {
            let state: TaskTimelineRow.State = index < phaseIndex ? .complete : (index == phaseIndex ? .current : .pending)
            timelineRows[index].configure(state: state, time: index == phaseIndex ? "Now".localized : "")
        }
        propertyValues[0].stringValue = record.widgetName
        propertyValues[1].stringValue = record.source?.lastPathComponent ?? "Media"
        propertyValues[2].stringValue = record.remoteTaskID == nil ? "—" : "Remote"
        propertyValues[3].stringValue = "\(record.progress)%"
        propertyValues[4].stringValue = record.phase.isActive ? "2 seconds".localized : "—"
        centerStatus.stringValue = record.errorMessage ?? detailText(record)
        inspectButton.isEnabled = selectedOutputExists
        revealButton.isEnabled = selectedOutputExists
        retryButton.isEnabled = record.phase == .failed || record.phase == .interrupted || (record.phase == .completed && !selectedOutputExists)
        removeButton.isEnabled = !record.phase.isActive
    }

    private func detailText(_ record: WidgetTaskRecord) -> String {
        "\(record.source?.lastPathComponent ?? "Media")  •  \(DateFormatter.localizedString(from: record.createdAt, dateStyle: .short, timeStyle: .short))"
    }

    private func stateText(_ record: WidgetTaskRecord) -> String {
        switch record.phase {
        case .processing: return record.progress > 0 ? "\(record.progress)%" : "Processing".localized
        case .uploading: return "Uploading".localized
        case .submitting: return "Submitting".localized
        case .downloading: return "Downloading".localized
        case .completed: return "Completed".localized
        case .failed: return "Failed".localized
        case .interrupted: return "Interrupted".localized
        }
    }

    @objc private func tasksChanged() { refresh() }
    @objc private func refreshTapped() { refresh() }
    @objc private func filterChanged() { refresh() }
    @objc private func selectionChanged() { updateDetail(selected) }
    @objc private func searchTapped() { searchField.isHidden.toggle(); if !searchField.isHidden { makeFirstResponder(searchField) } }
    @objc private func toggleDetails() { detailsVisible.toggle(); propertiesPanel.isHidden = !detailsVisible; timelinePanel.isHidden = !detailsVisible }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }

    @objc private func showInInspect() {
        guard let url = selected?.output, FileManager.default.fileExists(atPath: url.path) else { return }
        (NSApp.delegate as? AppDelegate)?.openTaskOutputInInspect(url)
    }

    @objc private func openSelected() {
        if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    @objc private func revealSelected() {
        if let url = selected?.output, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func retrySelected() { if let id = selected?.id { WidgetTaskManager.shared.retry(id) } }
    @objc private func removeSelected() { if let id = selected?.id { WidgetTaskManager.shared.remove(id) } }

    @objc private func clearAll() {
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
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { event.clickCount == 2 ? window?.zoom(nil) : window?.performDrag(with: event) }
}

private final class TaskTrafficLightButton: NSButton {
    init(color: NSColor, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        isBordered = false; title = ""; wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(color); layer?.cornerRadius = 6
        self.target = target; self.action = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class TaskCenterCellView: NSTableCellView {
    private let preview = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stateBadge = NSView()
    private let stateLabel = NSTextField(labelWithString: "")
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 9; layer?.borderWidth = 1; layer?.masksToBounds = true
        preview.imageScaling = .scaleProportionallyUpOrDown; preview.wantsLayer = true; preview.layer?.cornerRadius = 7; preview.layer?.masksToBounds = true; preview.layer?.borderWidth = 1; preview.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold); titleLabel.textColor = PanelStyle.textPrimary
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11); detailLabel.textColor = PanelStyle.textTertiary
        stateBadge.wantsLayer = true; stateBadge.layer?.cornerRadius = 6; stateBadge.layer?.masksToBounds = true
        stateLabel.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold); stateLabel.alignment = .center; stateLabel.lineBreakMode = .byClipping
        stateBadge.addSubview(stateLabel)
        [preview, titleLabel, detailLabel, stateBadge].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(record: WidgetTaskRecord, selected: Bool) {
        layer?.backgroundColor = PanelStyle.resolvedCG(selected ? NSColor(srgbRed: 36 / 255, green: 34 / 255, blue: 41 / 255, alpha: 1) : PanelStyle.inspectChrome)
        layer?.borderColor = PanelStyle.resolvedCG(selected ? PanelStyle.accent.withAlphaComponent(0.42) : PanelStyle.inspectLine)
        let previewURL = record.output.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? record.source
        preview.image = previewURL.flatMap { $0.isFileURL ? NSImage(contentsOf: $0) : nil } ?? NSImage(systemSymbolName: record.phase.isActive ? "hourglass" : "photo", accessibilityDescription: nil)
        titleLabel.stringValue = record.commandName
        detailLabel.stringValue = "\(relativeDate(record.createdAt))  •  \(record.source?.lastPathComponent ?? "Media")"
        let color: NSColor = record.phase.isActive ? PanelStyle.accent : ((record.phase == .failed || record.phase == .interrupted) ? PanelStyle.failure : PanelStyle.success)
        stateLabel.stringValue = taskState(record)
        stateLabel.textColor = color
        stateBadge.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        setAccessibilityLabel("\(record.commandName), \(stateLabel.stringValue)")
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
        titleLabel.frame = NSRect(x: 82 * sx, y: 17 * sy, width: 160 * sx, height: 17 * sy)
        detailLabel.frame = NSRect(x: 82 * sx, y: 43 * sy, width: 160 * sx, height: 14 * sy)
        stateBadge.frame = NSRect(x: 250 * sx, y: 28 * sy, width: 70 * sx, height: 26 * sy)
        let labelHeight = ceil(stateLabel.fittingSize.height)
        stateLabel.frame = NSRect(x: 2 * sx,
                                  y: floor((stateBadge.bounds.height - labelHeight) / 2) + 1,
                                  width: stateBadge.bounds.width - 4 * sx,
                                  height: labelHeight)
    }

    private func taskState(_ record: WidgetTaskRecord) -> String {
        switch record.phase { case .processing: return record.progress > 0 ? "\(record.progress)%" : "Running"; case .uploading: return "Uploading"; case .submitting: return "Submitting"; case .downloading: return "Downloading"; case .completed: return "Done"; case .failed: return "Failed"; case .interrupted: return "Interrupted" }
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
    init(title: String) { waitingLabel = NSTextField(labelWithString: title); super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas); layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine); layer?.borderWidth = 1; layer?.cornerRadius = 10; imageView.imageScaling = .scaleProportionallyUpOrDown; addSubview(imageView); waitingLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium); waitingLabel.textColor = PanelStyle.textTertiary; waitingLabel.alignment = .center; addSubview(waitingLabel) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(url: URL?, waiting: Bool) { imageView.image = url.flatMap { $0.isFileURL ? NSImage(contentsOf: $0) : nil }; waitingLabel.isHidden = imageView.image != nil; if waiting { waitingLabel.stringValue = "Waiting for result".localized } }
    override func layout() { super.layout(); imageView.frame = bounds.insetBy(dx: 12, dy: 12); waitingLabel.frame = NSRect(x: 20, y: bounds.midY - 9, width: bounds.width - 40, height: 18) }
}

private final class TaskTimelineRow: NSView {
    enum State { case complete, current, pending, disabled }
    private let mark = NSView(), halo = NSView(), connector = NSView(), titleLabel: NSTextField, detailLabel: NSTextField, timeLabel = NSTextField(labelWithString: "")
    private let showsConnector: Bool
    init(title: String, detail: String, showsConnector: Bool) { self.showsConnector = showsConnector; titleLabel = NSTextField(labelWithString: title); detailLabel = NSTextField(labelWithString: detail); super.init(frame: .zero); mark.wantsLayer = true; halo.wantsLayer = true; connector.wantsLayer = true; connector.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine); addSubview(connector); addSubview(halo); addSubview(mark); titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium); titleLabel.textColor = PanelStyle.textPrimary; detailLabel.font = PanelStyle.inspectFont(ofSize: 11); detailLabel.textColor = PanelStyle.textTertiary; timeLabel.font = PanelStyle.inspectFont(ofSize: 11); timeLabel.textColor = PanelStyle.textTertiary; timeLabel.alignment = .right; [titleLabel, detailLabel, timeLabel].forEach(addSubview) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(state: State, time: String) { let color: NSColor = state == .complete ? PanelStyle.success : (state == .current ? PanelStyle.accent : PanelStyle.textTertiary); mark.layer?.backgroundColor = color.cgColor; halo.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor; halo.isHidden = state != .current; timeLabel.stringValue = time }
    override func layout() { super.layout(); halo.frame = NSRect(x: 3, y: bounds.height - 28, width: 24, height: 24); halo.layer?.cornerRadius = 12; mark.frame = NSRect(x: 8, y: bounds.height - 23, width: 14, height: 14); mark.layer?.cornerRadius = 7; connector.isHidden = !showsConnector; connector.frame = NSRect(x: 14.5, y: 0, width: 1, height: max(0, bounds.height - 23)); titleLabel.frame = NSRect(x: 38, y: bounds.height - 22, width: bounds.width - 170, height: 16); detailLabel.frame = NSRect(x: 38, y: bounds.height - 44, width: bounds.width - 90, height: 14); timeLabel.frame = NSRect(x: bounds.width - 110, y: bounds.height - 22, width: 100, height: 14) }
}

private final class TaskFilterBar: NSView {
    var onSelect: ((Int) -> Void)?
    var selectedSegment = 0 { didSet { updateAppearance() } }
    private let buttons: [PanelButton]

    init(titles: [String]) {
        buttons = titles.enumerated().map { index, title in
            let button = PanelStyle.makeSegmentButton(title: title, target: nil, action: nil)
            button.tag = index
            return button
        }
        super.init(frame: .zero)
        for button in buttons {
            button.target = self
            button.action = #selector(tapped(_:))
            button.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
            addSubview(button)
        }
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ sender: NSButton) { selectedSegment = sender.tag; onSelect?(sender.tag) }
    private func updateAppearance() { for (index, button) in buttons.enumerated() { PanelStyle.setSegmentActive(button, active: index == selectedSegment) } }
    override func layout() { super.layout(); let widths: [CGFloat] = [72, 80, 72, 72]; let scale = bounds.width / 320; var x: CGFloat = 0; for (button, width) in zip(buttons, widths) { button.frame = NSRect(x: x, y: 0, width: width * scale, height: bounds.height); button.layer?.cornerRadius = 8 * min(scale, bounds.height / 38); x += (width + 8) * scale } }
}
