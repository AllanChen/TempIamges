#if DEBUG
import SwiftUI
import AppKit

// 你可以直接修改下面的 urls 数组来测试不同的图片
let previewURLs: [String] = [
    "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/0434049c-d9e7-4a36-9e68-4f8a3faad7b4.jpg"
]

struct PreviewPanelPreviewWrapper: NSViewRepresentable {
    let infos: [MediaInfo]

    func makeNSView(context: Context) -> NSView {
        let panel = PreviewPanel()
        let content = panel.buildPreviewContainer(infos: infos)

        // Simulate the floating-panel window chrome (shadow + background) so
        // the Canvas preview looks like the real on-screen window.
        let windowChrome = NSView(frame: content.frame)
        windowChrome.wantsLayer = true
        windowChrome.layer?.shadowColor = NSColor.black.cgColor
        windowChrome.layer?.shadowOpacity = 0.45
        windowChrome.layer?.shadowOffset = CGSize(width: 0, height: 12)
        windowChrome.layer?.shadowRadius = 32
        windowChrome.layer?.backgroundColor = NSColor.clear.cgColor

        content.frame = NSRect(origin: .zero, size: content.frame.size)
        windowChrome.addSubview(content)

        // Desktop backdrop so the window pops visually.
        let desktop = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        desktop.wantsLayer = true
        desktop.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor

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
            .frame(width: 900, height: 700)
            .background(Color.black)
    }
}
#endif
