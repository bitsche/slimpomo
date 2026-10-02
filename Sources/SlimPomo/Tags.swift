import AppKit
import SwiftUI
import SlimPomoCore

/// Look and measure of a tag, the project label in front of a task name. Display only: the stored name keeps its text.
enum TagStyle {
    static let fontSize: CGFloat = 11
    /// The task under NOW is one step larger.
    static let nowFontSize: CGFloat = 11.5
    /// 0.04 em of the font size.
    static func tracking(for size: CGFloat) -> CGFloat { size * 0.04 }
    /// Space between the widest label and the name column.
    static let columnGap: CGFloat = 8
    static let minColumn: CGFloat = 28
    static let maxColumn: CGFloat = 60
    /// A tag in Done and History is quieter.
    static let doneStrength = 0.6

    @MainActor private static var widths: [String: CGFloat] = [:]

    @MainActor
    static func labelWidth(_ tag: String, size: CGFloat = fontSize) -> CGFloat {
        let key = "\(size)|\(tag)"
        if let known = widths[key] { return known }
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let width = ceil((tag as NSString).size(withAttributes: [.font: font, .kern: tracking(for: size)]).width)
        widths[key] = width
        return width
    }

    /// The column every row of one list gets when any of its rows shows a tag: the widest label plus 8 pt, from 28 to 60 pt.
    /// Zero without tags. A label wider than the column ends in "…".
    @MainActor
    static func columnWidth<S: Sequence>(for names: S, size: CGFloat = fontSize) -> CGFloat where S.Element == String {
        var widest: CGFloat = 0
        var seen = Set<String>()
        for name in names {
            guard let tag = TaskName.tag(of: name), seen.insert(tag).inserted else { continue }
            widest = max(widest, labelWidth(tag, size: size))
        }
        guard widest > 0 else { return 0 }
        return min(maxColumn, max(minColumn, widest + columnGap))
    }
}

private struct TagColumnKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Width of the tag column in the rows below, decided by their own list. Zero when no row of that list shows a tag.
    var tagColumn: CGFloat {
        get { self[TagColumnKey.self] }
        set { self[TagColumnKey.self] = newValue }
    }
}

/// A tag in its color: the old muted prefix, 11 pt regular, with only the color changed. Plain text, not a control.
struct TagLabel: View {
    var tag: String
    var model: AppModel
    /// 1 in the queue and LATER, `TagStyle.doneStrength` in Done and History.
    var strength = 1.0
    /// The row's tag column. A label wider than the column minus its gap is cut with "…". Nil keeps the whole label.
    var column: CGFloat?
    var size = TagStyle.fontSize

    var body: some View {
        let text = Text(tag)
            .font(.system(size: size).monospacedDigit().smallCaps())
            .tracking(TagStyle.tracking(for: size))
            .foregroundStyle(Theme.tag(model.tagColorIndex(tag)).opacity(strength))
            .lineLimit(1)
            .truncationMode(.tail)
        if let column {
            text.frame(width: max(0, column - TagStyle.columnGap), alignment: .leading)
        } else {
            text.fixedSize()
        }
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
