import AppKit
import WebKit

/// Standalone window that displays markdown, plain-text formats (txt/json/xml),
/// or arbitrary web pages from a preview-panel tile.
///
/// - Webpages render in a WKWebView and are read-only.
/// - .txt/.json/.xml open straight into an editable NSTextView with the
///   content pretty-printed (JSON / XML) where applicable.
/// - .markdown defaults to a rendered WKWebView view; an "Edit" toggle
///   swaps to the raw source in NSTextView.
/// - For local files a Save button writes the buffer back to disk. Remote
///   files are editable in-memory but the Save button is disabled.
final class ContentViewerWindow: NSWindow, NSTextFieldDelegate {
    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let toolbarBar = NSView()
    private let saveButton = NSButton()
    private let toggleButton = NSButton()  // Edit ↔ View for markdown

    // WebView find UI
    private let webFindBar = NSView()
    private let webFindField = NSTextField()
    private let webFindCountLabel = NSTextField(labelWithString: "")
    private var webFindMatchCount = 0
    private var webFindCurrentIndex = -1

    private enum Kind { case webpage, markdown, text }
    private var kind: Kind = .webpage
    private var currentURL: URL?
    private var isEditing: Bool = false

    init() {
        // Standard desktop browser dimensions — fits most modern websites
        // comfortably without dominating the screen.
        let initialSize = NSSize(width: 1100, height: 720)
        let config = WKWebViewConfiguration()
        // Inject the find helper so every loaded document has window.__tdfind.
        let findScript = WKUserScript(
            source: Self.findHelperJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findScript)
        webView = WKWebView(frame: .zero, configuration: config)

        let tv = NSTextView(frame: .zero)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        // Built-in find-bar support: ⌘F opens an inline find bar across the
        // top of the scroll view; ⌘G / ⌘⇧G cycle next / previous matches.
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        textView = tv

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.documentView = tv
        textScroll = scroll

        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.center()
        self.title = "TempDisplay"

        buildLayout()
        showWebView()  // default
    }

    // MARK: - Public load API

    /// Loads a web page URL directly (read-only).
    func loadWebPage(_ url: URL) {
        currentURL = url
        kind = .webpage
        title = url.host ?? url.absoluteString
        webView.load(URLRequest(url: url))
        saveButton.isHidden = true
        toggleButton.isHidden = true
        showWebView()
    }

    /// Loads a markdown file. Starts in rendered (view) mode with an Edit
    /// toggle that swaps to the raw source.
    func loadMarkdown(_ url: URL) {
        currentURL = url
        kind = .markdown
        title = url.lastPathComponent
        isEditing = false
        toggleButton.isHidden = false
        toggleButton.title = "Edit"
        saveButton.isHidden = true
        renderMarkdownView(url: url)
    }

    /// Loads a plain-text file (.txt / .json / .xml). Opens straight into
    /// editable mode with JSON/XML pretty-printed.
    func loadText(_ url: URL) {
        currentURL = url
        kind = .text
        title = url.lastPathComponent
        isEditing = true
        toggleButton.isHidden = true
        saveButton.isHidden = !url.isFileURL  // only local files are savable
        loadEditableText(url: url, prettyPrint: true)
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let content = contentView else { return }
        let bounds = content.bounds
        let toolbarH: CGFloat = 36

        // Toolbar across the top.
        toolbarBar.frame = NSRect(x: 0, y: bounds.height - toolbarH,
                                width: bounds.width, height: toolbarH)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        let sep = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        sep.autoresizingMask = [.width]
        toolbarBar.addSubview(sep)

        // Toggle (Edit ↔ View) — only shown for markdown.
        toggleButton.bezelStyle = .rounded
        toggleButton.title = "Edit"
        toggleButton.target = self
        toggleButton.action = #selector(toggleEditTapped)
        toggleButton.frame = NSRect(x: bounds.width - 170, y: 6, width: 70, height: 24)
        toggleButton.autoresizingMask = [.minXMargin]
        toggleButton.isHidden = true
        toolbarBar.addSubview(toggleButton)

        // Save — only when editing a local file.
        saveButton.bezelStyle = .rounded
        saveButton.title = "Save"
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.frame = NSRect(x: bounds.width - 90, y: 6, width: 70, height: 24)
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.isHidden = true
        toolbarBar.addSubview(saveButton)

        content.addSubview(toolbarBar)

        // Body — webView + textScroll occupy the area below the toolbar.
        let bodyFrame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: bounds.height - toolbarH)
        webView.frame = bodyFrame
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)

        textScroll.frame = bodyFrame
        textScroll.autoresizingMask = [.width, .height]
        // Track the scroll view's content width so the text view word-wraps.
        textView.textContainer?.containerSize = NSSize(
            width: bodyFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        content.addSubview(textScroll)

        // ─── Web find bar (overlays the top edge of the web view) ───────
        let findBarH: CGFloat = 36
        webFindBar.frame = NSRect(
            x: 0, y: bodyFrame.maxY - findBarH,
            width: bodyFrame.width, height: findBarH
        )
        webFindBar.autoresizingMask = [.width, .minYMargin]
        webFindBar.wantsLayer = true
        webFindBar.layer?.backgroundColor = NSColor(white: 0.97, alpha: 0.98).cgColor
        webFindBar.isHidden = true

        let findSep = NSView(frame: NSRect(x: 0, y: 0, width: bodyFrame.width, height: 1))
        findSep.wantsLayer = true
        findSep.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        findSep.autoresizingMask = [.width]
        webFindBar.addSubview(findSep)

        webFindField.placeholderString = "Find in page"
        webFindField.frame = NSRect(x: 12, y: 6, width: 240, height: 24)
        webFindField.delegate = self
        webFindBar.addSubview(webFindField)

        webFindCountLabel.font = NSFont.systemFont(ofSize: 11)
        webFindCountLabel.textColor = .secondaryLabelColor
        webFindCountLabel.frame = NSRect(x: 260, y: 9, width: 80, height: 18)
        webFindBar.addSubview(webFindCountLabel)

        let prevBtn = NSButton(title: "‹", target: self, action: #selector(webFindPrev))
        prevBtn.bezelStyle = .rounded
        prevBtn.frame = NSRect(x: bodyFrame.width - 140, y: 6, width: 32, height: 24)
        prevBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(prevBtn)

        let nextBtn = NSButton(title: "›", target: self, action: #selector(webFindNext))
        nextBtn.bezelStyle = .rounded
        nextBtn.frame = NSRect(x: bodyFrame.width - 102, y: 6, width: 32, height: 24)
        nextBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(nextBtn)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(hideWebFindBar))
        doneBtn.bezelStyle = .rounded
        doneBtn.frame = NSRect(x: bodyFrame.width - 60, y: 6, width: 50, height: 24)
        doneBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(doneBtn)

        content.addSubview(webFindBar)
    }

    private func showWebView() {
        webView.isHidden = false
        textScroll.isHidden = true
    }

    private func showTextView() {
        webView.isHidden = true
        textScroll.isHidden = false
    }

    // MARK: - Loading helpers

    private func renderMarkdownView(url: URL) {
        Task.detached { [weak self] in
            let raw = await Self.fetchMarkdownText(from: url)
            let html = Self.wrapMarkdownInHTML(raw)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
            }
        }
    }

    private func loadEditableText(url: URL, prettyPrint: Bool) {
        Task.detached { [weak self] in
            let raw = await Self.fetchMarkdownText(from: url)
            let body: String
            if prettyPrint {
                let ext = url.pathExtension.lowercased()
                switch ext {
                case "json": body = Self.prettyPrintJSON(raw) ?? raw
                case "xml":  body = Self.prettyPrintXML(raw)  ?? raw
                default:     body = raw
                }
            } else {
                body = raw
            }
            await MainActor.run {
                self?.textView.string = body
                self?.showTextView()
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleEditTapped() {
        guard kind == .markdown, let url = currentURL else { return }
        isEditing.toggle()
        if isEditing {
            toggleButton.title = "View"
            saveButton.isHidden = !url.isFileURL
            // Show raw markdown source in the editor (no pretty-printing).
            loadEditableText(url: url, prettyPrint: false)
        } else {
            toggleButton.title = "Edit"
            saveButton.isHidden = true
            renderMarkdownView(url: url)
        }
    }

    @objc private func saveTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        let body = textView.string
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            // Quick visual ack — flip the title for ~1.5s, then back.
            saveButton.title = "Saved ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.saveButton.title = "Save"
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't save \(url.lastPathComponent)"
            alert.beginSheetModal(for: self, completionHandler: nil)
        }
    }

    // MARK: - Static content helpers (reused by PreviewPanel)

    /// Reads the raw markdown source from a local file or remote URL.
    /// Exposed so other views (e.g. an in-panel markdown push) can reuse it.
    static func fetchMarkdownText(from url: URL) async -> String {
        if url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "# Could not read file\n\nPath: `\(url.path)`"
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)
                ?? "# Could not decode content\n\nURL: \(url.absoluteString)"
        } catch {
            return "# Failed to load\n\n\(error.localizedDescription)\n\n`\(url.absoluteString)`"
        }
    }

    /// Pretty-print a JSON document. Returns nil if the input isn't valid JSON.
    static func prettyPrintJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let pretty = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Pretty-print an XML document via Foundation's XMLDocument.
    static func prettyPrintXML(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveAll]) else {
            return nil
        }
        let xmlData = doc.xmlData(options: [.nodePrettyPrint])
        return String(data: xmlData, encoding: .utf8)
    }

    // MARK: - Web find

    /// Intercept ⌘F / ⌘G / ⌘⇧G when the web view is showing. The text-view
    /// path already gets ⌘F through `usesFindBar = true`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers ?? ""
            if key == "f", !webView.isHidden {
                showWebFindBar()
                return true
            }
            if key == "g", !webFindBar.isHidden {
                if event.modifierFlags.contains(.shift) { webFindPrev(nil) }
                else                                    { webFindNext(nil) }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func showWebFindBar() {
        webFindBar.isHidden = false
        webFindBar.frame.origin.y = (contentView?.bounds.height ?? 0) - 36 /* toolbar */ - webFindBar.bounds.height
        makeFirstResponder(webFindField)
        webFindField.selectText(nil)
        if !webFindField.stringValue.isEmpty {
            runWebFind(query: webFindField.stringValue)
        }
    }

    @objc private func hideWebFindBar() {
        webFindBar.isHidden = true
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.clear()", completionHandler: nil)
        webFindMatchCount = 0
        webFindCurrentIndex = -1
        updateWebFindCountLabel()
        makeFirstResponder(webView)
    }

    private func runWebFind(query: String) {
        let jsQuery = Self.jsStringLiteral(query)
        let js = "window.__tdfind && window.__tdfind.highlight(\(jsQuery))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let count = (result as? Int) ?? 0
            self.webFindMatchCount = count
            self.webFindCurrentIndex = count > 0 ? 0 : -1
            self.updateWebFindCountLabel()
        }
    }

    @objc private func webFindNext(_ sender: Any?) {
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.next()") { [weak self] r, _ in
            guard let self = self, let idx = r as? Int, idx >= 0 else { return }
            self.webFindCurrentIndex = idx
            self.updateWebFindCountLabel()
        }
    }

    @objc private func webFindPrev(_ sender: Any?) {
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.prev()") { [weak self] r, _ in
            guard let self = self, let idx = r as? Int, idx >= 0 else { return }
            self.webFindCurrentIndex = idx
            self.updateWebFindCountLabel()
        }
    }

    private func updateWebFindCountLabel() {
        if webFindMatchCount == 0 {
            webFindCountLabel.stringValue = webFindField.stringValue.isEmpty ? "" : "0 results"
        } else {
            webFindCountLabel.stringValue = "\(webFindCurrentIndex + 1) / \(webFindMatchCount)"
        }
    }

    // NSTextFieldDelegate — incremental search + Esc/Enter handling.
    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf === webFindField else { return }
        runWebFind(query: tf.stringValue)
    }

    func control(_ control: NSControl, textView fieldEditor: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard control === webFindField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideWebFindBar()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            webFindNext(nil)
            return true
        }
        return false
    }

    /// Encode an arbitrary string as a JS string literal (handles quotes,
    /// backslashes, newlines, control chars). Used when interpolating user
    /// input into evaluateJavaScript calls.
    private static func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// JS injected at document-end on every page load. Exposes
    /// `window.__tdfind` with `highlight(query)`, `next()`, `prev()`,
    /// `clear()`.
    private static let findHelperJS: String = """
    (function(){
      if (window.__tdfind) return;
      const SCROLL_OPTS = { block: 'center', behavior: 'smooth' };
      function clear(self){
        self.marks.forEach(m => {
          if (m.parentNode) {
            const t = document.createTextNode(m.textContent);
            m.parentNode.replaceChild(t, m);
          }
        });
        // Coalesce adjacent text nodes back together.
        try { document.body.normalize(); } catch(e) {}
        self.marks = [];
        self.current = -1;
      }
      function refresh(self){
        for (let i = 0; i < self.marks.length; i++) {
          self.marks[i].style.background = (i === self.current) ? '#ff9800' : '#ffe066';
          self.marks[i].style.color = '#000';
        }
        if (self.current >= 0 && self.current < self.marks.length) {
          self.marks[self.current].scrollIntoView(SCROLL_OPTS);
        }
      }
      window.__tdfind = {
        marks: [],
        current: -1,
        clear: function(){ clear(this); },
        highlight: function(query){
          clear(this);
          if (!query) return 0;
          const q = String(query).toLowerCase();
          if (q.length === 0) return 0;
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function(n){
              const p = n.parentElement;
              if (!p) return NodeFilter.FILTER_REJECT;
              if (p.closest('script, style, noscript')) return NodeFilter.FILTER_REJECT;
              if (p.classList && p.classList.contains('tdfind')) return NodeFilter.FILTER_REJECT;
              return NodeFilter.FILTER_ACCEPT;
            }
          });
          const targets = [];
          let n;
          while ((n = walker.nextNode())) {
            if (n.nodeValue && n.nodeValue.toLowerCase().indexOf(q) !== -1) targets.push(n);
          }
          const marks = [];
          targets.forEach(node => {
            const text = node.nodeValue;
            const lower = text.toLowerCase();
            const frag = document.createDocumentFragment();
            let last = 0, i;
            while ((i = lower.indexOf(q, last)) !== -1) {
              if (i > last) frag.appendChild(document.createTextNode(text.slice(last, i)));
              const mk = document.createElement('mark');
              mk.className = 'tdfind';
              mk.style.background = '#ffe066';
              mk.style.color = '#000';
              mk.textContent = text.slice(i, i + q.length);
              frag.appendChild(mk);
              marks.push(mk);
              last = i + q.length;
            }
            if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
            if (node.parentNode) node.parentNode.replaceChild(frag, node);
          });
          this.marks = marks;
          this.current = marks.length > 0 ? 0 : -1;
          refresh(this);
          return marks.length;
        },
        next: function(){
          if (this.marks.length === 0) return -1;
          this.current = (this.current + 1) % this.marks.length;
          refresh(this);
          return this.current;
        },
        prev: function(){
          if (this.marks.length === 0) return -1;
          this.current = (this.current - 1 + this.marks.length) % this.marks.length;
          refresh(this);
          return this.current;
        }
      };
    })();
    """

    /// Wrap markdown source in an HTML host page that renders via marked.js
    /// from a CDN (falls back to plain-text display when offline).
    static func wrapMarkdownInHTML(_ markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                   max-width: 760px; margin: 32px auto; padding: 0 24px;
                   line-height: 1.65; color: #1f1f1f; }
            h1, h2, h3, h4 { line-height: 1.25; margin-top: 1.5em; }
            h1 { border-bottom: 1px solid #ddd; padding-bottom: 0.3em; }
            p, ul, ol, blockquote { margin: 0.85em 0; }
            blockquote { border-left: 3px solid #d0d0d0; padding-left: 1em; color: #555; }
            code { font-family: ui-monospace, "SF Mono", Menlo, monospace;
                   background: #f3f3f3; padding: 2px 6px; border-radius: 4px;
                   font-size: 0.92em; }
            pre { background: #f6f8fa; padding: 14px 16px; border-radius: 6px;
                  overflow-x: auto; line-height: 1.5; }
            pre code { background: transparent; padding: 0; font-size: 0.88em; }
            img { max-width: 100%; height: auto; border-radius: 4px; }
            a { color: #0a66c2; text-decoration: none; }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; margin: 1em 0; }
            th, td { border: 1px solid #ddd; padding: 6px 12px; }
            th { background: #f6f8fa; }
            @media (prefers-color-scheme: dark) {
              body { background: #1c1c1c; color: #e5e5e5; }
              h1 { border-color: #333; }
              blockquote { border-color: #444; color: #aaa; }
              code { background: #2a2a2a; }
              pre { background: #1a1a1a; }
              a { color: #6cb6ff; }
              th, td { border-color: #333; }
              th { background: #2a2a2a; }
            }
          </style>
        </head>
        <body>
          <pre id="raw" style="display:none">\(escaped)</pre>
          <div id="rendered"></div>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <script>
            (function() {
              var raw = document.getElementById('raw').textContent;
              var target = document.getElementById('rendered');
              if (typeof marked === 'object' && typeof marked.parse === 'function') {
                target.innerHTML = marked.parse(raw);
              } else if (typeof marked === 'function') {
                target.innerHTML = marked(raw);
              } else {
                var pre = document.createElement('pre');
                pre.textContent = raw;
                target.appendChild(pre);
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}
