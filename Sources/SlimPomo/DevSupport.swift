#if SLIMPOMO_DEV
import Foundation
import SwiftUI
import SlimPomoCore

struct DevBadge: View {
    var color: Color

    var body: some View {
        Text("DEV")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum DevLaunch {
    static func apply(to session: inout Session, now: Date) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetAll") {
            resetDefaults()
            session = Session()
            return
        }
        if args.contains("-seedHistoryLarge") {
            DevSeed.install(into: &session, now: now, large: true)
        } else if args.contains("-seedHistory") {
            DevSeed.install(into: &session, now: now, large: false)
        } else if args.contains("-clearHistory") {
            session.devClearHistory()
        } else if args.contains("-staleDone") {
            DevSeed.installStaleDone(into: &session, now: now)
        }
    }

    private static func resetDefaults() {
        let defaults = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: id)
        }
        for key in ["SlimPomo.draftIntensity", "SlimPomo.windowSize", "SlimPomo.historyWindowSize", "SlimPomo.depthHintDismissed"] {
            defaults.removeObject(forKey: key)
        }
    }
}

enum DevSeed {
    private static let seed: UInt64 = 0x534C494D504F4D4F
    fileprivate static let longTaskName = "Prepare the release notes for the history window, including the day headers, push-back, and the empty-state copy today."

    static func install(into session: inout Session, now: Date, large: Bool) {
        let calendar = Calendar.current
        let builder = Builder(now: now, calendar: calendar, rng: SeededRandom(seed: seed))
        builder.build(large: large)
        let today = calendar.startOfDay(for: now)
        session.devReplaceHistory(
            builder.events,
            doneToday: builder.doneRows(on: today),
            day: today
        )
    }

    static func installStaleDone(into session: inout Session, now: Date) {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let rows = [
            QueueItem(id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!, intensity: .regular, description: "Write the notes", count: 2, sourceID: UUID(uuidString: "B1000001-0000-4000-8000-000000000001")!),
            QueueItem(id: UUID(uuidString: "A1000001-0000-4000-8000-000000000002")!, intensity: .focus, description: "Review the queue", count: 1, sourceID: UUID(uuidString: "B1000001-0000-4000-8000-000000000002")!),
            QueueItem(id: UUID(uuidString: "A1000001-0000-4000-8000-000000000003")!, intensity: .intense, description: "Plan the next day", count: 3, sourceID: UUID(uuidString: "B1000001-0000-4000-8000-000000000003")!),
        ]
        session.devInstallStaleDone(rows, day: yesterday)
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func int(_ range: Range<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func uuid() -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 {
            bytes[index] = UInt8(truncatingIfNeeded: next())
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private final class Builder {
    let now: Date
    let calendar: Calendar
    var rng: SeededRandom
    var events: [HistoryEvent] = []
    var occupied: Set<Date> = []

    init(now: Date, calendar: Calendar, rng: SeededRandom) {
        self.now = now
        self.calendar = calendar
        self.rng = rng
    }

    func build(large: Bool) {
        let write = rng.uuid()
        let review = rng.uuid()
        let reviewCopy = rng.uuid()
        let plan = rng.uuid()
        let email = rng.uuid()
        let reading = rng.uuid()
        let fix = rng.uuid()
        let deep = rng.uuid()
        let outline = rng.uuid()
        let longTask = rng.uuid()
        let late = rng.uuid()
        let early = rng.uuid()
        let archive = rng.uuid()
        let budget = rng.uuid()
        let retro = rng.uuid()
        let notes = rng.uuid()

        repeatAdd(daysAgo: 0, startHour: 9, startMinute: 15, step: 50, count: 2, task: write, name: "Write", mode: .regular)
        add(daysAgo: 0, hour: 11, minute: 20, task: review, name: "Review", mode: .focus)
        repeatAdd(daysAgo: 0, startHour: 13, startMinute: 0, step: 70, count: 3, task: plan, name: "Plan", mode: .intense)
        add(daysAgo: 0, hour: 17, minute: 5, task: longTask, name: DevSeed.longTaskName, mode: .regular)

        repeatAdd(daysAgo: 1, startHour: 9, startMinute: 40, step: 80, count: 2, task: email, name: "Email", mode: .regular)
        repeatAdd(daysAgo: 1, startHour: 13, startMinute: 10, step: 60, count: 2, task: reading, name: "Read", mode: .focus)
        add(daysAgo: 1, hour: 16, minute: 45, task: fix, name: "Fix", mode: .intense)

        repeatAdd(daysAgo: 4, startHour: 8, startMinute: 0, step: 40, count: 9, task: deep, name: "Deep work", mode: .focus)

        repeatAdd(daysAgo: 5, startHour: 10, startMinute: 0, step: 50, count: 2, task: review, name: "Review", mode: .regular)
        repeatAdd(daysAgo: 5, startHour: 14, startMinute: 0, step: 40, count: 3, task: reviewCopy, name: "Review", mode: .focus)

        repeatAdd(daysAgo: 7, startHour: 9, startMinute: 0, step: 50, count: 2, task: outline, name: "Outline", mode: .regular)
        repeatAdd(daysAgo: 7, startHour: 11, startMinute: 30, step: 50, count: 3, task: outline, name: "Outline for the talk", mode: .intense)

        add(daysAgo: 12, hour: 23, minute: 54, task: late, name: "Late session", mode: .regular)
        add(daysAgo: 11, hour: 0, minute: 6, task: early, name: "After midnight", mode: .focus)

        let lastYear = calendar.component(.year, from: now) - 1
        add(on: date(lastYear, 12, 4, 10, 30), task: archive, name: "Archive", mode: .regular)
        add(on: date(lastYear, 12, 11, 11, 15), task: budget, name: "Budget", mode: .focus)
        add(on: date(lastYear, 12, 18, 15, 40), task: retro, name: "Retro", mode: .intense)
        add(on: date(lastYear, 12, 27, 9, 5), task: notes, name: "Notes", mode: .regular)

        let pool: [(UUID, String, Intensity)] = [
            (write, "Write", .regular),
            (plan, "Plan", .intense),
            (email, "Email", .regular),
            (reading, "Read", .focus),
            (fix, "Fix", .intense),
        ]
        // Forced days stay filled, so the remaining days skip often enough that about 30% of the 60-day span is empty.
        for ago in 2..<60 where !occupied.contains(day(ago)) && rng.int(0..<100) >= 34 {
            scatter(daysAgo: ago, count: rng.int(1..<5), pool: pool, step: 40)
        }
        if large {
            for ago in 60...(365 * 3) where !occupied.contains(day(ago)) && rng.int(0..<100) < 70 {
                scatter(daysAgo: ago, count: rng.int(2..<13), pool: pool, step: 40)
            }
        }

        events.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        check(large: large)
    }

    func doneRows(on today: Date) -> [QueueItem] {
        var order: [UUID] = []
        var rows: [UUID: (name: String, mode: Intensity, count: Int)] = [:]
        for event in events where calendar.isDate(event.timestamp, inSameDayAs: today) {
            if rows[event.queueItemId] == nil {
                order.append(event.queueItemId)
                rows[event.queueItemId] = (event.taskName, event.mode, 0)
            }
            rows[event.queueItemId]?.name = event.taskName
            rows[event.queueItemId]?.mode = event.mode
            rows[event.queueItemId]?.count += 1
        }
        return order.map { id in
            let row = rows[id]!
            return QueueItem(
                id: rng.uuid(),
                intensity: row.mode,
                description: row.name,
                count: row.count,
                sourceID: id
            )
        }
    }

    private func scatter(daysAgo ago: Int, count: Int, pool: [(UUID, String, Intensity)], step: Int) {
        for index in 0..<count {
            let minute = 8 * 60 + index * step
            guard minute < 22 * 60 else { break }
            let item = pool[rng.int(0..<pool.count)]
            add(daysAgo: ago, hour: minute / 60, minute: minute % 60, task: item.0, name: item.1, mode: item.2)
        }
    }

    private func repeatAdd(daysAgo: Int, startHour: Int, startMinute: Int, step: Int, count: Int, task: UUID, name: String, mode: Intensity) {
        var minute = startHour * 60 + startMinute
        for _ in 0..<count {
            add(daysAgo: daysAgo, hour: minute / 60, minute: minute % 60, task: task, name: name, mode: mode)
            minute += step
        }
    }

    private func add(daysAgo: Int, hour: Int, minute: Int, task: UUID, name: String, mode: Intensity) {
        add(on: calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day(daysAgo))!, task: task, name: name, mode: mode)
    }

    private func add(on timestamp: Date, task: UUID, name: String, mode: Intensity) {
        events.append(HistoryEvent(
            id: rng.uuid(),
            timestamp: timestamp,
            queueItemId: task,
            taskName: name,
            mode: mode,
            workMinutes: mode.mode.workMinutes
        ))
        occupied.insert(calendar.startOfDay(for: timestamp))
    }

    private func day(_ ago: Int) -> Date {
        calendar.date(byAdding: .day, value: -ago, to: calendar.startOfDay(for: now))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func check(large: Bool) {
        precondition(DevSeed.longTaskName.count >= 110 && DevSeed.longTaskName.count <= 140)
        precondition(events.contains { $0.taskName == DevSeed.longTaskName })
        precondition(events.allSatisfy { $0.workMinutes == $0.mode.mode.workMinutes })
        precondition(Set(events.map(\.mode)) == Set(Intensity.allCases))

        var byDay: [Date: [HistoryEvent]] = [:]
        for event in events {
            byDay[calendar.startOfDay(for: event.timestamp), default: []].append(event)
        }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        precondition(Set(byDay[today, default: []].map(\.queueItemId)).count >= 3)
        precondition(Set(byDay[yesterday, default: []].map(\.queueItemId)).count >= 3)
        precondition(byDay.values.contains { Dictionary(grouping: $0, by: \.queueItemId).values.contains { $0.count >= 8 } })
        precondition(byDay.values.contains { day in
            Dictionary(grouping: day, by: \.taskName).values.contains { Set($0.map(\.queueItemId)).count >= 2 }
        })
        precondition(byDay.values.contains { day in
            Dictionary(grouping: day, by: \.queueItemId).values.contains { group in
                Set(group.map(\.taskName)).count >= 2 && group.last?.taskName == "Outline for the talk"
            }
        })

        func stamp(_ event: HistoryEvent) -> (hour: Int, minute: Int) {
            (calendar.component(.hour, from: event.timestamp), calendar.component(.minute, from: event.timestamp))
        }
        let lateEvent = events.first { stamp($0).hour == 23 && (50..<60).contains(stamp($0).minute) }
        let earlyEvent = events.first { stamp($0).hour == 0 && (0..<10).contains(stamp($0).minute) }
        precondition(lateEvent != nil && earlyEvent != nil)
        precondition(!calendar.isDate(lateEvent!.timestamp, inSameDayAs: earlyEvent!.timestamp))

        let thisYear = calendar.component(.year, from: now)
        let lastYearDays = Set(byDay.keys.filter { calendar.component(.year, from: $0) == thisYear - 1 })
        if large || calendar.component(.year, from: day(59)) < thisYear {
            precondition(lastYearDays.count >= 3)
        } else {
            precondition(lastYearDays.count == 4)
        }

        var empty = 0
        for ago in 0..<60 where byDay[day(ago)] == nil {
            empty += 1
        }
        precondition((12...24).contains(empty), "Expected about 30% of 60 days to be empty, got \(empty)")
    }
}
#endif
