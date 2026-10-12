import AppKit
import SwiftUI
import SlimPomoCore

// MARK: - The tag area of a row

/// Where each row's tag area sits, so the picker can open below it. Only the row whose picker is open reports its frame.
struct TagAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension TagStyle {
    /// The `+ TAG` hint of an untagged row.
    static let hintFontSize: CGFloat = 9.5
    /// Least space between the hint's text and its border.
    static let hintPadding: CGFloat = 2
    /// Space between the hint's right border and the name, inside the column.
    static let hintGap: CGFloat = 4
    static let hintHeight: CGFloat = 18
    /// Height of the click area and the hover background of a tagged row.
    static let areaHeight: CGFloat = 22
    /// How far the hover background reaches past the tag's text on each side.
    static let plateOutset: CGFloat = 4

    @MainActor
    static var hintTextWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: hintFontSize, weight: .regular)
        return ceil(("+ TAG" as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The hint fills its column, less the gap before the name, so it never reaches into the name. A column too narrow for
    /// the text (a one-letter tag) lets it grow just enough to hold it.
    @MainActor
    static func hintWidth(column: CGFloat) -> CGFloat {
        max(column - hintGap, hintTextWidth + hintPadding * 2 + 2)
    }
}

/// The subtle hover background behind a row's tag. The tag's own look does not change.
struct TagHoverPlate: View {
    var tag: String
    var column: CGFloat

    var body: some View {
        HoverPlate(cornerRadius: 4, color: Theme.hoverWashNS)
            .frame(width: TagArea.textWidth(tag, column: column) + TagStyle.plateOutset * 2, height: TagStyle.areaHeight)
            .offset(x: -TagStyle.plateOutset)
            .allowsHitTesting(false)
    }
}

enum TagArea {
    /// The width the tag's text takes in a column: the label itself, cut short by a narrow column.
    @MainActor
    static func textWidth(_ tag: String, column: CGFloat) -> CGFloat {
        min(TagStyle.labelWidth(tag), max(0, column - TagStyle.columnGap))
    }
}

/// The click target of a row's tag column, drawn over the row at the column's place. A tagged row shows the tag's hover
/// background and the hand; an untagged row shows `+ TAG` while it is hovered. A click without 4 pt of movement opens the
/// picker, and a press that moves still drags the row. Where the list has no tag column the slot has no width and no target:
/// it only marks the start of the name for the picker that "Add tag…" opens.
struct TagSlot: View {
    var model: AppModel
    var id: UUID
    var tag: String?
    /// The row's tag column. Zero when the list has none, or while a tagged row's name is edited.
    var column: CGFloat
    /// False while the row is lifted, edited, or part of the tour, and while a row is held.
    var interactive: Bool
    /// The row shows its hover details.
    var rowHovered: Bool
    /// The row's hover background, so the hint covers the name under it.
    var hintFill: Color

    @FocusState private var focused: Bool

    private var clickable: Bool { interactive && column > 0 }
    private var active: Bool { model.tagPickerID == id }

    private var spoken: String {
        tag.map { "Tag \($0), change tag" } ?? "Add tag"
    }

    private var areaWidth: CGFloat {
        if let tag { return TagArea.textWidth(tag, column: column) + TagStyle.plateOutset * 2 }
        return max(column, TagStyle.hintWidth(column: column))
    }

    private var areaOffset: CGFloat { tag == nil ? 0 : -TagStyle.plateOutset }

    var body: some View {
        ZStack(alignment: .leading) {
            if clickable {
                if tag == nil {
                    hint
                }
                TagClickArea(onClick: open)
                    .frame(width: areaWidth, height: tag == nil ? RowGrid.height : TagStyle.areaHeight)
                    .overlay {
                        if model.focusVisible(focused) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Theme.link, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(x: areaOffset)
            }
        }
        .frame(width: column, height: RowGrid.height, alignment: .leading)
        .anchorPreference(key: TagAnchorKey.self, value: .bounds) { anchor in
            active ? [id: anchor] : [:]
        }
        .focusable(clickable, interactions: .activate)
        .focused($focused)
        .keyboardFocusOnly($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            open()
            return .handled
        }
        .onKeyPress(.space) {
            open()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(!clickable)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the tag list")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open() }
    }

    /// `+ TAG`, in the tag column, only while the row is hovered.
    private var hint: some View {
        Text("+ TAG")
            .font(.system(size: TagStyle.hintFontSize).monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: TagStyle.hintWidth(column: column), height: TagStyle.hintHeight)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(hintFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.lineField, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            .opacity(rowHovered ? 1 : 0)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: rowHovered)
            .allowsHitTesting(false)
    }

    private func open() {
        guard clickable else { return }
        model.openTagPicker(id: id)
    }
}

struct TagClickArea: NSViewRepresentable {
    var onClick: () -> Void

    func makeNSView(context: Context) -> TagClickAreaView {
        let view = TagClickAreaView()
        view.setAccessibilityElement(false)
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: TagClickAreaView, context: Context) {
        nsView.onClick = onClick
    }
}

/// Takes the click on mouse up, and only when the pointer stayed within the drag threshold. A press that moves further
/// belongs to the row drag.
final class TagClickAreaView: PointingHandAnchorView {
    var onClick: (() -> Void)?
    private var pressedAt: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        guard !AppRuntime.model.isTouring else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
        if !AppRuntime.model.isTouring { NSCursor.pointingHand.set() }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil }
        guard let pressedAt, !AppRuntime.model.isTouring else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let moved = hypot(event.locationInWindow.x - pressedAt.x, event.locationInWindow.y - pressedAt.y)
        guard moved < RowDrag.threshold, inside else { return }
        onClick?()
    }
}

// MARK: - The picker

enum TagPickerMetrics {
    static let width: CGFloat = 210
    static let rowHeight: CGFloat = 28
    static let maxVisible = 8
    static let padding: CGFloat = 6
    static let fieldHeight: CGFloat = 28
    static let gap: CGFloat = 4
    /// A 1 pt line with 4 pt above and below.
    static let separator: CGFloat = 9
    /// Distance from the tag area, and from the window edge.
    static let offset: CGFloat = 4
    static let margin: CGFloat = 8

    static func listHeight(_ existing: Int) -> CGFloat {
        CGFloat(min(existing, maxVisible)) * rowHeight
    }

    static func height(existing: Int, creates: Bool) -> CGFloat {
        padding + fieldHeight + gap + listHeight(existing) + (creates ? rowHeight : 0) + separator + rowHeight + padding
    }

    /// Below the tag area, or above it when the window has no room below. Always inside the window.
    static func origin(anchor: CGRect, size: CGSize, height: CGFloat) -> CGPoint {
        let x = min(max(margin, anchor.minX), max(margin, size.width - width - margin))
        var y = anchor.maxY + offset
        if y + height > size.height - margin {
            let above = anchor.minY - offset - height
            y = above >= margin ? above : max(margin, size.height - height - margin)
        }
        return CGPoint(x: x, y: y)
    }
}

/// The picker over the window: a catcher that closes it on a click outside, and the popover itself.
struct TagPickerOverlay: View {
    @Bindable var model: AppModel
    var rowID: UUID
    var anchor: CGRect
    var size: CGSize

    var body: some View {
        let choices = model.tagChoices
        let existing = choices.existingCount
        let height = TagPickerMetrics.height(existing: existing, creates: choices.createName != nil)
        let origin = TagPickerMetrics.origin(anchor: anchor, size: size, height: height)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.closeTagPicker() } // cursor-exempt: dismisses the picker, not a visible control
                .accessibilityHidden(true)
            TagPickerPanel(model: model, rowID: rowID, choices: choices, existing: existing)
                .frame(width: TagPickerMetrics.width, height: height)
                .contentShape(Rectangle())
                .offset(x: origin.x, y: origin.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .transition(.opacity)
    }
}

private struct TagPickerPanel: View {
    @Bindable var model: AppModel
    var rowID: UUID
    var choices: TagChoices
    var existing: Int

    private var currentTag: String? { model.tag(ofRow: rowID) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.bottom, TagPickerMetrics.gap)
            list
            if let name = choices.createName {
                TagChoiceRow(
                    title: "Create \u{201C}\(name)\u{201D}",
                    leading: .plus,
                    checked: false,
                    selected: model.tagSelection == existing,
                    spoken: "Create tag \(name)"
                ) {
                    model.pickTag(name)
                }
            }
            Rectangle()
                .fill(Theme.popoverBorder)
                .frame(height: 1)
                .padding(.vertical, 4)
                .accessibilityHidden(true)
            TagChoiceRow(
                title: "Remove tag",
                leading: .none,
                checked: false,
                selected: false,
                enabled: currentTag != nil,
                disabledHelp: "This task has no tag",
                spoken: "Remove tag"
            ) {
                model.removeTagFromPickedRow()
            }
        }
        .padding(TagPickerMetrics.padding)
        .background(Theme.popover)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.popoverBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: Theme.popoverShadow, radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose a tag")
        .accessibilityAddTraits(.isModal)
        .onExitCommand { model.closeTagPicker() }
    }

    private var searchField: some View {
        TagSearchField(
            text: model.tagQuery,
            onChange: { model.setTagQuery($0) },
            onMove: { model.moveTagSelection(by: $0) },
            onSubmit: { model.commitTagSelection() },
            onCancel: { model.closeTagPicker() }
        )
        .padding(.horizontal, 8)
        .frame(height: TagPickerMetrics.fieldHeight)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.bgField)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.lineField, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var list: some View {
        if existing > 0 {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(choices.entries.prefix(existing).enumerated()), id: \.offset) { index, entry in
                            TagChoiceRow(
                                title: entry.tag,
                                leading: .dot(Theme.tag(model.tagColorIndex(entry.tag))),
                                checked: entry.tag == currentTag,
                                selected: model.tagSelection == index,
                                spoken: entry.tag == currentTag ? "\(entry.tag), current tag" : entry.tag
                            ) {
                                model.pickTag(entry.tag)
                            }
                            .id(index)
                        }
                    }
                }
                .scrollIndicators(existing > TagPickerMetrics.maxVisible ? .automatic : .never)
                .frame(height: TagPickerMetrics.listHeight(existing))
                .onChange(of: model.tagSelection) { _, index in
                    guard let index, index < existing else { return }
                    proxy.scrollTo(index)
                }
            }
        }
    }
}

private struct TagChoiceRow: View {
    enum Leading {
        case dot(Color)
        case plus
        case none
    }

    var title: String
    var leading: Leading
    var checked: Bool
    var selected: Bool
    var enabled = true
    var disabledHelp: String? = nil
    var spoken: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leadingMark
                    .frame(width: 10)
                Text(title)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.link)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: TagPickerMetrics.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected && enabled ? Theme.popoverSelected : Color.clear)
            }
            .overlay {
                if enabled {
                    HoverPlate(cornerRadius: 6, color: Theme.hoverWashNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PointingHandButtonStyle(enabled: enabled))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .modifier(OptionalHelp(text: enabled ? nil : disabledHelp))
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var leadingMark: some View {
        switch leading {
        case .dot(let color):
            Circle().fill(color).frame(width: 8, height: 8)
        case .plus:
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.link)
        case .none:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

private struct OptionalHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

// MARK: - The search field

/// The picker's search field, focused when it opens. Text is forced to the tag rule: uppercase, no spaces or colons, at
/// most 12 characters. ↑ and ↓ move the highlight, Return applies it, Esc closes.
struct TagSearchField: NSViewRepresentable {
    var text: String
    var onChange: (String) -> Void
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TagTextField {
        let field = TagTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.textColor = Theme.textPrimaryRGB.nsColor
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.contentType = nil
        field.placeholderAttributedString = NSAttributedString(
            string: "Search or create tag",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: Theme.textTertiaryRGB.nsColor,
            ]
        )
        field.setAccessibilityLabel("Search or create a tag")
        if #available(macOS 15.2, *) {
            field.allowsWritingTools = false
        }
        field.isAutomaticTextCompletionEnabled = false
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: TagTextField, context: Context) {
        context.coordinator.parent = self
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if field.stringValue != text, !composing {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TagSearchField

        init(_ parent: TagSearchField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView else { return }
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            if #available(macOS 15.0, *) {
                editor.writingToolsBehavior = .none
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let clean = TaskName.sanitizedTag(field.stringValue)
            if clean != field.stringValue {
                field.stringValue = clean
            }
            parent.onChange(clean)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                return true
            default:
                return false
            }
        }
    }
}

final class TagTextField: NSTextField {
    private var tookFocus = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !tookFocus, window != nil else { return }
        tookFocus = true
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
