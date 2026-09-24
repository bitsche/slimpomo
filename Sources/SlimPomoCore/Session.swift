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
            IntensityMode(name: "Regular", workMinutes: 25, breakMinutes: 5, red: 0.78, green: 0.84, blue: 0.80)
        case .focus:
            IntensityMode(name: "Focus", workMinutes: 50, breakMinutes: 10, red: 0.93, green: 0.80, blue: 0.58)
        case .intense:
            IntensityMode(name: "Intense", workMinutes: 75, breakMinutes: 15, red: 0.95, green: 0.64, blue: 0.60)
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

    public init(id: UUID, intensity: Intensity, description: String, count: Int, completed: Int = 0, sourceID: UUID? = nil) {
        self.id = id
        self.intensity = intensity
        self.description = description
        self.count = count
        self.completed = completed
        self.sourceID = sourceID
    }

    private enum CodingKeys: String, CodingKey {
        case id, intensity, description, count, completed, sourceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        intensity = try container.decode(Intensity.self, forKey: .intensity)
        description = try container.decode(String.self, forKey: .description)
        count = try container.decode(Int.self, forKey: .count)
        completed = try container.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        sourceID = try container.decodeIfPresent(UUID.self, forKey: .sourceID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(description, forKey: .description)
        try container.encode(count, forKey: .count)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(sourceID, forKey: .sourceID)
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
    public var workMinutes: Int

    public init(id: UUID, timestamp: Date, queueItemId: UUID, taskName: String, mode: Intensity, workMinutes: Int) {
        self.id = id
        self.timestamp = timestamp
        self.queueItemId = queueItemId
        self.taskName = taskName
        self.mode = mode
        self.workMinutes = workMinutes
    }
}

public struct HistoryRow: Identifiable, Equatable, Sendable {
    public var queueItemId: UUID
    public var taskName: String
    public var mode: Intensity
    public var count: Int

    public var id: UUID { queueItemId }
}

public struct HistoryDay: Identifiable, Equatable, Sendable {
    public var day: Date
    public var pomodoros: Int
    public var workMinutes: Int
    public var rows: [HistoryRow]

    public var id: Date { day }
}

public struct SessionMenuAction: Equatable, Sendable {
    public var title: String
    public var isEnabled: Bool
}

public struct Session: Equatable, Codable {
    public static let maxPomodoros = 5

    public private(set) var queue: [QueueItem]
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

    public init() {
        queue = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case queue, done, phase, isRunning, remaining, phaseDuration, activeItemID, activeDescription, endsAt, lockedBreakDuration
        case history, doneDay, didMigrateHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decode([QueueItem].self, forKey: .queue)
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(queue, forKey: .queue)
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
    }

    public var activeItem: QueueItem? {
        guard let activeItemID else { return nil }
        return queue.first { $0.id == activeItemID }
    }

    public var hasWorkQueued: Bool {
        queue.contains { $0.count > 0 }
    }

    public var menuAction: SessionMenuAction {
        switch phase {
        case .idle:
            return SessionMenuAction(title: "Start next pomodoro", isEnabled: hasWorkQueued)
        case .work:
            if isRunning {
                return SessionMenuAction(title: "Pomodoro running", isEnabled: false)
            }
            return SessionMenuAction(title: "Resume pomodoro", isEnabled: true)
        case .breakTime:
            if isRunning {
                return SessionMenuAction(title: "Break running", isEnabled: false)
            }
            return SessionMenuAction(title: "Resume break", isEnabled: true)
        }
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
                    workMinutes: item.intensity.mode.workMinutes
                ))
            }
        }
        doneDay = calendar.startOfDay(for: now)
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
                        count: 0
                    )
                }
                rows[event.queueItemId]?.taskName = event.taskName
                rows[event.queueItemId]?.mode = event.mode
                rows[event.queueItemId]?.count += 1
            }
            return HistoryDay(
                day: day,
                pomodoros: events.count,
                workMinutes: events.reduce(0) { $0 + $1.workMinutes },
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

    public mutating func moveUp(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }), index > 0 else { return }
        queue.swapAt(index, index - 1)
    }

    public mutating func moveDown(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }), index + 1 < queue.count else { return }
        queue.swapAt(index, index + 1)
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
        settleDoneDay(now: now, calendar: calendar, force: true)
        let finished = queue[index]
        activeDescription = finished.description
        queue[index].count = max(0, queue[index].count - 1)
        queue[index].completed += 1
        recordFinishedPomodoro(from: finished, at: now)
        let breakDuration = lockedBreakDuration ?? finished.intensity.breakDuration
        if queue[index].count <= 0 {
            queue.remove(at: index)
        }
        beginBreak(duration: breakDuration, itemID: id, now: now)
    }

    private mutating func recordFinishedPomodoro(from item: QueueItem, at now: Date) {
        history.append(HistoryEvent(
            id: UUID(),
            timestamp: now,
            queueItemId: item.id,
            taskName: item.description,
            mode: item.intensity,
            workMinutes: item.intensity.mode.workMinutes
        ))
        if let index = done.lastIndex(where: { $0.sourceID == item.id }) {
            done[index].count += 1
            return
        }
        done.append(QueueItem(
            id: UUID(),
            intensity: item.intensity,
            description: item.description,
            count: 1,
            sourceID: item.id
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
}
