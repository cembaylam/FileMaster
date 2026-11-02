import AppKit
import FMPreview

/// Right column. Hosts one of: directory listing, image, text/hex, or a message.
@MainActor
final class PreviewPaneView: NSView {
    let dirList = FileListView()
    private let imageView = ImageLayerView()
    private let caption = NSTextField(labelWithString: "")
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private let messageLabel = NSTextField(labelWithString: "")

    /// Last text shown, kept so a font size change can re-render it.
    private var lastText: (String, [SyntaxToken])?

    override init(frame: NSRect) {
        super.init(frame: frame)
        dirList.isActive = false

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center

        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = PreviewFont.regular
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textScroll.documentView = textView
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = true
        textScroll.autohidesScrollers = true

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center

        for v in [dirList, imageView, caption, textScroll, messageLabel] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(fontDidChange),
                                               name: PreviewFont.didChange, object: nil)
    }

    @objc private func fontDidChange() {
        guard !textScroll.isHidden, let (s, h) = lastText else { return }
        let origin = textScroll.contentView.bounds.origin
        setText(s, highlights: h)
        textScroll.contentView.scroll(to: origin)
        textScroll.reflectScrolledClipView(textScroll.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let b = bounds
        dirList.frame = b
        textScroll.frame = b
        let captionH: CGFloat = 18
        imageView.frame = NSRect(x: 8, y: 8, width: b.width - 16, height: b.height - 16 - captionH)
        caption.frame = NSRect(x: 8, y: b.height - captionH - 4, width: b.width - 16, height: captionH)
        messageLabel.frame = NSRect(x: 8, y: b.height / 2 - 10, width: b.width - 16, height: 20)
    }

    /// Pixel size an image preview should be decoded at.
    var maxPixel: Int {
        let scale = window?.backingScaleFactor ?? 2
        return Int(max(bounds.width, bounds.height) * scale)
    }

    private func reveal(_ views: NSView...) {
        for v in [dirList, imageView, caption, textScroll, messageLabel] as [NSView] {
            v.isHidden = !views.contains(v)
        }
    }

    func showDirectory() {
        reveal(dirList)
    }

    func showNothing() {
        imageView.image = nil
        reveal()
    }

    func show(_ result: PreviewResult) {
        switch result {
        case let .image(img, text):
            imageView.setZoom(1)
            imageView.image = img.cgImage
            caption.stringValue = text
            reveal(imageView, caption)
        case let .text(s, truncated, highlights):
            setText(truncated ? s + "\n…" : s, highlights: highlights)
        case let .hex(s, total):
            setText(s + (total > 4096 ? "… \(total - 4096) more bytes" : ""), highlights: [])
        case let .message(s):
            imageView.image = nil
            messageLabel.stringValue = s
            reveal(messageLabel)
        }
    }

    private func setText(_ s: String, highlights: [SyntaxToken]) {
        imageView.image = nil
        lastText = (s, highlights)
        let font = PreviewFont.regular
        let attributed = NSMutableAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor,
        ])
        let length = attributed.length
        for t in highlights where Int(t.start) + Int(t.length) <= length {
            attributed.addAttributes(SyntaxTheme.attributes(t.kind, base: font),
                                     range: NSRange(location: Int(t.start), length: Int(t.length)))
        }
        textView.textStorage?.setAttributedString(attributed)
        textView.scroll(.zero)
        reveal(textScroll)
    }

    /// yazi `seek`: scroll the preview by lines.
    func seek(lines: Int) {
        if !dirList.isHidden {
            dirList.scroll(by: lines)
        } else if !textScroll.isHidden {
            let font = PreviewFont.regular
            let lineHeight = font.ascender - font.descender + font.leading
            textScroll.scrollContent(by: CGFloat(lines) * lineHeight)
        }
    }

    var isShowingText: Bool { !textScroll.isHidden }

    /// Viewer zoom: image → magnify, text → preview font size. `direction` +1/-1, 0 = reset.
    func zoom(_ direction: Int) {
        if !imageView.isHidden {
            imageView.setZoom(direction == 0 ? 1 : imageView.zoom * (direction > 0 ? 1.25 : 0.8))
        } else if !textScroll.isHidden {
            PreviewFont.setSize(direction == 0 ? PreviewFont.defaultSize : PreviewFont.size + CGFloat(direction))
        }
    }

    /// Scroll text/hex content by points; `page` uses the visible height.
    func scrollText(by points: CGFloat) { textScroll.scrollContent(by: points) }
    var textPageHeight: CGFloat { textScroll.contentView.bounds.height }
}

extension NSScrollView {
    /// Scroll vertically by `dy` points (positive = towards the end), clamped, for flipped or unflipped documents.
    func scrollContent(by dy: CGFloat) {
        guard let doc = documentView else { return }
        let clip = contentView
        var origin = clip.bounds.origin
        let maxY = max(0, doc.frame.height - clip.bounds.height)
        origin.y = min(max(0, origin.y + (doc.isFlipped ? dy : -dy)), maxY)
        clip.scroll(to: origin)
        reflectScrolledClipView(clip)
    }
}

/// Shows a CGImage via a sublayer's contents (GPU-composited, no NSImage conversion). Zoom scales the
/// sublayer around the center; drag pans while zoomed; trackpad pinch zooms.
@MainActor
final class ImageLayerView: NSView {
    var image: CGImage? { didSet { imageLayer.contents = image } }
    private let imageLayer = CALayer()
    private(set) var zoom: CGFloat = 1
    private var pan = CGPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        imageLayer.bounds = bounds
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        applyTransform()
    }

    func setZoom(_ z: CGFloat) {
        zoom = min(max(z, 1), 32)
        if zoom == 1 { pan = .zero }
        applyTransform()
    }

    private func applyTransform() {
        // Keep the image covering the view: clamp the pan to the zoomed overflow.
        let maxX = bounds.width * (zoom - 1) / 2, maxY = bounds.height * (zoom - 1) / 2
        pan = CGPoint(x: min(max(pan.x, -maxX), maxX), y: min(max(pan.y, -maxY), maxY))
        imageLayer.setAffineTransform(CGAffineTransform(translationX: pan.x, y: pan.y).scaledBy(x: zoom, y: zoom))
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoom > 1 else { return }
        pan.x += event.deltaX
        pan.y += isFlipped ? event.deltaY : -event.deltaY
        applyTransform()
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification))
    }
}
