import AppKit
import WebKit

final class WidgetMarketPanel: NSPanel, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WidgetMarketPanel()
    private let webView: WKWebView
    private weak var attachedParent: NSWindow?
    private let marketURL = URL(string: "https://glance.mcreator.ai/widgets/")!

    private init() {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 620), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true; isReleasedWhenClosed = false; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        webView.navigationDelegate = self
        controller.add(self, name: "glanceWidgetMarket")
        let root = NSView(frame: contentView?.bounds ?? .zero); root.wantsLayer = true
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 0); frost.frame = root.bounds; frost.autoresizingMask = [.width, .height]; root.addSubview(frost)
        webView.frame = root.bounds; webView.autoresizingMask = [.width, .height]; root.addSubview(webView); contentView = root
    }

    func toggle(from parent: NSWindow) {
        if isVisible, attachedParent === parent { close(); return }
        if let oldParent = attachedParent { oldParent.removeChildWindow(self) }
        attachedParent = parent
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        if webView.url == nil { webView.load(URLRequest(url: marketURL)) }
        makeKeyAndOrderFront(nil)
    }

    private func position(alongside parent: NSWindow) {
        let gap: CGFloat = 2; let width: CGFloat = 380
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let height = min(parent.frame.height, visible.height)
        var x = parent.frame.maxX + gap
        if x + width > visible.maxX { x = parent.frame.minX - width - gap }
        x = max(visible.minX, min(x, visible.maxX - width))
        let y = max(visible.minY, min(parent.frame.minY, visible.maxY - height))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "glanceWidgetMarket",
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "glance.mcreator.ai",
              let body = message.body as? [String: Any],
              (body["type"] as? String) == "installWidget",
              let widgetID = body["widgetID"] as? String,
              widgetID.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil else { return }
        WidgetCatalogClient.shared.fetch(widgetID: widgetID) { result in
            switch result {
            case .success(let manifest): WidgetRegistry.shared.install(manifest)
            case .failure(let error): Logger.info("WidgetMarketPanel: install failed: \(error.localizedDescription)")
            }
        }
    }

    override func close() {
        if let attachedParent { attachedParent.removeChildWindow(self) }
        attachedParent = nil
        orderOut(nil)
    }
}
