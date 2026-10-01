import CoreGraphics
import Foundation
import Testing
@testable import SlimPomoCore

private let monday = DragRegionID.day("2026-10-05")
private let tuesday = DragRegionID.day("2026-10-06")

private func regions(queue: Int, slots: ClosedRange<Int>? = nil, first: Int, second: Int, planning: Bool = true) -> [DragRegionSpec] {
    [
        DragRegionSpec(id: .queue, items: queue, slots: slots ?? 0...queue, showsZoneWhenEmpty: false),
        DragRegionSpec(id: monday, items: first, slots: 0...first, showsZoneWhenEmpty: planning),
        DragRegionSpec(id: tuesday, items: second, slots: 0...second, showsZoneWhenEmpty: planning),
    ]
}

@Suite struct DragGeometryTests {
    @Test func blocksStackFromTheQueueDown() {
        let blocks = DragGeometry.blocks(regions(queue: 2, first: 0, second: 3), held: .queue)
        #expect(blocks.map(\.rows) == [3, 1, 3])
        let tops = DragGeometry.tops(blocks)
        #expect(tops[0] == 8)
        let firstDayTop: CGFloat = 8 + 123 + 9 + 24 + 6 + 18
        let secondDayTop: CGFloat = tops[1] + 41 + 10 + 18
        #expect(tops[1] == firstDayTop)
        #expect(tops[2] == secondDayTop)
        #expect(DragGeometry.bottom(blocks) == tops[2] + 123)
    }

    @Test func anEmptyQueueTakesNoSpaceAndLaterUsesTheLongerGap() {
        let blocks = DragGeometry.blocks(regions(queue: 0, first: 1, second: 0), held: nil)
        #expect(blocks.map(\.rows) == [0, 1, 1])
        let expected: CGFloat = 14 + 24 + 6 + 18
        #expect(DragGeometry.tops(blocks)[1] == expected)
    }

    @Test func hiddenRegionsDrawNothing() {
        var specs = regions(queue: 1, first: 1, second: 1)
        specs[1].visible = false
        specs[2].visible = false
        let blocks = DragGeometry.blocks(specs, held: nil)
        #expect(blocks.map(\.rows) == [1, 0, 0])
        #expect(DragGeometry.laterHeader(blocks) == nil)
    }

    @Test func laterHeaderSitsAboveTheFirstHeading() {
        let blocks = DragGeometry.blocks(regions(queue: 1, first: 1, second: 0), held: nil)
        let range = DragGeometry.laterHeader(blocks)
        let top = DragGeometry.tops(blocks)[1]
        let upper: CGFloat = top - 24
        #expect(range?.upperBound == upper)
        #expect(range?.lowerBound == upper - 24)
    }

    @Test func rowLookupIgnoresTheGapBetweenRows() {
        let blocks = DragGeometry.blocks(regions(queue: 2, first: 0, second: 0), held: nil)
        let top = DragGeometry.tops(blocks)[0]
        #expect(DragGeometry.row(at: top + 10, in: blocks)?.row == 0)
        #expect(DragGeometry.row(at: top + 38, in: blocks) == nil)
        #expect(DragGeometry.row(at: top + 41 + 5, in: blocks)?.row == 1)
        #expect(DragGeometry.row(at: top - 4, in: blocks) == nil)
    }

    @Test func staysInsideItsRegionWithTheUsualHysteresis() {
        let specs = regions(queue: 3, first: 0, second: 0)
        let start = DragSlot(region: .queue, index: 1)
        let top = DragGeometry.tops(DragGeometry.blocks(specs, held: .queue))[0]
        let near = DragGeometry.resolve(pointerY: top + 1.2 * 41, regions: specs, current: start)
        #expect(near == start)
        let down = DragGeometry.resolve(pointerY: top + 2.6 * 41, regions: specs, current: start)
        #expect(down == DragSlot(region: .queue, index: 2))
    }

    @Test func movesIntoAnEmptyDayZone() {
        let specs = regions(queue: 2, first: 0, second: 0)
        let start = DragSlot(region: .queue, index: 2)
        let blocks = DragGeometry.blocks(specs, held: .queue)
        let zone = DragGeometry.tops(blocks)[1]
        let slot = DragGeometry.resolve(pointerY: zone + 20, regions: specs, current: start)
        #expect(slot == DragSlot(region: monday, index: 0))
    }

    @Test func movesBackToTheQueueAndKeepsTheRunningTaskOnTop() {
        let specs = regions(queue: 3, slots: 1...3, first: 1, second: 0)
        let start = DragSlot(region: monday, index: 1)
        let blocks = DragGeometry.blocks(specs, held: monday)
        let queueTop = DragGeometry.tops(blocks)[0]
        let slot = DragGeometry.resolve(pointerY: queueTop + 5, regions: specs, current: start)
        #expect(slot.region == .queue)
        #expect(slot.index == 1)
    }

    @Test func sweepingDownThenUpVisitsEachRegionOnce() {
        let specs = regions(queue: 3, first: 2, second: 0)
        func order(_ id: DragRegionID) -> Int {
            switch id {
            case .queue: 0
            case .day(let day): day == "2026-10-05" ? 1 : 2
            }
        }
        var slot = DragSlot(region: .queue, index: 0)
        var seen: [Int] = []
        var y: CGFloat = 0
        while y < 600 {
            slot = DragGeometry.resolve(pointerY: y, regions: specs, current: slot)
            seen.append(order(slot.region))
            y += 2
        }
        #expect(seen == seen.sorted())
        #expect(seen.last == 2)
        var back: [Int] = []
        while y > 0 {
            slot = DragGeometry.resolve(pointerY: y, regions: specs, current: slot)
            back.append(order(slot.region))
            y -= 2
        }
        #expect(back == back.sorted(by: >))
        #expect(back.last == 0)
    }

    @Test func aMoveNeverEndsInAFlipFlop() {
        let specs = regions(queue: 2, first: 0, second: 0)
        var slot = DragSlot(region: .queue, index: 0)
        var y: CGFloat = 0
        while y < 400 {
            let next = DragGeometry.resolve(pointerY: y, regions: specs, current: slot)
            let again = DragGeometry.resolve(pointerY: y, regions: specs, current: next)
            #expect(again == next)
            slot = next
            y += 3
        }
    }
}

@Suite struct PlanDaysTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ stamp: String) -> Date {
        CalendarDay.date(stamp, calendar: calendar()) ?? Date()
    }

    @Test func weekdayOffersTomorrowAndNextMonday() {
        let days = Snooze.planDays(on: date("2026-10-01"), existing: [], calendar: calendar())
        #expect(days.map(\.day) == ["2026-10-02", "2026-10-05"])
        #expect(days.first?.heading == "Tomorrow")
        #expect(days.last?.heading.contains("5") == true)
    }

    @Test func sundayHasOnlyTomorrow() {
        let days = Snooze.planDays(on: date("2026-10-04"), existing: [], calendar: calendar())
        #expect(days.count == 1)
        #expect(days.first?.heading.hasPrefix("Tomorrow (") == true)
    }

    @Test func existingDaysJoinTheOffers() {
        let days = Snooze.planDays(on: date("2026-10-01"), existing: ["2026-10-03"], calendar: calendar())
        #expect(days.map(\.day) == ["2026-10-02", "2026-10-03", "2026-10-05"])
    }
}
