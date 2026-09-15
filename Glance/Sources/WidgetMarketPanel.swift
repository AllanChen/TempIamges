import AppKit
import WebKit

final class WidgetMarketPanel: NSPanel, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WidgetMarketPanel()
    private let webView: WKWebView
    private let loadingView = ModularImageLoadingView(frame: .zero)
    private let loadingOverlay = NSView(frame: .zero)
    private weak var attachedParent: NSWindow?
    private let marketURL = URL(string: "https://glance.mcreator.ai/widgets/")!

    private init() {
        let controller = WKUserContentController()
        // The market is hosted remotely, so keep the detail interaction
        // resilient even when an older catalog build is served: clicking a
        // widget card opens a lightweight in-page introduction overlay.
        let detailScript = """
        (() => { const show = (card) => { if (document.querySelector('[data-glance-widget-detail]')) return; const shade=document.createElement('div'); shade.dataset.glanceWidgetDetail='1'; shade.style='position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.72);display:flex;align-items:center;justify-content:center;padding:24px'; const box=document.createElement('div'); box.style='max-width:520px;width:100%;max-height:80vh;overflow:auto;border-radius:20px;padding:24px;background:#18181c;color:#f3eee8;box-shadow:0 20px 60px rgba(0,0,0,.5)'; box.innerHTML=card.innerHTML+'<div style="margin-top:18px;text-align:right"><button style="border:1px solid rgba(255,255,255,.2);border-radius:999px;padding:8px 16px;background:transparent;color:inherit">Close</button></div>'; shade.appendChild(box); shade.onclick=e=>{if(e.target===shade||e.target.tagName==='BUTTON')shade.remove()}; document.body.appendChild(shade); }; document.addEventListener('click',e=>{ const card=e.target.closest('article'); if(card && !e.target.closest('button')) show(card); }); })();
        """
        controller.addUserScript(WKUserScript(source: detailScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 620), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true; isReleasedWhenClosed = false; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        controller.add(self, name: "glanceWidgetMarket")
        let root = NSView(frame: contentView?.bounds ?? .zero); root.wantsLayer = true
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 0); frost.frame = root.bounds; frost.autoresizingMask = [.width, .height]; root.addSubview(frost)
        webView.frame = root.bounds; webView.autoresizingMask = [.width, .height]; root.addSubview(webView)
        loadingOverlay.wantsLayer = true; loadingOverlay.layer?.backgroundColor = PanelStyle.canvas.withAlphaComponent(0.94).cgColor
        loadingOverlay.frame = root.bounds; loadingOverlay.autoresizingMask = [.width, .height]
        loadingView.frame = NSRect(x: (root.bounds.width - ModularImageLoadingView.preferredSize.width) / 2, y: (root.bounds.height - ModularImageLoadingView.preferredSize.height) / 2, width: ModularImageLoadingView.preferredSize.width, height: ModularImageLoadingView.preferredSize.height)
        loadingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        loadingOverlay.addSubview(loadingView); root.addSubview(loadingOverlay); contentView = root
        loadingView.setLoading(true)
    }

    func toggle(from parent: NSWindow) {
        if isVisible, attachedParent === parent { close(); return }
        if let oldParent = attachedParent { oldParent.removeChildWindow(self) }
        attachedParent = parent
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        if webView.url == nil { webView.load(URLRequest(url: marketURL)) }
        else { syncInstalledState() }
        makeKeyAndOrderFront(nil)
    }

    private func position(alongside parent: NSWindow) {
        let gap: CGFloat = 2; let width: CGFloat = 380
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let height = min(parent.frame.height, visible.height)
        // Keep the market attached on the parent's right side. When the
        // parent is close to the screen edge, clamp into the visible frame
        // instead of flipping the panel to the left (which is disorienting
        // and breaks the toolbar -> market spatial relationship).
        let x = max(visible.minX, min(parent.frame.maxX + gap, visible.maxX - width))
        let y = max(visible.minY, min(parent.frame.minY, visible.maxY - height))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "glanceWidgetMarket",
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "glance.mcreator.ai",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let widgetID = body["widgetID"] as? String,
              widgetID.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil else { return }
        if type == "uninstallWidget" {
            WidgetRegistry.shared.uninstall(id: widgetID)
            syncInstalledState()
            return
        }
        guard type == "installWidget" else { return }
        WidgetCatalogClient.shared.fetch(widgetID: widgetID) { result in
            switch result {
            case .success(let manifest):
                WidgetRegistry.shared.install(manifest)
                self.syncInstalledState()
            case .failure(let error): Logger.info("WidgetMarketPanel: install failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncInstalledState() {
        let ids = WidgetRegistry.shared.installed.map { $0.id }
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.glanceSetInstalled && window.glanceSetInstalled(\(json));")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadingView.setLoading(false); loadingOverlay.isHidden = true; syncInstalledState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadingView.setLoading(false); loadingOverlay.isHidden = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadingView.setLoading(false); loadingOverlay.isHidden = true }

    override func close() {
        if let attachedParent { attachedParent.removeChildWindow(self) }
        attachedParent = nil
        orderOut(nil)
    }
}
