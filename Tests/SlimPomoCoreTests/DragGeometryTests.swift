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
        let firstDayTop: CGFloat = 8 + 114 + 12 + 24 + 6 + 18
        let secondDayTop: CGFloat = tops[1] + 38 + 10 + 18
        #expect(tops[1] == firstDayTop)
        #expect(tops[2] == secondDayTop)
        #expect(DragGeometry.bottom(blocks) == tops[2] + 114)
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
        #expect(DragGeometry.row(at: top + 37, in: blocks) == nil)
        #expect(DragGeometry.row(at: top + 38 + 5, in: blocks)?.row == 1)
        #expect(DragGeometry.row(at: top - 4, in: blocks) == nil)
    }

    @Test func rowCellsTouchAndCoverTheGaps() {
        let blocks = DragGeometry.blocks(regions(queue: 2, first: 0, second: 0), held: nil)
        let top = DragGeometry.tops(blocks)[0]
        #expect(DragGeometry.rowCell(at: top + 36.5, in: blocks)?.row == 0)
        #expect(DragGeometry.rowCell(at: top + 37.5, in: blocks)?.row == 1)
        #expect(DragGeometry.rowCell(at: top - 1, in: blocks)?.row == 0)
        #expect(DragGeometry.rowCell(at: top - 2, in: blocks) == nil)
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
