import Foundation

public enum Intensity: String, Codable, CaseIterable, Equatable {
    case regular
    case focus
    case intense

    public var workDuration: TimeInterval {
        switch self {
        case .regular: 25 * 60
        case .focus: 50 * 60
        case .intense: 75 * 60
        }
    }

    public var breakDuration: TimeInterval {
        switch self {
        case .regular: 5 * 60
        case .focus: 10 * 60
        case .intense: 15 * 60
        }
    }
}

public struct QueueItem: Identifiable, Equatable, Codable {
    public var id: UUID
    public var intensity: Intensity
    public var description: String
    public var count: Int

    public init(id: UUID, intensity: Intensity, description: String, count: Int) {
        self.id = id
        self.intensity = intensity
        self.description = description
        self.count = count
    }
}

public enum Phase: String, Codable, Equatable {
    case idle
    case work
    case breakTime
}

public enum SessionEffect: Equatable {
    case none
    case playBell
}

public struct Session: Equatable, Codable {
    public private(set) var queue: [QueueItem]
    public private(set) var phase: Phase
    public private(set) var isRunning: Bool
    public private(set) var remaining: TimeInterval
    public private(set) var phaseDuration: TimeInterval
    public private(set) var activeItemID: UUID?
    public private(set) var endsAt: Date?
    public private(set) var lockedBreakDuration: TimeInterval?

    public init() {
        queue = []
        phase = .idle
        isRunning = false
        remaining = 0
        phaseDuration = 0
        activeItemID = nil
        endsAt = nil
        lockedBreakDuration = nil
    }

    public var activeItem: QueueItem? {
        guard let activeItemID else { return nil }
        return queue.first { $0.id == activeItemID }
    }

    public var hasWorkQueued: Bool {
        queue.contains { $0.count > 0 }
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
            lockedBreakDuration = nil
        }
    }

    public mutating func start(now: Date) -> SessionEffect {
        guard phase == .idle, let next = queue.first(where: { $0.count > 0 }) else { return .none }
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

    public mutating func markDone(now: Date) -> SessionEffect {
        guard phase == .work else { return .none }
        completeWork(now: now)
        return .none
    }

    public mutating func skipBreak(now: Date) -> SessionEffect {
        guard phase == .breakTime else { return .none }
        finishBreak(now: now)
        return .none
    }

    public mutating func reconcile(now: Date) -> SessionEffect {
        guard isRunning, let endsAt, now >= endsAt else { return .none }
        switch phase {
        case .work:
            completeWork(now: now)
            return .playBell
        case .breakTime:
            finishBreak(now: now)
            return .playBell
        case .idle:
            return .none
        }
    }

    public mutating func addItem(description: String, intensity: Intensity, count: Int) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clamped = min(99, max(1, count))
        queue.append(QueueItem(id: UUID(), intensity: intensity, description: trimmed, count: clamped))
    }

    public mutating func updateDescription(id: UUID, description: String) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].description = description
    }

    public mutating func updateIntensity(id: UUID, intensity: Intensity) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].intensity = intensity
    }

    /// Count is the remaining pomodoros, including the one in progress.
    /// The active work item stays at least 1. Zero removes a queued item.
    /// During its break, the active item may sit at 0 until the break ends.
    public mutating func setCount(id: UUID, count: Int) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if count < 1 {
            if phase == .work, activeItemID == id {
                queue[index].count = 1
                return
            }
            if phase == .breakTime, activeItemID == id {
                queue[index].count = 0
                return
            }
            queue.remove(at: index)
            return
        }
        queue[index].count = min(count, 99)
    }

    public mutating func remove(id: UUID, now: Date) -> SessionEffect {
        let wasActive = id == activeItemID && phase != .idle
        queue.removeAll { $0.id == id }
        guard wasActive else { return .none }
        if let next = queue.first(where: { $0.count > 0 }) {
            beginWork(on: next, now: now)
        } else {
            becomeIdle()
        }
        return .none
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

    private mutating func completeWork(now: Date) {
        guard phase == .work, let id = activeItemID, let index = queue.firstIndex(where: { $0.id == id }) else {
            becomeIdle()
            return
        }
        queue[index].count = max(0, queue[index].count - 1)
        let breakDuration = lockedBreakDuration ?? queue[index].intensity.breakDuration
        beginBreak(duration: breakDuration, itemID: id, now: now)
    }

    private mutating func finishBreak(now: Date) {
        queue.removeAll { $0.count <= 0 }
        if let next = queue.first(where: { $0.count > 0 }) {
            beginWork(on: next, now: now)
        } else {
            becomeIdle()
        }
    }

    private mutating func becomeIdle() {
        phase = .idle
        isRunning = false
        remaining = 0
        phaseDuration = 0
        activeItemID = nil
        endsAt = nil
        lockedBreakDuration = nil
    }
}
