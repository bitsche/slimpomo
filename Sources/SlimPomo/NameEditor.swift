import AppKit
import SwiftUI
import SlimPomoCore

/// Font and line metrics shared by the task-name text, its editor, and the add field.
enum NameFieldMetrics {
    static let maxLines = 4

    static func font(semibold: Bool = false) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: semibold ? .semibold : .regular)
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Height of the text area for `content` points of text: one line at least, `maxLines` at most.
    static func fieldHeight(content: CGFloat, font: NSFont) -> CGFloat {
        let line = lineHeight(font)
        return min(max(content, line), line * CGFloat(maxLines))
    }
}

/// Where the caret goes when a click lands on a task name drawn as a muted label plus the rest.
@MainActor
enum NameCaret {
    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// UTF-16 offset in the raw name nearest to `x`, measured from the left edge of the drawn name.
    static func offset(in raw: String, x: CGFloat, semibold: Bool) -> Int {
        let parts = TaskName.split(raw)
        var origin: CGFloat = 0
        if let prefix = parts.prefix {
            let width = (prefix as NSString).size(withAttributes: [.font: labelFont]).width
            if x < width + LabelStyle.gap {
                return x < width / 2 ? 0 : parts.restOffset
            }
            origin = width + LabelStyle.gap
        }
        let storage = NSTextStorage(string: parts.rest, attributes: [.font: NameFieldMetrics.font(semibold: semibold)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100_000, height: 100_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        guard layout.numberOfGlyphs > 0 else { return parts.restOffset }
        var fraction: CGFloat = 0
        let index = layout.characterIndex(
            for: NSPoint(x: max(0, x - origin), y: 4),
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let length = parts.rest.utf16.count
        return parts.restOffset + min(length, index + (fraction > 0.5 ? 1 : 0))
    }
}

/// The muted project label in front of a task name.
enum LabelStyle {
    static let gap: CGFloat = 6
}

/// A click target over a task name. A click without movement opens the editor; the label under it keeps drawing.
/// The cursor stays the arrow until the editor is open, and a press that moves 4 pt drags the row instead.
struct NameClickArea: NSViewRepresentable {
    var fullText: String
    var semibold: Bool
    /// The click's x in the name column, or nil for the keyboard.
    var onActivate: (CGFloat?) -> Void

    func makeNSView(context: Context) -> NameClickAreaView {
        let view = NameClickAreaView()
        view.kind = .arrow
        view.setAccessibilityElement(false)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NameClickAreaView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NameClickAreaView) {
        view.onActivate = onActivate
        view.fullText = fullText
        view.semibold = semibold
        view.updateTip()
    }
}

/// Decides whether a name is cut short, and measures it the way the label draws it.
@MainActor
enum NameTruncation {
    static func isTruncated(_ text: String, semibold: Bool, width: CGFloat) -> Bool {
        guard width > 1 else { return false }
        let parts = TaskName.split(text)
        var available = width
        if let prefix = parts.prefix {
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]).width
            available -= prefixWidth + LabelStyle.gap
        }
        let drawn = (parts.rest as NSString).size(withAttributes: [.font: NameFieldMetrics.font(semibold: semibold)]).width
        return drawn > available + 0.5
    }
}

/// Covers a read-only name. It only supplies the tooltip, and only while the name is cut short.
struct NameTipArea: NSViewRepresentable {
    var fullText: String
    var semibold: Bool

    func makeNSView(context: Context) -> NameTipView {
        let view = NameTipView()
        view.setAccessibilityElement(false)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NameTipView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NameTipView) {
        view.fullText = fullText
        view.semibold = semibold
        view.updateTip()
    }
}

final class NameTipView: NSView {
    var fullText = ""
    var semibold = false

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateTip()
    }

    func updateTip() {
        let cut = NameTruncation.isTruncated(fullText, semibold: semibold, width: bounds.width)
        let tip = cut ? fullText : nil
        if toolTip != tip { toolTip = tip }
    }
}

final class NameClickAreaView: PointingHandAnchorView {
    var onActivate: ((CGFloat?) -> Void)?
    var fullText = ""
    var semibold = false
    private var pressedAt: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    func updateTip() {
        let cut = NameTruncation.isTruncated(fullText, semibold: semibold, width: bounds.width)
        let tip = cut ? fullText : nil
        if toolTip != tip { toolTip = tip }
    }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }

    override func layout() {
        super.layout()
        updateTip()
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil }
        guard let pressedAt else { return }
        let moved = hypot(event.locationInWindow.x - pressedAt.x, event.locationInWindow.y - pressedAt.y)
        guard moved < RowDrag.threshold else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onActivate?(convert(pressedAt, from: nil).x)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:
            onActivate?(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

/// A word-wrapping text field for one task name. It grows with its text and reports the height of the text,
/// and the caller caps what it shows. Return submits, Esc cancels, and line breaks never enter the text.
struct NameEditor: NSViewRepresentable {
    @Binding var text: String
    var semibold = false
    var color: NSColor
    /// Two-way focus for a field that is always on screen. Nil for an editor that takes focus once when it appears.
    var focus: Binding<Bool>? = nil
    var autoFocus = false
    /// UTF-16 offset for the first caret. Nil puts it at the end.
    var caret: Int? = nil
    var fieldLabel = "Task name"
    var onHeight: (CGFloat) -> Void = { _ in }
    var onSubmit: () -> Void
    var onCancel: () -> Void = {}
    /// Focus left the field.
    var onEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NameEditorView {
        let view = NameEditorView(font: NameFieldMetrics.font(semibold: semibold), color: color)
        let coordinator = context.coordinator
        view.textView.delegate = coordinator
        view.textView.setAccessibilityLabel(fieldLabel)
        view.autoFocus = autoFocus
        view.initialCaret = caret
        view.syncText(text)
        view.textView.onFocusChange = { [weak coordinator] focused in
            coordinator?.focusChanged(focused)
        }
        view.onHeight = { [weak coordinator] height in
            coordinator?.parent.onHeight(height)
        }
        view.focusWanted = { [weak coordinator] in
            coordinator?.parent.focus?.wrappedValue
        }
        return view
    }

    func updateNSView(_ view: NameEditorView, context: Context) {
        context.coordinator.parent = self
        view.apply(font: NameFieldMetrics.font(semibold: semibold), color: color)
        view.syncText(text)
        view.syncFocus()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NameEditor

        init(_ parent: NameEditor) {
            self.parent = parent
        }

        func focusChanged(_ focused: Bool) {
            Task { @MainActor in
                if let binding = self.parent.focus, binding.wrappedValue != focused {
                    binding.wrappedValue = focused
                }
                if !focused {
                    self.parent.onEnd()
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            (textView.enclosingScrollView?.superview as? NameEditorView)?.reportHeight()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }
            let flat = TaskName.singleLine(replacement)
            if flat == replacement { return true }
            textView.insertText(flat, replacementRange: affectedCharRange)
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertParagraphSeparator(_:)):
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class NameTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    override func paste(_ sender: Any?) {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        insertText(TaskName.singleLine(pasted), replacementRange: selectedRange())
    }
}

final class NameEditorView: NSView {
    let scrollView = NSScrollView()
    let textView: NameTextView
    var onHeight: ((CGFloat) -> Void)?
    var focusWanted: (() -> Bool?)?
    var autoFocus = false
    var initialCaret: Int?

    private var font: NSFont
    private var reportedHeight: CGFloat = -1
    private var tookInitialFocus = false

    init(font: NSFont, color: NSColor) {
        self.font = font
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = NameTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        apply(font: font, color: color)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(font: NSFont, color: NSColor) {
        self.font = font
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [.font: font, .foregroundColor: color]
    }

    func syncText(_ value: String) {
        guard textView.string != value, !textView.hasMarkedText() else { return }
        textView.string = value
        textView.undoManager?.removeAllActions()
        needsLayout = true
    }

    /// Follows the caller's focus flag, checked again when the change runs so a click in between wins.
    func syncFocus() {
        guard window != nil, focusWanted?() != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, let wanted = self.focusWanted?() else { return }
            let isFirst = window.firstResponder === self.textView
            if wanted && !isFirst {
                window.makeFirstResponder(self.textView)
            } else if !wanted && isFirst {
                window.makeFirstResponder(nil)
            }
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let width = max(scrollView.contentSize.width, 1)
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        reportHeight()
        takeInitialFocus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    /// Height of all the text, not capped. The caller decides how much of it shows.
    func reportHeight() {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        layout.ensureLayout(for: container)
        let height = max(NameFieldMetrics.lineHeight(font), ceil(layout.usedRect(for: container).height))
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        Task { @MainActor [weak self] in
            self?.onHeight?(height)
        }
    }

    private func takeInitialFocus() {
        guard autoFocus, !tookInitialFocus, window != nil, bounds.width > 1 else { return }
        tookInitialFocus = true
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.textView)
            let length = self.textView.string.utf16.count
            let place = min(max(self.initialCaret ?? length, 0), length)
            self.textView.setSelectedRange(NSRange(location: place, length: 0))
            self.textView.scrollRangeToVisible(NSRange(location: place, length: 0))
        }
    }
}
