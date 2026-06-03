#if DEBUG
import SwiftUI
import AppKit

// 你可以直接修改下面的 urls 数组来测试不同的图片
let previewURLs: [String] = [
    "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/0434049c-d9e7-4a36-9e68-4f8a3faad7b4.jpg",
    "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80",
    "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&q=80",
    "https://images.unsplash.com/photo-1447752875215-b2761acb3c5d?w=800&q=80"
]

struct PreviewPanelPreviewWrapper: NSViewRepresentable {
    let infos: [MediaInfo]

    func makeNSView(context: Context) -> NSView {
        let panel = PreviewPanel()
        // Full chrome: frosted base + nav bar + content, exactly as on screen.
        let content = panel.buildPreviewRoot(infos: infos)

        // Window-level drop shadow so the frosted panel lifts off the desktop.
        let windowChrome = NSView(frame: content.frame)
        windowChrome.wantsLayer = true
        windowChrome.layer?.shadowColor = NSColor.black.cgColor
        windowChrome.layer?.shadowOpacity = 0.5
        windowChrome.layer?.shadowOffset = CGSize(width: 0, height: 14)
        windowChrome.layer?.shadowRadius = 36
        windowChrome.layer?.backgroundColor = NSColor.clear.cgColor

        content.frame = NSRect(origin: .zero, size: content.frame.size)
        windowChrome.addSubview(content)

        // A colorful gradient "wallpaper" behind the panel so the translucent
        // frost actually has something to blur — a flat gray would hide it.
        let desktop = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 760))
        desktop.wantsLayer = true
        let wallpaper = CAGradientLayer()
        wallpaper.frame = desktop.bounds
        wallpaper.colors = [
            NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.42, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.62, green: 0.20, blue: 0.45, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.30, alpha: 1).cgColor
        ]
        wallpaper.locations = [0.0, 0.55, 1.0]
        wallpaper.startPoint = CGPoint(x: 0, y: 1)
        wallpaper.endPoint = CGPoint(x: 1, y: 0)
        desktop.layer?.addSublayer(wallpaper)

        windowChrome.frame.origin = CGPoint(
            x: (desktop.frame.width - windowChrome.frame.width) / 2,
            y: (desktop.frame.height - windowChrome.frame.height) / 2
        )
        desktop.addSubview(windowChrome)
        return desktop
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@available(macOS 10.15, *)
struct PreviewPanel_Previews: PreviewProvider {
    static var previews: some View {
        let infos = previewURLs.compactMap { urlStr -> MediaInfo? in
            guard let url = URL(string: urlStr) else { return nil }
            return MediaInfo(url: url, isLocal: false, kind: .image)
        }
        return PreviewPanelPreviewWrapper(infos: infos)
            .frame(width: 900, height: 760)
            .background(Color.black)
    }
}
#endif
