import SwiftUI

struct QuickPreviewPage: View {
    @State private var pinned = false

    var body: some View {
        PageChrome(title: "Quick Preview", subtitle: "Compact transient panel · 720 × 520") {
            ZStack {
                GlanceTheme.background
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        StatusPill(title: "PNG", tone: .neutral)
                        Text("selected-image.png")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GlanceTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        ToolButton(symbol: pinned ? "pin.fill" : "pin", label: "Keep Open", selected: pinned) {
                            pinned.toggle()
                        }
                        ToolButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Open Inspector")
                        ToolButton(symbol: "xmark", label: "Close")
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(GlanceTheme.surface)

                    Divider().background(GlanceTheme.hairline)

                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ZStack {
                                GlanceTheme.canvas
                                ArtworkPreview()
                                    .frame(width: min(360, proxy.size.width * 0.52),
                                           height: min(420, proxy.size.height * 0.76))
                                    .shadow(color: .black.opacity(0.44), radius: 30, y: 18)
                            }
                            InspectorPanel(title: "Quick information") {
                                MetadataRow(label: "Dimensions", value: "2048 × 2736 px")
                                MetadataRow(label: "Color", value: "Display P3 · 8 bit")
                                MetadataRow(label: "Source", value: "Copied from Arc")
                                Spacer()
                                Text("Hold Space to inspect · Return opens the full workbench")
                                    .font(.system(size: 10))
                                    .foregroundColor(GlanceTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, maxHeight: 540)
                .glanceGlass(radius: 16, fill: GlanceTheme.surface.opacity(0.94))
                .padding(28)
            }
        }
    }
}

private enum PrototypeTaskState {
    case idle, processing, completed, failed
}

struct ImageInspectPage: View {
    @State private var mode = 0
    @State private var selectedIndex = 0
    @State private var taskState: PrototypeTaskState = .idle
    @State private var progress = 0.0
    @State private var infoVisible = true
    @State private var resultVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PageChrome(title: "Image Inspect", subtitle: "Preferred 1180 × 760 · minimum 900 × 600") {
            VStack(spacing: 0) {
                inspectToolbar
                Divider().background(GlanceTheme.hairline)

                HStack(spacing: 0) {
                    canvas
                    if infoVisible {
                        imageInspector
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: infoVisible)

                Divider().background(GlanceTheme.hairline)
                filmstrip
            }
        }
    }

    private var inspectToolbar: some View {
        HStack(spacing: 6) {
            SegmentedTabs(items: ["Focus", "Side by side", "Slider"], selection: $mode)
            Divider().frame(height: 20).background(GlanceTheme.hairline).padding(.horizontal, 4)
            ToolButton(symbol: "arrow.counterclockwise", label: "Rotate Left")
            ToolButton(symbol: "arrow.clockwise", label: "Rotate Right")
            ToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip Horizontal")
            ToolButton(symbol: "viewfinder", label: "Fit to Window")
            Spacer()

            if taskState == .processing {
                StatusPill(title: "\(Int(progress * 100))%", tone: .accent, symbol: "bolt.horizontal")
            } else if taskState == .completed {
                StatusPill(title: "Result ready", tone: .success, symbol: "checkmark")
            }

            ToolButton(symbol: "square.grid.2x2", label: "Widget Market")
            ToolButton(symbol: "checklist", label: "Task Center", badge: taskState == .processing)
            ToolButton(symbol: infoVisible ? "sidebar.right" : "sidebar.right", label: "Toggle Information", selected: infoVisible) {
                infoVisible.toggle()
            }
            ToolButton(symbol: "ellipsis", label: "More Actions")
        }
        .padding(.horizontal, 14)
        .frame(height: GlanceTheme.toolbarHeight)
        .background(GlanceTheme.surface.opacity(0.92))
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                GlanceTheme.canvas
                if mode == 1 {
                    HStack(spacing: 1) {
                        artworkFrame(processed: false)
                        artworkFrame(processed: resultVisible)
                    }
                } else if mode == 2 {
                    ZStack {
                        artworkFrame(processed: true)
                        artworkFrame(processed: false)
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: proxy.size.width * 0.48)
                                    Color.clear
                                }
                            )
                        Rectangle()
                            .fill(GlanceTheme.textPrimary.opacity(0.86))
                            .frame(width: 1)
                            .offset(x: -proxy.size.width * 0.02)
                    }
                } else {
                    ArtworkPreview(processed: selectedIndex == 2)
                        .frame(width: min(proxy.size.width * 0.56, 430),
                               height: min(proxy.size.height * 0.76, 500))
                        .shadow(color: .black.opacity(0.48), radius: 32, y: 18)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedIndex == 2 ? "Widget result" : "Focus · 01")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GlanceTheme.textSecondary)
                    Text(selectedIndex == 2 ? "background-removed.png" : "selected-image.jpg")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(GlanceTheme.textPrimary)
                }
                .padding(14)

                if taskState == .processing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Remove Background")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(GlanceTheme.textPrimary)
                            Text("Processing continues without covering the image")
                                .font(.system(size: 9))
                                .foregroundColor(GlanceTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 42)
                    .background(GlanceTheme.surface.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GlanceTheme.accent.opacity(0.28), lineWidth: 1))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: taskState == .processing)
        }
    }

    private func artworkFrame(processed: Bool) -> some View {
        GeometryReader { proxy in
            ZStack {
                GlanceTheme.canvas
                ArtworkPreview(processed: processed)
                    .frame(width: min(proxy.size.width * 0.72, 340),
                           height: min(proxy.size.height * 0.74, 460))
                    .shadow(color: .black.opacity(0.42), radius: 24, y: 14)
            }
        }
    }

    private var imageInspector: some View {
        InspectorPanel(title: "Image information") {
            MetadataRow(label: "Filename", value: selectedIndex == 2 ? "background-removed.png" : "selected-image.jpg")
            MetadataRow(label: "Dimensions", value: "2048 × 2736 px")
            MetadataRow(label: "Color", value: selectedIndex == 2 ? "RGBA · 8 bit" : "Display P3 · 8 bit")
            MetadataRow(label: "Source", value: selectedIndex == 2 ? "Remove Background" : "Copied from browser")

            if taskState == .processing {
                PanelSection("Active task") {
                    HStack {
                        Text("Remove Background")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(GlanceTheme.accent)
                            .monospacedDigit()
                    }
                    ProgressView(value: progress)
                        .tint(GlanceTheme.accent)
                    Text("Output is inserted after the source and never steals focus.")
                        .font(.system(size: 10))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
            }

            Spacer()

            if taskState == .idle || taskState == .failed {
                ActionButton(title: taskState == .failed ? "Retry Widget" : "Run Widget",
                             symbol: "wand.and.stars",
                             primary: true) {
                    startTask()
                }
            } else if taskState == .processing {
                ActionButton(title: "Cancel Task", symbol: "stop.fill", destructive: true) {
                    withAnimation { taskState = .idle; progress = 0 }
                }
            } else {
                ActionButton(title: "Show Result", symbol: "arrow.right") {
                    selectedIndex = 2
                }
            }
        }
    }

    private var filmstrip: some View {
        HStack(spacing: 10) {
            Text("2 items")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GlanceTheme.textTertiary)
                .frame(width: 48, alignment: .leading)

            thumbnail(index: 0, label: "Source", processed: false,
                      processing: taskState == .processing)
            thumbnail(index: 1, label: "Reference", processed: false, processing: false)

            if resultVisible {
                thumbnail(index: 2, label: "Result", processed: true, processing: false)
                    .transition(.asymmetric(
                        insertion: .offset(x: -12).combined(with: .scale(scale: 0.92)).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer()
            StatusPill(title: "⌘V Paste", tone: .neutral)
        }
        .padding(.horizontal, 14)
        .frame(height: GlanceTheme.filmstripHeight)
        .background(GlanceTheme.surface.opacity(0.94))
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: resultVisible)
    }

    private func thumbnail(index: Int, label: String, processed: Bool, processing: Bool) -> some View {
        Button {
            selectedIndex = index
        } label: {
            VStack(spacing: 5) {
                if processing {
                    BreathingThumbnail(processed: processed)
                } else {
                    ArtworkPreview(compact: true, processed: processed)
                        .frame(width: 60, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedIndex == index ? GlanceTheme.accent : GlanceTheme.hairline,
                                        lineWidth: selectedIndex == index ? 2 : 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            if processed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(GlanceTheme.background)
                                    .frame(width: 16, height: 16)
                                    .background(GlanceTheme.success)
                                    .clipShape(Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(processed ? GlanceTheme.success : GlanceTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) thumbnail")
    }

    private func startTask() {
        taskState = .processing
        progress = 0.08
        resultVisible = false

        Task { @MainActor in
            for value in [0.22, 0.41, 0.64, 0.82, 1.0] {
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard taskState == .processing else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    progress = value
                }
            }
            guard taskState == .processing else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                taskState = .completed
                resultVisible = true
            }
        }
    }
}

struct VideoInspectPage: View {
    @State private var state = 0
    @State private var playing = true
    @State private var muted = false
    @State private var infoVisible = true

    var body: some View {
        PageChrome(title: "Video Inspect", subtitle: "Playback controls remain separate from media tools") {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    SegmentedTabs(items: ["Ready", "Buffering", "Error"], selection: $state)
                    Divider().frame(height: 20).background(GlanceTheme.hairline).padding(.horizontal, 4)
                    ToolButton(symbol: "rectangle.split.2x1", label: "Side by Side")
                    ToolButton(symbol: "slider.horizontal.below.rectangle", label: "Slider Compare")
                    ToolButton(symbol: "viewfinder", label: "Fit to Window")
                    Spacer()
                    ToolButton(symbol: "sidebar.right", label: "Toggle Information", selected: infoVisible) {
                        infoVisible.toggle()
                    }
                    ToolButton(symbol: "ellipsis", label: "More Actions")
                }
                .padding(.horizontal, 14)
                .frame(height: GlanceTheme.toolbarHeight)
                .background(GlanceTheme.surface)

                Divider().background(GlanceTheme.hairline)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ZStack {
                            LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.22, green: 0.17, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 420, height: 238)
                                .overlay(
                                    Image(systemName: state == 2 ? "exclamationmark.triangle" : "play.fill")
                                        .font(.system(size: 30, weight: .medium))
                                        .foregroundColor(state == 2 ? GlanceTheme.failure : .white.opacity(0.78))
                                )
                                .shadow(color: .black.opacity(0.46), radius: 28, y: 16)

                            if state == 1 {
                                VStack(spacing: 10) {
                                    ProgressView().controlSize(.regular)
                                    Text("Buffering high-resolution preview")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(GlanceTheme.textSecondary)
                                }
                                .padding(14)
                                .background(GlanceTheme.surface.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else if state == 2 {
                                VStack(spacing: 8) {
                                    Text("Preview unavailable")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(GlanceTheme.textPrimary)
                                    Text("The decoder could not open this track.")
                                        .font(.system(size: 10))
                                        .foregroundColor(GlanceTheme.textTertiary)
                                    ActionButton(title: "Retry", symbol: "arrow.clockwise", primary: true) { state = 0 }
                                }
                                .padding(16)
                                .background(GlanceTheme.surface.opacity(0.96))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        VStack(spacing: 8) {
                            Slider(value: .constant(0.38))
                                .tint(GlanceTheme.accent)
                            HStack(spacing: 10) {
                                ToolButton(symbol: playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play") {
                                    playing.toggle()
                                }
                                ToolButton(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: muted ? "Unmute" : "Mute") {
                                    muted.toggle()
                                }
                                Text("00:18")
                                Spacer()
                                Text("00:48")
                                ToolButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Full Screen")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(GlanceTheme.textSecondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(GlanceTheme.surface)
                    }

                    if infoVisible {
                        InspectorPanel(title: "Video information") {
                            MetadataRow(label: "Filename", value: "product-demo.mov")
                            MetadataRow(label: "Dimensions", value: "3840 × 2160")
                            MetadataRow(label: "Codec", value: "HEVC · Main 10")
                            MetadataRow(label: "Duration", value: "00:48.284")
                            MetadataRow(label: "Frame rate", value: "29.97 fps")
                        }
                    }
                }
            }
        }
    }
}

struct ContentViewerPage: View {
    @State private var contentType = 0
    @State private var query = ""

    private let code = """
    struct PreviewRequest: Codable {
        let sourceURL: URL
        let displayName: String
        let contentType: String
    }

    func open(_ request: PreviewRequest) async throws {
        let content = try await loader.load(request.sourceURL)
        await MainActor.run { viewer.render(content) }
    }
    """

    var body: some View {
        PageChrome(title: "Content Viewer", subtitle: "Non-media content hides image and video controls") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SegmentedTabs(items: ["Code", "Markdown", "PDF"], selection: $contentType)
                    Spacer()
                    SearchField(text: $query, placeholder: "Find in document")
                        .frame(width: 220)
                    ToolButton(symbol: "square.and.arrow.up", label: "Share")
                    ToolButton(symbol: "ellipsis", label: "More Actions")
                }
                .padding(.horizontal, 14)
                .frame(height: GlanceTheme.toolbarHeight)
                .background(GlanceTheme.surface)

                Divider().background(GlanceTheme.hairline)

                HStack(spacing: 0) {
                    Group {
                        if contentType == 0 {
                            ScrollView {
                                Text(code)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(GlanceTheme.textPrimary.opacity(0.88))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(24)
                                    .textSelection(.enabled)
                            }
                        } else if contentType == 1 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text("Processing notes")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(GlanceTheme.textPrimary)
                                    Text("The selected image is ready. Run Remove Background to continue, then inspect the result from the adjacent filmstrip item.")
                                        .font(.system(size: 13))
                                        .foregroundColor(GlanceTheme.textSecondary)
                                        .lineSpacing(5)
                                    PanelSection("Status") {
                                        KeyValueField(title: "Input", value: "ready")
                                        KeyValueField(title: "Widget", value: "waiting")
                                        KeyValueField(title: "Output", value: "not created")
                                    }
                                }
                                .frame(maxWidth: 620, alignment: .leading)
                                .padding(32)
                            }
                        } else {
                            ZStack {
                                GlanceTheme.canvas
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.92))
                                        .frame(width: 360, height: 480)
                                        .overlay(
                                            VStack(alignment: .leading, spacing: 12) {
                                                Text("GLANCE REPORT")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.black.opacity(0.7))
                                                Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                                                ForEach(0..<8, id: \.self) { index in
                                                    Rectangle()
                                                        .fill(Color.black.opacity(index % 3 == 0 ? 0.14 : 0.08))
                                                        .frame(height: index % 3 == 0 ? 16 : 8)
                                                }
                                                Spacer()
                                            }
                                            .padding(30)
                                        )
                                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                                    Text("Page 1 of 6")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(GlanceTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GlanceTheme.canvas)

                    InspectorPanel(title: "Document information") {
                        MetadataRow(label: "Filename", value: contentType == 0 ? "PreviewRequest.swift" : contentType == 1 ? "processing-notes.md" : "glance-report.pdf")
                        MetadataRow(label: "Type", value: contentType == 0 ? "Swift source" : contentType == 1 ? "Markdown" : "PDF document")
                        MetadataRow(label: "Size", value: contentType == 2 ? "1.8 MB" : "4 KB")
                        MetadataRow(label: "Modified", value: "Today, 09:42")
                        Spacer()
                        Text("Media controls are intentionally absent in this view.")
                            .font(.system(size: 10))
                            .foregroundColor(GlanceTheme.textTertiary)
                    }
                }
            }
        }
    }
}
