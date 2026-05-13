import AppKit
import WebKit

/// Standalone window that hosts a WKWebView. Used to display markdown or
/// arbitrary web pages when the user clicks a non-image tile in the preview
/// panel.
final class ContentViewerWindow: NSWindow {
    private let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 640),
                                 configuration: config)
        self.webView = webView

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.center()
        self.title = "TempDisplay"

        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        webView.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        container.addSubview(webView)
        contentView = container
    }

    /// Loads a web page URL directly.
    func loadWebPage(_ url: URL) {
        title = url.host ?? url.absoluteString
        webView.load(URLRequest(url: url))
    }

    /// Fetches markdown text (local or remote) and renders it via marked.js.
    /// Falls back to plain-text preformatted display if the CDN script can't
    /// load (offline, etc.).
    func loadMarkdown(_ url: URL) {
        title = url.lastPathComponent
        Task.detached { [weak self] in
            let text = await Self.fetchMarkdownText(from: url)
            let html = Self.wrapMarkdownInHTML(text)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
            }
        }
    }

    private static func fetchMarkdownText(from url: URL) async -> String {
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

    /// Escapes the markdown source so it survives being injected into the
    /// HTML host, then lets marked.js (loaded from a CDN) render it
    /// client-side. If the script fails to load we still show the raw text
    /// in a styled `<pre>` block.
    private static func wrapMarkdownInHTML(_ markdown: String) -> String {
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
