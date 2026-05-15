import AppKit
import WebKit

final class LoginPanel: NSPanel {
    static let shared = LoginPanel()

    private let webView: WKWebView
    private let headerHeight: CGFloat = 48

    private init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        isMovableByWindowBackground = true

        buildLayout()
    }

    private func buildLayout() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let navBar = buildNavBar(width: 400)
        navBar.frame = NSRect(x: 0, y: 500 - headerHeight, width: 400, height: headerHeight)
        navBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(navBar)

        let webFrame = NSRect(x: 0, y: 0, width: 400, height: 500 - headerHeight)
        webView.frame = webFrame
        webView.autoresizingMask = [.width, .height]
        root.addSubview(webView)

        contentView = root
    }

    private func buildNavBar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .recessed
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = .labelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        bar.addSubview(closeBtn)

        let titleLbl = NSTextField(labelWithString: "Sign In")
        titleLbl.textColor = .labelColor
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.alignment = .center
        titleLbl.frame = NSRect(x: 48, y: (headerHeight - 18) / 2, width: width - 96, height: 18)
        titleLbl.autoresizingMask = [.width]
        bar.addSubview(titleLbl)

        return bar
    }

    @objc private func closeTapped() {
        orderOut(nil)
    }

    func show(at point: NSPoint) {
        let loginURL = Preferences.shared.loginURL
        if let url = loginURL, !url.isEmpty {
            if let target = URL(string: url) {
                webView.load(URLRequest(url: target))
            } else {
                loadDefaultPage()
            }
        } else {
            loadDefaultPage()
        }

        let size = NSSize(width: 400, height: 500)
        let frame = NSRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height), size: size)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    private func loadDefaultPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: #f5f5f5;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    min-height: 100vh;
                    padding: 20px;
                }
                .container {
                    background: white;
                    border-radius: 12px;
                    padding: 32px;
                    width: 100%;
                    max-width: 320px;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
                }
                h1 {
                    font-size: 20px;
                    font-weight: 600;
                    color: #1a1a1a;
                    margin-bottom: 8px;
                    text-align: center;
                }
                p {
                    font-size: 13px;
                    color: #666;
                    text-align: center;
                    margin-bottom: 24px;
                }
                .btn {
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100%;
                    padding: 10px 16px;
                    border-radius: 8px;
                    border: 1px solid #e0e0e0;
                    background: white;
                    font-size: 14px;
                    font-weight: 500;
                    cursor: pointer;
                    margin-bottom: 12px;
                    transition: background 0.2s;
                }
                .btn:hover {
                    background: #f8f8f8;
                }
                .btn img {
                    width: 18px;
                    height: 18px;
                    margin-right: 8px;
                }
                .divider {
                    display: flex;
                    align-items: center;
                    margin: 16px 0;
                    color: #999;
                    font-size: 12px;
                }
                .divider::before, .divider::after {
                    content: '';
                    flex: 1;
                    height: 1px;
                    background: #e0e0e0;
                }
                .divider span {
                    padding: 0 12px;
                }
                input {
                    width: 100%;
                    padding: 10px 12px;
                    border: 1px solid #e0e0e0;
                    border-radius: 8px;
                    font-size: 14px;
                    margin-bottom: 12px;
                    outline: none;
                }
                input:focus {
                    border-color: #4285f4;
                }
                .btn-primary {
                    background: #1a1a1a;
                    color: white;
                    border: none;
                }
                .btn-primary:hover {
                    background: #333;
                }
                .hint {
                    margin-top: 16px;
                    font-size: 12px;
                    color: #999;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Welcome</h1>
                <p>Sign in to sync your settings</p>

                <button class="btn" onclick="handleGoogleSignIn()">
                    <svg viewBox="0 0 24 24" width="18" height="18">
                        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
                        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                    </svg>
                    Sign in with Google
                </button>

                <div class="divider"><span>or</span></div>

                <input type="email" id="email" placeholder="Email address">
                <input type="password" id="password" placeholder="Password">
                <button class="btn btn-primary" onclick="handleEmailSignIn()">Sign In</button>

                <div class="hint">
                    Configure login URL in Preferences to use your own auth service.
                </div>
            </div>

            <script>
                function handleGoogleSignIn() {
                    window.webkit.messageHandlers.loginHandler.postMessage({type: 'google'});
                }
                function handleEmailSignIn() {
                    const email = document.getElementById('email').value;
                    const password = document.getElementById('password').value;
                    if (!email || !password) {
                        alert('Please enter both email and password');
                        return;
                    }
                    window.webkit.messageHandlers.loginHandler.postMessage({type: 'email', email: email, password: password});
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
