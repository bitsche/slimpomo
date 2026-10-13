import Foundation

/// Which of the six tag colors each tag uses. Assignments never change on their own, so a tag keeps its
/// color across days and relaunches. Only the user changes one, or a seventh tag reuses the oldest color.
public struct TagPalette: Equatable, Codable, Sendable {
    public static let size = 6

    public struct Entry: Equatable, Codable, Sendable {
        public var tag: String
        public var colorIndex: Int
    }

    /// In the order the colors were handed out, oldest first.
    public private(set) var entries: [Entry] = []

    public init() {}

    public func colorIndex(for tag: String) -> Int? {
        entries.first { $0.tag == tag }?.colorIndex
    }

    /// The color a tag has, handing one out the first time the tag is seen: the first color no known tag uses,
    /// and when all six are taken the one whose latest assignment is the oldest.
    @discardableResult
    public mutating func assign(_ tag: String) -> Int {
        if let existing = colorIndex(for: tag) { return existing }
        let used = Set(entries.map(\.colorIndex))
        let index: Int
        if let free = (0..<Self.size).first(where: { !used.contains($0) }) {
            index = free
        } else {
            index = (0..<Self.size).min { lastAssigned($0) < lastAssigned($1) } ?? 0
        }
        entries.append(Entry(tag: tag, colorIndex: index))
        return index
    }

    /// The user picked a color. The choice counts as the newest assignment.
    public mutating func set(_ tag: String, colorIndex: Int) {
        guard (0..<Self.size).contains(colorIndex) else { return }
        entries.removeAll { $0.tag == tag }
        entries.append(Entry(tag: tag, colorIndex: colorIndex))
    }

    /// A tag the user just picked or created counts as the most recently used. Its color does not change.
    public mutating func touch(_ tag: String) {
        guard let index = entries.firstIndex(where: { $0.tag == tag }), index != entries.count - 1 else { return }
        entries.append(entries.remove(at: index))
    }

    /// Every tag with a color, the most recently used first.
    public var tagsMostRecentFirst: [String] {
        entries.reversed().map(\.tag)
    }

    /// Gives every tag in `tags` a color, in the order given. Known tags keep theirs.
    public mutating func assign(all tags: [String]) {
        for tag in tags { assign(tag) }
    }

    private func lastAssigned(_ colorIndex: Int) -> Int {
        entries.lastIndex { $0.colorIndex == colorIndex } ?? -1
    }
}

/// What the tag picker lists for the text typed in its search field.
public struct TagChoices: Equatable, Sendable {
    public enum Entry: Equatable, Sendable {
        case existing(String)
        /// "Create XYZ", offered when the typed text is not a known tag yet.
        case create(String)

        public var tag: String {
            switch self {
            case .existing(let tag), .create(let tag): tag
            }
        }
    }

    /// Known tags that contain the typed text (case-insensitive), in the order given, then the create entry if any.
    public var entries: [Entry]

    /// `known` is in display order, most recently used first.
    public init(known: [String], query: String) {
        let typed = TaskName.sanitizedTag(query)
        var entries = known.filter { typed.isEmpty || $0.uppercased().contains(typed) }.map(Entry.existing)
        if !typed.isEmpty, !known.contains(where: { $0.uppercased() == typed }) {
            entries.append(.create(typed))
        }
        self.entries = entries
    }

    /// How many of the entries are known tags. The create entry, if any, follows them.
    public var existingCount: Int {
        entries.filter { if case .existing = $0 { true } else { false } }.count
    }

    /// The text of the create entry, when there is one.
    public var createName: String? {
        if case .create(let name)? = entries.last { name } else { nil }
    }

    /// The first match is preselected. With no match, the create entry is.
    public var preselected: Int? { entries.isEmpty ? nil : 0 }

    /// Moves the selection one step and stops at the ends.
    public func moved(from index: Int?, by step: Int) -> Int? {
        guard !entries.isEmpty else { return nil }
        guard let index else { return step > 0 ? 0 : entries.count - 1 }
        return min(max(0, index + step), entries.count - 1)
    }
}

/// Worked time of one day split by tag, for the History day header.
public struct TagTime: Equatable, Sendable {
    /// Nil is untagged work, shown as "Other".
    public var tag: String?
    public var seconds: Int

    public init(tag: String?, seconds: Int) {
        self.tag = tag
        self.seconds = seconds
    }
}

public struct TagBreakdown: Equatable, Sendable {
    public static let shownLimit = 4

    /// Biggest first, "Other" last. Empty when the day has only untagged work.
    public var all: [TagTime]

    public var shown: [TagTime] { Array(all.prefix(Self.shownLimit)) }
    public var hidden: [TagTime] { Array(all.dropFirst(Self.shownLimit)) }

    public init(rows: [HistoryRow]) {
        var seconds: [String: Int] = [:]
        var firstSeen: [String] = []
        var other = 0
        for row in rows {
            let worked = max(0, row.workedSeconds)
            if let tag = TaskName.tag(of: row.taskName) {
                if seconds[tag] == nil { firstSeen.append(tag) }
                seconds[tag, default: 0] += worked
            } else {
                other += worked
            }
        }
        guard !firstSeen.isEmpty else {
            all = []
            return
        }
        var tagged = firstSeen.map { TagTime(tag: $0, seconds: seconds[$0] ?? 0) }
        tagged.sort { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            return (lhs.tag ?? "") < (rhs.tag ?? "")
        }
        if other > 0 { tagged.append(TagTime(tag: nil, seconds: other)) }
        all = tagged
    }
}

extension Session {
    /// The task START, or the end of a break, begins next. Nil while working, paused in work, or with nothing to start.
    public var nextStartID: UUID? {
        guard phase == .idle || phase == .breakTime else { return nil }
        return queue.first { $0.count > 0 }?.id
    }

    /// Every tag in use, in order of first appearance: History events, then Done, LATER, and the queue.
    /// `knownHistory` is how many history events, from the front, an earlier call already covered. History is append-only,
    /// so a caller that has handed out colors for those can skip them and pay only for what came since.
    public func tagsByFirstAppearance(knownHistory: Int = 0) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        func note(_ name: String) {
            guard let tag = TaskName.tag(of: name), seen.insert(tag).inserted else { return }
            order.append(tag)
        }
        if knownHistory > 0, knownHistory <= history.count {
            for event in history[knownHistory...] { note(event.taskName) }
        } else {
            for event in history.sorted(by: { $0.timestamp < $1.timestamp }) { note(event.taskName) }
        }
        for item in done { note(item.description) }
        for item in later { note(item.description) }
        for item in queue { note(item.description) }
        return order
    }
}
