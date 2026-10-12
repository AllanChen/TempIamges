import AppKit
import WebKit

/// Shown when the focused item in a mixed session has no inline preview
/// (video, unsupported file, folder): a large type icon over the filename.
final class FilePlaceholderView: NSView {
    weak var dropTarget: MediaDropCanvasView?
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        nameLabel.font = PanelStyle.headline
        nameLabel.textColor = PanelStyle.textSecondary
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }

    func configure(info: MediaInfo) {
        iconView.image = FileTypeIcon.makeImage(for: info, size: CGSize(width: 128, height: 128))
        nameLabel.stringValue = info.filename
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 128
        iconView.frame = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2 + 12,
                                width: size, height: size)
        nameLabel.frame = NSRect(x: 20, y: bounds.midY - size / 2 - 28,
                                 width: bounds.width - 40, height: 20)
    }
}

/// WKWebView is itself a drag destination, so mixed-file sessions must
/// explicitly forward media drops instead of relying on superview bubbling.
final class InspectFileWebView: WKWebView {
    weak var dropTarget: MediaDropCanvasView?

    convenience init() {
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }
}
