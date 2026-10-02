import AppKit
import SwiftUI
import SlimPomoCore

/// Look and measure of a tag, the project label in front of a task name. Display only: the stored name keeps its text.
enum TagStyle {
    static let fontSize: CGFloat = 10.5
    /// 0.06 em of the font size.
    static let tracking: CGFloat = fontSize * 0.06
    /// Space between the widest label and the name column.
    static let columnGap: CGFloat = 8
    static let minColumn: CGFloat = 28
    /// A tag in Done and History is quieter.
    static let doneStrength = 0.6

    @MainActor private static let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)

    @MainActor private static var widths: [String: CGFloat] = [:]

    @MainActor
    static func labelWidth(_ tag: String) -> CGFloat {
        if let known = widths[tag] { return known }
        let width = ceil((tag as NSString).size(withAttributes: [.font: font, .kern: tracking]).width)
        widths[tag] = width
        return width
    }

    /// The column every row gets when any row shows a tag: the widest label plus 8 pt, at least 28 pt. Zero without tags.
    /// A label is never cut, so a long one widens the column instead of being clamped.
    @MainActor
    static func columnWidth<S: Sequence>(for names: S) -> CGFloat where S.Element == String {
        var widest: CGFloat = 0
        var seen = Set<String>()
        for name in names {
            guard let tag = TaskName.tag(of: name), seen.insert(tag).inserted else { continue }
            widest = max(widest, labelWidth(tag))
        }
        guard widest > 0 else { return 0 }
        return max(minColumn, widest + columnGap)
    }
}

private struct TagColumnKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Width of the tag column in the rows below. Zero when no row shows a tag.
    var tagColumn: CGFloat {
        get { self[TagColumnKey.self] }
        set { self[TagColumnKey.self] = newValue }
    }
}

/// A tag in its color. In the main window a click focuses the tag; everywhere, a right-click changes its color.
struct TagLabel: View {
    var tag: String
    var model: AppModel
    /// 1 in the queue and LATER, `TagStyle.doneStrength` in Done and History.
    var strength = 1.0
    /// False in History, where a click does nothing.
    var focusable = true

    private var index: Int { model.tagColorIndex(tag) }
    private var focused: Bool { model.tagFocus == tag }

    var body: some View {
        Text(tag)
            .font(.system(size: TagStyle.fontSize, weight: .semibold).monospacedDigit())
            .tracking(TagStyle.tracking)
            .foregroundStyle(Theme.tag(index).opacity(strength))
            .lineLimit(1)
            .fixedSize()
            .overlay {
                TagPlate(
                    tip: focusable ? (focused ? "Show all tasks" : "Show only \(tag)") : "Right-click to change the color",
                    clickable: focusable,
                    onClick: { model.toggleTagFocus(tag) },
                    onContext: { TagColorMenu.show(tag: tag, model: model) }
                )
                .padding(.horizontal, -4)
                .padding(.vertical, -6)
            }
            .pointingHandCursor(enabled: focusable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(focusable ? "Focus \(tag)" : tag)
            .accessibilityAddTraits(focusable ? .isButton : [])
            .accessibilityAction(.default) {
                if focusable { model.toggleTagFocus(tag) }
            }
            .accessibilityAction(named: "Change color of \(tag)") {
                TagColorMenu.show(tag: tag, model: model)
            }
    }
}

/// The tag's hit area: a click, a right-click, a tooltip, and a hover wash. It sits over the text.
struct TagPlate: NSViewRepresentable {
    var tip: String
    var clickable: Bool
    var onClick: () -> Void
    var onContext: () -> Void

    func makeNSView(context: Context) -> TagPlateView {
        let view = TagPlateView()
        view.setAccessibilityElement(false)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: TagPlateView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: TagPlateView) {
        view.toolTip = tip
        view.clickable = clickable
        view.onClick = onClick
        view.onContext = onContext
        view.window?.invalidateCursorRects(for: view)
    }
}

final class TagPlateView: NSView {
    var clickable = true
    var onClick: (() -> Void)?
    var onContext: (() -> Void)?
    private var hovering = false
    private var pressed = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        if clickable, !AppRuntime.model.isTouring {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            setHovering(false)
            pressed = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard clickable, let fill = pressed ? IconMetrics.pressed : (hovering ? IconMetrics.hover : nil) else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: IconMetrics.radius, yRadius: IconMetrics.radius).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard clickable, !AppRuntime.model.isTouring else { return }
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressed
        pressed = false
        needsDisplay = true
        guard wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !AppRuntime.model.isTouring else { return }
        onContext?()
    }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        needsDisplay = true
    }
}

private final class TagColorTarget: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire(_ sender: Any?) {
        action()
    }
}

/// The menu a right-click on a tag opens: the tag's name, then the six colors with a swatch and a checkmark on the current one.
@MainActor
enum TagColorMenu {
    static func show(tag: String, model: AppModel) {
        let menu = NSMenu(title: tag)
        menu.appearance = NSAppearance(named: .darkAqua)
        let header = NSMenuItem(title: tag, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let current = model.tagColorIndex(tag)
        var targets: [TagColorTarget] = []
        for index in 0..<TagPalette.size {
            let item = NSMenuItem(title: Theme.tagNames[index], action: #selector(TagColorTarget.fire(_:)), keyEquivalent: "")
            let target = TagColorTarget { model.setTagColor(tag, colorIndex: index) }
            targets.append(target)
            item.target = target
            item.image = swatch(index)
            item.state = index == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = targets
    }

    private static func swatch(_ index: Int) -> NSImage {
        let color = Theme.tagRGB(index).nsColor
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Fades a row to 35% while another tag has the focus. Hover brings it back to full strength.
struct TagDim: ViewModifier {
    var dimmed: Bool
    var hovered: Bool
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(dimmed && !hovered ? 0.35 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dimmed && !hovered)
    }
}

/// The TODO header's chip while a tag has the focus: the tag, the work still planned for it, and a clear button.
struct TagFocusChip: View {
    var tag: String
    var remaining: TimeInterval
    var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.system(size: TagStyle.fontSize, weight: .semibold).monospacedDigit())
                .tracking(TagStyle.tracking)
                .foregroundStyle(Theme.tag(model.tagColorIndex(tag)))
                .lineLimit(1)
                .fixedSize()
            Text("· \(TimeFormat.span(remaining))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .fixedSize()
            SquareIconButton(
                systemName: "xmark",
                size: 9,
                weight: .bold,
                slot: IconMetrics.column,
                help: "Clear focus"
            ) {
                model.clearTagFocus()
            }
            .padding(.vertical, -2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 0)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: IconMetrics.radius, style: .continuous)
                .fill(Theme.bgCard)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// Under a History day header: worked time per tag, biggest first, untagged work last as "Other".
/// More than four entries end in "+N more", and the full list is the tooltip.
struct TagBreakdownLine: View {
    var breakdown: TagBreakdown
    var model: AppModel

    var body: some View {
        Text(attributed(breakdown.shown, hidden: breakdown.hidden.count))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .help(breakdown.hidden.isEmpty ? "" : plain(breakdown.all))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Worked time by project: \(plain(breakdown.all))")
    }

    private func name(_ entry: TagTime) -> String { entry.tag ?? "Other" }

    private func plain(_ entries: [TagTime]) -> String {
        entries.map { "\(name($0)) \(TimeFormat.span(TimeInterval($0.seconds)))" }.joined(separator: " · ")
    }

    private func attributed(_ entries: [TagTime], hidden: Int) -> AttributedString {
        var line = AttributedString()
        for (position, entry) in entries.enumerated() {
            if position > 0 { line.append(AttributedString(" · ")) }
            var label = AttributedString(name(entry))
            if let tag = entry.tag {
                label.swiftUI.foregroundColor = Theme.tag(model.tagColorIndex(tag))
            }
            line.append(label)
            line.append(AttributedString(" \(TimeFormat.span(TimeInterval(entry.seconds)))"))
        }
        if hidden > 0 {
            line.append(AttributedString(" · +\(hidden) more"))
        }
        return line
    }
}
