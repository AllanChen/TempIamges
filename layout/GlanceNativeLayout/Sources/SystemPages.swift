import SwiftUI

struct HistoryPage: View {
    @State private var search = ""
    @State private var selected = 0
    @State private var viewMode = 0

    var body: some View {
        PageChrome(title: "History", subtitle: "Recent previews grouped by day, with non-destructive detail") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SearchField(text: $search, placeholder: "Search history")
                        .frame(width: 260)
                    SegmentedTabs(items: ["Grid", "List"], selection: $viewMode)
                    Spacer()
                    ActionButton(title: "Clear History", symbol: "trash", destructive: true)
                }
                .padding(.horizontal, 16)
                .frame(height: GlanceTheme.toolbarHeight)
                .background(GlanceTheme.surface)

                Divider().background(GlanceTheme.hairline)

                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            historySection(title: "Today", range: 0..<4)
                            historySection(title: "Yesterday", range: 4..<7)
                        }
                        .padding(20)
                    }

                    Rectangle().fill(GlanceTheme.hairline).frame(width: 1)

                    InspectorPanel(title: "History item") {
                        ArtworkPreview(processed: selected == 2 || selected == 5)
                            .frame(height: 180)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlanceTheme.hairline, lineWidth: 1))
                        MetadataRow(label: "Filename", value: selected == 2 ? "background-removed.png" : "selected-image-\(selected + 1).jpg")
                        MetadataRow(label: "Previewed", value: selected < 4 ? "Today, 09:\(42 + selected)" : "Yesterday, 18:\(20 + selected)")
                        MetadataRow(label: "Source", value: selected == 2 ? "Widget result" : "Clipboard")
                        Spacer()
                        ActionButton(title: "Open Again", symbol: "arrow.up.forward", primary: true)
                    }
                }
            }
        }
    }

    private func historySection(title: String, range: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GlanceTheme.textPrimary)
                Spacer()
                Text("\(range.count) items")
                    .font(.system(size: 10))
                    .foregroundColor(GlanceTheme.textTertiary)
            }

            if viewMode == 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(range), id: \.self) { index in
                        historyTile(index)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(range), id: \.self) { index in
                        historyListRow(index)
                    }
                }
            }
        }
    }

    private func historyTile(_ index: Int) -> some View {
        Button { selected = index } label: {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkPreview(compact: true, processed: index == 2 || index == 5)
                    .frame(height: 110)
                Text(index == 2 ? "background-removed.png" : "selected-image-\(index + 1).jpg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GlanceTheme.textPrimary)
                    .lineLimit(1)
                HStack {
                    Text(index < 4 ? "09:\(42 + index)" : "Yesterday")
                    Spacer()
                    Image(systemName: index == 2 || index == 5 ? "wand.and.stars" : "doc.on.clipboard")
                }
                .font(.system(size: 9))
                .foregroundColor(GlanceTheme.textTertiary)
            }
            .padding(9)
            .background(selected == index ? GlanceTheme.accentSoft : GlanceTheme.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected == index ? GlanceTheme.accent.opacity(0.36) : GlanceTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func historyListRow(_ index: Int) -> some View {
        Button { selected = index } label: {
            HStack(spacing: 12) {
                ArtworkPreview(compact: true, processed: index == 2 || index == 5)
                    .frame(width: 62, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(index == 2 ? "background-removed.png" : "selected-image-\(index + 1).jpg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text(index == 2 || index == 5 ? "Widget result" : "Clipboard image")
                        .font(.system(size: 9))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                Spacer()
                Text(index < 4 ? "09:\(42 + index)" : "Yesterday")
                    .font(.system(size: 10))
                    .foregroundColor(GlanceTheme.textSecondary)
            }
            .padding(10)
            .background(selected == index ? GlanceTheme.accentSoft : GlanceTheme.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == index ? GlanceTheme.accent.opacity(0.34) : GlanceTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PreferencesPage: View {
    @State private var category = 0
    @State private var enabled = true
    @State private var clipboard = true
    @State private var launchAtLogin = false
    @State private var reduceMotion = false
    @State private var language = "简体中文"

    var body: some View {
        PageChrome(title: "Settings", subtitle: "Preferred 820 × 600 · native form hierarchy") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["General", "Preview", "Widgets", "Account"].indices, id: \.self) { index in
                        Button { category = index } label: {
                            HStack(spacing: 9) {
                                Image(systemName: ["gearshape", "eye", "square.grid.2x2", "person.crop.circle"][index])
                                    .frame(width: 18)
                                Text(["General", "Preview", "Widgets", "Account"][index])
                                Spacer()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(category == index ? GlanceTheme.textPrimary : GlanceTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(category == index ? GlanceTheme.control : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Glance 1.0 · Build 162")
                        .font(.system(size: 9))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                .padding(14)
                .frame(width: 178)
                .frame(maxHeight: .infinity)
                .background(GlanceTheme.sidebar)

                Rectangle().fill(GlanceTheme.hairline).frame(width: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(["General", "Preview", "Widgets", "Account"][category])
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)

                        if category == 0 {
                            PanelSection("Application") {
                                settingToggle("Enable Glance", detail: "Listen for the preview shortcut.", value: $enabled)
                                Divider().background(GlanceTheme.hairline)
                                settingToggle("Read clipboard content", detail: "Preview copied text, URLs and media.", value: $clipboard)
                                Divider().background(GlanceTheme.hairline)
                                settingToggle("Launch at login", detail: "Keep Glance available after sign in.", value: $launchAtLogin)
                            }
                            PanelSection("Language") {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Application language")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(GlanceTheme.textPrimary)
                                        Text("Restart is required after changing language.")
                                            .font(.system(size: 9))
                                            .foregroundColor(GlanceTheme.textTertiary)
                                    }
                                    Spacer()
                                    Picker("", selection: $language) {
                                        Text("简体中文").tag("简体中文")
                                        Text("English").tag("English")
                                    }
                                    .labelsHidden()
                                    .frame(width: 140)
                                }
                            }
                        } else if category == 1 {
                            PanelSection("Appearance") {
                                settingToggle("Reduce interface motion", detail: "Use opacity changes instead of breathing and spring transitions.", value: $reduceMotion)
                                Divider().background(GlanceTheme.hairline)
                                KeyValueField(title: "Canvas", value: "Deep charcoal")
                                Divider().background(GlanceTheme.hairline)
                                KeyValueField(title: "Inspector position", value: "Right")
                            }
                            PanelSection("Shortcut") {
                                HStack {
                                    Text("Preview shortcut")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(GlanceTheme.textPrimary)
                                    Spacer()
                                    Text("⌥ Space")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(GlanceTheme.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 30)
                                        .background(GlanceTheme.control)
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(GlanceTheme.hairline, lineWidth: 1))
                                }
                            }
                        } else if category == 2 {
                            PanelSection("Installed Widgets") {
                                widgetSetting("Super Resolution", detail: "Local registry · version 1.4.2", installed: true)
                                Divider().background(GlanceTheme.hairline)
                                widgetSetting("OCR Extract", detail: "Local registry · version 2.1.0", installed: true)
                            }
                            PanelSection("Task behavior") {
                                KeyValueField(title: "Completed results", value: "Insert beside source")
                                Divider().background(GlanceTheme.hairline)
                                KeyValueField(title: "Main image focus", value: "Keep current item")
                            }
                        } else {
                            PanelSection("Glance Account") {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(GlanceTheme.accent)
                                        .frame(width: 42, height: 42)
                                        .overlay(Text("A").font(.system(size: 15, weight: .bold)).foregroundColor(GlanceTheme.background))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("allan@example.com")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(GlanceTheme.textPrimary)
                                        Text("Signed in · Cloud Widgets available")
                                            .font(.system(size: 9))
                                            .foregroundColor(GlanceTheme.textTertiary)
                                    }
                                    Spacer()
                                    ActionButton(title: "Sign Out")
                                }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 680, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(GlanceTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(GlanceTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).tint(GlanceTheme.accent)
        }
        .frame(minHeight: 42)
    }

    private func widgetSetting(_ title: String, detail: String, installed: Bool) -> some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .foregroundColor(GlanceTheme.accent)
                .frame(width: 32, height: 32)
                .background(GlanceTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(GlanceTheme.textPrimary)
                Text(detail).font(.system(size: 9)).foregroundColor(GlanceTheme.textTertiary)
            }
            Spacer()
            StatusPill(title: installed ? "Installed" : "Missing", tone: installed ? .success : .failure)
        }
        .frame(minHeight: 46)
    }
}

struct OnboardingPage: View {
    @State private var inputMonitoring = true
    @State private var accessibility = false
    @State private var fullDiskAccess = false

    var body: some View {
        PageChrome(title: "Onboarding", subtitle: "Focused permission window · preferred 620 × 600") {
            ZStack {
                GlanceTheme.background
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(GlanceTheme.accent)
                            .frame(width: 72, height: 72)
                            .overlay(Text("G").font(.system(size: 28, weight: .bold)).foregroundColor(GlanceTheme.background))
                            .shadow(color: .black.opacity(0.32), radius: 20, y: 10)
                        Text("Welcome to Glance")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(GlanceTheme.textPrimary)
                        Text("Grant the permissions Glance needs to inspect selected content. Optional access stays optional.")
                            .font(.system(size: 11))
                            .foregroundColor(GlanceTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 430)
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 24)

                    VStack(spacing: 10) {
                        permissionRow(title: "Input Monitoring", detail: "Detect the preview shortcut while another app is active.", granted: $inputMonitoring, required: true)
                        permissionRow(title: "Accessibility", detail: "Read the text or URL currently selected in the frontmost app.", granted: $accessibility, required: true)
                        permissionRow(title: "Full Disk Access", detail: "Preview files from protected folders without repeated prompts.", granted: $fullDiskAccess, required: false)
                    }

                    Spacer()

                    HStack {
                        Text(accessibility ? "Required permissions are ready." : "Accessibility permission is still required.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accessibility ? GlanceTheme.success : GlanceTheme.textTertiary)
                        Spacer()
                        ActionButton(title: "Continue", symbol: "arrow.right", primary: true, disabled: !inputMonitoring || !accessibility)
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 26)
                .frame(width: 620, height: 600)
                .background(FrostedMaterial())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(GlanceTheme.strongLine, lineWidth: 1))
                .shadow(color: .black.opacity(0.48), radius: 42, y: 20)
                .padding(24)
            }
        }
    }

    private func permissionRow(title: String, detail: String, granted: Binding<Bool>, required: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted.wrappedValue ? "checkmark.shield.fill" : "shield")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(granted.wrappedValue ? GlanceTheme.success : GlanceTheme.accent)
                .frame(width: 40, height: 40)
                .background((granted.wrappedValue ? GlanceTheme.success : GlanceTheme.accent).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text(required ? "Required" : "Optional")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(GlanceTheme.textTertiary)
            }
            Spacer()
            if granted.wrappedValue {
                StatusPill(title: "Granted", tone: .success, symbol: "checkmark")
            } else {
                ActionButton(title: "Open Settings", symbol: "gearshape") {
                    granted.wrappedValue = true
                }
            }
        }
        .padding(14)
        .frame(height: 78)
        .background(GlanceTheme.surface.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlanceTheme.hairline, lineWidth: 1))
    }
}

struct WidgetWebPage: View {
    @State private var state = 0

    var body: some View {
        PageChrome(title: "Widget Web", subtitle: "Hosted execution keeps native chrome and explicit states") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ToolButton(symbol: "chevron.left", label: "Back")
                    ToolButton(symbol: "chevron.right", label: "Forward")
                    ToolButton(symbol: "arrow.clockwise", label: "Reload") { state = 1; completeLoad() }
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(GlanceTheme.success)
                        Text("widgets.glance.app/remove-background")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(GlanceTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(GlanceTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(GlanceTheme.hairline, lineWidth: 1))
                    Spacer()
                    SegmentedTabs(items: ["Ready", "Loading", "Error"], selection: $state)
                }
                .padding(.horizontal, 14)
                .frame(height: GlanceTheme.toolbarHeight)
                .background(GlanceTheme.surface)

                Divider().background(GlanceTheme.hairline)

                Group {
                    if state == 1 {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    ShimmerBlock(height: 24, radius: 6).frame(width: 220)
                                    ShimmerBlock(height: 12, radius: 5).frame(width: 330)
                                }
                                Spacer()
                                ShimmerBlock(height: 34, radius: 8).frame(width: 110)
                            }
                            ShimmerBlock(height: 340, radius: 14)
                            HStack {
                                ShimmerBlock(height: 13, radius: 5).frame(width: 180)
                                Spacer()
                                ShimmerBlock(height: 32, radius: 8).frame(width: 92)
                            }
                        }
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else if state == 2 {
                        EmptyState(symbol: "wifi.exclamationmark", title: "Widget could not load", detail: "The service returned an unavailable response. Retry without closing the current image.")
                            .overlay(alignment: .bottom) {
                                ActionButton(title: "Retry", symbol: "arrow.clockwise", primary: true) {
                                    state = 1
                                    completeLoad()
                                }
                                .padding(.bottom, 90)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Remove Background")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(GlanceTheme.textPrimary)
                                        Text("Review the input, then submit the hosted command.")
                                            .font(.system(size: 11))
                                            .foregroundColor(GlanceTheme.textSecondary)
                                    }
                                    Spacer()
                                    StatusPill(title: "Secure upload", tone: .success, symbol: "lock.fill")
                                }

                                ArtworkPreview()
                                    .frame(maxHeight: 390)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(GlanceTheme.hairline, lineWidth: 1))

                                HStack {
                                    Text("selected-image.jpg · 2.8 MB")
                                        .font(.system(size: 10))
                                        .foregroundColor(GlanceTheme.textTertiary)
                                    Spacer()
                                    ActionButton(title: "Submit Widget", symbol: "paperplane.fill", primary: true)
                                }
                            }
                            .padding(26)

                            Rectangle().fill(GlanceTheme.hairline).frame(width: 1)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("COMMAND OPTIONS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(GlanceTheme.textTertiary)
                                PanelSection("Output") {
                                    KeyValueField(title: "Format", value: "PNG")
                                    Divider().background(GlanceTheme.hairline)
                                    KeyValueField(title: "Transparency", value: "Enabled")
                                }
                                PanelSection("Privacy") {
                                    Text("The selected image is uploaded for this task and removed after the result expires.")
                                        .font(.system(size: 10))
                                        .foregroundColor(GlanceTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(20)
                            .frame(width: 300)
                            .background(GlanceTheme.surface.opacity(0.68))
                        }
                    }
                }
                .background(GlanceTheme.background)
            }
        }
    }

    private func completeLoad() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            withAnimation(.easeOut(duration: 0.2)) { state = 0 }
        }
    }
}
