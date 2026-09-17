import SwiftUI

private struct WidgetDefinition: Identifiable {
    let id: Int
    let name: String
    let summary: String
    let symbol: String
    let command: String
    let privacy: String
}

struct WidgetMarketPage: View {
    private let widgets = [
        WidgetDefinition(id: 0, name: "Super Resolution", summary: "Restore detail and upscale 2×", symbol: "arrow.up.left.and.arrow.down.right", command: "upscale-2x", privacy: "Selected media is uploaded for processing."),
        WidgetDefinition(id: 1, name: "Remove Background", summary: "Create a transparent subject cutout", symbol: "person.crop.rectangle", command: "remove-bg", privacy: "Selected media is uploaded, processed, then deleted."),
        WidgetDefinition(id: 2, name: "OCR Extract", summary: "Extract selectable text from images", symbol: "text.viewfinder", command: "ocr", privacy: "Runs locally when the language pack is available."),
        WidgetDefinition(id: 3, name: "Compress PNG", summary: "Reduce file size without visible loss", symbol: "archivebox", command: "compress-png", privacy: "Runs locally on this Mac.")
    ]

    @State private var selected = 1
    @State private var search = ""
    @State private var installed: Set<Int> = [0]
    @State private var loading = false
    @State private var installing = false

    var body: some View {
        PageChrome(title: "Widget Market", subtitle: "Preferred 980 × 650 · list 340 · detail flexible") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Widget Market")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    StatusPill(title: "4 available", tone: .neutral)
                    Spacer()
                    ToolButton(symbol: "arrow.clockwise", label: "Reload Widgets") { reload() }
                    ToolButton(symbol: "xmark", label: "Close Market")
                }
                .padding(.horizontal, 16)
                .frame(height: GlanceTheme.toolbarHeight)
                .background(GlanceTheme.surface)

                Divider().background(GlanceTheme.hairline)

                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        SearchField(text: $search, placeholder: "Search Widgets")

                        if loading {
                            VStack(spacing: 10) {
                                ForEach(0..<4, id: \.self) { _ in
                                    ShimmerBlock(height: 74, radius: 10)
                                }
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredWidgets) { widget in
                                        widgetRow(widget)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(width: 340, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(GlanceTheme.sidebar)

                    Rectangle().fill(GlanceTheme.hairline).frame(width: 1)

                    widgetDetail(widgets[selected])
                }
            }
        }
    }

    private var filteredWidgets: [WidgetDefinition] {
        guard !search.isEmpty else { return widgets }
        return widgets.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search) }
    }

    private func widgetRow(_ widget: WidgetDefinition) -> some View {
        Button {
            selected = widget.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: widget.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(selected == widget.id ? GlanceTheme.background : GlanceTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(selected == widget.id ? GlanceTheme.accent : GlanceTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(widget.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text(widget.summary)
                        .font(.system(size: 10))
                        .foregroundColor(GlanceTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if installed.contains(widget.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GlanceTheme.success)
                        .accessibilityLabel("Installed")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
            }
            .padding(11)
            .frame(height: 72)
            .background(selected == widget.id ? GlanceTheme.accentSoft : GlanceTheme.surface.opacity(0.74))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected == widget.id ? GlanceTheme.accent.opacity(0.38) : GlanceTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func widgetDetail(_ widget: WidgetDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: widget.symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(GlanceTheme.background)
                        .frame(width: 58, height: 58)
                        .background(GlanceTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(widget.name)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Text(widget.summary)
                            .font(.system(size: 12))
                            .foregroundColor(GlanceTheme.textSecondary)
                    }
                    Spacer()
                    StatusPill(title: installed.contains(widget.id) ? "Installed" : "Not installed",
                               tone: installed.contains(widget.id) ? .success : .neutral)
                }

                PanelSection("Widget information") {
                    KeyValueField(title: "Command", value: widget.command)
                    Divider().background(GlanceTheme.hairline)
                    KeyValueField(title: "Version", value: "1.4.2")
                    Divider().background(GlanceTheme.hairline)
                    KeyValueField(title: "Runtime", value: widget.id == 2 || widget.id == 3 ? "Local" : "Cloud")
                }

                PanelSection("Privacy") {
                    Text(widget.privacy)
                        .font(.system(size: 11))
                        .foregroundColor(GlanceTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PanelSection("Commands") {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(GlanceTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(widget.command)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(GlanceTheme.textPrimary)
                            Text("Single-command Widgets expose this action directly.")
                                .font(.system(size: 10))
                                .foregroundColor(GlanceTheme.textTertiary)
                        }
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    if installed.contains(widget.id) {
                        ActionButton(title: "Run Widget", symbol: "play.fill", primary: true)
                        ActionButton(title: "Uninstall", symbol: "trash", destructive: true, loading: installing) {
                            mutateInstallation(widget.id, install: false)
                        }
                    } else {
                        ActionButton(title: "Install Widget", symbol: "arrow.down.circle", primary: true, loading: installing) {
                            mutateInstallation(widget.id, install: true)
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.background)
    }

    private func reload() {
        loading = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeOut(duration: 0.18)) { loading = false }
        }
    }

    private func mutateInstallation(_ id: Int, install: Bool) {
        installing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                if install { installed.insert(id) } else { installed.remove(id) }
                installing = false
            }
        }
    }
}

private enum DemoTaskStatus: String {
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"

    var tone: StatusTone {
        switch self {
        case .processing: return .accent
        case .completed: return .success
        case .failed: return .failure
        }
    }
}

private struct DemoTask: Identifiable {
    let id: Int
    let widget: String
    let file: String
    let status: DemoTaskStatus
    let progress: Double
    let time: String
}

struct TaskCenterPage: View {
    private let tasks = [
        DemoTask(id: 0, widget: "Remove Background", file: "selected-image.jpg", status: .processing, progress: 0.64, time: "Started 12 seconds ago"),
        DemoTask(id: 1, widget: "Super Resolution", file: "landscape.jpg", status: .completed, progress: 1, time: "Today, 14:24"),
        DemoTask(id: 2, widget: "OCR Extract", file: "invoice-scan.png", status: .failed, progress: 0.28, time: "Today, 14:19")
    ]

    @State private var filter = 0
    @State private var selected = 0

    var body: some View {
        PageChrome(title: "Task Center", subtitle: "Preferred 1040 × 680 · list 58% · detail 42%") {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tasks")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Text("3 total · updated just now")
                            .font(.system(size: 10))
                            .foregroundColor(GlanceTheme.textTertiary)
                    }
                    Spacer()
                    ToolButton(symbol: "arrow.clockwise", label: "Refresh Tasks")
                    ToolButton(symbol: "trash", label: "Clear Completed")
                }
                .padding(.horizontal, 18)
                .frame(height: 58)
                .background(GlanceTheme.surface)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            SegmentedTabs(items: ["All 3", "Processing 1", "Completed 1", "Failed 1"], selection: $filter)
                            Spacer()
                        }
                        .padding(14)

                        Divider().background(GlanceTheme.hairline)

                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredTasks) { task in
                                    taskRow(task)
                                }
                            }
                            .padding(14)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(GlanceTheme.hairline).frame(width: 1)
                    taskDetail(tasks[selected])
                        .frame(width: 360)
                }
            }
        }
    }

    private var filteredTasks: [DemoTask] {
        switch filter {
        case 1: return tasks.filter { $0.status == .processing }
        case 2: return tasks.filter { $0.status == .completed }
        case 3: return tasks.filter { $0.status == .failed }
        default: return tasks
        }
    }

    private func taskRow(_ task: DemoTask) -> some View {
        Button { selected = task.id } label: {
            HStack(spacing: 12) {
                ArtworkPreview(compact: true, processed: task.status == .completed)
                    .frame(width: 54, height: 46)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(GlanceTheme.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.widget)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text(task.file)
                        .font(.system(size: 10))
                        .foregroundColor(GlanceTheme.textSecondary)
                    Text(task.time)
                        .font(.system(size: 9))
                        .foregroundColor(GlanceTheme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 7) {
                    StatusPill(title: task.status.rawValue, tone: task.status.tone)
                    if task.status == .processing {
                        ProgressView(value: task.progress)
                            .tint(GlanceTheme.accent)
                            .frame(width: 110)
                    } else if task.status == .failed {
                        Text("Retry available")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(GlanceTheme.failure)
                    } else {
                        Text("Output ready")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(GlanceTheme.success)
                    }
                }
            }
            .padding(12)
            .background(selected == task.id ? GlanceTheme.accentSoft : GlanceTheme.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected == task.id ? GlanceTheme.accent.opacity(0.34) : GlanceTheme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func taskDetail(_ task: DemoTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.widget)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text("task_8f31c2")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                Spacer()
                StatusPill(title: task.status.rawValue, tone: task.status.tone)
            }

            PanelSection("Input") {
                HStack(spacing: 10) {
                    ArtworkPreview(compact: true)
                        .frame(width: 58, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.file)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Text("2048 × 2736 · 2.8 MB")
                            .font(.system(size: 9))
                            .foregroundColor(GlanceTheme.textTertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("TIMELINE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(GlanceTheme.textTertiary)
                    .padding(.bottom, 12)
                TimelineStep(title: "Task submitted", detail: "09:41:02 · Server accepted", tone: .success)
                TimelineStep(title: task.status == .failed ? "Worker stopped" : "Worker processing",
                             detail: task.status == .failed ? "09:41:08 · Worker timeout" : "09:41:08 · 64% complete",
                             tone: task.status == .failed ? .failure : task.status == .completed ? .success : .accent)
                TimelineStep(title: task.status == .completed ? "Output downloaded" : "Waiting for output",
                             detail: task.status == .completed ? "09:41:19 · Added beside source" : task.status == .failed ? "Retry can reuse the same source" : "Next check in 4 seconds",
                             tone: task.status == .completed ? .success : .neutral,
                             last: true)
            }

            Spacer()
            HStack(spacing: 8) {
                if task.status == .processing {
                    ActionButton(title: "Cancel", symbol: "stop.fill", destructive: true)
                } else if task.status == .failed {
                    ActionButton(title: "Retry", symbol: "arrow.clockwise", primary: true)
                } else {
                    ActionButton(title: "Reveal Result", symbol: "arrow.right", primary: true)
                }
                ActionButton(title: "Show Input", symbol: "photo")
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlanceTheme.surface.opacity(0.68))
    }
}

struct Base64Page: View {
    @State private var input = "data:image/png;base64,\niVBORw0KGgoAAAANSUhEUgAA..."
    @State private var status = 0

    var body: some View {
        PageChrome(title: "Base64", subtitle: "Two-column conversion workspace · no modal-sized single-line field") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Base64 to Image")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Text("Paste a data URL or raw Base64 string. Whitespace and line breaks are supported.")
                            .font(.system(size: 11))
                            .foregroundColor(GlanceTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("BASE64 INPUT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(GlanceTheme.textTertiary)
                        TextEditor(text: $input)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(GlanceTheme.textPrimary.opacity(0.86))
                            .padding(10)
                            .background(GlanceTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(status == 3 ? GlanceTheme.failure.opacity(0.58) : GlanceTheme.hairline, lineWidth: 1))
                    }

                    if status == 3 {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("The value is not a valid Base64 image. Check the prefix or encoded data.")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GlanceTheme.failure)
                    }

                    HStack {
                        ActionButton(title: "Clear", symbol: "xmark") { input = ""; status = 0 }
                        Spacer()
                        ActionButton(title: "Convert", symbol: "arrow.right", primary: true, loading: status == 1) { convert() }
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Rectangle().fill(GlanceTheme.hairline).frame(width: 1)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("PREVIEW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(GlanceTheme.textTertiary)
                        Spacer()
                        if status == 2 { StatusPill(title: "PNG detected", tone: .success) }
                    }

                    Group {
                        if status == 1 {
                            VStack(spacing: 10) {
                                ShimmerBlock(height: 240, radius: 12)
                                ShimmerBlock(height: 14, radius: 5)
                                ShimmerBlock(height: 14, radius: 5)
                            }
                        } else if status == 2 {
                            ArtworkPreview(processed: true)
                                .frame(height: 320)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlanceTheme.success.opacity(0.32), lineWidth: 1))
                        } else {
                            EmptyState(symbol: "photo", title: "No preview yet", detail: "A decoded image appears here without replacing the input.")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(GlanceTheme.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlanceTheme.hairline, lineWidth: 1))
                        }
                    }

                    if status == 2 {
                        PanelSection("Decoded image") {
                            KeyValueField(title: "Type", value: "PNG")
                            Divider().background(GlanceTheme.hairline)
                            KeyValueField(title: "Dimensions", value: "1024 × 1024")
                            Divider().background(GlanceTheme.hairline)
                            KeyValueField(title: "Size", value: "684 KB")
                        }
                    }
                }
                .padding(22)
                .frame(width: 360, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(GlanceTheme.surface.opacity(0.74))
            }
        }
    }

    private func convert() {
        guard input.contains("base64") && input.count > 24 else {
            status = 3
            return
        }
        status = 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeOut(duration: 0.2)) { status = 2 }
        }
    }
}
