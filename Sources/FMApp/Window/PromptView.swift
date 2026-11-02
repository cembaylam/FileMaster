import AppKit

/// Single-line input bar above the status bar (yazi's input popup): rename, create, find, filter, go to path.
/// Return submits, Esc cancels, Tab asks `onComplete` for a completion.
@MainActor
final class PromptView: NSVisualEffectView, NSTextFieldDelegate {
    private let label = NSTextField(labelWithString: "")
    private var separator: NSView?
    let field = NSTextField()

    private var onChange: ((String) -> Void)?
    private var onSubmit: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var onComplete: ((String) -> String?)?
    /// Called after the prompt closes either way (BrowserView takes focus back).
    var onEnd: (() -> Void)?

    static let height: CGFloat = 32

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        let line = Canvas()
        line.draw = { NSColor.separatorColor.setFill(); NSRect(x: 0, y: 0, width: 10_000, height: 1).fill() }
        line.autoresizingMask = [.width, .minYMargin]
        line.frame = NSRect(x: 0, y: frame.height - 1, width: frame.width, height: 1)
        separator = line
        addSubview(line)
        addSubview(label)
        addSubview(field)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isActive: Bool { !isHidden }

    override func layout() {
        super.layout()
        separator?.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let lw = ceil(label.intrinsicContentSize.width)
        label.frame = NSRect(x: 12, y: (bounds.height - 16) / 2, width: lw, height: 16)
        field.frame = NSRect(x: label.frame.maxX + 8, y: (bounds.height - 22) / 2,
                             width: bounds.width - label.frame.maxX - 20, height: 22)
    }


    /// `select`: range to select initially (rename selects the stem); nil selects all.
    func begin(_ prompt: String, text: String = "", select: NSRange? = nil,
               onChange: ((String) -> Void)? = nil, onComplete: ((String) -> String?)? = nil,
               onCancel: (() -> Void)? = nil, onSubmit: @escaping (String) -> Void) {
        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onComplete = onComplete
        label.stringValue = prompt
        field.stringValue = text
        isHidden = false
        needsLayout = true
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = select ?? NSRange(location: 0, length: (text as NSString).length)
        }
    }

    private func end() {
        isHidden = true
        onChange = nil
        onSubmit = nil
        onCancel = nil
        onComplete = nil
        onEnd?()
    }

    func cancel() {
        guard isActive else { return }
        let cancel = onCancel
        end()
        cancel?()
    }

    func controlTextDidChange(_ obj: Notification) {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            let submit = onSubmit, text = field.stringValue
            end()
            submit?(text)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        case #selector(NSResponder.insertTab(_:)):
            if let complete = onComplete, let s = complete(field.stringValue) {
                field.stringValue = s
                textView.selectedRange = NSRange(location: (s as NSString).length, length: 0)
                onChange?(s)
            }
            return true
        default:
            return false
        }
    }
}
