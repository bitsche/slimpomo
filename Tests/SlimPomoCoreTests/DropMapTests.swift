import CoreGraphics
import Foundation
import Testing
@testable import SlimPomoCore

private let tomorrow = DragRegionID.day("2026-10-02")
private let monday = DragRegionID.day("2026-10-05")

/// Regions as the drag sees them while a task is held: `items` excludes the held task.
private func regions(queue: Int, slots: ClosedRange<Int>? = nil, tomorrow first: Int, monday second: Int) -> [DragRegionSpec] {
    [
        DragRegionSpec(id: .queue, items: queue, slots: slots ?? 0...queue, showsZoneWhenEmpty: false),
        DragRegionSpec(id: tomorrow, items: first, slots: 0...first, showsZoneWhenEmpty: true),
        DragRegionSpec(id: monday, items: second, slots: 0...second, showsZoneWhenEmpty: true),
    ]
}

private func target(at y: CGFloat, regions: [DragRegionSpec], from slot: DragSlot) -> DragSlot? {
    DropMap.band(at: y, in: DropMap.bands(regions: regions, held: slot))?.slot
}

/// The pointer stays where it is while the list shifts under it. Returns where the held task ends up.
private func settle(pointerY y: CGFloat, regions: [DragRegionSpec], from slot: DragSlot, rounds: Int = 6) -> DropTarget {
    var current = DropTarget(slot: slot)
    for _ in 0..<rounds {
        current = DropMap.resolve(pointerY: y, regions: regions, current: current)
    }
    return current
}

@Suite struct DropMapTests {
    private let heldConfigs: [(specs: [DragRegionSpec], held: DragSlot)] = [
        (regions(queue: 3, tomorrow: 0, monday: 0), DragSlot(region: .queue, index: 2)),
        (regions(queue: 3, tomorrow: 2, monday: 0), DragSlot(region: tomorrow, index: 1)),
        (regions(queue: 0, tomorrow: 1, monday: 4), DragSlot(region: monday, index: 0)),
        (regions(queue: 4, slots: 1...4, tomorrow: 0, monday: 2), DragSlot(region: monday, index: 2)),
        (regions(queue: 1, tomorrow: 0, monday: 0), DragSlot(region: tomorrow, index: 0)),
    ]

    @Test func bandsTileTheListWithoutGapsOrOverlaps() throws {
        for config in heldConfigs {
            let bands = DropMap.bands(regions: config.specs, held: config.held)
            #expect(bands.first?.minY == -.infinity)
            #expect(bands.last?.maxY == .infinity)
            for pair in zip(bands, bands.dropFirst()) {
                #expect(pair.0.maxY == pair.1.minY)
                #expect(pair.0.minY < pair.0.maxY)
            }
            var y: CGFloat = -200
            while y < 1500 {
                #expect(bands.filter { $0.contains(y) }.count == 1)
                y += 0.5
            }
        }
    }

    @Test func aRowTakesBeforeInItsUpperHalfAndAfterInItsLowerHalf() {
        let specs = regions(queue: 3, tomorrow: 0, monday: 0)
        let held = DragSlot(region: .queue, index: 3)
        let blocks = DragGeometry.blocks(specs, held: .queue)
        let top = DragGeometry.tops(blocks)[0]
        #expect(target(at: top + 5, regions: specs, from: held) == DragSlot(region: .queue, index: 0))
        #expect(target(at: top + 30, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
        #expect(target(at: top + 41 + 5, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
        #expect(target(at: top + 41 + 30, regions: specs, from: held) == DragSlot(region: .queue, index: 2))
        #expect(target(at: top + 38.2, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
        #expect(target(at: top + 41 - 2.4, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
    }

    @Test func aboveTheListAndBelowTheRunningTaskMeansTheTop() {
        let specs = regions(queue: 3, slots: 1...3, tomorrow: 0, monday: 0)
        let held = DragSlot(region: .queue, index: 3)
        #expect(target(at: -300, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
        #expect(target(at: 0, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
        #expect(target(at: 12, regions: specs, from: held) == DragSlot(region: .queue, index: 1))
    }

    @Test func belowTheLastQueueRowUpToTheHeaderMeansTheEndOfTheQueue() {
        let specs = regions(queue: 2, tomorrow: 1, monday: 0)
        let held = DragSlot(region: .queue, index: 2)
        let blocks = DragGeometry.blocks(specs, held: .queue)
        let top = DragGeometry.tops(blocks)[0]
        let end = top + 3 * 41
        #expect(target(at: end, regions: specs, from: held) == DragSlot(region: .queue, index: 2))
        #expect(target(at: end + 8, regions: specs, from: held) == DragSlot(region: .queue, index: 2))
    }

    @Test func theHeaderAndEveryDayLabelMeanTheStartOfTheGroupBelow() {
        let specs = regions(queue: 2, tomorrow: 2, monday: 1)
        let held = DragSlot(region: .queue, index: 2)
        let blocks = DragGeometry.blocks(specs, held: .queue)
        let tops = DragGeometry.tops(blocks)
        let header = DragGeometry.laterHeader(blocks)
        #expect(header != nil)
        let middle = ((header?.lowerBound ?? 0) + (header?.upperBound ?? 0)) / 2
        #expect(target(at: middle, regions: specs, from: held) == DragSlot(region: tomorrow, index: 0))
        let label = tops[1] - 18
        #expect(target(at: label + 4, regions: specs, from: held) == DragSlot(region: tomorrow, index: 0))
        let mondayLabel = tops[2] - 18 + 2
        #expect(target(at: mondayLabel, regions: specs, from: held) == DragSlot(region: monday, index: 0))
    }

    @Test func anEmptyDayZoneCoversItsHeightAndHalfTheSpacingAround() {
        let specs = regions(queue: 2, tomorrow: 0, monday: 0)
        let held = DragSlot(region: .queue, index: 2)
        let blocks = DragGeometry.blocks(specs, held: .queue)
        let tops = DragGeometry.tops(blocks)
        let zone = tops[2]
        let expected = DragSlot(region: monday, index: 0)
        #expect(target(at: zone, regions: specs, from: held) == expected)
        #expect(target(at: zone + 35, regions: specs, from: held) == expected)
        #expect(target(at: zone + 100, regions: specs, from: held) == expected)
        #expect(target(at: zone - 15, regions: specs, from: held) == expected)
        let above = target(at: tops[2] - 18 - 6, regions: specs, from: held)
        #expect(above == DragSlot(region: tomorrow, index: 0))
    }

    @Test func doneAndBelowMapToTheEndOfTheLastDay() {
        let specs = regions(queue: 2, tomorrow: 1, monday: 3)
        let held = DragSlot(region: .queue, index: 0)
        #expect(target(at: 5000, regions: specs, from: held) == DragSlot(region: monday, index: 3))
        let empty = regions(queue: 2, tomorrow: 1, monday: 0)
        #expect(target(at: 5000, regions: empty, from: held) == DragSlot(region: monday, index: 0))
    }

    @Test func anEmptyQueueIsStillATargetAboveTheLaterHeader() {
        let specs = regions(queue: 0, tomorrow: 1, monday: 0)
        let held = DragSlot(region: tomorrow, index: 0)
        #expect(target(at: -20, regions: specs, from: held) == DragSlot(region: .queue, index: 0))
        #expect(target(at: 5, regions: specs, from: held) == DragSlot(region: .queue, index: 0))
    }

    @Test func holdsTheSlotUntilThePointerIsFourPointsPast() {
        let specs = regions(queue: 3, tomorrow: 0, monday: 0)
        let held = DragSlot(region: .queue, index: 1)
        let bands = DropMap.bands(regions: specs, held: held)
        let current = bands.filter { $0.slot == held }
        let edge = current.map(\.maxY).max() ?? 0
        let stay = DropMap.resolve(pointerY: edge + 2, regions: specs, current: DropTarget(slot: held))
        #expect(stay.slot == held)
        let go = DropMap.resolve(pointerY: edge + 5, regions: specs, current: DropTarget(slot: held))
        #expect(go.slot == DragSlot(region: .queue, index: 2))
    }

    @Test func goingDownIntoTheLastEmptyDayLandsThereAtOnce() {
        let specs = regions(queue: 3, tomorrow: 2, monday: 0)
        let start = DragSlot(region: .queue, index: 3)
        let zone = DragGeometry.tops(DragGeometry.blocks(specs, held: .queue))[2]
        for offset: CGFloat in [2, 12, 20, 30, 35] {
            let result = settle(pointerY: zone + offset, regions: specs, from: start)
            #expect(result.slot == DragSlot(region: monday, index: 0))
        }
    }

    @Test func goingDownIntoAnEmptyDayThatIsNotLastDoesNotSkipPastIt() {
        let specs = regions(queue: 3, tomorrow: 0, monday: 0)
        let start = DragSlot(region: .queue, index: 3)
        let zone = DragGeometry.tops(DragGeometry.blocks(specs, held: .queue))[1]
        for offset: CGFloat in [2, 12, 20, 30, 35] {
            let result = settle(pointerY: zone + offset, regions: specs, from: start)
            #expect(result.slot == DragSlot(region: tomorrow, index: 0))
        }
    }

    @Test func goingBackUpIntoTheQueueLandsThereAtOnce() {
        let specs = regions(queue: 3, tomorrow: 2, monday: 0)
        let start = DragSlot(region: monday, index: 0)
        let queueTop = DragGeometry.tops(DragGeometry.blocks(specs, held: monday))[0]
        for row in 0..<3 {
            let y = queueTop + CGFloat(row) * 41 + 18
            let result = settle(pointerY: y, regions: specs, from: start)
            #expect(result.slot.region == .queue)
        }
        let result = settle(pointerY: queueTop + 10, regions: specs, from: start)
        #expect(result.slot == DragSlot(region: .queue, index: 0))
    }

    @Test func aSettledTargetStaysPutWhileThePointerDoesNotMove() {
        for config in heldConfigs {
            var y: CGFloat = -40
            while y < 700 {
                let first = settle(pointerY: y, regions: config.specs, from: config.held)
                let again = DropMap.resolve(pointerY: y, regions: config.specs, current: first)
                #expect(again.slot == first.slot)
                y += 3
            }
        }
    }

    @Test func sweepingDownAndBackUpVisitsEachRegionOnce() {
        let specs = regions(queue: 3, tomorrow: 2, monday: 0)
        func order(_ id: DragRegionID) -> Int {
            switch id {
            case .queue: 0
            case .day(let day): day == "2026-10-02" ? 1 : 2
            }
        }
        var current = DropTarget(slot: DragSlot(region: .queue, index: 0))
        var down: [Int] = []
        var y: CGFloat = 0
        while y < 700 {
            current = DropMap.resolve(pointerY: y, regions: specs, current: current)
            down.append(order(current.slot.region))
            y += 1
        }
        #expect(down == down.sorted())
        #expect(down.last == 2)
        var up: [Int] = []
        while y > -10 {
            current = DropMap.resolve(pointerY: y, regions: specs, current: current)
            up.append(order(current.slot.region))
            y -= 1
        }
        #expect(up == up.sorted(by: >))
        #expect(up.last == 0)
    }

    @Test func aSlowMoveNeverFlickersBetweenTwoSlots() {
        for config in heldConfigs {
            var current = DropTarget(slot: config.held)
            var changes = 0
            var previous = config.held
            var y: CGFloat = -20
            while y < 700 {
                current = DropMap.resolve(pointerY: y, regions: config.specs, current: current)
                if current.slot != previous {
                    changes += 1
                    previous = current.slot
                }
                y += 0.5
            }
            let bound = config.specs.reduce(0) { $0 + $1.items + 2 } + 2
            #expect(changes <= bound)
        }
    }
}
