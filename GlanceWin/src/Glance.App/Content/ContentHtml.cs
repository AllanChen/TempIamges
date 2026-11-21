using System.Net;
using System.Text.Json;
using Glance.App.Theme;
using Markdig;

namespace Glance.App.Content;

/// <summary>
/// HTML generated for the content viewer (port of macOS <c>wrapMarkdownInHTML</c> and the
/// <c>__tdfind</c> helper). Markdown renders offline with Markdig; colors come from Tokens.xaml.
/// </summary>
internal static class ContentHtml
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder().UseAdvancedExtensions().Build();

    /// <param name="baseHref">Base for relative links/images of a remote document; null for local ones.</param>
    /// <param name="css">From <see cref="MarkdownCss"/> (read on the UI thread; this method can run on any thread).</param>
    public static string MarkdownPage(string markdown, string title, string? baseHref, string css)
    {
        var body = Markdown.ToHtml(markdown, Pipeline);
        var baseTag = baseHref is null ? "" : $"<base href=\"{WebUtility.HtmlEncode(baseHref)}\">";
        // No scripts from the document itself: a README must not be able to read sibling files
        // through the virtual host and send them anywhere. Glance's own find helper is injected by
        // the host and is not subject to the page CSP.
        const string csp = "default-src 'none'; img-src * data: blob:; media-src *; style-src 'unsafe-inline' *; font-src * data:";
        return $$"""
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta http-equiv="Content-Security-Policy" content="{{csp}}">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>{{WebUtility.HtmlEncode(title)}}</title>
              {{baseTag}}
              <style>{{css}}</style>
            </head>
            <body>
            {{body}}
            </body>
            </html>
            """;
    }

    /// <summary>Light reading theme; macOS dark CSS with the palette swapped for the light tokens.</summary>
    public static string MarkdownCss()
    {
        var ui = Ui.UiFont.Source;
        var code = Ui.CodeFont.Source;
        return $$"""
            :root {
              --bg: {{Ui.CssHex("SurfaceColor")}};
              --surface: {{Ui.CssHex("CanvasColor")}};
              --fg: {{Ui.CssHex("TextPrimaryColor")}};
              --muted: {{Ui.CssHex("TextSecondaryColor")}};
              --hairline: {{Ui.CssRgba("TextPrimaryColor", 0.10)}};
              --fill: {{Ui.CssRgba("TextPrimaryColor", 0.06)}};
              --fill-strong: {{Ui.CssRgba("TextPrimaryColor", 0.08)}};
              --accent: {{Ui.CssHex("AccentColor")}};
              --accent-text: {{Ui.CssHex("AccentTextColor")}};
              --selection: {{Ui.CssRgba("AccentColor", 0.30)}};
            }
            * { box-sizing: border-box; }
            body {
              font-family: "Segoe UI Variable Text", {{ui}}, system-ui, sans-serif;
              font-size: 15px; line-height: 1.72;
              color: var(--fg); background: var(--bg);
              max-width: 740px; margin: 0 auto; padding: 40px 28px 64px;
            }
            ::selection { background: var(--selection); }
            h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.6em 0 0.6em; font-weight: 600; letter-spacing: -0.01em; }
            h1 { font-size: 1.9em; border-bottom: 1px solid var(--hairline); padding-bottom: 0.3em; }
            h2 { font-size: 1.5em; border-bottom: 1px solid var(--hairline); padding-bottom: 0.25em; }
            h3 { font-size: 1.25em; }
            h4 { font-size: 1.05em; }
            body > :first-child { margin-top: 0; }
            p, ul, ol, blockquote, table { margin: 0.9em 0; }
            ul, ol { padding-left: 1.4em; }
            li { margin: 0.25em 0; }
            li.task-list-item { list-style: none; }
            li.task-list-item input { margin: 0 0.5em 0 -1.3em; }
            blockquote { border-left: 3px solid var(--accent); padding: 0.2em 0 0.2em 1em; margin-left: 0; color: var(--muted); }
            hr { border: none; border-top: 1px solid var(--hairline); margin: 2em 0; }
            code { font-family: {{code}}, monospace; background: var(--fill-strong); padding: 0.15em 0.4em; border-radius: 5px; font-size: 0.88em; }
            pre { background: var(--surface); border: 1px solid var(--hairline); padding: 14px 16px; border-radius: 10px;
                  white-space: pre-wrap; word-wrap: break-word; overflow-x: auto; line-height: 1.55; }
            pre code { background: transparent; padding: 0; font-size: 0.86em; border: none; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            a { color: var(--accent-text); text-decoration: none; }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
            th, td { border: 1px solid var(--hairline); padding: 7px 12px; text-align: left; }
            th { background: var(--fill); font-weight: 600; }
            tr:nth-child(even) td { background: var(--fill); }
            """;
    }

    /// <summary>Encodes a string as a JavaScript string literal.</summary>
    public static string JsString(string value) => JsonSerializer.Serialize(value);

    /// <summary>
    /// Injected into every document: <c>window.__tdfind</c> with highlight(query) → count,
    /// next()/prev() → index, clear(). Verbatim port of the macOS helper, accent from the tokens.
    /// </summary>
    public static string FindHelperScript()
    {
        var current = Ui.CssHex("AccentColor");
        var other = Ui.CssRgba("AccentColor", 0.40);
        var ink = Ui.CssHex("AccentInkColor");
        return $$"""
            (function(){
              if (window.__tdfind) return;
              const SCROLL_OPTS = { block: 'center', behavior: 'smooth' };
              function clear(self){
                self.marks.forEach(m => {
                  if (m.parentNode) { m.parentNode.replaceChild(document.createTextNode(m.textContent), m); }
                });
                try { document.body.normalize(); } catch(e) {}
                self.marks = [];
                self.current = -1;
              }
              function refresh(self){
                for (let i = 0; i < self.marks.length; i++) {
                  self.marks[i].style.background = (i === self.current) ? '{{current}}' : '{{other}}';
                  self.marks[i].style.color = '{{ink}}';
                }
                if (self.current >= 0 && self.current < self.marks.length) self.marks[self.current].scrollIntoView(SCROLL_OPTS);
              }
              window.__tdfind = {
                marks: [], current: -1,
                clear: function(){ clear(this); },
                highlight: function(query){
                  clear(this);
                  if (!query || !document.body) return 0;
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
                    const text = node.nodeValue, lower = text.toLowerCase();
                    const frag = document.createDocumentFragment();
                    let last = 0, i;
                    while ((i = lower.indexOf(q, last)) !== -1) {
                      if (i > last) frag.appendChild(document.createTextNode(text.slice(last, i)));
                      const mk = document.createElement('mark');
                      mk.className = 'tdfind';
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
            """;
    }

    /// <summary>Content-Type for files served from a Markdown document's folder.</summary>
    public static string MimeType(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".jpg" or ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
        ".svg" => "image/svg+xml",
        ".bmp" => "image/bmp",
        ".ico" => "image/x-icon",
        ".avif" => "image/avif",
        ".css" => "text/css",
        ".mp4" => "video/mp4",
        ".webm" => "video/webm",
        ".mp3" => "audio/mpeg",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2",
        ".ttf" => "font/ttf",
        _ => "application/octet-stream",
    };
}
