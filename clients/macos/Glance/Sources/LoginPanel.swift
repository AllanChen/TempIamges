import AppKit
import WebKit

final class LoginPanel: NSPanel, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = LoginPanel()

    private let webView: WKWebView
    private let loadingIndicator = FocusSweepLoadingView(frame: .zero)
    /// 静 Shizuka window size (Figma "35 · Sign in", 480 × 600).
    private static let panelSize = NSSize(width: 480, height: 600)
    private let loadFailedView = LoadFailedAnimationView(frame: .zero)
    private let headerHeight: CGFloat = PanelStyle.titlebarHeight
    private weak var titleLabel: NSTextField?

    private init() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        PanelStyle.styleWebScrollbars(in: config)
        webView = WKWebView(frame: .zero, configuration: config)

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        webView.navigationDelegate = self

        contentController.add(self, name: "loginHandler")

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        buildLayout()
    }

    private func buildLayout() {
        let width = Self.panelSize.width
        let height = Self.panelSize.height
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        // Figma window chrome: ink/1 fill, 1px line/strong border, 12px radius.
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = PanelStyle.surface.cgColor
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.themed(PanelStyle.Sumi.lineStrong, PanelStyle.Washi.lineStrong).cgColor

        let navBar = buildNavBar(width: width)
        navBar.frame = NSRect(x: 0, y: height - headerHeight, width: width, height: headerHeight)
        navBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(navBar)

        let webFrame = NSRect(x: 0, y: 0, width: width, height: height - headerHeight)
        webView.frame = webFrame
        webView.autoresizingMask = [.width, .height]
        root.addSubview(webView)

        loadingIndicator.frame = NSRect(
            x: webFrame.midX - FocusSweepLoadingView.preferredSize.width / 2,
            y: webFrame.midY - FocusSweepLoadingView.preferredSize.height / 2,
            width: FocusSweepLoadingView.preferredSize.width,
            height: FocusSweepLoadingView.preferredSize.height
        )
        loadingIndicator.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        root.addSubview(loadingIndicator)

        loadFailedView.frame = NSRect(
            x: webFrame.midX - LoadFailedAnimationView.preferredSize.width / 2,
            y: webFrame.midY - LoadFailedAnimationView.preferredSize.height / 2,
            width: LoadFailedAnimationView.preferredSize.width,
            height: LoadFailedAnimationView.preferredSize.height
        )
        loadFailedView.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        loadFailedView.isHidden = true
        root.addSubview(loadFailedView)

        contentView = root
    }

    private func buildNavBar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        // The Figma title bar is part of the ink/1 window surface: no fill, no rule.
        bar.layer?.backgroundColor = PanelStyle.surface.cgColor

        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .recessed
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = PanelStyle.textSecondary
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        bar.addSubview(closeBtn)

        let titleLbl = NSTextField(labelWithString: "Sign In".localized)
        // Figma "Account" title: Inter Medium 13, text/2, centered.
        titleLbl.textColor = PanelStyle.textSecondary
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
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

        let size = Self.panelSize
        let frame = ScreenManager.shared.centeredFrame(for: size, near: point)
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

    private func showLoading() {
        loadFailedView.isHidden = true
        loadingIndicator.setLoading(true)
    }

    private func hideLoading() {
        loadingIndicator.setLoading(false)
    }

    private func showLoadFailed() {
        loadingIndicator.setLoading(false)
        loadFailedView.isHidden = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        showLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailed()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadFailed()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "loginHandler",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        #if MAS
        case "apple":
            AppleSignIn.shared.start(from: self) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success: self.orderOut(nil)
                case .failure(let error):
                    self.evaluate("window.GlanceAuth.setStatus(\(Self.jsString(error.localizedDescription)), 'error')")
                }
            }
        #endif
        case "google":
            evaluate("window.GlanceAuth.setStatus(\(Self.jsString("Continue in your browser to finish Google sign-in.".localized)), 'info')")
            AuthManager.shared.openGoogleSignIn()
            orderOut(nil)

        case "sendEmailCode":
            guard let email = (body["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else {
                evaluate("window.GlanceAuth.setStatus(\(Self.jsString("Enter your email address.".localized)), 'error')")
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
                evaluate("window.GlanceAuth.setStatus(\(Self.jsString("Enter your email and 6 digit code.".localized)), 'error')")
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
            AuthManager.shared.refreshAccount { [weak self] result in
                guard let self, self.isVisible else { return }
                if case .success = result, let updated = AuthManager.shared.session {
                    self.loadAccountPage(session: updated)
                } else if !AuthManager.shared.isSignedIn { self.loadAuthPage() }
            }
        } else {
            loadAuthPage()
        }
    }

    // MARK: - 静 Shizuka page styling

    /// CSS color for a theme token, so the HTML pages follow Sumi / Washi.
    private static func css(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "rgba(%ld,%ld,%ld,%.3f)",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()),
                      c.alphaComponent)
    }

    /// Theme tokens interpolated from `PanelStyle` (Sumi on dark, Washi on light)
    /// plus the base type and control styles shared by both pages.
    private static let baseCSS: String = {
        let t = { (dark: NSColor, light: NSColor) in css(PanelStyle.themed(dark, light)) }
        typealias S = PanelStyle.Sumi
        typealias W = PanelStyle.Washi
        return """
        :root {
            --ink-1: \(t(S.ink1, W.ink1));
            --ink-2: \(t(S.ink2, W.ink2));
            --ink-3: \(t(S.ink3, W.ink3));
            --ink-4: \(t(S.ink4, W.ink4));
            --line-hair: \(t(S.line, W.line));
            --line-strong: \(t(S.lineStrong, W.lineStrong));
            --text-1: \(t(S.text1, W.text1));
            --text-2: \(t(S.text2, W.text2));
            --text-3: \(t(S.text3, W.text3));
            --text-4: \(t(S.text4, W.text4));
            --accent: \(css(PanelStyle.accent));
            --accent-ink: \(css(PanelStyle.accentInk));
            --accent-hover: \(css(PanelStyle.accentHover));
            --shu: \(t(S.shu, W.shu));
            --font-ui: -apple-system, BlinkMacSystemFont, sans-serif;
            --font-title: "Hiragino Mincho ProN", "Hiragino Mincho Pro", serif;
            --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { height: 100%; }
        body {
            font-family: var(--font-ui);
            background: var(--ink-1);
            color: var(--text-1);
            -webkit-font-smoothing: antialiased;
        }
        .container {
            width: 100%;
            min-height: 100%;
            padding: 40px 48px 24px;
            display: flex;
            flex-direction: column;
        }
        h1 {
            font-family: var(--font-title);
            font-size: 28px;
            line-height: 36px;
            font-weight: 400;
            color: var(--text-1);
            overflow-wrap: anywhere;
        }
        .btn {
            height: 32px;
            padding: 0 16px;
            border-radius: 6px;
            border: 0;
            background: var(--ink-3);
            color: var(--text-1);
            font-family: var(--font-ui);
            font-size: 13px;
            font-weight: 500;
            line-height: 32px;
            white-space: nowrap;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }
        .btn:hover { background: var(--ink-4); }
        .btn:disabled { opacity: 0.55; cursor: default; }
        .btn:disabled:hover { background: var(--ink-3); }
        .btn-primary { background: var(--accent); color: var(--accent-ink); }
        .btn-primary:hover { background: var(--accent-hover); }
        .btn-primary:disabled:hover { background: var(--accent); }
        .btn:focus-visible, .link:focus-visible { outline: 1px solid var(--text-2); outline-offset: 2px; }
        .link {
            border: 0;
            background: none;
            padding: 0;
            font-family: var(--font-ui);
            font-size: 12px;
            line-height: 15px;
            color: var(--text-3);
            cursor: pointer;
            text-align: left;
        }
        .link:hover { color: var(--text-1); }
        .link:disabled { opacity: 0.55; cursor: default; }
        .link:disabled:hover { color: var(--text-3); }
        """
    }()

    private func loadAuthPage(status: String? = nil) {
        showLoading()
        titleLabel?.stringValue = "Sign In".localized
        let statusScript = status.map { "window.addEventListener('load', function() { window.GlanceAuth.setStatus(\(Self.jsString($0)), 'error'); });" } ?? ""
        let codePlaceholder = htmlEscape("6 digit code".localized)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                \(Self.baseCSS)
                h1 { margin-bottom: 8px; }
                .sub { font-size: 13px; line-height: 20px; color: var(--text-2); margin-bottom: 32px; }
                .btn-block { width: 100%; }
                .divider {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    margin: 20px 0;
                    font-size: 12px;
                    line-height: 15px;
                    color: var(--text-3);
                    white-space: nowrap;
                }
                .divider:before, .divider:after { content: ""; flex: 1; height: 1px; background: var(--line-hair); }
                input#email {
                    display: block;
                    width: 100%;
                    height: 36px;
                    padding: 9px 12px;
                    border: 1px solid var(--line-hair);
                    border-radius: 8px;
                    background: var(--ink-2);
                    color: var(--text-1);
                    font-family: var(--font-ui);
                    font-size: 13px;
                    outline: none;
                }
                input#email::placeholder { color: var(--text-3); }
                input#email:focus { border-color: var(--text-2); }
                #codeWrap { display: none; margin-top: 10px; }
                .cells { position: relative; display: flex; gap: 8px; height: 48px; }
                .cell {
                    flex: 1 1 0;
                    min-width: 0;
                    height: 48px;
                    border: 1px solid var(--line-hair);
                    border-radius: 8px;
                    background: var(--ink-2);
                    color: var(--text-1);
                    font-family: var(--font-mono);
                    font-size: 18px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    overflow: hidden;
                    pointer-events: none;
                }
                .cell.active, .cell.selected { border-color: var(--text-2); }
                /* The real field stays a single input (same value, paste,
                   backspace and arrow keys); the cells only mirror it. */
                input#code {
                    position: absolute;
                    inset: 0;
                    width: 100%;
                    height: 100%;
                    opacity: 0;
                    border: 0;
                    font-size: 18px;
                    cursor: text;
                }
                #status {
                    margin-top: 10px;
                    font-size: 12px;
                    line-height: 18px;
                    color: var(--text-3);
                    overflow-wrap: anywhere;
                }
                #status:empty { display: none; }
                #status.info, #status.ok { color: var(--text-2); }
                #status.error { color: var(--shu); }
                .actions { display: flex; align-items: center; gap: 8px; margin-top: 24px; }
                .actions .spacer { flex: 1; }
                #sendBtn { width: 100%; }
                #verifyBtn { display: none; }
                body.code-sent #verifyBtn { display: inline-flex; }
                body.code-sent .actions .spacer { display: block; }
                body:not(.code-sent) .actions .spacer { display: none; }
                body.code-sent #sendBtn {
                    width: auto;
                    height: auto;
                    padding: 0;
                    border: 0;
                    background: none;
                    font-size: 12px;
                    font-weight: 400;
                    line-height: 15px;
                    color: var(--text-3);
                }
                body.code-sent #sendBtn:hover { color: var(--text-1); }
                body.code-sent #sendBtn:disabled:hover { color: var(--text-3); }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>\(htmlEscape("Sign in to Glance".localized))</h1>
                <p class="sub">\(htmlEscape("Connect this Mac.".localized))</p>

                \(appleButtonHTML)<button class="btn btn-primary btn-block" onclick="GlanceAuth.google()">\(htmlEscape("Continue with Google".localized))</button>

                <div class="divider"><span>\(htmlEscape("Or use an email code".localized))</span></div>

                <input type="email" id="email" autocomplete="email" placeholder="\(htmlEscape("Email address".localized))">

                <div id="codeWrap">
                    <div class="cells">
                        <div class="cell"></div><div class="cell"></div><div class="cell"></div>
                        <div class="cell"></div><div class="cell"></div><div class="cell"></div>
                        <input type="text" id="code" inputmode="numeric" maxlength="6" placeholder="\(codePlaceholder)" aria-label="\(codePlaceholder)">
                    </div>
                </div>

                <div id="status"></div>

                <div class="actions">
                    <button id="sendBtn" class="btn" onclick="GlanceAuth.sendCode()">\(htmlEscape("Send code".localized))</button>
                    <span class="spacer"></span>
                    <button id="verifyBtn" class="btn" onclick="GlanceAuth.verifyCode()">\(htmlEscape("Verify and sign in".localized))</button>
                </div>
            </div>

            <script>
                window.GlanceAuth = {
                    post(payload) {
                        window.webkit.messageHandlers.loginHandler.postMessage(payload);
                    },
                    apple() {
                        this.setStatus('', 'info');
                        this.post({ type: 'apple' });
                    },
                    google() {
                        this.setStatus(\(Self.jsString("Opening Google sign-in in your browser.".localized)), 'info');
                        this.post({ type: 'google' });
                    },
                    sendCode() {
                        const email = document.getElementById('email').value.trim();
                        if (!email) {
                            this.setStatus(\(Self.jsString("Enter your email address.".localized)), 'error');
                            return;
                        }
                        this.setBusy(true);
                        this.setStatus(\(Self.jsString("Sending code...".localized)), 'info');
                        this.post({ type: 'sendEmailCode', email });
                    },
                    verifyCode() {
                        const email = document.getElementById('email').value.trim();
                        const code = document.getElementById('code').value.trim();
                        if (!email || !/^\\d{6}$/.test(code)) {
                            this.setStatus(\(Self.jsString("Enter the 6 digit code from your email.".localized)), 'error');
                            return;
                        }
                        this.setBusy(true);
                        this.setStatus(\(Self.jsString("Verifying code...".localized)), 'info');
                        this.post({ type: 'verifyEmailCode', email, code });
                    },
                    emailCodeSent(email) {
                        document.getElementById('email').value = email;
                        document.getElementById('codeWrap').style.display = 'block';
                        document.body.classList.add('code-sent');
                        document.getElementById('sendBtn').textContent = \(Self.jsString("Resend code".localized));
                        document.getElementById('code').focus();
                        this.setBusy(false);
                        this.setStatus(\(Self.jsString("Code sent. Check your email and enter the 6 digit code.".localized)), 'ok');
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
                (function() {
                    const input = document.getElementById('code');
                    const cells = Array.prototype.slice.call(document.querySelectorAll('.cell'));
                    function render() {
                        const value = input.value;
                        const focused = document.activeElement === input;
                        const start = input.selectionStart == null ? value.length : input.selectionStart;
                        const end = input.selectionEnd == null ? start : input.selectionEnd;
                        const caret = Math.min(start, cells.length - 1);
                        cells.forEach(function(cell, index) {
                            cell.textContent = value.charAt(index);
                            cell.classList.toggle('active', focused && start === end && index === caret);
                            cell.classList.toggle('selected', focused && start !== end && index >= start && index < end);
                        });
                    }
                    ['input', 'focus', 'blur', 'keyup', 'click', 'select'].forEach(function(name) {
                        input.addEventListener(name, render);
                    });
                    document.addEventListener('selectionchange', render);
                    render();
                })();
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
        showLoading()
        titleLabel?.stringValue = "Account".localized
        let displayName = session.user.name?.isEmpty == false ? session.user.name! : session.user.email
        let email = session.user.email
        let provider = session.user.authProvider == "google" ? "Google" : "Email"
        let userID = String(session.user.id)
        let expires = formattedDate(session.expiresAt)
        let initial = accountInitial(from: displayName)
        let statusLabel = htmlEscape("Status".localized)
        let statusValue = htmlEscape(session.user.status.capitalized.localized)
        let expiresLabel = htmlEscape("Session expires".localized)
        let expiresValue = htmlEscape(expires)
        let statusRow = session.user.status.isDisplayableValue
            ? "<div class=\"row\"><span class=\"label\">\(statusLabel)</span><span class=\"value\">\(statusValue)</span></div>"
            : ""
        let expiresRow = expires.isDisplayableValue
            ? "<div class=\"row\"><span class=\"label\">\(expiresLabel)</span><span class=\"value\">\(expiresValue)</span></div>"
            : ""
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                \(Self.baseCSS)
                .profile { display: flex; align-items: center; gap: 10px; min-width: 0; }
                .avatar {
                    width: 28px;
                    height: 28px;
                    flex: 0 0 28px;
                    border-radius: 14px;
                    background: var(--ink-4);
                    color: var(--text-1);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 12px;
                    font-weight: 500;
                }
                .who { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
                .name { font-size: 13px; color: var(--text-1); overflow-wrap: anywhere; }
                .email { font-size: 11px; color: var(--text-3); overflow-wrap: anywhere; }
                .eyebrow {
                    margin-top: 40px;
                    font-family: var(--font-mono);
                    font-size: 11px;
                    letter-spacing: 1.1px;
                    text-transform: uppercase;
                    color: var(--text-3);
                }
                .balance { display: flex; align-items: baseline; gap: 12px; margin-top: 14px; }
                .amount {
                    font-family: var(--font-title);
                    font-size: 56px;
                    line-height: 64px;
                    font-weight: 400;
                    color: var(--text-1);
                }
                .unit { font-size: 15px; color: var(--text-2); }
                .info { margin-top: 32px; border-top: 1px solid var(--line-hair); }
                .row {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    gap: 16px;
                    padding: 11px 0;
                    border-bottom: 1px solid var(--line-hair);
                }
                .label { font-size: 13px; color: var(--text-2); flex: 0 0 auto; }
                .value {
                    font-family: var(--font-mono);
                    font-size: 12px;
                    color: var(--text-1);
                    text-align: right;
                    overflow-wrap: anywhere;
                    min-width: 0;
                }
                .footer { margin-top: auto; padding-top: 24px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="profile">
                    <div class="avatar">\(htmlEscape(initial))</div>
                    <div class="who">
                        <div class="name">\(htmlEscape(displayName))</div>
                        <div class="email">\(htmlEscape(email))</div>
                    </div>
                </div>
                <div class="eyebrow">\(htmlEscape("Credits".localized))</div>
                <div class="balance">
                    <span class="amount">\(session.user.credits.map(String.init) ?? "—")</span>
                    <span class="unit">\(htmlEscape("credits".localized))</span>
                </div>
                <div class="info">
                    <div class="row"><span class="label">\(htmlEscape("Provider".localized))</span><span class="value">\(htmlEscape(provider))</span></div>
                    <div class="row"><span class="label">\(htmlEscape("User ID".localized))</span><span class="value">\(htmlEscape(userID))</span></div>
                    \(statusRow)
                    \(expiresRow)
                </div>
                <div class="footer">
                    <button class="link" onclick="window.webkit.messageHandlers.loginHandler.postMessage({type:'logout'})">\(htmlEscape("Sign out".localized))</button>
                </div>
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
        formatter.locale = Locale(identifier: Preferences.shared.appLanguage.rawValue)
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

    /// App Store build: Sign in with Apple above Google, at the same size
    /// (guideline 4.8), in Apple's black-or-white style with the Apple logo.
    private var appleButtonHTML: String {
        #if MAS
        let dark = AppleSignIn.buttonStyle == .white
        return """
        <button class="btn btn-block" style="margin-bottom: 8px; background: \(dark ? "#fff" : "#000"); color: \(dark ? "#000" : "#fff");" onclick="GlanceAuth.apple()">\u{F8FF} \(htmlEscape("Continue with Apple".localized))</button>
        """
        #else
        return ""
        #endif
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
