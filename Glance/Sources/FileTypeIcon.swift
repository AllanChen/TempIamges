import AppKit

/// Programmatically-drawn colored icon for a file kind. Style is loosely
/// inspired by VSCode's Material / Seti icon themes: a rounded square in a
/// language-specific colour with a short identifier glyph centred on top.
///
/// We draw at a fixed canvas size and let the tile's NSImageView scale —
/// the design is flat, so up- or down-scaling keeps its appearance.
enum FileTypeIcon {
    struct Style {
        let backgroundColor: NSColor
        let symbol: String
        let symbolColor: NSColor
        /// 0–1 multiplier on the canvas width; lets compact symbols ("M↓",
        /// "{ }") sit larger than verbose ones ("HTML").
        let fontFraction: CGFloat
        /// Bold weight by default; some glyphs read better at .heavy.
        let fontWeight: NSFont.Weight
    }

    static func style(for info: MediaInfo) -> Style {
        // Muted palette — each colour is the original vivid hue lerped 35%
        // toward neutral grey (0.5, 0.5, 0.5). Keeps the hue recognisable
        // but takes the heat out of the saturation.
        let ext = (info.filename as NSString).pathExtension.lowercased()
        switch info.kind {
        case .markdown:
            return Style(
                backgroundColor: NSColor(red: 0.38, green: 0.57, blue: 0.65, alpha: 1),
                symbol: "M↓",
                symbolColor: .white,
                fontFraction: 0.34,
                fontWeight: .bold
            )
        case .text:
            return textStyle(ext: ext)
        case .webPage:
            return Style(
                backgroundColor: NSColor(red: 0.28, green: 0.58, blue: 0.69, alpha: 1),
                symbol: "WEB",
                symbolColor: .white,
                fontFraction: 0.28,
                fontWeight: .bold
            )
        case .image:
            return Style(
                backgroundColor: NSColor(red: 0.53, green: 0.44, blue: 0.68, alpha: 1),
                symbol: "IMG",
                symbolColor: .white,
                fontFraction: 0.28,
                fontWeight: .bold
            )
        case .video:
            return Style(
                backgroundColor: NSColor(red: 0.78, green: 0.43, blue: 0.41, alpha: 1),
                symbol: "▶",
                symbolColor: .white,
                fontFraction: 0.42,
                fontWeight: .bold
            )
        case .pdf:
            return Style(
                backgroundColor: NSColor(red: 0.72, green: 0.36, blue: 0.32, alpha: 1),
                symbol: "PDF",
                symbolColor: .white,
                fontFraction: 0.32,
                fontWeight: .heavy
            )
        case .other:
            return otherStyle(ext: ext)
        case .folder:
            return Style(
                backgroundColor: NSColor(red: 0.40, green: 0.55, blue: 0.72, alpha: 1),
                symbol: "📁",
                symbolColor: .white,
                fontFraction: 0.38,
                fontWeight: .bold
            )
        }
    }

    /// Per-language colour and label for code/text files. Distinctive icons
    /// for json / xml; everything else gets a neutral slate badge with the
    /// extension text so the user can still tell files apart at a glance.
    private static func textStyle(ext: String) -> Style {
        switch ext {
        case "json":
            return Style(
                backgroundColor: NSColor(red: 0.80, green: 0.70, blue: 0.32, alpha: 1),
                symbol: "{ }",
                symbolColor: NSColor(white: 0.18, alpha: 1),
                fontFraction: 0.36, fontWeight: .heavy
            )
        case "xml":
            return Style(
                backgroundColor: NSColor(red: 0.76, green: 0.48, blue: 0.30, alpha: 1),
                symbol: "</>",
                symbolColor: .white,
                fontFraction: 0.30, fontWeight: .heavy
            )
        case "html", "htm":
            return Style(
                backgroundColor: NSColor(red: 0.78, green: 0.46, blue: 0.32, alpha: 1),
                symbol: "HTML",
                symbolColor: .white,
                fontFraction: 0.24, fontWeight: .bold
            )
        case "css", "scss", "sass", "less", "styl":
            return Style(
                backgroundColor: NSColor(red: 0.32, green: 0.50, blue: 0.70, alpha: 1),
                symbol: "CSS",
                symbolColor: .white,
                fontFraction: 0.28, fontWeight: .bold
            )
        case "js", "mjs", "cjs", "jsx":
            return Style(
                backgroundColor: NSColor(red: 0.80, green: 0.70, blue: 0.32, alpha: 1),
                symbol: "JS",
                symbolColor: NSColor(white: 0.18, alpha: 1),
                fontFraction: 0.32, fontWeight: .heavy
            )
        case "ts", "tsx":
            return Style(
                backgroundColor: NSColor(red: 0.30, green: 0.50, blue: 0.72, alpha: 1),
                symbol: "TS",
                symbolColor: .white,
                fontFraction: 0.32, fontWeight: .heavy
            )
        case "py":
            return Style(
                backgroundColor: NSColor(red: 0.34, green: 0.55, blue: 0.46, alpha: 1),
                symbol: "PY",
                symbolColor: .white,
                fontFraction: 0.32, fontWeight: .heavy
            )
        case "swift":
            return Style(
                backgroundColor: NSColor(red: 0.78, green: 0.45, blue: 0.30, alpha: 1),
                symbol: "SW",
                symbolColor: .white,
                fontFraction: 0.32, fontWeight: .heavy
            )
        default:
            // Generic code/text — slate background, extension text as badge.
            return Style(
                backgroundColor: NSColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1),
                symbol: badgeText(forExt: ext, fallback: "TXT"),
                symbolColor: .white,
                fontFraction: fontFraction(forBadge: ext, fallback: "TXT"),
                fontWeight: .bold
            )
        }
    }

    /// "Other" (non-previewable) files — neutral grey card with the file
    /// extension text. The whole tile click reveals the file in Finder.
    private static func otherStyle(ext: String) -> Style {
        return Style(
            backgroundColor: NSColor(red: 0.46, green: 0.48, blue: 0.52, alpha: 1),
            symbol: badgeText(forExt: ext, fallback: "FILE"),
            symbolColor: .white,
            fontFraction: fontFraction(forBadge: ext, fallback: "FILE"),
            fontWeight: .bold
        )
    }

    /// Uppercased extension trimmed to 4 chars, or a fallback if missing.
    private static func badgeText(forExt ext: String, fallback: String) -> String {
        let upper = ext.uppercased()
        if upper.isEmpty { return fallback }
        return upper.count > 4 ? String(upper.prefix(4)) : upper
    }

    /// Scales the badge font down for longer extension text so it doesn't
    /// overrun the badge bounds.
    private static func fontFraction(forBadge ext: String, fallback: String) -> CGFloat {
        let s = ext.isEmpty ? fallback : ext
        switch s.count {
        case 0...2: return 0.34
        case 3:     return 0.28
        default:    return 0.22
        }
    }

    /// Render the icon at `size`. Returned image draws a rounded-square badge
    /// (~78% of the canvas) centred on a transparent background, so the tile
    /// background shows through the corners.
    static func makeImage(for info: MediaInfo, size: CGSize) -> NSImage {
        let style = style(for: info)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        let inset: CGFloat = size.width * 0.11
        let rect = NSRect(
            x: inset, y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )
        let radius = size.width * 0.18

        // Drop a subtle "paper" highlight at the top so the badge reads as a
        // tangible card rather than a flat block.
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        style.backgroundColor.setFill()
        backgroundPath.fill()

        // Highlight strip across the top edge.
        let highlightHeight = rect.height * 0.18
        let highlightRect = NSRect(
            x: rect.minX, y: rect.maxY - highlightHeight,
            width: rect.width, height: highlightHeight
        )
        NSGraphicsContext.saveGraphicsState()
        backgroundPath.setClip()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: highlightRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Bottom shadow band, same trick.
        let shadowHeight = rect.height * 0.16
        let shadowRect = NSRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: shadowHeight
        )
        NSGraphicsContext.saveGraphicsState()
        backgroundPath.setClip()
        NSColor.black.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: shadowRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Symbol text, centred. Use a fixed-design weight so it scales with
        // the canvas (smaller tiles get a smaller glyph).
        let fontSize = max(10, size.width * style.fontFraction)
        let font = NSFont.systemFont(ofSize: fontSize, weight: style.fontWeight)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.symbolColor,
            .paragraphStyle: para,
            .kern: 0.5
        ]
        let text = style.symbol as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: rect.midX - textSize.width / 2,
                // Optical-centre nudge — the cap-height baseline sits slightly
                // above the geometric centre.
                y: rect.midY - textSize.height / 2 - size.height * 0.01
            ),
            withAttributes: attrs
        )

        return img
    }
}
