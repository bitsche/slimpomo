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

    /// Gives every tag in `tags` a color, in the order given. Known tags keep theirs.
    public mutating func assign(all tags: [String]) {
        for tag in tags { assign(tag) }
    }

    private func lastAssigned(_ colorIndex: Int) -> Int {
        entries.lastIndex { $0.colorIndex == colorIndex } ?? -1
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

    /// Planned work still in the queue for one tag.
    public func plannedWork(tag: String) -> TimeInterval {
        queue.reduce(0) { total, item in
            guard TaskName.tag(of: item.description) == tag else { return total }
            return total + TimeInterval(max(0, item.count)) * item.intensity.workDuration
        }
    }

    /// Every tag in use, in order of first appearance: History events, then Done, LATER, and the queue.
    public func tagsByFirstAppearance() -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        func note(_ name: String) {
            guard let tag = TaskName.tag(of: name), seen.insert(tag).inserted else { return }
            order.append(tag)
        }
        for event in history.sorted(by: { $0.timestamp < $1.timestamp }) { note(event.taskName) }
        for item in done { note(item.description) }
        for item in later { note(item.description) }
        for item in queue { note(item.description) }
        return order
    }
}
