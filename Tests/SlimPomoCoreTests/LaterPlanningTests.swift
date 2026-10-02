import Foundation
import Testing
@testable import SlimPomoCore

struct LaterPlanningTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let tomorrow = "2026-09-26"
    let monday = "2026-09-28"

    private func session(_ names: [String]) -> Session {
        var session = Session()
        for name in names {
            session.addItem(description: name, intensity: .regular, count: 1)
        }
        return session
    }

    private func id(_ name: String, in session: Session) -> UUID {
        (session.queue.first { $0.description == name } ?? session.queue[0]).id
    }

    private func names(_ session: Session, day: String) -> [String] {
        session.laterGroups().first { $0.day == day }?.items.map(\.description) ?? []
    }

    @Test func snoozeAtAPositionLandsInThatDayGroup() {
        var s = session(["A", "B", "C", "D"])
        s.snooze(id: id("A", in: s), returnDay: tomorrow, now: start)
        s.snooze(id: id("B", in: s), returnDay: tomorrow, now: start)
        #expect(names(s, day: tomorrow) == ["A", "B"])
        s.snooze(id: id("C", in: s), returnDay: tomorrow, now: start, position: 1)
        #expect(names(s, day: tomorrow) == ["A", "C", "B"])
        s.snooze(id: id("D", in: s), returnDay: tomorrow, now: start, position: 0)
        #expect(names(s, day: tomorrow) == ["D", "A", "C", "B"])
        #expect(s.queue.isEmpty)
    }

    @Test func snoozeIntoAnEmptyDayCreatesTheGroup() {
        var s = session(["A", "B"])
        s.snooze(id: id("A", in: s), returnDay: monday, now: start, position: 0)
        s.snooze(id: id("B", in: s), returnDay: tomorrow, now: start, position: 5)
        #expect(s.laterGroups().map(\.day) == [tomorrow, monday])
    }

    @Test func menuSnoozesGoToTheEndOfTheDay() {
        var s = session(["A", "B", "C"])
        s.snooze(id: id("A", in: s), returnDay: tomorrow, now: start)
        s.snooze(id: id("B", in: s), returnDay: monday, now: start)
        s.snooze(id: id("C", in: s), returnDay: monday, now: start)
        s.retargetLater(id: s.later.first { $0.description == "B" }!.id, returnDay: tomorrow, now: start)
        #expect(names(s, day: tomorrow) == ["A", "B"])
        #expect(names(s, day: monday) == ["C"])
    }

    @Test func moveLaterReordersWithinADayAndAcrossDays() {
        var s = session(["A", "B", "C", "D"])
        for name in ["A", "B", "C"] {
            s.snooze(id: id(name, in: s), returnDay: tomorrow, now: start)
        }
        s.snooze(id: id("D", in: s), returnDay: monday, now: start)
        let a = s.later.first { $0.description == "A" }!.id
        s.moveLater(id: a, toDay: tomorrow, position: 2)
        #expect(names(s, day: tomorrow) == ["B", "C", "A"])
        s.moveLater(id: a, toDay: monday, position: 0, now: start)
        #expect(names(s, day: tomorrow) == ["B", "C"])
        #expect(names(s, day: monday) == ["A", "D"])
        #expect(s.later.first { $0.id == a }?.returnDay == monday)
    }

    @Test func movingBetweenDaysKeepsModeCountAndName() {
        var s = Session()
        s.addItem(description: "Deep", intensity: .intense, count: 3)
        let deep = s.queue[0].id
        s.snooze(id: deep, returnDay: tomorrow, now: start)
        s.moveLater(id: deep, toDay: monday, position: 0, now: start)
        let item = s.later[0]
        #expect(item.description == "Deep")
        #expect(item.intensity == .intense)
        #expect(item.count == 3)
    }

    @Test func returnLaterAtAnIndexLandsThereButNeverAboveARunningTask() {
        var s = session(["Running", "B", "C"])
        _ = s.start(now: start)
        s.addItem(description: "Parked", intensity: .focus, count: 2)
        let parked = s.queue.last!.id
        s.snooze(id: parked, returnDay: tomorrow, now: start)

        s.returnLater(id: parked, to: 0)
        #expect(s.queue.map(\.description) == ["Running", "Parked", "B", "C"])

        s.snooze(id: parked, returnDay: tomorrow, now: start)
        s.returnLater(id: parked, to: 2)
        #expect(s.queue.map(\.description) == ["Running", "B", "Parked", "C"])
        #expect(s.queue[2].count == 2)
        #expect(s.queue[2].intensity == .focus)
    }

    @Test func backToQueueAppendsToTheEnd() {
        var s = session(["A", "B", "C"])
        s.snooze(id: id("A", in: s), returnDay: tomorrow, now: start)
        s.returnLater(id: s.later[0].id)
        #expect(s.queue.map(\.description) == ["B", "C", "A"])
    }

    @Test func queueSlotsStartBelowTheTaskUnderNow() {
        var s = session(["Running", "B", "C"])
        #expect(s.queueSlots(excluding: nil) == 0...3)
        _ = s.start(now: start)
        #expect(s.queueSlots(excluding: nil) == 1...3)
        let c = id("C", in: s)
        #expect(s.queueSlots(excluding: c) == 1...2)
        s.addItem(description: "Parked", intensity: .regular, count: 1)
        let parked = s.queue.last!.id
        s.snooze(id: parked, returnDay: tomorrow, now: start)
        #expect(s.queueSlots(excluding: parked) == 1...3)
    }

    @Test func dragRulesFollowTheRunningTask() {
        var s = session(["Running", "B"])
        let running = id("Running", in: s)
        let b = id("B", in: s)
        #expect(s.canDrag(id: running))
        _ = s.start(now: start)
        #expect(s.canDrag(id: running) == false)
        #expect(s.canDrag(id: b))
        s.snooze(id: b, returnDay: tomorrow, now: start)
        #expect(s.canDrag(id: b))
        _ = s.markDone(now: start.addingTimeInterval(60))
        #expect(s.phase == .breakTime)
    }

    @Test func midnightReturnsEachDayInItsPlannedOrderEarlierDaysFirst() {
        let calendar = PlanClock.calendar
        let friday = PlanClock.date(2026, 9, 25, 18, 0)
        var s = session(["A", "B", "C", "D", "Stay"])
        for name in ["A", "B", "C"] {
            s.snooze(id: id(name, in: s), returnDay: tomorrow, now: friday)
        }
        s.snooze(id: id("D", in: s), returnDay: "2026-09-24", now: friday)
        let c = s.later.first { $0.description == "C" }!.id
        s.moveLater(id: c, toDay: tomorrow, position: 0)
        #expect(names(s, day: tomorrow) == ["C", "A", "B"])
        let saturday = PlanClock.date(2026, 9, 26, 0, 5)
        let returned = s.returnDueLater(now: saturday, calendar: calendar)
        #expect(returned)
        #expect(s.queue.map(\.description) == ["Stay", "D", "C", "A", "B"])
        #expect(s.later.isEmpty)
    }

    @Test func legacyLaterDataMigratesOnceBySnoozeTime() throws {
        var s = session(["A", "B", "C"])
        for name in ["A", "B", "C"] {
            s.snooze(id: id(name, in: s), returnDay: tomorrow, now: start)
        }
        let json = try JSONEncoder().encode(s)
        var object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object.removeValue(forKey: "didMigrateLaterOrder")
        var later = try #require(object["later"] as? [[String: Any]])
        let stamps: [String: Double] = ["A": 300, "B": 100, "C": 200]
        for index in later.indices {
            let name = later[index]["description"] as? String ?? ""
            later[index]["snoozedAt"] = stamps[name]
        }
        object["later"] = later
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        var loaded = try decoder.decode(Session.self, from: legacy)
        #expect(loaded.didMigrateLaterOrder == false)
        loaded.migrateLaterOrderIfNeeded()
        #expect(names(loaded, day: tomorrow) == ["B", "C", "A"])
        loaded.moveLater(id: loaded.later[0].id, toDay: tomorrow, position: 2)
        loaded.migrateLaterOrderIfNeeded()
        #expect(names(loaded, day: tomorrow) == ["C", "A", "B"])
    }

    @Test func laterOrderSurvivesEncoding() throws {
        var s = session(["A", "B", "C"])
        for name in ["A", "B", "C"] {
            s.snooze(id: id(name, in: s), returnDay: tomorrow, now: start)
        }
        s.moveLater(id: s.later.first { $0.description == "C" }!.id, toDay: tomorrow, position: 0)
        let data = try JSONEncoder().encode(s)
        let loaded = try JSONDecoder().decode(Session.self, from: data)
        #expect(names(loaded, day: tomorrow) == ["C", "A", "B"])
    }

    @Test func laterRowsCanBeEdited() {
        var s = session(["A"])
        let a = id("A", in: s)
        s.snooze(id: a, returnDay: tomorrow, now: start)
        s.updateLaterDescription(id: a, description: "Renamed")
        s.updateLaterIntensity(id: a, intensity: .intense)
        s.setLaterCount(id: a, count: 9)
        #expect(s.later[0].description == "Renamed")
        #expect(s.later[0].intensity == .intense)
        #expect(s.later[0].count == Session.maxPomodoros)
        s.setLaterCount(id: a, count: -2)
        #expect(s.later[0].count == 0)
    }
}

private enum PlanClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
