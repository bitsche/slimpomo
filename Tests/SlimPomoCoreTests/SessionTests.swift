import Foundation
import Testing
@testable import SlimPomoCore

struct SessionTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func emptyQueueCannotStart() {
        var session = Session()
        #expect(session.start(now: start) == .none)
        #expect(session.phase == .idle)
        #expect(session.isRunning == false)
    }

    @Test func blankDescriptionIsIgnored() {
        var session = Session()
        session.addItem(description: "   ", intensity: .regular, count: 2)
        #expect(session.queue.isEmpty)
    }

    @Test func multiCountItemThenNextItem() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        #expect(session.start(now: start) == .none)
        #expect(session.phase == .work)
        #expect(session.displayedRemaining(at: start) == 25 * 60)
        #expect(session.elapsedFraction(at: start) == 0)

        let firstWorkEnd = start.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: firstWorkEnd) == .playBell)
        #expect(session.phase == .breakTime)
        #expect(session.queue[0].count == 1)
        #expect(session.displayedRemaining(at: firstWorkEnd) == 5 * 60)

        let firstBreakEnd = firstWorkEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: firstBreakEnd) == .playBell)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Write", "Review"])
        #expect(session.displayedRemaining(at: firstBreakEnd) == 25 * 60)

        let secondWorkEnd = firstBreakEnd.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: secondWorkEnd) == .playBell)
        #expect(session.queue[0].count == 0)
        #expect(session.phase == .breakTime)

        let secondBreakEnd = secondWorkEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: secondBreakEnd) == .playBell)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.displayedRemaining(at: secondBreakEnd) == 50 * 60)
    }

    @Test func pauseAndResumePreserveRemaining() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)

        let pausedAt = start.addingTimeInterval(10 * 60)
        #expect(abs(session.elapsedFraction(at: pausedAt) - 0.4) < 0.000_1)
        #expect(session.pause(now: pausedAt) == .none)
        #expect(session.isRunning == false)
        let later = pausedAt.addingTimeInterval(1_000)
        #expect(session.displayedRemaining(at: later) == 15 * 60)
        #expect(session.reconcile(now: later) == .none)
        #expect(session.phase == .work)

        #expect(session.resume(now: later) == .none)
        #expect(session.isRunning)
        #expect(session.displayedRemaining(at: later) == 15 * 60)
        #expect(session.endsAt == Optional(later.addingTimeInterval(15 * 60)))
    }

    @Test func markDoneStartsBreakWithoutBell() {
        var session = Session()
        session.addItem(description: "Write", intensity: .focus, count: 3)
        _ = session.start(now: start)
        _ = session.pause(now: start.addingTimeInterval(30))

        #expect(session.markDone(now: start.addingTimeInterval(40)) == .none)
        #expect(session.phase == .breakTime)
        #expect(session.isRunning)
        #expect(session.queue[0].count == 2)
        #expect(session.displayedRemaining(at: start.addingTimeInterval(40)) == 10 * 60)
    }

    @Test func markDoneDoesNothingDuringBreak() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        #expect(session.markDone(now: start.addingTimeInterval(1)) == .none)
        #expect(session.phase == .breakTime)
        #expect(session.displayedRemaining(at: start.addingTimeInterval(1)) == 5 * 60 - 1)
    }

    @Test func skipBreakAdvancesToNextWork() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .intense, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        #expect(session.skipBreak(now: start.addingTimeInterval(3)) == .none)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.displayedRemaining(at: start.addingTimeInterval(3)) == 75 * 60)
    }

    @Test func skipBreakOnLastItemReturnsToIdle() {
        var session = Session()
        session.addItem(description: "Write", intensity: .intense, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        _ = session.pause(now: start.addingTimeInterval(20))
        #expect(session.skipBreak(now: start.addingTimeInterval(25)) == .none)
        #expect(session.phase == .idle)
        #expect(session.queue.isEmpty)
        #expect(session.isRunning == false)
    }

    @Test func lastItemReturnsToIdleAfterBreak() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        let workEnd = start.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: workEnd) == .playBell)
        let breakEnd = workEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: breakEnd) == .playBell)
        #expect(session.phase == .idle)
        #expect(session.queue.isEmpty)
        #expect(session.isRunning == false)
        #expect(session.reconcile(now: breakEnd.addingTimeInterval(10)) == .none)
    }

    @Test func breakCanBePaused() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        #expect(session.pause(now: start.addingTimeInterval(30)) == .none)
        #expect(session.phase == .breakTime)
        #expect(session.isRunning == false)
        #expect(session.displayedRemaining(at: start.addingTimeInterval(90)) == 5 * 60 - 30)
    }

    @Test func reconcileBeforeDeadlineDoesNothing() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        #expect(session.reconcile(now: start.addingTimeInterval(10)) == .none)
        #expect(session.phase == .work)
        #expect(session.queue[0].count == 1)
    }

    @Test func startingTwiceDoesNotResetTheClock() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        let later = start.addingTimeInterval(5)
        #expect(session.start(now: later) == .none)
        #expect(session.displayedRemaining(at: later) == 25 * 60 - 5)
    }

    @Test func intensityChangeDoesNotAlterTheCurrentPhase() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        session.updateIntensity(id: session.queue[0].id, intensity: .intense)
        #expect(session.displayedRemaining(at: start) == 25 * 60)
        _ = session.markDone(now: start)
        #expect(session.displayedRemaining(at: start) == 5 * 60)
    }

    @Test func activeWorkCountStaysAtLeastOne() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        _ = session.start(now: start)
        session.setCount(id: session.queue[0].id, count: 0)
        #expect(session.queue[0].count == 1)
        #expect(session.phase == .work)
    }

    @Test func settingQueuedCountToZeroRemovesIt() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .focus, count: 2)
        _ = session.start(now: start)
        session.setCount(id: session.queue[1].id, count: 0)
        #expect(session.queue.map(\.description) == ["Write"])
        #expect(session.phase == .work)
    }

    @Test func deletingTheActiveItemStartsTheNextOne() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        _ = session.start(now: start)
        let now = start.addingTimeInterval(30)
        #expect(session.remove(id: session.queue[0].id, now: now) == .none)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.displayedRemaining(at: now) == 50 * 60)
    }

    @Test func deletingTheOnlyActiveItemReturnsToIdle() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        _ = session.remove(id: session.queue[0].id, now: start)
        #expect(session.phase == .idle)
        #expect(session.queue.isEmpty)
        #expect(session.isRunning == false)
    }

    @Test func deletingALaterItemLeavesTheTimerAlone() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        _ = session.start(now: start)
        _ = session.remove(id: session.queue[1].id, now: start.addingTimeInterval(8))
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Write"])
        #expect(session.displayedRemaining(at: start.addingTimeInterval(8)) == 25 * 60 - 8)
    }

    @Test func moveReordersTheQueue() {
        var session = Session()
        session.addItem(description: "A", intensity: .regular, count: 1)
        session.addItem(description: "B", intensity: .regular, count: 1)
        session.addItem(description: "C", intensity: .regular, count: 1)
        session.move(from: IndexSet(integer: 0), to: 2)
        #expect(session.queue.map(\.description) == ["B", "A", "C"])
        session.moveUp(id: session.queue[1].id)
        #expect(session.queue.map(\.description) == ["A", "B", "C"])
        session.moveDown(id: session.queue[0].id)
        #expect(session.queue.map(\.description) == ["B", "A", "C"])
    }

    @Test func reorderBeforeTheBreakFollowsTheNewFront() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        session.moveUp(id: session.queue[1].id)
        _ = session.skipBreak(now: start)
        #expect(session.phase == .work)
        #expect(session.activeItem?.description == "Review")
        #expect(session.queue.map(\.description) == ["Review", "Write"])
        #expect(session.queue[1].count == 1)
    }

    @Test func restoreDoesNotKeepCounting() throws {
        var session = Session()
        session.addItem(description: "Write", intensity: .intense, count: 2)
        _ = session.start(now: start)
        let saved = session.snapshot(at: start.addingTimeInterval(90))
        let data = try JSONEncoder().encode(saved)
        var restored = try JSONDecoder().decode(Session.self, from: data)
        restored.restoreAsPaused()
        #expect(restored.phase == .work)
        #expect(restored.isRunning == false)
        #expect(restored.endsAt == nil)
        #expect(restored.queue[0].description == "Write")
        #expect(restored.queue[0].intensity == .intense)
        #expect(restored.displayedRemaining(at: start.addingTimeInterval(10_000)) == 75 * 60 - 90)
    }

    @Test func chimeIsAPlayableWAV() {
        let data = Chime.wavData()
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data.dropFirst(8).prefix(4) == Data("WAVE".utf8))
        #expect(data.count > 44)

        var peak = 0
        data.withUnsafeBytes { buffer in
            var offset = 44
            while offset + 1 < buffer.count {
                let sample = buffer.loadUnaligned(fromByteOffset: offset, as: Int16.self)
                peak = max(peak, abs(Int(Int16(littleEndian: sample))))
                offset += 2
            }
        }
        #expect(peak > 8_000)
    }
}
