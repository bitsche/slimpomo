import Foundation
import Testing
@testable import SlimPomoCore

struct SessionTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func modeDurationsComeFromOneConfig() {
        #expect(Intensity.allCases.map(\.mode.workMinutes) == [25, 50, 75])
        #expect(Intensity.allCases.map(\.mode.breakMinutes) == [5, 10, 15])
        for mode in Intensity.allCases {
            #expect(mode.workDuration == TimeInterval(mode.mode.workMinutes * 60))
            #expect(mode.breakDuration == TimeInterval(mode.mode.breakMinutes * 60))
        }
        #expect(Intensity.regular.sessionScale == 1)
        #expect(Intensity.intense.sessionScale == 3)
    }

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
        #expect(session.reconcile(now: firstWorkEnd) == .workDone)
        #expect(session.phase == .breakTime)
        #expect(session.queue[0].count == 1)
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
        #expect(session.displayedRemaining(at: firstWorkEnd) == 5 * 60)

        let firstBreakEnd = firstWorkEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: firstBreakEnd) == .breakOver)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Write", "Review"])
        #expect(session.displayedRemaining(at: firstBreakEnd) == 25 * 60)

        let secondWorkEnd = firstBreakEnd.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: secondWorkEnd) == .workDone)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.done[0].count == 2)
        #expect(session.phase == .breakTime)

        let secondBreakEnd = secondWorkEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: secondBreakEnd) == .breakOver)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 2)
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

    @Test func markDoneStartsBreakAndRings() {
        var session = Session()
        session.addItem(description: "Write", intensity: .focus, count: 3)
        _ = session.start(now: start)
        _ = session.pause(now: start.addingTimeInterval(30))

        #expect(session.markDone(now: start.addingTimeInterval(40)) == .workDone)
        #expect(session.phase == .breakTime)
        #expect(session.isRunning)
        #expect(session.queue[0].count == 2)
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
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
        #expect(session.skipBreak(now: start.addingTimeInterval(3)) == .breakOver)
        #expect(session.phase == .work)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.displayedRemaining(at: start.addingTimeInterval(3)) == 75 * 60)
    }

    @Test func skipBreakOnLastItemReturnsToIdle() {
        var session = Session()
        session.addItem(description: "Write", intensity: .intense, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        _ = session.pause(now: start.addingTimeInterval(20))
        #expect(session.skipBreak(now: start.addingTimeInterval(25)) == .breakOver)
        #expect(session.phase == .idle)
        #expect(session.queue.isEmpty)
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
        #expect(session.isRunning == false)
    }

    @Test func lastItemReturnsToIdleAfterBreak() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        _ = session.start(now: start)
        let workEnd = start.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: workEnd) == .workDone)
        let breakEnd = workEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: breakEnd) == .breakOver)
        #expect(session.phase == .idle)
        #expect(session.queue.isEmpty)
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
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

    @Test func activeSessionIntensityIsLocked() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Other", intensity: .regular, count: 1)
        _ = session.start(now: start)
        let active = session.queue[0].id
        session.updateIntensity(id: active, intensity: .intense)
        #expect(session.queue[0].intensity == .regular)
        #expect(session.displayedRemaining(at: start) == 25 * 60)
        session.updateIntensity(id: session.queue[1].id, intensity: .focus)
        #expect(session.queue[1].intensity == .focus)

        _ = session.pause(now: start)
        session.updateIntensity(id: active, intensity: .intense)
        #expect(session.queue[0].intensity == .regular)

        _ = session.resume(now: start)
        _ = session.markDone(now: start)
        #expect(session.phase == .breakTime)
        #expect(session.displayedRemaining(at: start) == 5 * 60)
        session.updateIntensity(id: active, intensity: .intense)
        #expect(session.queue[0].intensity == .regular)

        _ = session.stop()
        #expect(session.phase == .breakTime)
        let breakEnd = start.addingTimeInterval(5 * 60)
        _ = session.reconcile(now: breakEnd)
        #expect(session.phase == .work)
        _ = session.stop()
        #expect(session.phase == .idle)
        session.updateIntensity(id: active, intensity: .intense)
        #expect(session.queue[0].intensity == .intense)
        _ = session.start(now: breakEnd)
        #expect(session.displayedRemaining(at: breakEnd) == 75 * 60)
    }

    @Test func activeWorkCountStaysAtLeastOne() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        _ = session.start(now: start)
        session.setCount(id: session.queue[0].id, count: 0)
        #expect(session.queue[0].count == 1)
        #expect(session.phase == .work)
    }

    @Test func clearingTheLastPomodoroKeepsTheItem() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        session.setCount(id: session.queue[1].id, count: 0)
        #expect(session.queue.map(\.description) == ["Write", "Review"])
        #expect(session.queue[1].count == 0)

        _ = session.start(now: start)
        #expect(session.activeItem?.description == "Write")
        let workEnd = start.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: workEnd) == .workDone)
        let breakEnd = workEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: breakEnd) == .breakOver)
        #expect(session.phase == .idle)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.queue[0].count == 0)
        #expect(session.done.map(\.description) == ["Write"])
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

    @Test func countIsCappedAtFive() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 9)
        #expect(session.queue[0].count == 5)
        session.setCount(id: session.queue[0].id, count: 8)
        #expect(session.queue[0].count == 5)
    }

    @Test func finishedItemMovesToDoneAndCanReturn() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        _ = session.start(now: start)
        let workEnd = start.addingTimeInterval(25 * 60)
        #expect(session.reconcile(now: workEnd) == .workDone)
        #expect(session.phase == .breakTime)
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
        let breakEnd = workEnd.addingTimeInterval(5 * 60)
        #expect(session.reconcile(now: breakEnd) == .breakOver)
        #expect(session.queue.map(\.description) == ["Review"])
        #expect(session.done.map(\.description) == ["Write"])
        #expect(session.done[0].count == 1)
        #expect(session.done[0].intensity == .regular)

        let doneID = session.done[0].id
        session.requeue(id: doneID)
        #expect(session.done.map(\.id) == [doneID])
        #expect(session.done[0].description == "Write")
        #expect(session.queue.map(\.description) == ["Review", "Write"])
        #expect(session.queue[1].id != doneID)
        #expect(session.queue[1].count == 1)
        #expect(session.queue[1].completed == 0)

        session.clearDone()
        #expect(session.done.isEmpty)
        #expect(session.queue.map(\.description) == ["Review", "Write"])
    }

    @Test func finishTimesAccumulateFromNow() {
        var session = Session()
        session.addItem(description: "A", intensity: .regular, count: 1)
        session.addItem(description: "B", intensity: .regular, count: 2)
        let dates = session.finishDates(at: start)
        #expect(dates[session.queue[0].id] == start.addingTimeInterval(25 * 60))
        #expect(dates[session.queue[1].id] == start.addingTimeInterval(85 * 60))
    }

    @Test func finishTimeIncludesThePomodoroAlreadyUnderway() {
        var session = Session()
        session.addItem(description: "A", intensity: .regular, count: 1)
        session.addItem(description: "B", intensity: .regular, count: 1)
        _ = session.start(now: start)
        let now = start.addingTimeInterval(10 * 60)
        let dates = session.finishDates(at: now)
        #expect(dates[session.queue[0].id] == now.addingTimeInterval(15 * 60))
        #expect(dates[session.queue[1].id] == now.addingTimeInterval(45 * 60))
    }

    @Test func stopResetsARunningPomodoroWithoutFinishingIt() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        _ = session.start(now: start)
        _ = session.stop()
        #expect(session.phase == .idle)
        #expect(session.isRunning == false)
        #expect(session.queue[0].count == 2)
        #expect(session.done.isEmpty)
        #expect(session.displayedRemaining(at: start.addingTimeInterval(10 * 60)) == 0)
    }

    @Test func menuActionAdaptsToThePhase() {
        var session = Session()
        #expect(session.menuAction == SessionMenuAction(title: "Start next pomodoro", isEnabled: false))
        session.addItem(description: "Write", intensity: .regular, count: 1)
        #expect(session.menuAction == SessionMenuAction(title: "Start next pomodoro", isEnabled: true))
        _ = session.start(now: start)
        #expect(session.menuAction == SessionMenuAction(title: "Pomodoro running", isEnabled: false))
        _ = session.pause(now: start.addingTimeInterval(30))
        #expect(session.menuAction == SessionMenuAction(title: "Resume pomodoro", isEnabled: true))
        _ = session.resume(now: start.addingTimeInterval(30))
        _ = session.markDone(now: start.addingTimeInterval(30))
        #expect(session.menuAction == SessionMenuAction(title: "Break running", isEnabled: false))
        _ = session.pause(now: start.addingTimeInterval(40))
        #expect(session.menuAction == SessionMenuAction(title: "Resume break", isEnabled: true))
    }

    @Test func legacySnapshotWithoutDoneStillLoads() throws {
        let json = """
        {"isRunning":false,"phase":"idle","phaseDuration":0,"queue":[{"count":2,"description":"Write","id":"11111111-1111-1111-1111-111111111111","intensity":"regular"}],"remaining":0}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.queue.count == 1)
        #expect(session.queue[0].description == "Write")
        #expect(session.queue[0].completed == 0)
        #expect(session.done.isEmpty)
        #expect(session.phase == .idle)
    }
}
