import Foundation

public struct IntensityMode: Equatable, Sendable {
    public var name: String
    public var workMinutes: Int
    public var breakMinutes: Int
    /// Pale heat-scale fill: regular, focus, then intense.
    public var red: Double
    public var green: Double
    public var blue: Double
}

public enum Intensity: String, Codable, CaseIterable, Equatable, Sendable {
    case regular
    case focus
    case intense

    /// Single source for a mode's name, durations, and chip color.
    public var mode: IntensityMode {
        switch self {
        case .regular:
            IntensityMode(name: "Dip", workMinutes: 25, breakMinutes: 5, red: 0.73, green: 0.84, blue: 0.74)
        case .focus:
            IntensityMode(name: "Dive", workMinutes: 50, breakMinutes: 10, red: 0.93, green: 0.80, blue: 0.58)
        case .intense:
            IntensityMode(name: "Deep dive", workMinutes: 75, breakMinutes: 15, red: 0.95, green: 0.64, blue: 0.60)
        }
    }

    public var workDuration: TimeInterval { TimeInterval(mode.workMinutes * 60) }
    public var breakDuration: TimeInterval { TimeInterval(mode.breakMinutes * 60) }
    public var label: String { mode.name }

    /// Work minutes, as shown on the chip. The prime marks minutes.
    public var workMark: String { "\(mode.workMinutes)′" }

    public var summary: String {
        "\(mode.name) — \(mode.workMinutes) min work, \(mode.breakMinutes) min break"
    }

    /// Full session length relative to regular. Regular is 1, focus 2, intense 3.
    public var sessionScale: Double {
        let minutes = mode.workMinutes + mode.breakMinutes
        let base = Intensity.regular.mode.workMinutes + Intensity.regular.mode.breakMinutes
        return Double(minutes) / Double(base)
    }

    /// Share of the session that is work. The rest is the break segment.
    public var workShare: Double {
        let total = mode.workMinutes + mode.breakMinutes
        guard total > 0 else { return 1 }
        return Double(mode.workMinutes) / Double(total)
    }
}

public struct QueueItem: Identifiable, Equatable, Codable {
    public var id: UUID
    public var intensity: Intensity
    public var description: String
    public var count: Int
    /// Pomodoros finished on this queue stint. Kept so a completed line can move to Done intact.
    public var completed: Int
    /// Queue item these done pomodoros came from, so later finishes accumulate on the same row.
    public var sourceID: UUID?
    /// Seconds actually worked across this done row's completions. Queue rows leave it at 0.
    public var workedSeconds: Int

    public init(id: UUID, intensity: Intensity, description: String, count: Int, completed: Int = 0, sourceID: UUID? = nil, workedSeconds: Int = 0) {
        self.id = id
        self.intensity = intensity
        self.description = description
        self.count = count
        self.completed = completed
        self.sourceID = sourceID
        self.workedSeconds = workedSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, intensity, description, count, completed, sourceID, workedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        intensity = try container.decode(Intensity.self, forKey: .intensity)
        description = try container.decode(String.self, forKey: .description)
        count = try container.decode(Int.self, forKey: .count)
        completed = try container.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        sourceID = try container.decodeIfPresent(UUID.self, forKey: .sourceID)
        workedSeconds = try container.decodeIfPresent(Int.self, forKey: .workedSeconds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(description, forKey: .description)
        try container.encode(count, forKey: .count)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(sourceID, forKey: .sourceID)
        try container.encode(workedSeconds, forKey: .workedSeconds)
    }
}

public enum Phase: String, Codable, Equatable {
    case idle
    case work
    case breakTime
}

public enum SessionEffect: Equatable {
    case none
    /// The work interval ended, including Finish.
    case workDone
    /// The break ended, including Skip.
    case breakOver
}

/// One finished pomodoro. Kept permanently; the Done list is only today.
public struct HistoryEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var queueItemId: UUID
    public var taskName: String
    public var mode: Intensity
    /// Planned length of the mode. Early finishes keep this and store the real time in `workedSeconds`.
    public var workMinutes: Int
    /// Seconds that actually ran for this one pomodoro. Never below 1.
    public var workedSeconds: Int

    public init(id: UUID, timestamp: Date, queueItemId: UUID, taskName: String, mode: Intensity, workMinutes: Int, workedSeconds: Int) {
        self.id = id
        self.timestamp = timestamp
        self.queueItemId = queueItemId
        self.taskName = taskName
        self.mode = mode
        self.workMinutes = workMinutes
        self.workedSeconds = workedSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, queueItemId, taskName, mode, workMinutes, workedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        queueItemId = try container.decode(UUID.self, forKey: .queueItemId)
        taskName = try container.decode(String.self, forKey: .taskName)
        mode = try container.decode(Intensity.self, forKey: .mode)
        workMinutes = try container.decode(Int.self, forKey: .workMinutes)
        workedSeconds = try container.decodeIfPresent(Int.self, forKey: .workedSeconds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(queueItemId, forKey: .queueItemId)
        try container.encode(taskName, forKey: .taskName)
        try container.encode(mode, forKey: .mode)
        try container.encode(workMinutes, forKey: .workMinutes)
        try container.encode(workedSeconds, forKey: .workedSeconds)
    }
}

/// Shared header and row label. Seconds are added first; the total is rounded once.
public enum TimeSpan {
    public static func text(_ seconds: TimeInterval) -> String {
        if seconds > 0, seconds < 30 {
            return "<1m"
        }
        let minutes = max(0, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(remainder)m"
    }
}

public struct HistoryRow: Identifiable, Equatable, Sendable {
    public var queueItemId: UUID
    public var taskName: String
    public var mode: Intensity
    public var count: Int
    public var workedSeconds: Int

    public var id: UUID { queueItemId }
}

public struct HistoryDay: Identifiable, Equatable, Sendable {
    public var day: Date
    public var pomodoros: Int
    public var workMinutes: Int
    public var workedSeconds: Int
    public var rows: [HistoryRow]

    public var id: Date { day }
}

/// The status-item menu's grey line and its Start, Pause, or Resume item.
public struct StatusMenuContent: Equatable, Sendable {
    public var statusPrefix: String
    /// The only part of the status line that may be shortened.
    public var taskName: String
    public var statusSuffix: String
    public var actionTitle: String
    public var actionEnabled: Bool

    public var statusLine: String { statusPrefix + taskName + statusSuffix }
}

public enum MenuClock {
    /// Whole minutes, rounded up. Zero stays zero. Matches the menu-bar ring's number.
    public static func minutes(_ seconds: TimeInterval) -> Int {
        let remaining = max(0, seconds)
        guard remaining > 0 else { return 0 }
        return Int((remaining / 60).rounded(.up))
    }
}

public enum MenuTitleFit {
    public static let maxMenuWidth: CGFloat = 300

    /// Shortens only `name`, with a trailing ellipsis, until `measure` of the whole line is within `maxWidth`.
    public static func line(
        prefix: String,
        name: String,
        suffix: String,
        maxWidth: CGFloat,
        measure: (String) -> CGFloat
    ) -> String {
        let full = prefix + name + suffix
        if name.isEmpty || measure(full) <= maxWidth {
            return full
        }
        let ellipsis = "…"
        let characters = Array(name)
        var best = prefix + ellipsis + suffix
        var low = 0
        var high = characters.count
        while low <= high {
            let mid = (low + high) / 2
            let candidate = prefix + String(characters.prefix(mid)) + ellipsis + suffix
            if measure(candidate) <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}

/// A calendar date with no time, stored as `yyyy-MM-dd` in the local calendar.
public enum CalendarDay {
    public static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func date(_ stamp: String, calendar: Calendar = .current) -> Date? {
        let parts = stamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

public struct SnoozeOffer: Equatable, Identifiable, Sendable {
    public var title: String
    public var returnDay: String
    public var id: String { returnDay }
}

public enum Snooze {
    /// Tomorrow, and next Monday when that is a different day. On Sunday the only offer is tomorrow.
    public static func offers(on now: Date, calendar: Calendar = .current) -> [SnoozeOffer] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let tomorrowStamp = CalendarDay.stamp(tomorrow, calendar: calendar)
        let monday = nextMonday(after: today, calendar: calendar)
        let mondayStamp = CalendarDay.stamp(monday, calendar: calendar)
        if tomorrowStamp == mondayStamp {
            let weekday = shortWeekday(monday, calendar: calendar)
            return [SnoozeOffer(title: "Move to tomorrow (\(weekday))", returnDay: tomorrowStamp)]
        }
        return [
            SnoozeOffer(title: "Move to tomorrow", returnDay: tomorrowStamp),
            SnoozeOffer(title: "Move to next Monday", returnDay: mondayStamp),
        ]
    }

    public static func offers(on now: Date, excluding returnDay: String, calendar: Calendar = .current) -> [SnoozeOffer] {
        offers(on: now, calendar: calendar).filter { $0.returnDay != returnDay }
    }

    /// The first Monday after `today`. A Monday yields the Monday seven days later.
    public static func nextMonday(after today: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilMonday = (9 - weekday) % 7
        let offset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private static func shortWeekday(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

public struct LaterItem: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var intensity: Intensity
    public var description: String
    public var count: Int
    /// Local calendar date, `yyyy-MM-dd`.
    public var returnDay: String
    public var snoozedAt: Date

    public init(id: UUID, intensity: Intensity, description: String, count: Int, returnDay: String, snoozedAt: Date) {
        self.id = id
        self.intensity = intensity
        self.description = description
        self.count = count
        self.returnDay = returnDay
        self.snoozedAt = snoozedAt
    }
}

public struct Session: Equatable, Codable {
    public static let maxPomodoros = 5

    public private(set) var queue: [QueueItem]
    public private(set) var later: [LaterItem]
    public private(set) var done: [QueueItem]
    public private(set) var phase: Phase
    public private(set) var isRunning: Bool
    public private(set) var remaining: TimeInterval
    public private(set) var phaseDuration: TimeInterval
    public private(set) var activeItemID: UUID?
    public private(set) var activeDescription: String
    public private(set) var endsAt: Date?
    public private(set) var lockedBreakDuration: TimeInterval?
    public private(set) var history: [HistoryEvent]
    /// Start of the local day the Done list belongs to.
    public private(set) var doneDay: Date?
    /// Existing Done rows are copied into history once.
    public private(set) var didMigrateHistory: Bool
    /// Older events and Done rows receive full-length worked time once.
    public private(set) var didMigrateWorkedSeconds: Bool

    public init() {
        queue = []
        later = []
        done = []
        phase = .idle
        isRunning = false
        remaining = 0
        phaseDuration = 0
        activeItemID = nil
        activeDescription = ""
        endsAt = nil
        lockedBreakDuration = nil
        history = []
        doneDay = nil
        didMigrateHistory = false
        didMigrateWorkedSeconds = true
    }

    private enum CodingKeys: String, CodingKey {
        case queue, later, done, phase, isRunning, remaining, phaseDuration, activeItemID, activeDescription, endsAt, lockedBreakDuration
        case history, doneDay, didMigrateHistory, didMigrateWorkedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decode([QueueItem].self, forKey: .queue)
        later = try container.decodeIfPresent([LaterItem].self, forKey: .later) ?? []
        done = try container.decodeIfPresent([QueueItem].self, forKey: .done) ?? []
        phase = try container.decode(Phase.self, forKey: .phase)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        remaining = try container.decode(TimeInterval.self, forKey: .remaining)
        phaseDuration = try container.decode(TimeInterval.self, forKey: .phaseDuration)
        activeItemID = try container.decodeIfPresent(UUID.self, forKey: .activeItemID)
        activeDescription = try container.decodeIfPresent(String.self, forKey: .activeDescription) ?? ""
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        lockedBreakDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .lockedBreakDuration)
        history = try container.decodeIfPresent([HistoryEvent].self, forKey: .history) ?? []
        doneDay = try container.decodeIfPresent(Date.self, forKey: .doneDay)
        didMigrateHistory = try container.decodeIfPresent(Bool.self, forKey: .didMigrateHistory) ?? false
        didMigrateWorkedSeconds = try container.decodeIfPresent(Bool.self, forKey: .didMigrateWorkedSeconds) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(queue, forKey: .queue)
        try container.encode(later, forKey: .later)
        try container.encode(done, forKey: .done)
        try container.encode(phase, forKey: .phase)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(phaseDuration, forKey: .phaseDuration)
        try container.encodeIfPresent(activeItemID, forKey: .activeItemID)
        if !activeDescription.isEmpty {
            try container.encode(activeDescription, forKey: .activeDescription)
        }
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(lockedBreakDuration, forKey: .lockedBreakDuration)
        try container.encode(history, forKey: .history)
        try container.encodeIfPresent(doneDay, forKey: .doneDay)
        try container.encode(didMigrateHistory, forKey: .didMigrateHistory)
        try container.encode(didMigrateWorkedSeconds, forKey: .didMigrateWorkedSeconds)
    }

    public var activeItem: QueueItem? {
        guard let activeItemID else { return nil }
        return queue.first { $0.id == activeItemID }
    }

    public var hasWorkQueued: Bool {
        queue.contains { $0.count > 0 }
    }

    public func statusMenu(at now: Date) -> StatusMenuContent {
        let minutes = MenuClock.minutes(displayedRemaining(at: now))
        let left = " · \(minutes) min left"
        switch phase {
        case .idle:
            if let next = queue.first(where: { $0.count > 0 }) {
                return StatusMenuContent(
                    statusPrefix: "Idle · Next: ",
                    taskName: Self.menuTaskName(next.description),
                    statusSuffix: "",
                    actionTitle: "Start",
                    actionEnabled: true
                )
            }
            return StatusMenuContent(
                statusPrefix: "Idle · Nothing queued",
                taskName: "",
                statusSuffix: "",
                actionTitle: "Start",
                actionEnabled: false
            )
        case .work:
            let name = Self.menuTaskName(activeItem?.description ?? activeDescription)
            if isRunning {
                return StatusMenuContent(
                    statusPrefix: "",
                    taskName: name,
                    statusSuffix: left,
                    actionTitle: "Pause",
                    actionEnabled: true
                )
            }
            return StatusMenuContent(
                statusPrefix: "Paused · ",
                taskName: name,
                statusSuffix: left,
                actionTitle: "Resume",
                actionEnabled: true
            )
        case .breakTime:
            if isRunning {
                return StatusMenuContent(
                    statusPrefix: "Break · \(minutes) min left",
                    taskName: "",
                    statusSuffix: "",
                    actionTitle: "Pause",
                    actionEnabled: true
                )
            }
            return StatusMenuContent(
                statusPrefix: "Paused · Break · \(minutes) min left",
                taskName: "",
                statusSuffix: "",
                actionTitle: "Resume",
                actionEnabled: true
            )
        }
    }

    private static func menuTaskName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    public func displayedRemaining(at now: Date) -> TimeInterval {
        if isRunning, let endsAt {
            return max(0, endsAt.timeIntervalSince(now))
        }
        return max(0, remaining)
    }

    public func elapsedFraction(at now: Date) -> Double {
        guard phase != .idle, phaseDuration > 0 else { return 0 }
        let fraction = 1 - (displayedRemaining(at: now) / phaseDuration)
        return min(1, max(0, fraction))
    }

    /// When each queued line's last remaining pomodoro finishes and its break starts.
    public func finishDates(at now: Date) -> [UUID: Date] {
        var cursor = now
        var remainingCounts = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0.count) })
        var finishes: [UUID: Date] = [:]

        if phase == .work, let id = activeItemID, var left = remainingCounts[id] {
            let workLeft = displayedRemaining(at: now)
            let breakDuration = lockedBreakDuration ?? activeItem?.intensity.breakDuration ?? 0
            if left <= 1 {
                finishes[id] = cursor + workLeft
            }
            cursor += workLeft + breakDuration
            left -= 1
            remainingCounts[id] = max(0, left)
        } else if phase == .breakTime {
            cursor += displayedRemaining(at: now)
        }

        for item in queue {
            let cycles = remainingCounts[item.id] ?? 0
            guard cycles > 0 else { continue }
            let work = item.intensity.workDuration
            let breakDuration = item.intensity.breakDuration
            let finish = cursor + TimeInterval(cycles - 1) * (work + breakDuration) + work
            finishes[item.id] = finish
            cursor = finish + breakDuration
        }
        return finishes
    }

    public func snapshot(at now: Date) -> Session {
        var copy = self
        if isRunning, let endsAt {
            copy.remaining = max(0, endsAt.timeIntervalSince(now))
        }
        return copy
    }

    /// Drops a live end date so a relaunch does not keep counting time the app was closed.
    public mutating func restoreAsPaused() {
        isRunning = false
        endsAt = nil
        if phase == .idle {
            remaining = 0
            phaseDuration = 0
            activeItemID = nil
            activeDescription = ""
            lockedBreakDuration = nil
        }
    }

    public mutating func normalize() {
        for index in queue.indices {
            queue[index].count = min(Self.maxPomodoros, max(0, queue[index].count))
            queue[index].completed = max(0, queue[index].completed)
        }
        if phase == .work, let id = activeItemID, let index = queue.firstIndex(where: { $0.id == id }), queue[index].count < 1 {
            queue[index].count = 1
        }
        for index in later.indices {
            later[index].count = min(Self.maxPomodoros, max(0, later[index].count))
        }
        done = done.map { item in
            var copy = item
            copy.count = min(Self.maxPomodoros, max(1, copy.count))
            copy.completed = 0
            return copy
        }
    }

    public mutating func start(now: Date, calendar: Calendar = .current) -> SessionEffect {
        guard phase == .idle, let next = queue.first(where: { $0.count > 0 }) else { return .none }
        settleDoneDay(now: now, calendar: calendar, force: false)
        beginWork(on: next, now: now)
        return .none
    }

    public mutating func pause(now: Date) -> SessionEffect {
        guard isRunning, phase != .idle else { return .none }
        if let endsAt {
            remaining = max(0, endsAt.timeIntervalSince(now))
        }
        self.endsAt = nil
        isRunning = false
        return .none
    }

    public mutating func resume(now: Date) -> SessionEffect {
        guard !isRunning, phase != .idle else { return .none }
        endsAt = now.addingTimeInterval(max(0, remaining))
        isRunning = true
        return .none
    }

    public mutating func markDone(now: Date, calendar: Calendar = .current) -> SessionEffect {
        guard phase == .work else { return .none }
        completeWork(now: now, calendar: calendar)
        return .workDone
    }

    /// Drops the running pomodoro without finishing it and returns to the unstarted queue.
    public mutating func stop(now: Date = Date(), calendar: Calendar = .current) -> SessionEffect {
        guard phase == .work, isRunning else { return .none }
        becomeIdle()
        settleDoneDay(now: now, calendar: calendar, force: false)
        return .none
    }

    public mutating func skipBreak(now: Date, calendar: Calendar = .current) -> SessionEffect {
        guard phase == .breakTime else { return .none }
        finishBreak(now: now, calendar: calendar)
        return .breakOver
    }

    public mutating func reconcile(now: Date, calendar: Calendar = .current) -> SessionEffect {
        guard isRunning, let endsAt, now >= endsAt else { return .none }
        switch phase {
        case .work:
            completeWork(now: now, calendar: calendar)
            return .workDone
        case .breakTime:
            finishBreak(now: now, calendar: calendar)
            return .breakOver
        case .idle:
            return .none
        }
    }

    /// Clears Done when its day is no longer today. A running or paused phase waits.
    public mutating func refreshDoneDay(now: Date, calendar: Calendar = .current) {
        settleDoneDay(now: now, calendar: calendar, force: false)
    }

    /// Copies a pre-history Done list into events once. Later launches do nothing.
    public mutating func migrateHistoryIfNeeded(now: Date, calendar: Calendar = .current) {
        guard !didMigrateHistory else { return }
        didMigrateHistory = true
        for item in done {
            let source = item.sourceID ?? item.id
            let copies = max(1, item.count)
            for _ in 0..<copies {
                history.append(HistoryEvent(
                    id: UUID(),
                    timestamp: now,
                    queueItemId: source,
                    taskName: item.description,
                    mode: item.intensity,
                    workMinutes: item.intensity.mode.workMinutes,
                    workedSeconds: item.intensity.mode.workMinutes * 60
                ))
            }
        }
        doneDay = calendar.startOfDay(for: now)
    }

    /// Fills missing worked time with the planned length, once. It never adds events.
    public mutating func migrateWorkedSecondsIfNeeded() {
        guard !didMigrateWorkedSeconds else { return }
        didMigrateWorkedSeconds = true
        for index in history.indices where history[index].workedSeconds == 0 {
            history[index].workedSeconds = history[index].workMinutes * 60
        }
        for index in done.indices where done[index].workedSeconds == 0 {
            let minutes = done[index].intensity.mode.workMinutes
            done[index].workedSeconds = minutes * 60 * done[index].count
        }
    }

    /// Newest day first. Rows follow the order the task first finished that day.
    public func groupedHistory(calendar: Calendar = .current) -> [HistoryDay] {
        var dayOrder: [Date] = []
        var eventsByDay: [Date: [HistoryEvent]] = [:]
        for event in history {
            let day = calendar.startOfDay(for: event.timestamp)
            if eventsByDay[day] == nil {
                dayOrder.append(day)
                eventsByDay[day] = []
            }
            eventsByDay[day]?.append(event)
        }
        return dayOrder.map { day in
            let events = eventsByDay[day] ?? []
            var rowOrder: [UUID] = []
            var rows: [UUID: HistoryRow] = [:]
            for event in events {
                if rows[event.queueItemId] == nil {
                    rowOrder.append(event.queueItemId)
                    rows[event.queueItemId] = HistoryRow(
                        queueItemId: event.queueItemId,
                        taskName: event.taskName,
                        mode: event.mode,
                        count: 0,
                        workedSeconds: 0
                    )
                }
                rows[event.queueItemId]?.taskName = event.taskName
                rows[event.queueItemId]?.mode = event.mode
                rows[event.queueItemId]?.count += 1
                rows[event.queueItemId]?.workedSeconds += event.workedSeconds
            }
            return HistoryDay(
                day: day,
                pomodoros: events.count,
                workMinutes: events.reduce(0) { $0 + $1.workMinutes },
                workedSeconds: events.reduce(0) { $0 + $1.workedSeconds },
                rows: rowOrder.compactMap { rows[$0] }
            )
        }
        .sorted { $0.day > $1.day }
    }

    public mutating func addItem(description: String, intensity: Intensity, count: Int) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clamped = min(Self.maxPomodoros, max(1, count))
        queue.append(QueueItem(id: UUID(), intensity: intensity, description: trimmed, count: clamped))
    }

    public mutating func updateDescription(id: UUID, description: String) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].description = description
    }

    public mutating func updateIntensity(id: UUID, intensity: Intensity) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if phase != .idle, activeItemID == id { return }
        queue[index].intensity = intensity
    }

    /// Count is the remaining pomodoros, including the one in progress.
    /// The active work item stays at least 1. Any other item may sit at 0 and stays in the queue.
    public mutating func setCount(id: UUID, count: Int) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if count < 1, phase == .work, activeItemID == id {
            queue[index].count = 1
            return
        }
        queue[index].count = min(max(0, count), Self.maxPomodoros)
    }

    public func canSnooze(id: UUID) -> Bool {
        guard queue.contains(where: { $0.id == id }) else { return false }
        return !(phase == .work && activeItemID == id)
    }

    public mutating func snooze(id: UUID, returnDay: String, now: Date) {
        guard canSnooze(id: id), let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue.remove(at: index)
        later.append(LaterItem(
            id: item.id,
            intensity: item.intensity,
            description: item.description,
            count: item.count,
            returnDay: returnDay,
            snoozedAt: now
        ))
    }

    public func laterGroups() -> [(day: String, items: [LaterItem])] {
        let sorted = later.sorted { lhs, rhs in
            if lhs.returnDay != rhs.returnDay { return lhs.returnDay < rhs.returnDay }
            return lhs.snoozedAt < rhs.snoozedAt
        }
        var order: [String] = []
        var grouped: [String: [LaterItem]] = [:]
        for item in sorted {
            if grouped[item.returnDay] == nil {
                order.append(item.returnDay)
                grouped[item.returnDay] = []
            }
            grouped[item.returnDay, default: []].append(item)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    public mutating func deleteLater(id: UUID) {
        later.removeAll { $0.id == id }
    }

    public mutating func retargetLater(id: UUID, returnDay: String, now: Date) {
        guard let index = later.firstIndex(where: { $0.id == id }), later[index].returnDay != returnDay else { return }
        later[index].returnDay = returnDay
        later[index].snoozedAt = now
    }

    /// Puts one snoozed task back now, in the same spot a scheduled return would use.
    public mutating func returnLater(id: UUID) {
        guard let index = later.firstIndex(where: { $0.id == id }) else { return }
        let item = later.remove(at: index)
        insertReturned([item])
    }

    /// Moves every later item whose day is today or earlier back into the queue. Does not wait for an idle timer.
    @discardableResult
    public mutating func returnDueLater(now: Date, calendar: Calendar = .current) -> Bool {
        let today = CalendarDay.stamp(now, calendar: calendar)
        let due = later.filter { $0.returnDay <= today }.sorted { lhs, rhs in
            if lhs.returnDay != rhs.returnDay { return lhs.returnDay < rhs.returnDay }
            return lhs.snoozedAt < rhs.snoozedAt
        }
        guard !due.isEmpty else { return false }
        let ids = Set(due.map(\.id))
        later.removeAll { ids.contains($0.id) }
        insertReturned(due)
        return true
    }

    private mutating func insertReturned(_ items: [LaterItem]) {
        let index = (activeWorkIndex() ?? -1) + 1
        let rows = items.map {
            QueueItem(id: $0.id, intensity: $0.intensity, description: $0.description, count: $0.count)
        }
        queue.insert(contentsOf: rows, at: min(max(0, index), queue.count))
    }

    public mutating func remove(id: UUID, now: Date, calendar: Calendar = .current) -> SessionEffect {
        let wasActive = id == activeItemID && phase != .idle
        queue.removeAll { $0.id == id }
        guard wasActive else { return .none }
        if let next = queue.first(where: { $0.count > 0 }) {
            beginWork(on: next, now: now)
        } else {
            becomeIdle()
            settleDoneDay(now: now, calendar: calendar, force: false)
        }
        return .none
    }

    /// Copies one day's history row onto the end of the queue. The history row stays.
    public mutating func requeueHistory(queueItemId: UUID, day: Date, calendar: Calendar = .current) {
        guard let row = groupedHistory(calendar: calendar)
            .first(where: { calendar.isDate($0.day, inSameDayAs: day) })?
            .rows.first(where: { $0.queueItemId == queueItemId }) else { return }
        queue.append(QueueItem(
            id: UUID(),
            intensity: row.mode,
            description: row.taskName,
            count: min(Self.maxPomodoros, max(1, row.count)),
            completed: 0
        ))
    }

    /// Copies a finished line onto the end of the queue. The done entry stays.
    public mutating func requeue(id: UUID) {
        guard let item = done.first(where: { $0.id == id }) else { return }
        queue.append(QueueItem(
            id: UUID(),
            intensity: item.intensity,
            description: item.description,
            count: min(Self.maxPomodoros, max(1, item.count)),
            completed: 0
        ))
    }

    public mutating func clearDone() {
        done.removeAll()
    }

    public mutating func move(from source: IndexSet, to destination: Int) {
        let indexes = source.sorted()
        guard !indexes.isEmpty, indexes.allSatisfy({ queue.indices.contains($0) }) else { return }
        let moving = indexes.map { queue[$0] }
        for index in indexes.reversed() {
            queue.remove(at: index)
        }
        let shift = indexes.filter { $0 < destination }.count
        let insertion = max(0, min(queue.count, destination - shift))
        queue.insert(contentsOf: moving, at: insertion)
    }

    /// The row whose work is running or paused. Nil while idle or on a break.
    public func activeWorkIndex() -> Int? {
        guard phase == .work, let id = activeItemID else { return nil }
        return queue.firstIndex { $0.id == id }
    }

    /// Indexes this row may occupy after it is lifted out. Nil when it cannot move.
    /// The index is in the queue with this row already removed.
    public func reorderDestinations(for id: UUID) -> ClosedRange<Int>? {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return nil }
        let count = queue.count
        guard count > 1 else { return nil }
        guard let pinned = activeWorkIndex() else { return 0...(count - 1) }
        if index == pinned { return nil }
        let pinnedAfterRemoval = index < pinned ? pinned - 1 : pinned
        let lower = pinnedAfterRemoval + 1
        let upper = count - 1
        guard lower <= upper else { return nil }
        return lower...upper
    }

    public func nearestReorderDestination(for id: UUID, proposed: Int) -> Int? {
        guard let allowed = reorderDestinations(for: id) else { return nil }
        return min(max(proposed, allowed.lowerBound), allowed.upperBound)
    }

    /// False when the row is pinned, or the only place it can land is where it already sits.
    public func canReorder(id: UUID) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == id }),
              let allowed = reorderDestinations(for: id) else { return false }
        return allowed.lowerBound != index || allowed.upperBound != index
    }

    public func canMoveUp(id: UUID) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == id }), index > 0,
              let allowed = reorderDestinations(for: id) else { return false }
        return allowed.contains(index - 1)
    }

    public func canMoveDown(id: UUID) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == id }),
              let allowed = reorderDestinations(for: id) else { return false }
        return allowed.contains(index + 1)
    }

    /// `destination` is the index after `id` has been removed.
    public mutating func reorder(id: UUID, to destination: Int) {
        guard let index = queue.firstIndex(where: { $0.id == id }),
              let allowed = reorderDestinations(for: id),
              allowed.contains(destination),
              destination != index else { return }
        let item = queue.remove(at: index)
        queue.insert(item, at: min(max(0, destination), queue.count))
    }

    public mutating func moveUp(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        reorder(id: id, to: index - 1)
    }

    public mutating func moveDown(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        reorder(id: id, to: index + 1)
    }

    private mutating func beginWork(on item: QueueItem, now: Date) {
        phase = .work
        isRunning = true
        phaseDuration = item.intensity.workDuration
        remaining = phaseDuration
        endsAt = now.addingTimeInterval(phaseDuration)
        activeItemID = item.id
        activeDescription = item.description
        lockedBreakDuration = item.intensity.breakDuration
    }

    private mutating func beginBreak(duration: TimeInterval, itemID: UUID, now: Date) {
        phase = .breakTime
        isRunning = true
        phaseDuration = duration
        remaining = duration
        endsAt = now.addingTimeInterval(duration)
        activeItemID = itemID
    }

    private mutating func completeWork(now: Date, calendar: Calendar) {
        guard phase == .work, let id = activeItemID, let index = queue.firstIndex(where: { $0.id == id }) else {
            becomeIdle()
            settleDoneDay(now: now, calendar: calendar, force: false)
            return
        }
        let worked = elapsedWorkSeconds(at: now)
        settleDoneDay(now: now, calendar: calendar, force: true)
        let finished = queue[index]
        activeDescription = finished.description
        queue[index].count = max(0, queue[index].count - 1)
        queue[index].completed += 1
        recordFinishedPomodoro(from: finished, at: now, workedSeconds: worked)
        let breakDuration = lockedBreakDuration ?? finished.intensity.breakDuration
        if queue[index].count <= 0 {
            queue.remove(at: index)
        }
        beginBreak(duration: breakDuration, itemID: id, now: now)
    }

    /// Planned work minus the time still left. Pauses and time the app was closed stay in `remaining`.
    private func elapsedWorkSeconds(at now: Date) -> Int {
        let left: TimeInterval
        if isRunning, let endsAt {
            left = max(0, endsAt.timeIntervalSince(now))
        } else {
            left = max(0, remaining)
        }
        let seconds = (phaseDuration - left).rounded()
        return max(1, Int(seconds))
    }

    private mutating func recordFinishedPomodoro(from item: QueueItem, at now: Date, workedSeconds: Int) {
        history.append(HistoryEvent(
            id: UUID(),
            timestamp: now,
            queueItemId: item.id,
            taskName: item.description,
            mode: item.intensity,
            workMinutes: item.intensity.mode.workMinutes,
            workedSeconds: workedSeconds
        ))
        if let index = done.lastIndex(where: { $0.sourceID == item.id }) {
            done[index].count += 1
            done[index].workedSeconds += workedSeconds
            return
        }
        done.append(QueueItem(
            id: UUID(),
            intensity: item.intensity,
            description: item.description,
            count: 1,
            sourceID: item.id,
            workedSeconds: workedSeconds
        ))
    }

    private mutating func finishBreak(now: Date, calendar: Calendar) {
        settleDoneDay(now: now, calendar: calendar, force: true)
        if let id = activeItemID {
            queue.removeAll { $0.id == id && $0.count <= 0 }
        }
        if let next = queue.first(where: { $0.count > 0 }) {
            beginWork(on: next, now: now)
        } else {
            becomeIdle()
        }
    }

    /// `force` clears even during work or a break. Used at completion and when a break ends.
    private mutating func settleDoneDay(now: Date, calendar: Calendar, force: Bool) {
        let today = calendar.startOfDay(for: now)
        if let doneDay {
            guard calendar.startOfDay(for: doneDay) != today else { return }
            guard force || phase == .idle else { return }
            done = []
        }
        self.doneDay = today
    }

    private mutating func becomeIdle() {
        phase = .idle
        isRunning = false
        remaining = 0
        phaseDuration = 0
        activeItemID = nil
        activeDescription = ""
        endsAt = nil
        lockedBreakDuration = nil
    }

    /// Idle queue and Done list shown during the tour. It is never saved.
    public static func tourSample() -> Session {
        var session = Session()
        session.queue = [
            QueueItem(id: TourSample.outline, intensity: .focus, description: "Write project outline", count: 2),
            QueueItem(id: TourSample.emails, intensity: .regular, description: "Answer emails", count: 1),
            QueueItem(id: TourSample.contract, intensity: .intense, description: "Review contract", count: 1),
        ]
        session.done = [
            QueueItem(id: TourSample.plannedWeek, intensity: .regular, description: "Plan the week", count: 1, workedSeconds: 25 * 60),
        ]
        session.didMigrateHistory = true
        session.didMigrateWorkedSeconds = true
        return session
    }
}

public enum TourSample {
    public static let outline = UUID(uuidString: "C2000001-0000-4000-8000-000000000001")!
    public static let emails = UUID(uuidString: "C2000001-0000-4000-8000-000000000002")!
    public static let contract = UUID(uuidString: "C2000001-0000-4000-8000-000000000003")!
    public static let plannedWeek = UUID(uuidString: "C2000001-0000-4000-8000-000000000004")!
}

#if SLIMPOMO_DEV
extension Session {
    /// Replaces history and today's Done. The queue and the running timer stay.
    public mutating func devReplaceHistory(_ events: [HistoryEvent], doneToday: [QueueItem], day: Date) {
        history = events
        done = doneToday
        doneDay = day
        didMigrateHistory = true
        didMigrateWorkedSeconds = true
    }

    public mutating func devClearHistory() {
        history = []
        didMigrateHistory = true
        didMigrateWorkedSeconds = true
    }

    /// Done belongs to an earlier day, and the timer is idle, so launch can clear it.
    public mutating func devInstallStaleDone(_ rows: [QueueItem], day: Date) {
        done = rows
        doneDay = day
        didMigrateHistory = true
        didMigrateWorkedSeconds = true
        becomeIdle()
    }

    public mutating func devInstallLater(_ items: [LaterItem]) {
        later = items
    }
}
#endif
