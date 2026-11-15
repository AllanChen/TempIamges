import AppKit
import CoreText

/// Task Center, laid out from the Shizuka boards "04 · Task Center",
/// "13 · Task Center / Failed" and "47 · Empty states" (1440 × 900).
///
/// List actions (filters, search, refresh, clear finished) live in the list;
/// task actions sit in one group at the top right of the detail and change
/// with the selected task's state.
final class WidgetTaskCenterWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    private static let designSize = NSSize(width: 1554, height: 1012)
    /// Board the frames below are written in (top-left origin, uniform scale).
    private static let board = NSSize(width: 1440, height: 900)

    private enum DetailMode { case live, stopped }

    // Flipped so frames can be written with the board's top-left coordinates.
    private let root = FlippedDocView()
    private let titlebar = TaskCenterTitlebar()
    private let titleLabel = TaskText()
    private lazy var closeButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))

    // List column: list-level actions only.
    private let sidebarEdge = NSView()
    private let filters = TaskFilterTabs(titles: ["All".localized, "Running".localized, "Done".localized, "Failed".localized])
    private lazy var refreshButton = TaskIconButton(icon: "TaskIconRefresh", tooltip: "Refresh".localized) { [weak self] in self?.refreshTapped() }
    private lazy var clearButton = TaskIconButton(icon: "HistoryClear", tooltip: "Clear Finished".localized, danger: true) { [weak self] in self?.clearAll() }
    private let searchBox = TaskQuietSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let countLabel = TaskText()

    // Detail column: header and action group, status, then previews, timeline and details.
    private let eyebrow = TaskText()
    private let detailTitle = TaskText()
    private lazy var showSourceButton = TaskActionButton(label: "Show Source".localized, style: .ghost) { [weak self] in self?.showSource() }
    private lazy var cancelButton = TaskActionButton(label: "Cancel".localized, style: .ghost) { [weak self] in self?.cancelSelected() }
    private lazy var inspectButton = TaskActionButton(label: "Show in Image Inspect".localized, style: .ghost) { [weak self] in self?.showInInspect() }
    private lazy var copyURLButton = TaskActionButton(label: "Copy URL".localized, style: .ghost) { [weak self] in self?.copyResultURL() }
    private lazy var revealButton = TaskActionButton(label: "Reveal in Finder".localized, style: .ghost) { [weak self] in self?.revealSelected() }
    private lazy var retryButton = TaskActionButton(label: "Retry".localized, style: .primary) { [weak self] in self?.retrySelected() }
    private lazy var removeButton = TaskActionButton(icon: "HistoryClear", tooltip: "Remove Record".localized) { [weak self] in self?.removeSelected() }
    private let actionSeparator = NSView()
    /// Visible actions left to right, the separator included.
    private var actionOrder: [NSView] = []
    private let statusDot = NSView()
    private let statusLabel = TaskText()
    private let statusDetail = TaskText()
    private let percentLabel = TaskText()
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private var progressValue: CGFloat = 0
    private let outcomeBlock = TaskOutcomeBlock()
    private let sourcePreview = TaskPreviewView(title: "Source".localized)
    private let resultPreview = TaskPreviewView(title: "Waiting for result".localized)
    private let sourceCaption = TaskText()
    private let resultCaption = TaskText()
    private let timelineTitle = TaskText()
    private var timelineRows: [TaskTimelineRow] = []
    private let detailsTitle = TaskText()
    private var propertyKeys: [TaskText] = []
    private var propertyValues: [TaskText] = []
    private var propertyDividers: [NSView] = []
    private let emptyState = TaskEmptyStateView()
    private let toast = InspectToastWindow()

    private var visibleRecords: [WidgetTaskRecord] = []
    private var allRecords: [WidgetTaskRecord] = []
    private var mode: DetailMode = .live

    init() {
        let frame = Self.initialFrame()
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Tasks".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        appearance = PanelStyle.windowAppearance
        backgroundColor = PanelStyle.surface
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
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(TaskTone.lineStrong)
        root.layer?.masksToBounds = true

        titleLabel.string = "Tasks".localized
        titleLabel.color = PanelStyle.textSecondary
        titleLabel.alignment = .center
        titlebar.addSubview(titleLabel)
        // Traffic lights go on top of the (full-width, centered) title so
        // clicks land on the buttons instead of the label / drag surface.
        titlebar.addSubview(closeButton)
        titlebar.addSubview(minimizeButton)
        titlebar.addSubview(zoomButton)
        root.addSubview(titlebar)

        // List column.
        sidebarEdge.wantsLayer = true
        sidebarEdge.layer?.backgroundColor = PanelStyle.resolvedCG(TaskTone.line)
        root.addSubview(sidebarEdge)
        filters.onSelect = { [weak self] index in
            self?.filters.selectedSegment = index
            self?.refresh()
        }
        root.addSubview(filters)
        root.addSubview(refreshButton)
        root.addSubview(clearButton)
        searchBox.onChange = { [weak self] in self?.refresh() }
        root.addSubview(searchBox)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Task"))
        column.width = 312
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 56
        table.intercellSpacing = NSSize(width: 0, height: 2)
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
        PanelStyle.styleScrollers(in: scroll)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        root.addSubview(scroll)
        countLabel.color = PanelStyle.textTertiary
        root.addSubview(countLabel)

        // Detail column.
        eyebrow.color = PanelStyle.textTertiary
        detailTitle.color = PanelStyle.textPrimary
        root.addSubview(eyebrow)
        root.addSubview(detailTitle)
        actionSeparator.wantsLayer = true
        actionSeparator.layer?.backgroundColor = PanelStyle.resolvedCG(TaskTone.lineStrong)
        for view in [showSourceButton, cancelButton, inspectButton, copyURLButton, revealButton, retryButton, removeButton, actionSeparator] as [NSView] {
            view.isHidden = true
            root.addSubview(view)
        }
        statusDot.wantsLayer = true
        statusLabel.color = PanelStyle.textPrimary
        statusDetail.color = PanelStyle.textTertiary
        percentLabel.color = PanelStyle.textTertiary
        percentLabel.alignment = .right
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = PanelStyle.resolvedCG(TaskTone.line)
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.textPrimary)
        progressTrack.addSubview(progressFill)
        [statusDot, statusLabel, statusDetail, percentLabel, progressTrack, outcomeBlock].forEach(root.addSubview)
        root.addSubview(sourcePreview)
        root.addSubview(resultPreview)
        for caption in [sourceCaption, resultCaption] {
            caption.color = PanelStyle.textTertiary
            root.addSubview(caption)
        }
        timelineTitle.string = "Timeline".localized
        timelineTitle.color = PanelStyle.textTertiary
        root.addSubview(timelineTitle)
        let timelineSpecs = [
            ("Task submitted".localized, "Client uploaded the source image".localized),
            ("Worker claimed".localized, "GPU worker".localized),
            ("Processing".localized, "Polling every 2 seconds".localized),
            ("Download result".localized, "Waiting for output file".localized)
        ]
        for spec in timelineSpecs {
            let row = TaskTimelineRow(title: spec.0, detail: spec.1)
            root.addSubview(row)
            timelineRows.append(row)
        }
        detailsTitle.string = "Details".localized
        detailsTitle.color = PanelStyle.textTertiary
        root.addSubview(detailsTitle)
        for _ in 0..<5 {
            let keyLabel = TaskText(), valueLabel = TaskText()
            keyLabel.color = PanelStyle.textTertiary
            valueLabel.string = "—"
            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = PanelStyle.resolvedCG(TaskTone.line)
            [keyLabel, valueLabel, divider].forEach(root.addSubview)
            propertyKeys.append(keyLabel)
            propertyValues.append(valueLabel)
            propertyDividers.append(divider)
        }
        emptyState.isHidden = true
        root.addSubview(emptyState)
        layoutContent()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        guard width > 0, height > 0 else { return }
        let k = min(width / Self.board.width, height / Self.board.height)
        let boardW = width / k, boardH = height / k
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * k, y: y * k, width: max(0, w) * k, height: max(0, h) * k)
        }
        let hairline = 1 / k

        // Title bar (board 44 pt): traffic lights at (20, 16), title 13 pt at y 14.
        titlebar.frame = NSRect(x: 0, y: 0, width: width, height: 44 * k)
        [closeButton, minimizeButton, zoomButton].enumerated().forEach { index, button in
            button.frame = r(20 + CGFloat(index) * 20, 16, 12, 12)
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * k, weight: .medium)
        titleLabel.frame = r(0, 14, boardW, 16)

        // List column: divider at x 340, filters at (14, 60), rows 312 × 56 with a 2 pt gap.
        sidebarEdge.frame = NSRect(x: 340 * k, y: 44 * k, width: 1, height: height - 44 * k)
        filters.uiScale = k
        filters.frame = r(14, 60, 244, 28)
        refreshButton.uiScale = k
        clearButton.uiScale = k
        refreshButton.frame = r(262, 60, 28, 28)
        clearButton.frame = r(294, 60, 28, 28)
        searchBox.uiScale = k
        searchBox.frame = r(26, 98, 296, 28)
        let footerY = boardH - 62
        countLabel.font = PanelStyle.monoFont(ofSize: 11 * k)
        countLabel.frame = r(26, footerY, 296, 14)
        scroll.frame = r(14, 138, 312, footerY - 12 - 138)
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
        table.rowHeight = 56 * k
        table.intercellSpacing = NSSize(width: 0, height: 2 * k)
        table.frame.size.width = tableWidth
        table.tile()

        // Detail column: x 396 to 56 pt from the right edge.
        let left: CGFloat = 396
        let dw = max(320, boardW - left - 56)
        let right = left + dw
        let cw = (dw - 24) / 2

        // One action group, built from the right edge so it stays aligned
        // whichever buttons this state needs.
        var x = right
        for view in actionOrder.reversed() {
            if view === actionSeparator {
                actionSeparator.frame = r(x - 5, 112, hairline, 20)
                x -= 9
            } else if let button = view as? TaskActionButton {
                button.uiScale = k
                let w = button.designWidth
                button.frame = r(x - w, 106, w, 32)
                x -= w + 8
            }
        }
        let actionsLeft = actionOrder.isEmpty ? right : x
        eyebrow.font = PanelStyle.monoFont(ofSize: 11 * k)
        eyebrow.kern = 1 * k
        eyebrow.frame = r(left, 76, dw / 2, 14)
        detailTitle.font = PanelStyle.titleFont(ofSize: 30 * k)
        detailTitle.frame = r(left, 100, actionsLeft - 16 - left, 38)

        // Status row: dot, state, "· Widget", percentage on the right.
        statusDot.frame = r(left, 164.5, 6, 6)
        statusDot.layer?.cornerRadius = 3 * k
        statusLabel.font = PanelStyle.inspectFont(ofSize: 12 * k, weight: .medium)
        statusDetail.font = PanelStyle.inspectFont(ofSize: 12 * k)
        percentLabel.font = PanelStyle.monoFont(ofSize: 11 * k)
        let stateWidth = min(statusLabel.textWidth / k, dw / 2)
        statusLabel.frame = r(left + 14, 160, stateWidth, 15)
        statusDetail.frame = r(left + 14 + stateWidth + 8, 160, dw - 14 - stateWidth - 8 - 72, 15)
        percentLabel.frame = r(right - 64, 160.5, 64, 14)
        progressTrack.frame = r(left, 187, dw, 2)
        progressFill.frame = NSRect(x: 0, y: 0, width: progressTrack.bounds.width * progressValue, height: progressTrack.bounds.height)

        let previewTop: CGFloat
        let previewHeight: CGFloat
        let sectionTop: CGFloat
        if mode == .stopped {
            // Board 13: what happened at y 203, previews 32 pt below, timeline full width.
            outcomeBlock.uiScale = k
            let blockHeight = outcomeBlock.preferredHeight(width: dw * k) / k
            outcomeBlock.frame = r(left, 203, dw, blockHeight)
            previewTop = 203 + blockHeight + 32
            previewHeight = max(120, min(241, boardH - 24 - 135 - 32 - 25 - previewTop))
            sectionTop = previewTop + previewHeight + 25 + 32
        } else {
            // Board 04: previews at y 221, timeline and details 40 pt below the captions.
            previewTop = 221
            previewHeight = max(160, min(318, boardH - 24 - 196 - 40 - 25 - previewTop))
            sectionTop = previewTop + previewHeight + 25 + 40
        }
        for preview in [sourcePreview, resultPreview] { preview.uiScale = k }
        sourcePreview.frame = r(left, previewTop, cw, previewHeight)
        resultPreview.frame = r(left + cw + 24, previewTop, cw, previewHeight)
        for caption in [sourceCaption, resultCaption] { caption.font = PanelStyle.inspectFont(ofSize: 12 * k) }
        sourceCaption.frame = r(left, previewTop + previewHeight + 10, cw, 15)
        resultCaption.frame = r(left + cw + 24, previewTop + previewHeight + 10, cw, 15)

        let timelineWidth = mode == .stopped ? dw : cw
        timelineTitle.font = PanelStyle.inspectFont(ofSize: 12 * k)
        timelineTitle.frame = r(left, sectionTop, 200, 15)
        for (index, row) in timelineRows.enumerated() {
            row.uiScale = k
            row.frame = r(left, sectionTop + 29 + CGFloat(index) * 30, timelineWidth, 16)
        }
        let dx = left + cw + 24
        detailsTitle.font = PanelStyle.inspectFont(ofSize: 12 * k)
        detailsTitle.frame = r(dx, sectionTop, 200, 15)
        for index in propertyKeys.indices {
            let y = sectionTop + 21 + CGFloat(index) * 35
            propertyKeys[index].font = PanelStyle.inspectFont(ofSize: 13 * k)
            propertyValues[index].font = PanelStyle.inspectFont(ofSize: 13 * k)
            propertyKeys[index].frame = r(dx, y + 9, 96, 16)
            propertyValues[index].frame = r(dx + 108, y + 9, cw - 108, 16)
            propertyDividers[index].frame = r(dx, y + 34, cw, hairline)
        }

        emptyState.uiScale = k
        emptyState.frame = NSRect(x: 341 * k, y: 44 * k, width: max(0, width - 341 * k), height: max(0, height - 44 * k))
        applyVisibility()
        clearButton.isEnabled = allRecords.contains { !$0.phase.isActive }
    }

    /// Which detail pieces this state shows; everything hides behind the empty state.
    private func applyVisibility() {
        let none = visibleRecords.isEmpty
        emptyState.isHidden = !none
        scroll.isHidden = none
        let stopped = mode == .stopped
        let header: [NSView] = [eyebrow, detailTitle, statusDot, statusLabel, statusDetail,
                                sourcePreview, resultPreview, sourceCaption, resultCaption, timelineTitle] + (timelineRows as [NSView])
        header.forEach { $0.isHidden = none }
        percentLabel.isHidden = none || percentLabel.string.isEmpty
        progressTrack.isHidden = none || stopped || !(shownRecord?.phase.isActive ?? false)
        outcomeBlock.isHidden = none || !stopped
        detailsTitle.isHidden = none || stopped
        for index in propertyKeys.indices {
            let hidden = none || stopped || propertyKeys[index].string.isEmpty
            propertyKeys[index].isHidden = hidden
            propertyValues[index].isHidden = hidden
            propertyDividers[index].isHidden = hidden
        }
    }

    func refresh() {
        allRecords = WidgetTaskManager.shared.records
        let records = allRecords
        let query = searchBox.query
        let filtered: [WidgetTaskRecord]
        switch filters.selectedSegment {
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
        filters.counts = [records.count,
                          records.filter { $0.phase.isActive }.count,
                          records.filter { $0.phase == .completed }.count,
                          records.filter { $0.phase.isFailure }.count]
        let running = WidgetTaskManager.shared.activeCount
        countLabel.string = records.isEmpty
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

    /// The detail explains itself when the list has nothing to show.
    private func updateEmptyStates() {
        guard visibleRecords.isEmpty else { return }
        let noTasks = allRecords.isEmpty
        emptyState.configure(icon: "TaskIconTasks",
                             heading: noTasks ? "No tasks yet".localized : "No matching tasks".localized,
                             detail: noTasks ? "Run a Widget on an image and it will show up here.".localized
                                             : "Try a different search or filter.".localized)
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

    /// The record the detail column currently shows.
    private var shownRecord: WidgetTaskRecord?

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

    private static func statusColor(_ record: WidgetTaskRecord) -> NSColor {
        record.phase.isActive ? PanelStyle.info
            : (record.phase.isFailure ? PanelStyle.failure
               : (record.phase == .cancelled ? PanelStyle.textTertiary : PanelStyle.success))
    }

    /// Credits read moss once a refund is recorded, ai while billing is still settling.
    private static func creditColor(_ record: WidgetTaskRecord) -> NSColor {
        if record.settlementOutcome != nil { return PanelStyle.info }
        return (record.refundedCredits ?? 0) > 0 ? PanelStyle.success : PanelStyle.textPrimary
    }

    private func updateDetail(_ record: WidgetTaskRecord?) {
        shownRecord = record
        guard let record else {
            mode = .live
            eyebrow.string = ""
            detailTitle.string = "Select a task".localized
            detailTitle.toolTip = nil
            statusLabel.string = ""
            statusDetail.string = ""
            percentLabel.string = ""
            statusDot.layer?.backgroundColor = NSColor.clear.cgColor
            progressValue = 0
            sourceCaption.string = ""
            resultCaption.string = ""
            sourcePreview.configure(url: nil, waiting: false)
            resultPreview.configure(url: nil, waiting: true, displaysText: false)
            timelineRows.enumerated().forEach { $0.element.configure(state: $0.offset == 0 ? .pending : .disabled, time: "") }
            for index in propertyKeys.indices {
                propertyKeys[index].string = ""
                propertyValues[index].string = "—"
            }
            setActions([])
            return
        }
        let failed = record.phase.isFailure
        let stopped = failed || record.phase == .cancelled
        mode = stopped ? .stopped : .live
        eyebrow.string = "\("Task".localized.uppercased())  \(record.id.uuidString.prefix(4).uppercased())"
        detailTitle.string = record.commandName
        detailTitle.toolTip = record.commandName
        statusDot.layer?.backgroundColor = PanelStyle.resolvedCG(Self.statusColor(record))
        let running = record.phase == .processing && record.progress > 0 && record.queueText == nil
        statusLabel.string = running ? "Running".localized : stateText(record)
        statusDetail.string = "·  \(record.widgetName)"
        percentLabel.string = record.phase.isActive && record.progress > 0 ? "\(record.progress)%" : ""
        progressValue = record.phase.isActive ? CGFloat(min(100, max(0, record.progress))) / 100 : 0
        sourceCaption.string = String(format: "Source · %@".localized, record.source?.lastPathComponent ?? "Media".localized)
        sourcePreview.configure(url: record.source, waiting: false)
        let failureReason = record.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = (failureReason?.isEmpty == false ? failureReason : nil)
            ?? "The task stopped without reporting a reason.".localized
        let outcome = (record.phase == .cancelled ? "Task cancelled" : "Task failed").localized
        resultCaption.string = record.phase == .completed && record.output != nil
            ? "\("Result".localized) · \(record.output?.lastPathComponent ?? "")" : "Result".localized
        if record.phase.isActive {
            resultPreview.showRunning(detail: (record.queueWaitSeconds ?? 0) >= 120 && record.queuePosition != nil
                ? "No worker has claimed this task yet. You can cancel; any deducted credits will be refunded.".localized
                : record.queueText ?? record.widgetName)
        } else if stopped {
            resultPreview.showFailure(title: "No result".localized, reason: outcome)
        } else if resultPreview.isShowingRunning {
            // The chip says "Done ✓" for 1.6 s, then the result.
            let elapsed = Self.durationText(record.updatedAt.timeIntervalSince(record.createdAt))
            resultPreview.finishRunning(detail: "\(record.widgetName) · \(elapsed)") { [weak self] in
                guard let self, let current = self.selected, current.id == record.id else { return }
                self.showResult(current)
            }
        } else {
            showResult(record)
        }

        // Timeline: finished steps are quiet, the live step ai, a failed step shu.
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

        // Details follow the state: live tasks poll, finished ones report a
        // duration and a file, stopped ones say what failed, why, and the credits.
        // Billing is part of every task state, including failure and cancellation.
        let credits = ("Credits", record.billingStatusText ?? "—", Self.creditColor(record))
        let pricing: (String, String, NSColor)? = record.quote.flatMap { $0.mode == "duration" ? ("Pricing", $0.detail, PanelStyle.textPrimary) : nil }
        if stopped {
            var rows: [(String, String, NSColor)] = [
                (record.phase == .cancelled ? "What happened" : "What failed",
                 "\(outcome) · \(String(format: "Stopped at %d%%".localized, record.progress))", PanelStyle.textPrimary),
                ("Reason", record.phase == .cancelled ? "You cancelled this task.".localized : reasonText, PanelStyle.textPrimary)
            ]
            if let pricing { rows.append(pricing) }
            rows.append(credits)
            outcomeBlock.configure(rows: rows.map { ($0.0.localized, $0.1, $0.2) },
                                   rule: failed ? PanelStyle.failure : PanelStyle.textTertiary)
            for index in propertyKeys.indices { propertyKeys[index].string = "" }
        } else {
            var rows: [(String, String, NSColor)]
            if record.phase.isActive {
                rows = [("Widget", record.widgetName, PanelStyle.textPrimary), ("Input", record.source?.lastPathComponent ?? "Media", PanelStyle.textPrimary),
                        credits, ("Progress", "\(record.progress)%", PanelStyle.textPrimary),
                        ("Polling", "2 seconds".localized, PanelStyle.textPrimary)]
            } else {
                rows = [("Widget", record.widgetName, PanelStyle.textPrimary), ("Input", record.source?.lastPathComponent ?? "Media", PanelStyle.textPrimary),
                        credits,
                        ("Duration", Self.durationText(record.updatedAt.timeIntervalSince(record.createdAt)), PanelStyle.textPrimary),
                        ("Result", record.output?.lastPathComponent ?? "—", PanelStyle.textPrimary)]
            }
            if let pricing { rows[3] = pricing }
            for index in propertyKeys.indices {
                guard index < rows.count else { propertyKeys[index].string = ""; continue }
                propertyKeys[index].string = rows[index].0.localized
                propertyValues[index].string = rows[index].1
                propertyValues[index].color = rows[index].2
                propertyValues[index].toolTip = rows[index].1
            }
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
        case .uploading: return (record.isPreparing ? "Preparing" : "Uploading").localized
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
                       !GlanceAPIHosts.contains(url.host ?? "") {
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

    private func retrySelected() { if let id = selected?.id { WidgetTaskManager.shared.retry(id, over: self) } }
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

// MARK: - Shizuka tokens and text

private enum TaskTone {
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let lineStrong = PanelStyle.inspectLine
    static let text4 = PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4)
    static let selectedRow = PanelStyle.themed(PanelStyle.Sumi.ink3, PanelStyle.Washi.ink3)
    static let pane = PanelStyle.overlay
}

private enum TaskType {
    static func attributed(_ string: String, font: NSFont, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    static func width(_ string: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(string, font: font, color: .black, kern: kern))
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    /// Breaks `text` into at most `maxLines` lines of `width`; the last one truncates with "…".
    static func lines(_ text: NSAttributedString, width: CGFloat, maxLines: Int) -> [CTLine] {
        guard text.length > 0, width > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: text.attributes(at: 0, effectiveRange: nil)))
        var lines: [CTLine] = []
        var start = 0
        while start < text.length && lines.count < max(1, maxLines) {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            if lines.count == max(1, maxLines) - 1 && start + count < text.length {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: text.length - start))
                lines.append(CTLineCreateTruncatedLine(rest, Double(width), .end, token) ?? rest)
                break
            }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            lines.append(width < CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - 0.5
                         ? (CTLineCreateTruncatedLine(line, Double(width), .end, token) ?? line) : line)
            start += count
        }
        return lines
    }

    /// Draws `line` in a flipped view with its baseline at `baseline` (top-origin).
    static func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Top-origin baseline that centres the font's line box in a frame.
    static func baseline(top: CGFloat, height: CGFloat, font: NSFont) -> CGFloat {
        top + (height - (font.ascender - font.descender)) / 2 + font.ascender
    }

    static func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
    }
}

/// A text frame that stays exactly where the board puts it: the line box is
/// centred in the frame (or stacked at `lineHeight`), never sized by the text.
private final class TaskText: NSView {
    var string = "" { didSet { if string != oldValue { setAccessibilityLabel(string); needsDisplay = true } } }
    var font = PanelStyle.inspectFont(ofSize: 13) { didSet { needsDisplay = true } }
    var color = PanelStyle.textPrimary { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var kern: CGFloat = 0 { didSet { needsDisplay = true } }
    var maxLines = 1 { didSet { needsDisplay = true } }
    /// Line pitch for multi-line text; nil centres one line in the frame.
    var lineHeight: CGFloat? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Labels only take the mouse when they carry a tooltip.
    override func hitTest(_ point: NSPoint) -> NSView? { toolTip == nil ? nil : super.hitTest(point) }

    var textWidth: CGFloat { TaskType.width(string, font: font, kern: kern) }

    func lineCount(forWidth width: CGFloat) -> Int {
        max(1, TaskType.lines(TaskType.attributed(string, font: font, color: color, kern: kern),
                              width: width, maxLines: maxLines).count)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !string.isEmpty else { return }
        let lines = TaskType.lines(TaskType.attributed(string, font: font, color: color, kern: kern),
                                   width: bounds.width, maxLines: maxLines)
        let pitch = lineHeight ?? bounds.height
        for (index, line) in lines.enumerated() {
            let width = TaskType.lineWidth(line)
            let x: CGFloat
            switch alignment {
            case .right: x = bounds.width - width
            case .center: x = (bounds.width - width) / 2
            default: x = 0
            }
            TaskType.draw(line, x: x, baseline: TaskType.baseline(top: CGFloat(index) * pitch, height: pitch, font: font))
        }
    }
}

/// Drag surface for the 44 pt title bar; double-click zooms.
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

// MARK: - List

/// Board FileRow: 40 pt thumbnail, name over metadata, state on the right.
private final class TaskCenterCellView: NSTableCellView {
    /// Thumbnail tile: aspect-fill layer contents.
    private let preview = NSView()
    private let placeholder = NSImageView()
    private let titleLabel = TaskText()
    private let detailLabel = TaskText()
    private let stateLabel = TaskText()
    private let stateEllipsis = TaskRunningEllipsis()
    private let runningScrim = NSView()
    private let runningPeeker = PeekerView()
    /// Which thumbnail request this cell is waiting for; a reused cell ignores
    /// results that arrive for the record it used to show.
    private var thumbnailToken = UUID()
    /// 40 pt tile at 2× Retina, with headroom for a scaled-up window.
    private static let thumbnailPixelSize = 112
    private var isSelectedRow = false
    private var isHovering = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.masksToBounds = true
        preview.wantsLayer = true
        preview.layer?.cornerRadius = PanelStyle.Radius.thumb
        preview.layer?.masksToBounds = true
        preview.layer?.contentsGravity = .resizeAspectFill
        preview.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.contentTintColor = PanelStyle.textTertiary
        preview.addSubview(placeholder)
        titleLabel.color = PanelStyle.textPrimary
        detailLabel.color = PanelStyle.textTertiary
        stateLabel.alignment = .right
        stateEllipsis.isHidden = true
        [preview, titleLabel, detailLabel, stateLabel, stateEllipsis].forEach(addSubview)
        runningScrim.wantsLayer = true
        runningScrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        runningScrim.isHidden = true
        runningPeeker.isHidden = true
        addSubview(runningScrim)
        addSubview(runningPeeker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(record: WidgetTaskRecord, selected: Bool) {
        isSelectedRow = selected
        applyBackground()
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
        titleLabel.string = record.commandName
        detailLabel.string = "\(record.billingStatusText ?? record.source?.lastPathComponent ?? "Media")  ·  \(relativeDate(record.createdAt))"
        let color: NSColor = record.phase.isActive ? PanelStyle.info : (record.phase.isFailure ? PanelStyle.failure : (record.phase == .cancelled ? PanelStyle.textTertiary : PanelStyle.success))
        runningScrim.isHidden = !record.phase.isActive
        runningPeeker.isHidden = !record.phase.isActive
        let state = taskState(record)
        stateEllipsis.isHidden = !record.phase.isActive || record.queueText != nil
        stateLabel.string = stateEllipsis.isHidden ? state : state.replacingOccurrences(of: "…", with: "")
        stateLabel.color = color
        setAccessibilityLabel("\(record.commandName), \(state)")
        needsLayout = true
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
        // Board FileRow 312 × 56: thumb (12, 8) 40, name (64, 11.5) 13 pt,
        // metadata (64, 30.5) mono 11, state right-aligned 12 pt at y 20.5.
        let k = bounds.height / 56
        let width = bounds.width / k
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * k, y: y * k, width: max(0, w) * k, height: h * k)
        }
        layer?.cornerRadius = PanelStyle.Radius.control * k
        preview.layer?.cornerRadius = PanelStyle.Radius.thumb * k
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * k)
        detailLabel.font = PanelStyle.monoFont(ofSize: 11 * k)
        stateLabel.font = PanelStyle.inspectFont(ofSize: 12 * k)
        preview.frame = r(12, 8, 40, 40)
        placeholder.frame = preview.bounds.insetBy(dx: 11 * k, dy: 11 * k)
        let ellipsisRoom: CGFloat = stateEllipsis.isHidden ? 0 : 13
        let stateWidth = min(stateLabel.textWidth / k, 96)
        let stateRight = width - 12 - ellipsisRoom
        stateLabel.frame = r(stateRight - stateWidth, 20.5, stateWidth, 15)
        // Text stops 12 pt before the state so long names truncate instead of running under it.
        let textWidth = stateRight - stateWidth - 12 - 64
        titleLabel.frame = r(64, 11.5, textWidth, 16)
        detailLabel.frame = r(64, 30.5, textWidth, 14)
        // The ellipsis sits on the state's baseline.
        let baseline = TaskType.baseline(top: 20.5 * k, height: 15 * k, font: stateLabel.font)
        stateEllipsis.frame = NSRect(x: (stateRight + 3) * k, y: baseline - 2 * k, width: 10 * k, height: 2 * k)
        runningScrim.frame = preview.frame
        runningScrim.layer?.cornerRadius = PanelStyle.Radius.thumb * k
        runningPeeker.frame = r(20, 16, 24, 24)
    }

    private func applyBackground() {
        // Selection is a quiet ink step; hover is lighter, never as strong.
        let color = isSelectedRow ? TaskTone.selectedRow : (isHovering ? PanelStyle.rowHover : NSColor.clear)
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
        // The list names the state; the percentage lives in the detail.
        switch record.phase {
        case .processing: return "Running…".localized
        case .uploading: return (record.isPreparing ? "Preparing" : "Uploading").localized
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
        // Selection is rendered by TaskCenterCellView. Never draw AppKit blue.
    }

    override var isEmphasized: Bool {
        get { false }
        set { }
    }

    override func drawSeparator(in dirtyRect: NSRect) { }
}

/// Board filter tabs: label 12 pt with a mono count; the active tab is ink
/// with a 1 pt underline.
private final class TaskFilterTabs: NSView {
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

    private var labelFont: NSFont { PanelStyle.inspectFont(ofSize: 12 * uiScale) }
    private var countFont: NSFont { PanelStyle.monoFont(ofSize: 11 * uiScale) }

    private func tabRects() -> [CGRect] {
        let s = uiScale
        var x: CGFloat = 12 * s
        return titles.indices.map { index in
            let w = TaskType.width(titles[index], font: labelFont) + 5 * s + TaskType.width(String(counts[index]), font: countFont)
            defer { x += w + 18 * s }
            return CGRect(x: x, y: 0, width: w, height: bounds.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        for (index, rect) in tabRects().enumerated() {
            let active = index == selectedSegment
            // Board: the active tab's label sits at y 3 above its underline at 24; the others at 6.5.
            let top = (active ? 3 : 6.5) * s
            let baseline = TaskType.baseline(top: top, height: 15 * s, font: labelFont)
            let title = CTLineCreateWithAttributedString(TaskType.attributed(titles[index], font: labelFont,
                                                                             color: active ? PanelStyle.textPrimary : PanelStyle.textTertiary))
            TaskType.draw(title, x: rect.minX, baseline: baseline)
            let count = CTLineCreateWithAttributedString(TaskType.attributed(String(counts[index]), font: countFont,
                                                                             color: active ? PanelStyle.textTertiary : TaskTone.text4))
            TaskType.draw(count, x: rect.minX + TaskType.width(titles[index], font: labelFont) + 5 * s, baseline: baseline)
            if active {
                PanelStyle.textPrimary.setFill()
                CGRect(x: rect.minX, y: 24 * s, width: rect.width, height: max(1, s)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = tabRects().firstIndex(where: { $0.contains(point) }) { onSelect?(index) }
    }
}

/// 28 pt quiet icon button for list actions (refresh, clear finished).
private final class TaskIconButton: NSView {
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    private let icon: String
    private let danger: Bool
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String, danger: Bool = false, onClick: @escaping () -> Void) {
        self.icon = icon; self.danger = danger; self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
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
    override func accessibilityPerformPress() -> Bool { if isEnabled { onClick() }; return isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        if hovering && isEnabled {
            PanelStyle.controlFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: PanelStyle.Radius.control * s, yRadius: PanelStyle.Radius.control * s).fill()
        }
        let tint = danger && hovering && isEnabled ? PanelStyle.failure : PanelStyle.textSecondary
        HistoryStyle.drawIcon(icon, color: tint, in: CGRect(x: 6 * s, y: 6 * s, width: 16 * s, height: 16 * s))
    }
}

/// 28 pt search field under the filters; Esc clears it, then leaves it.
private final class TaskQuietSearchField: NSView, NSTextFieldDelegate {
    var uiScale: CGFloat = 1 {
        didSet { guard uiScale != oldValue else { return }; needsLayout = true; needsDisplay = true; updatePlaceholder() }
    }
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
        field.textColor = PanelStyle.textPrimary
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.onFocusChange = { [weak self] in self?.focused = $0 }
        field.setAccessibilityLabel("Search tasks".localized)
        addSubview(field)
        updatePlaceholder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updatePlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: "Search tasks".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 12 * uiScale), .foregroundColor: PanelStyle.textTertiary])
    }

    private var clearRect: CGRect {
        let s = uiScale
        return CGRect(x: bounds.width - 6 * s - 16 * s, y: (bounds.height - 16 * s) / 2, width: 16 * s, height: 16 * s)
    }

    override func layout() {
        super.layout()
        let s = uiScale
        field.font = PanelStyle.inspectFont(ofSize: 12 * s)
        let fieldHeight = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: 28 * s, y: (bounds.height - fieldHeight) / 2, width: max(0, bounds.width - 28 * s - 26 * s), height: fieldHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: PanelStyle.Radius.control * s, yRadius: PanelStyle.Radius.control * s)
        PanelStyle.controlFill.setFill(); path.fill()
        if focused {
            TaskTone.lineStrong.setStroke(); path.lineWidth = 1; path.stroke()
        }
        HistoryStyle.drawIcon("HistorySearch", color: focused ? PanelStyle.textSecondary : PanelStyle.textTertiary,
                              in: CGRect(x: 8 * s, y: (bounds.height - 14 * s) / 2, width: 14 * s, height: 14 * s))
        if !field.stringValue.isEmpty {
            HistoryStyle.drawIcon("HistoryClose", color: PanelStyle.textTertiary, in: clearRect.insetBy(dx: 2 * s, dy: 2 * s))
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

// MARK: - Detail

/// Board button: 32 pt, radius 6, 13 pt medium label centred on its ink.
/// Ghost (hairline), primary (ink fill), or icon only (remove, shu glyph).
private final class TaskActionButton: NSView {
    enum Style { case ghost, primary, icon }
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true; needsLayout = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    private let label: String?
    private let icon: String?
    private let style: Style
    private let onClick: () -> Void
    private let title = PanelCenteredTextView()
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Width on the board: 16 pt either side of the label, or a 32 pt square.
    var designWidth: CGFloat {
        guard let label else { return 32 }
        return 16 + TaskType.width(label, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium)) + 16
    }

    init(label: String, style: Style, onClick: @escaping () -> Void) {
        self.label = label; self.icon = nil; self.style = style; self.onClick = onClick
        super.init(frame: .zero)
        title.string = label
        title.textColor = style == .primary ? PanelStyle.accentInk : PanelStyle.textPrimary
        addSubview(title)
        configureAccessibility(label)
    }

    init(icon: String, tooltip: String, onClick: @escaping () -> Void) {
        self.label = nil; self.icon = icon; self.style = .icon; self.onClick = onClick
        super.init(frame: .zero)
        configureAccessibility(tooltip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureAccessibility(_ text: String) {
        toolTip = text
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)
    }

    override func layout() {
        super.layout()
        title.font = PanelStyle.inspectFont(ofSize: 13 * uiScale, weight: .medium)
        title.frame = bounds.insetBy(dx: 12 * uiScale, dy: 0)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick() } }
    override func accessibilityPerformPress() -> Bool { if isEnabled { onClick() }; return isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let radius = PanelStyle.Radius.control * s
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        switch style {
        case .primary:
            (hovering && isEnabled ? PanelStyle.accentHover : PanelStyle.warmCue).setFill(); path.fill()
        case .ghost, .icon:
            if hovering && isEnabled { PanelStyle.controlFill.setFill(); path.fill() }
            TaskTone.lineStrong.setStroke(); path.stroke()
        }
        if let icon {
            HistoryStyle.drawIcon(icon, color: PanelStyle.failure,
                                  in: CGRect(x: (bounds.width - 16 * s) / 2, y: (bounds.height - 16 * s) / 2, width: 16 * s, height: 16 * s))
        }
    }
}

/// Board 13 "what happened": a quiet panel with a 2 pt rule on the left
/// (shu for a failure), key 120 pt wide, value from x 136.
private final class TaskOutcomeBlock: NSView {
    var uiScale: CGFloat = 1 { didSet { needsLayout = true } }
    private var keys: [TaskText] = []
    private var values: [TaskText] = []
    private let rule = NSView()
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(TaskTone.pane)
        layer?.masksToBounds = true
        rule.wantsLayer = true
        addSubview(rule)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(rows: [(String, String, NSColor)], rule color: NSColor) {
        rule.layer?.backgroundColor = PanelStyle.resolvedCG(color)
        while keys.count < rows.count {
            let key = TaskText(), value = TaskText()
            key.color = PanelStyle.textTertiary
            value.maxLines = 3
            addSubview(key); addSubview(value)
            keys.append(key); values.append(value)
        }
        for index in keys.indices {
            let shown = index < rows.count
            keys[index].isHidden = !shown
            values[index].isHidden = !shown
            guard shown else { continue }
            keys[index].string = rows[index].0
            values[index].string = rows[index].1
            values[index].color = rows[index].2
            values[index].toolTip = rows[index].1
        }
        needsLayout = true
    }

    private var shownCount: Int { keys.filter { !$0.isHidden }.count }

    private func lineCounts(width: CGFloat) -> [Int] {
        let s = uiScale
        let valueWidth = max(1, width - (22 + 136 + 22) * s)
        return (0..<shownCount).map { index in
            values[index].font = PanelStyle.inspectFont(ofSize: 13 * s)
            return values[index].lineCount(forWidth: valueWidth)
        }
    }

    /// Height for `width` points: 18 pt padding, 34 pt per one-line row, 20 pt per extra line.
    func preferredHeight(width: CGFloat) -> CGFloat {
        let s = uiScale
        return (36 + lineCounts(width: width).reduce(0) { $0 + 14 + CGFloat($1) * 20 }) * s
    }

    override func layout() {
        super.layout()
        let s = uiScale
        layer?.cornerRadius = PanelStyle.Radius.control * s
        rule.frame = CGRect(x: 0, y: 0, width: 2 * s, height: bounds.height)
        var y = 18 * s
        for (index, lines) in lineCounts(width: bounds.width).enumerated() {
            keys[index].font = PanelStyle.inspectFont(ofSize: 13 * s)
            keys[index].frame = CGRect(x: 22 * s, y: y + 7 * s, width: 120 * s, height: 16 * s)
            values[index].lineHeight = 20 * s
            values[index].frame = CGRect(x: (22 + 136) * s, y: y + 7 * s,
                                         width: max(0, bounds.width - (22 + 136 + 22) * s), height: CGFloat(lines) * 20 * s)
            y += (14 + CGFloat(lines) * 20) * s
        }
    }
}

/// "47 · Empty states" card content: icon, Mincho title, one sentence.
private final class TaskEmptyStateView: NSView {
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    private var icon = "TaskIconTasks"
    private var heading = ""
    private var detail = ""
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(icon: String, heading: String, detail: String) {
        self.icon = icon; self.heading = heading; self.detail = detail
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(heading). \(detail)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        // Board group: icon 24, 10 pt, title 28 pt line, 10 pt, sentence 254 wide at 19 pt lines.
        let hintFont = PanelStyle.inspectFont(ofSize: 12 * s)
        let hint = TaskType.lines(TaskType.attributed(detail, font: hintFont, color: PanelStyle.textTertiary),
                                  width: 254 * s, maxLines: 3)
        let groupHeight = (24 + 10 + 28 + 10) * s + CGFloat(hint.count) * 19 * s
        let top = max(24 * s, (bounds.height - groupHeight) / 2 - 24 * s)
        HistoryStyle.drawIcon(icon, color: PanelStyle.textTertiary,
                              in: CGRect(x: (bounds.width - 24 * s) / 2, y: top, width: 24 * s, height: 24 * s))
        let titleFont = PanelStyle.titleFont(ofSize: 22 * s)
        let title = TaskType.lines(TaskType.attributed(heading, font: titleFont, color: PanelStyle.textPrimary),
                                   width: bounds.width - 56 * s, maxLines: 1)
        if let line = title.first {
            TaskType.draw(line, x: (bounds.width - TaskType.lineWidth(line)) / 2,
                          baseline: TaskType.baseline(top: top + 34 * s, height: 28 * s, font: titleFont))
        }
        for (index, line) in hint.enumerated() {
            TaskType.draw(line, x: (bounds.width - TaskType.lineWidth(line)) / 2,
                          baseline: TaskType.baseline(top: top + 72 * s + CGFloat(index) * 19 * s, height: 19 * s, font: hintFont))
        }
    }
}

/// Source or result pane: the image on a quiet ink pane; a running task shows
/// the peeker chip, a stopped one a dashed frame with "No result".
private final class TaskPreviewView: NSView {
    var uiScale: CGFloat = 1 { didSet { needsLayout = true } }
    private let imageView = NSImageView()
    private let waitingLabel = TaskText()
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private var loadGeneration = UUID()
    private let runningChip = TaskRunningChip()
    private let failureTitle = TaskText()
    private let failureReason = TaskText()
    private let dashedFrame = CAShapeLayer()
    /// True while the running chip (working or "Done") is on screen.
    var isShowingRunning: Bool { !runningChip.isHidden }
    private var doneWork: DispatchWorkItem?
    override var isFlipped: Bool { true }

    init(title: String) {
        super.init(frame: .zero)
        waitingLabel.string = title
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        dashedFrame.fillColor = nil
        dashedFrame.strokeColor = PanelStyle.resolvedCG(TaskTone.lineStrong)
        dashedFrame.lineWidth = 1
        dashedFrame.isHidden = true
        layer?.addSublayer(dashedFrame)
        setSolid(true)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: textScroll)
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
        waitingLabel.color = PanelStyle.textTertiary
        waitingLabel.alignment = .center
        addSubview(waitingLabel)
        runningChip.isHidden = true
        addSubview(runningChip)
        failureTitle.color = PanelStyle.textPrimary
        failureTitle.alignment = .center
        failureReason.color = PanelStyle.textTertiary
        failureReason.alignment = .center
        failureReason.maxLines = 2
        [failureTitle, failureReason].forEach { $0.isHidden = true; addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Solid pane for images and progress; a dashed empty frame when nothing was produced.
    private func setSolid(_ solid: Bool) {
        layer?.backgroundColor = solid ? PanelStyle.resolvedCG(TaskTone.pane) : NSColor.clear.cgColor
        layer?.borderColor = solid ? PanelStyle.resolvedCG(TaskTone.line) : NSColor.clear.cgColor
        dashedFrame.isHidden = solid
    }

    private func resetModes() {
        doneWork?.cancel()
        doneWork = nil
        runningChip.isHidden = true
        failureTitle.isHidden = true
        failureReason.isHidden = true
        setSolid(true)
    }

    /// A running task: the peeker chip instead of a "waiting" label.
    func showRunning(detail: String) {
        if isShowingRunning && !runningChip.isDone {
            runningChip.showRunning(detail: detail)
            return
        }
        loadGeneration = UUID()
        imageView.image = nil
        textScroll.isHidden = true
        waitingLabel.isHidden = true
        resetModes()
        runningChip.showRunning(detail: detail)
        runningChip.isHidden = false
        needsLayout = true
    }

    /// The task finished while the chip was up: show "Done ✓" with `detail`
    /// ("Remove Background · 12.4 s"), hold 1.6 s, then `completion`.
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

    /// A failed or cancelled task: an empty dashed frame, the outcome under the title.
    func showFailure(title: String, reason: String) {
        loadGeneration = UUID()
        imageView.image = nil
        textScroll.isHidden = true
        waitingLabel.isHidden = true
        resetModes()
        setSolid(false)
        failureTitle.string = title
        failureReason.string = reason
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
        waitingLabel.string = waiting ? "Waiting for result".localized : "Preview unavailable".localized
        guard let url else { return }
        if displaysText {
            waitingLabel.string = "Loading text…".localized
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
                        self.waitingLabel.string = "Unable to read text result".localized
                    }
                }
            }
            return
        }
        guard url.isFileURL else { return }
        waitingLabel.string = "Loading preview…".localized
        // The pane is at most a few hundred points wide; 1600 px keeps Retina
        // sharp without decoding the full-size result on the main thread.
        MediaThumbnailCache.shared.load(url, maxPixelSize: 1600) { [weak self] image in
            guard let self, self.loadGeneration == generation else { return }
            if let image {
                self.imageView.image = image
                self.waitingLabel.isHidden = true
            } else {
                self.waitingLabel.string = waiting ? "Waiting for result".localized : "Preview unavailable".localized
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
        let s = uiScale
        let radius = PanelStyle.Radius.thumb * s
        layer?.cornerRadius = radius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dashedFrame.frame = bounds
        let dashRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        dashedFrame.path = dashRect.width > radius * 2 && dashRect.height > radius * 2
            ? CGPath(roundedRect: dashRect, cornerWidth: radius, cornerHeight: radius, transform: nil) : nil
        dashedFrame.lineDashPattern = [NSNumber(value: Double(3 * s)), NSNumber(value: Double(3 * s))]
        CATransaction.commit()
        imageView.frame = bounds
        textScroll.frame = bounds.insetBy(dx: 12 * s, dy: 12 * s)
        // Board 04 "Generating…" sits on the pane's middle; the chip replaces it.
        waitingLabel.font = PanelStyle.inspectFont(ofSize: 12 * s)
        waitingLabel.frame = CGRect(x: 20 * s, y: bounds.midY - 8 * s, width: max(0, bounds.width - 40 * s), height: 16 * s)
        let chipWidth = min(360 * s, bounds.width - 24 * s)
        let chipHeight = chipWidth * 76 / 360
        runningChip.frame = CGRect(x: (bounds.width - chipWidth) / 2, y: (bounds.height - chipHeight) / 2, width: chipWidth, height: chipHeight)
        // Board 13: "No result" 13 pt at 102 of 241, the line under it 12 pt at 124.
        failureTitle.font = PanelStyle.inspectFont(ofSize: 13 * s)
        failureReason.font = PanelStyle.inspectFont(ofSize: 12 * s)
        failureReason.lineHeight = 15 * s
        failureTitle.frame = CGRect(x: 24 * s, y: bounds.midY - 18.5 * s, width: max(0, bounds.width - 48 * s), height: 16 * s)
        failureReason.frame = CGRect(x: 24 * s, y: bounds.midY + 3.5 * s, width: max(0, bounds.width - 48 * s), height: 30 * s)
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

/// Board timeline event: 6 pt dot, step 13 pt at x 18 with its note after it,
/// time in mono on the right.
private final class TaskTimelineRow: NSView {
    enum State { case complete, current, pending, disabled, failed }
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    private let title: String
    private let defaultDetail: String
    private var detail: String
    private var time = ""
    private var state: State = .pending
    override var isFlipped: Bool { true }

    init(title: String, detail: String) {
        self.title = title
        defaultDetail = detail
        self.detail = detail
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `detail` replaces the default description for this state (nil restores it).
    func configure(state: State, time: String, detail: String? = nil) {
        self.state = state
        self.time = time
        self.detail = detail ?? defaultDetail
        toolTip = self.detail
        setAccessibilityLabel([title, self.detail, time].filter { !$0.isEmpty }.joined(separator: ", "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        let dot = CGRect(x: 0, y: 5 * s, width: 6 * s, height: 6 * s)
        switch state {
        case .pending:
            TaskTone.text4.setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 1; ring.stroke()
        case .complete: PanelStyle.textTertiary.setFill(); NSBezierPath(ovalIn: dot).fill()
        case .current: PanelStyle.info.setFill(); NSBezierPath(ovalIn: dot).fill()
        case .failed: PanelStyle.failure.setFill(); NSBezierPath(ovalIn: dot).fill()
        case .disabled: TaskTone.text4.setFill(); NSBezierPath(ovalIn: dot).fill()
        }
        let quiet = state == .pending || state == .disabled
        let titleFont = PanelStyle.inspectFont(ofSize: 13 * s)
        let noteFont = PanelStyle.inspectFont(ofSize: 12 * s)
        let timeFont = PanelStyle.monoFont(ofSize: 11 * s)
        let baseline = TaskType.baseline(top: 0, height: 16 * s, font: titleFont)
        let timeWidth = min(TaskType.width(time, font: timeFont), 96 * s)
        let textRight = bounds.width - timeWidth - 12 * s
        let titleLine = TaskType.lines(TaskType.attributed(title, font: titleFont, color: quiet ? PanelStyle.textTertiary : PanelStyle.textPrimary),
                                       width: max(1, textRight - 18 * s), maxLines: 1)
        var x = 18 * s
        if let line = titleLine.first {
            TaskType.draw(line, x: x, baseline: baseline)
            x += TaskType.lineWidth(line) + 8 * s
        }
        if !detail.isEmpty, textRight - x > 24 * s,
           let line = TaskType.lines(TaskType.attributed("·  \(detail)", font: noteFont, color: PanelStyle.textTertiary),
                                     width: textRight - x, maxLines: 1).first {
            TaskType.draw(line, x: x, baseline: baseline)
        }
        if !time.isEmpty, let line = TaskType.lines(TaskType.attributed(time, font: timeFont, color: PanelStyle.textTertiary),
                                                    width: 96 * s, maxLines: 1).first {
            TaskType.draw(line, x: bounds.width - TaskType.lineWidth(line), baseline: baseline)
        }
    }
}

// MARK: - Redesign controls

/// 32 × 32 list-level icon button (refresh, clear finished, sort).
final class TaskGhostButton: NSView {
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    /// Toggled state (e.g. sort on): warm fill and accent icon, like an active filter pill.
    var isActive = false { didSet { needsDisplay = true } }
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
        if isActive {
            HistoryStyle.chipActiveFill.setFill(); path.fill()
            HistoryStyle.accent.withAlphaComponent(0.6).setStroke()
        } else {
            PanelStyle.contrast.withAlphaComponent(hovering ? 0.09 : 0.05).setFill(); path.fill()
            (danger ? PanelStyle.failure.withAlphaComponent(0.32) : PanelStyle.contrast.withAlphaComponent(0.08)).setStroke()
        }
        path.lineWidth = max(1, s); path.stroke()
        HistoryStyle.drawIcon(icon, color: isActive ? HistoryStyle.accent : tint, in: CGRect(x: 8 * s, y: 8 * s, width: 16 * s, height: 16 * s))
    }
}


/// 36 pt search field, always visible in the list header (Task Center and Widget Market).
final class TaskSearchBox: NSView, NSTextFieldDelegate {
    var uiScale: CGFloat = 1 { didSet { needsLayout = true; needsDisplay = true } }
    var onChange: (() -> Void)?
    var placeholder = "Search tasks".localized { didSet { updatePlaceholder() } }
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
            string: placeholder,
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
        (focused ? HistoryStyle.accent.withAlphaComponent(0.6) : PanelStyle.contrast.withAlphaComponent(0.10)).setStroke()
        path.lineWidth = max(1, s); path.stroke()
        HistoryStyle.drawIcon("HistorySearch", color: focused ? HistoryStyle.accent : HistoryStyle.muted,
                              in: CGRect(x: 12 * s, y: 9 * s, width: 18 * s, height: 18 * s))
        if !field.stringValue.isEmpty {
            PanelStyle.contrast.withAlphaComponent(0.10).setFill()
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

/// Filter pills with counts (All / Running / Done / Failed, Marketplace / Installed / Updates).
final class TaskPillBar: NSView {
    var onSelect: ((Int) -> Void)?
    var selectedSegment = 0 { didSet { needsDisplay = true } }
    var counts: [Int] = [0, 0, 0, 0] { didSet { needsDisplay = true } }
    var showsCounts = true { didSet { needsDisplay = true } }
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
            let countWidth = showsCounts ? 6 + HistoryStyle.width(String(counts[index]), size: 12) : 0
            let w = (24 + HistoryStyle.width(titles[index], size: 12, weight: active ? .semibold : .medium) + countWidth) * s
            defer { x += w + 8 * s }
            return CGRect(x: x, y: 0, width: w, height: 30 * s)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = uiScale
        for (index, rect) in pillRects().enumerated() {
            let active = index == selectedSegment
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 15 * s, yRadius: 15 * s)
            (active ? HistoryStyle.chipActiveFill : PanelStyle.contrast.withAlphaComponent(0.05)).setFill(); path.fill()
            (active ? HistoryStyle.accent.withAlphaComponent(0.6) : PanelStyle.contrast.withAlphaComponent(0.08)).setStroke()
            path.lineWidth = max(1, s); path.stroke()
            let weight: NSFont.Weight = active ? .semibold : .medium
            let labelW = HistoryStyle.width(titles[index], size: 12 * s, weight: weight)
            HistoryStyle.draw(titles[index], in: CGRect(x: rect.minX + 12 * s, y: 7 * s, width: labelW + 2, height: 16 * s), size: 12 * s,
                              weight: weight, color: active ? HistoryStyle.accent : HistoryStyle.secondary)
            if showsCounts {
                HistoryStyle.draw(String(counts[index]), in: CGRect(x: rect.minX + 12 * s + labelW + 6 * s, y: 7 * s, width: 50, height: 16 * s), size: 12 * s,
                                  color: active ? HistoryStyle.accent : HistoryStyle.muted)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = pillRects().firstIndex(where: { $0.contains(point) }) { onSelect?(index) }
    }
}
