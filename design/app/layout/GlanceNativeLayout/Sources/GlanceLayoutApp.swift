import SwiftUI

@main
struct GlanceLayoutApp: App {
    var body: some Scene {
        WindowGroup("Glance Layout") {
            LayoutGalleryView()
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

enum LayoutPage: String, CaseIterable, Identifiable {
    case quickPreview
    case imageInspect
    case videoInspect
    case contentViewer
    case widgetMarket
    case taskCenter
    case base64
    case history
    case preferences
    case onboarding
    case widgetWeb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickPreview: return "Quick Preview"
        case .imageInspect: return "Image Inspect"
        case .videoInspect: return "Video Inspect"
        case .contentViewer: return "Content Viewer"
        case .widgetMarket: return "Widget Market"
        case .taskCenter: return "Task Center"
        case .base64: return "Base64"
        case .history: return "History"
        case .preferences: return "Settings"
        case .onboarding: return "Onboarding"
        case .widgetWeb: return "Widget Web"
        }
    }

    var subtitle: String {
        switch self {
        case .quickPreview: return "Transient focus panel"
        case .imageInspect: return "Canvas, inspector, filmstrip"
        case .videoInspect: return "Playback and comparison"
        case .contentViewer: return "Code, Markdown and PDF"
        case .widgetMarket: return "Discover, inspect and install"
        case .taskCenter: return "Queue, progress and results"
        case .base64: return "Convert and validate"
        case .history: return "Recent previews and actions"
        case .preferences: return "Behavior and account"
        case .onboarding: return "Permissions and readiness"
        case .widgetWeb: return "Hosted Widget execution"
        }
    }

    var symbol: String {
        switch self {
        case .quickPreview: return "eye"
        case .imageInspect: return "photo"
        case .videoInspect: return "play.rectangle"
        case .contentViewer: return "doc.text"
        case .widgetMarket: return "square.grid.2x2"
        case .taskCenter: return "checklist"
        case .base64: return "textformat.abc"
        case .history: return "clock.arrow.circlepath"
        case .preferences: return "gearshape"
        case .onboarding: return "hand.raised"
        case .widgetWeb: return "network"
        }
    }
}

struct LayoutGalleryView: View {
    @State private var selection: LayoutPage = .imageInspect

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GLANCE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(GlanceTheme.accent)
                    Text("Native layout system")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(GlanceTheme.textPrimary)
                    Text("Design prototype, not production navigation")
                        .font(.system(size: 11))
                        .foregroundColor(GlanceTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                Divider().background(GlanceTheme.hairline)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(LayoutPage.allCases) { page in
                            Button {
                                selection = page
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: page.symbol)
                                        .font(.system(size: 14, weight: .medium))
                                        .frame(width: 20)
                                        .foregroundColor(selection == page ? GlanceTheme.accent : GlanceTheme.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(page.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(GlanceTheme.textPrimary)
                                        Text(page.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundColor(GlanceTheme.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 46)
                                .background(selection == page ? GlanceTheme.accentSoft : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selection == page ? GlanceTheme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(page.title), \(page.subtitle)")
                        }
                    }
                    .padding(10)
                }

                Divider().background(GlanceTheme.hairline)
                HStack(spacing: 8) {
                    Circle()
                        .fill(GlanceTheme.success)
                        .frame(width: 7, height: 7)
                    Text("Native SwiftUI prototype")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GlanceTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(minWidth: 218, idealWidth: 228, maxWidth: 238)
            .background(GlanceTheme.sidebar)

            Rectangle()
                .fill(GlanceTheme.hairline)
                .frame(width: 1)

            Group {
                switch selection {
                case .quickPreview: QuickPreviewPage()
                case .imageInspect: ImageInspectPage()
                case .videoInspect: VideoInspectPage()
                case .contentViewer: ContentViewerPage()
                case .widgetMarket: WidgetMarketPage()
                case .taskCenter: TaskCenterPage()
                case .base64: Base64Page()
                case .history: HistoryPage()
                case .preferences: PreferencesPage()
                case .onboarding: OnboardingPage()
                case .widgetWeb: WidgetWebPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlanceTheme.background)
        }
        .background(GlanceTheme.background)
    }
}
