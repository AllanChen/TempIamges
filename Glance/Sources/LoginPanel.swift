import AppKit
import WebKit

final class LoginPanel: NSPanel, WKScriptMessageHandler {
    static let shared = LoginPanel()

    private let webView: WKWebView
    private let headerHeight: CGFloat = 48
    private weak var titleLabel: NSTextField?

    private init() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: config)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        contentController.add(self, name: "loginHandler")

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
        titleLabel = titleLbl

        return bar
    }

    @objc private func closeTapped() {
        orderOut(nil)
    }

    func show(at point: NSPoint) {
        loadCurrentState()

        let size = NSSize(width: 400, height: 500)
        let frame = NSRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height), size: size)
        setFrame(frame, display: true)
        showAsKeyPanel()
    }

    func showSignedIn(session: AuthSession) {
        loadAccountPage(session: session)
        showAsKeyPanel()
    }

    func completeSignIn(session: AuthSession) {
        webView.stopLoading()
        orderOut(nil)
    }

    func showAuthError(_ message: String) {
        evaluate("window.GlanceAuth && window.GlanceAuth.setStatus(\(jsString(message)), 'error')")
        if !isVisible {
            loadAuthPage(status: message)
            showAsKeyPanel()
        }
    }

    private func showAsKeyPanel() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "loginHandler",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "google":
            evaluate("window.GlanceAuth.setStatus('Continue in your browser to finish Google sign-in.', 'info')")
            AuthManager.shared.openGoogleSignIn()
            orderOut(nil)

        case "sendEmailCode":
            guard let email = (body["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else {
                evaluate("window.GlanceAuth.setStatus('Enter your email address.', 'error')")
                return
            }
            AuthManager.shared.sendEmailCode(email: email) { [weak self] result in
                switch result {
                case .success:
                    self?.evaluate("window.GlanceAuth.emailCodeSent(\(Self.jsString(email)))")
                case .failure(let error):
                    self?.evaluate("window.GlanceAuth.setStatus(\(Self.jsString(error.localizedDescription)), 'error')")
                    self?.evaluate("window.GlanceAuth.setBusy(false)")
                }
            }

        case "verifyEmailCode":
            let email = (body["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let code = (body["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !email.isEmpty, !code.isEmpty else {
                evaluate("window.GlanceAuth.setStatus('Enter your email and 6 digit code.', 'error')")
                return
            }
            AuthManager.shared.verifyEmailCode(email: email, code: code) { [weak self] result in
                switch result {
                case .success(let session):
                    self?.completeSignIn(session: session)
                case .failure(let error):
                    self?.evaluate("window.GlanceAuth.setStatus(\(Self.jsString(error.localizedDescription)), 'error')")
                    self?.evaluate("window.GlanceAuth.setBusy(false)")
                }
            }

        case "logout":
            AuthManager.shared.signOut()
            loadAuthPage()

        default:
            break
        }
    }

    private func loadCurrentState() {
        if let session = AuthManager.shared.session {
            loadAccountPage(session: session)
        } else {
            loadAuthPage()
        }
    }

    private func loadAuthPage(status: String? = nil) {
        titleLabel?.stringValue = "Sign In"
        let statusScript = status.map { "window.addEventListener('load', function() { window.GlanceAuth.setStatus(\(Self.jsString($0)), 'error'); });" } ?? ""
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
                    background: #f6f7f8;
                    color: #1f2328;
                    min-height: 100vh;
                    padding: 28px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container { width: 100%; max-width: 320px; }
                h1 { font-size: 22px; line-height: 1.2; font-weight: 650; text-align: center; margin-bottom: 8px; }
                p { font-size: 13px; color: #6b7280; text-align: center; margin-bottom: 22px; }
                .btn {
                    width: 100%;
                    min-height: 42px;
                    border-radius: 8px;
                    border: 1px solid #d7dce2;
                    background: #fff;
                    color: #1f2328;
                    font-size: 14px;
                    font-weight: 560;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    gap: 9px;
                    margin-bottom: 12px;
                }
                .btn:hover { background: #f9fafb; }
                .btn:disabled { opacity: 0.55; cursor: default; }
                .btn-primary { background: #14181f; color: #fff; border-color: #14181f; }
                .btn-primary:hover { background: #202631; }
                .divider {
                    display: flex;
                    align-items: center;
                    color: #8a939f;
                    font-size: 12px;
                    margin: 17px 0;
                }
                .divider:before, .divider:after { content: ""; flex: 1; height: 1px; background: #dfe3e8; }
                .divider span { padding: 0 12px; }
                input {
                    width: 100%;
                    height: 40px;
                    padding: 9px 11px;
                    border: 1px solid #d7dce2;
                    border-radius: 8px;
                    background: #fff;
                    font-size: 14px;
                    margin-bottom: 10px;
                    outline: none;
                }
                input:focus { border-color: #2f6fed; box-shadow: 0 0 0 3px rgba(47,111,237,0.14); }
                #codeWrap { display: none; }
                #status {
                    min-height: 36px;
                    border-radius: 8px;
                    padding: 10px 11px;
                    font-size: 12px;
                    line-height: 1.35;
                    color: #6b7280;
                    text-align: center;
                }
                #status.info { background: #eef5ff; color: #2356a3; }
                #status.ok { background: #edf8f0; color: #1d7136; }
                #status.error { background: #fff1f0; color: #b42318; }
                .google-mark { width: 18px; height: 18px; flex: 0 0 auto; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Welcome to Glance</h1>
                <p>Sign in with mcreator to connect this Mac.</p>

                <button class="btn" onclick="GlanceAuth.google()">
                    <svg class="google-mark" viewBox="0 0 24 24">
                        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
                        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                    </svg>
                    Continue with Google
                </button>

                <div class="divider"><span>or</span></div>

                <input type="email" id="email" autocomplete="email" placeholder="Email address">
                <button id="sendBtn" class="btn btn-primary" onclick="GlanceAuth.sendCode()">Send code</button>

                <div id="codeWrap">
                    <input type="text" id="code" inputmode="numeric" maxlength="6" placeholder="6 digit code">
                    <button id="verifyBtn" class="btn btn-primary" onclick="GlanceAuth.verifyCode()">Verify and sign in</button>
                </div>

                <div id="status"></div>
            </div>

            <script>
                window.GlanceAuth = {
                    post(payload) {
                        window.webkit.messageHandlers.loginHandler.postMessage(payload);
                    },
                    google() {
                        this.setStatus('Opening Google sign-in in your browser.', 'info');
                        this.post({ type: 'google' });
                    },
                    sendCode() {
                        const email = document.getElementById('email').value.trim();
                        if (!email) {
                            this.setStatus('Enter your email address.', 'error');
                            return;
                        }
                        this.setBusy(true);
                        this.setStatus('Sending code...', 'info');
                        this.post({ type: 'sendEmailCode', email });
                    },
                    verifyCode() {
                        const email = document.getElementById('email').value.trim();
                        const code = document.getElementById('code').value.trim();
                        if (!email || !/^\\d{6}$/.test(code)) {
                            this.setStatus('Enter the 6 digit code from your email.', 'error');
                            return;
                        }
                        this.setBusy(true);
                        this.setStatus('Verifying code...', 'info');
                        this.post({ type: 'verifyEmailCode', email, code });
                    },
                    emailCodeSent(email) {
                        document.getElementById('email').value = email;
                        document.getElementById('codeWrap').style.display = 'block';
                        document.getElementById('code').focus();
                        this.setBusy(false);
                        this.setStatus('Code sent. Check your email and enter the 6 digit code.', 'ok');
                    },
                    setBusy(isBusy) {
                        document.getElementById('sendBtn').disabled = isBusy;
                        document.getElementById('verifyBtn').disabled = isBusy;
                    },
                    setStatus(message, tone) {
                        const status = document.getElementById('status');
                        status.textContent = message || '';
                        status.className = tone || '';
                    }
                };
                document.addEventListener('keydown', function(event) {
                    if (event.key === 'Enter') {
                        if (document.getElementById('codeWrap').style.display === 'block') {
                            GlanceAuth.verifyCode();
                        } else {
                            GlanceAuth.sendCode();
                        }
                    }
                });
                \(statusScript)
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func loadAccountPage(session: AuthSession) {
        titleLabel?.stringValue = "Account"
        let displayName = session.user.name?.isEmpty == false ? session.user.name! : session.user.email
        let email = session.user.email
        let provider = session.user.authProvider == "google" ? "Google" : "Email"
        let userID = String(session.user.id)
        let expires = formattedDate(session.expiresAt)
        let initial = accountInitial(from: displayName)
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
                    background: #f6f7f8;
                    color: #1f2328;
                    min-height: 100vh;
                    padding: 28px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container { width: 100%; max-width: 320px; }
                .avatar {
                    width: 56px;
                    height: 56px;
                    border-radius: 50%;
                    background: #14181f;
                    color: #fff;
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 24px;
                    font-weight: 650;
                    margin: 0 auto 16px;
                }
                h1 {
                    font-size: 20px;
                    line-height: 1.2;
                    font-weight: 650;
                    text-align: center;
                    margin-bottom: 4px;
                    overflow-wrap: anywhere;
                }
                .email {
                    font-size: 13px;
                    color: #6b7280;
                    text-align: center;
                    line-height: 1.4;
                    margin-bottom: 22px;
                    overflow-wrap: anywhere;
                }
                .info {
                    border: 1px solid #dfe3e8;
                    border-radius: 8px;
                    background: #fff;
                    margin-bottom: 18px;
                    overflow: hidden;
                }
                .row {
                    display: flex;
                    align-items: flex-start;
                    justify-content: space-between;
                    gap: 12px;
                    padding: 11px 12px;
                    border-bottom: 1px solid #edf0f3;
                    font-size: 13px;
                }
                .row:last-child { border-bottom: 0; }
                .label { color: #6b7280; flex: 0 0 auto; }
                .value { color: #1f2328; text-align: right; overflow-wrap: anywhere; min-width: 0; }
                .btn {
                    width: 100%;
                    min-height: 42px;
                    border-radius: 8px;
                    border: 1px solid #d7dce2;
                    background: #fff;
                    color: #1f2328;
                    font-size: 14px;
                    font-weight: 560;
                    cursor: pointer;
                }
                .btn:hover { background: #f9fafb; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="avatar">\(htmlEscape(initial))</div>
                <h1>\(htmlEscape(displayName))</h1>
                <div class="email">\(htmlEscape(email))</div>
                <div class="info">
                    <div class="row"><span class="label">Provider</span><span class="value">\(htmlEscape(provider))</span></div>
                    <div class="row"><span class="label">User ID</span><span class="value">\(htmlEscape(userID))</span></div>
                    <div class="row"><span class="label">Status</span><span class="value">\(htmlEscape(session.user.status.capitalized))</span></div>
                    <div class="row"><span class="label">Session expires</span><span class="value">\(htmlEscape(expires))</span></div>
                </div>
                <button class="btn" onclick="window.webkit.messageHandlers.loginHandler.postMessage({type:'logout'})">Sign out</button>
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func accountInitial(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "U" }
        return String(first).uppercased()
    }

    private func formattedDate(_ value: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: value) ?? plain.date(from: value) else {
            return value
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func jsString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\""
    }

    private func jsString(_ value: String) -> String {
        Self.jsString(value)
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { true }
}
