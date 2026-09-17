import SwiftUI

struct PageChrome<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                Spacer()
                Text("LAYOUT PROTOTYPE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(GlanceTheme.textTertiary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(GlanceTheme.raised)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(GlanceTheme.hairline, lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(FrostedMaterial(material: .headerView))

            Divider().background(GlanceTheme.hairline)
            content
        }
        .background(GlanceTheme.background)
    }
}

struct ToolButton: View {
    let symbol: String
    let label: String
    var selected = false
    var badge = false
    var action: () -> Void = { }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selected ? GlanceTheme.accent : GlanceTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(selected ? GlanceTheme.accentSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: GlanceTheme.radiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GlanceTheme.radiusSmall, style: .continuous)
                            .stroke(selected ? GlanceTheme.accent.opacity(0.36) : Color.clear, lineWidth: 1)
                    )
                if badge {
                    Circle()
                        .fill(GlanceTheme.failure)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(GlanceTheme.surface, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ActionButton: View {
    let title: String
    var symbol: String? = nil
    var primary = false
    var destructive = false
    var disabled = false
    var loading = false
    var action: () -> Void = { }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .frame(minWidth: 70, minHeight: GlanceTheme.controlHeight)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: GlanceTheme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GlanceTheme.radiusSmall, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled || loading)
        .opacity(disabled ? 0.48 : 1)
    }

    private var foreground: Color {
        if primary { return GlanceTheme.background }
        if destructive { return GlanceTheme.failure }
        return GlanceTheme.textPrimary
    }

    private var background: Color {
        if primary { return GlanceTheme.accent }
        if destructive { return GlanceTheme.failure.opacity(0.10) }
        return GlanceTheme.control
    }

    private var border: Color {
        if primary { return GlanceTheme.accent }
        if destructive { return GlanceTheme.failure.opacity(0.42) }
        return GlanceTheme.hairline
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

enum StatusTone {
    case neutral, accent, success, failure, info

    var color: Color {
        switch self {
        case .neutral: return GlanceTheme.textSecondary
        case .accent: return GlanceTheme.accent
        case .success: return GlanceTheme.success
        case .failure: return GlanceTheme.failure
        case .info: return GlanceTheme.info
        }
    }
}

struct StatusPill: View {
    let title: String
    var tone: StatusTone = .neutral
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(tone.color)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(tone.color.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(tone.color.opacity(0.32), lineWidth: 1))
    }
}

struct SegmentedTabs: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Text(items[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selection == index ? GlanceTheme.textPrimary : GlanceTheme.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(selection == index ? GlanceTheme.control : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(GlanceTheme.canvas.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(GlanceTheme.hairline, lineWidth: 1))
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(GlanceTheme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GlanceTheme.textPrimary)
                .lineLimit(2)
                .textSelection(.enabled)
            Divider().background(GlanceTheme.hairline)
        }
    }
}

struct InspectorPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GlanceTheme.textPrimary)
            content
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: GlanceTheme.inspectorWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.surface.opacity(0.88))
        .overlay(alignment: .leading) {
            Rectangle().fill(GlanceTheme.hairline).frame(width: 1)
        }
    }
}

struct ArtworkPreview: View {
    var compact = false
    var processed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: processed
                        ? [Color(red: 0.18, green: 0.29, blue: 0.25), Color(red: 0.39, green: 0.57, blue: 0.47)]
                        : [Color(red: 0.23, green: 0.19, blue: 0.21), Color(red: 0.67, green: 0.48, blue: 0.36)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: proxy.size.width * 0.56)
                    .offset(x: proxy.size.width * 0.18, y: -proxy.size.height * 0.14)
                RoundedRectangle(cornerRadius: compact ? 4 : 14)
                    .fill(Color.black.opacity(0.18))
                    .frame(width: proxy.size.width * 0.54, height: proxy.size.height * 0.46)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -proxy.size.width * 0.08, y: proxy.size.height * 0.15)
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    Text(processed ? "RESULT" : "SOURCE")
                        .font(.system(size: compact ? 7 : 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.74))
                    if !compact {
                        Text(processed ? "transparent output" : "selected-image.jpg")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.56))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(compact ? 5 : 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 14, style: .continuous))
        }
    }
}

struct ShimmerBlock: View {
    var height: CGFloat
    var radius: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(GlanceTheme.raised)
                if !reduceMotion {
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.08), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: proxy.size.width * 0.42)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * proxy.size.width * 1.4)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .frame(height: height)
    }
}

struct BreathingThumbnail: View {
    var processed = false
    var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath = false

    var body: some View {
        ArtworkPreview(compact: true, processed: processed)
            .frame(width: 60, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(failed ? GlanceTheme.failure : GlanceTheme.accent,
                            lineWidth: breath && !reduceMotion ? 2.4 : 1.4)
            )
            .shadow(color: (failed ? GlanceTheme.failure : GlanceTheme.accent)
                .opacity(breath && !reduceMotion ? 0.44 : 0.08),
                    radius: breath && !reduceMotion ? 10 : 2)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(failed ? GlanceTheme.failure : GlanceTheme.accent)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(GlanceTheme.surface, lineWidth: 2))
                    .offset(x: 3, y: -3)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                    breath = true
                }
            }
            .accessibilityLabel(failed ? "Task failed" : "Widget task processing")
    }
}

struct TimelineStep: View {
    let title: String
    let detail: String
    var tone: StatusTone = .neutral
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tone.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                if !last {
                    Rectangle()
                        .fill(GlanceTheme.hairline)
                        .frame(width: 1, height: 38)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GlanceTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(GlanceTheme.textTertiary)
            }
            Spacer()
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(GlanceTheme.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GlanceTheme.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(GlanceTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(28)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(GlanceTheme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(GlanceTheme.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(GlanceTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(GlanceTheme.hairline, lineWidth: 1))
    }
}

struct KeyValueField: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(GlanceTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GlanceTheme.textPrimary)
                .monospacedDigit()
        }
        .frame(height: 28)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(GlanceTheme.textTertiary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlanceTheme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: GlanceTheme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GlanceTheme.radiusMedium).stroke(GlanceTheme.hairline, lineWidth: 1))
    }
}
