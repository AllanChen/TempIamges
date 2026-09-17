import AppKit
import SwiftUI

enum GlanceTheme {
    static let background = Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255)
    static let sidebar = Color(red: 13 / 255, green: 13 / 255, blue: 16 / 255)
    static let surface = Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    static let raised = Color(red: 23 / 255, green: 23 / 255, blue: 28 / 255)
    static let control = Color(red: 32 / 255, green: 31 / 255, blue: 37 / 255)
    static let canvas = Color(red: 11 / 255, green: 11 / 255, blue: 14 / 255)
    static let textPrimary = Color(red: 243 / 255, green: 238 / 255, blue: 232 / 255)
    static let textSecondary = Color(red: 170 / 255, green: 164 / 255, blue: 160 / 255)
    static let textTertiary = Color(red: 114 / 255, green: 109 / 255, blue: 105 / 255)
    static let accent = Color(red: 232 / 255, green: 168 / 255, blue: 124 / 255)
    static let accentSoft = Color(red: 232 / 255, green: 168 / 255, blue: 124 / 255, opacity: 0.14)
    static let success = Color(red: 143 / 255, green: 208 / 255, blue: 175 / 255)
    static let failure = Color(red: 241 / 255, green: 139 / 255, blue: 134 / 255)
    static let info = Color(red: 169 / 255, green: 197 / 255, blue: 239 / 255)
    static let hairline = Color.white.opacity(0.10)
    static let strongLine = Color.white.opacity(0.16)
    static let shadow = Color.black.opacity(0.34)

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let controlHeight: CGFloat = 32
    static let toolbarHeight: CGFloat = 52
    static let filmstripHeight: CGFloat = 88
    static let inspectorWidth: CGFloat = 276
}

struct FrostedMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = GlanceTheme.radiusMedium
    var fill: Color = GlanceTheme.surface.opacity(0.82)

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(GlanceTheme.hairline, lineWidth: 1)
            )
            .shadow(color: GlanceTheme.shadow.opacity(0.45), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glanceGlass(radius: CGFloat = GlanceTheme.radiusMedium,
                     fill: Color = GlanceTheme.surface.opacity(0.82)) -> some View {
        modifier(GlassSurface(radius: radius, fill: fill))
    }
}
