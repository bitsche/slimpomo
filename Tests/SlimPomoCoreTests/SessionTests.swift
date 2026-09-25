import Foundation
import Testing
@testable import SlimPomoCore

struct SessionTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func modeDurationsComeFromOneConfig() {
        #expect(Intensity.allCases.map(\.mode.workMinutes) == [25, 50, 75])
        #expect(Intensity.allCases.map(\.mode.breakMinutes) == [5, 10, 15])
        #expect(Intensity.allCases.map(\.label) == ["Dip", "Dive", "Deep dive"])
        #expect(Intensity.allCases.map(\.workMark) == ["25′", "50′", "75′"])
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
        session.reorder(id: session.queue[2].id, to: 0)
        #expect(session.queue.map(\.description) == ["C", "B", "A"])
        #expect(session.canMoveDown(id: session.queue[2].id) == false)
        #expect(session.canMoveUp(id: session.queue[0].id) == false)

        var solo = Session()
        solo.addItem(description: "Solo", intensity: .regular, count: 1)
        #expect(solo.canReorder(id: solo.queue[0].id) == false)
        solo.moveUp(id: solo.queue[0].id)
        solo.moveDown(id: solo.queue[0].id)
        #expect(solo.queue.map(\.description) == ["Solo"])
    }

    @Test func runningAndPausedTasksCannotMoveOrBePassed() {
        var session = Session()
        session.addItem(description: "Zero", intensity: .regular, count: 1)
        session.addItem(description: "Write", intensity: .regular, count: 1)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        session.addItem(description: "Ship", intensity: .intense, count: 1)
        session.setCount(id: session.queue[0].id, count: 0)
        _ = session.start(now: start)
        #expect(session.activeWorkIndex() == 1)
        let zero = session.queue[0].id
        let write = session.queue[1].id
        let review = session.queue[2].id
        let ship = session.queue[3].id

        #expect(session.canReorder(id: write) == false)
        #expect(session.canMoveUp(id: write) == false)
        #expect(session.canMoveDown(id: write) == false)
        session.moveUp(id: write)
        session.moveDown(id: write)
        session.reorder(id: write, to: 0)
        #expect(session.queue.map(\.description) == ["Zero", "Write", "Review", "Ship"])

        #expect(session.canMoveUp(id: review) == false)
        #expect(session.canMoveDown(id: review) == true)
        #expect(session.canMoveUp(id: ship) == true)
        #expect(session.canMoveDown(id: ship) == false)
        session.reorder(id: review, to: 0)
        #expect(session.queue.map(\.description) == ["Zero", "Write", "Review", "Ship"])
        session.reorder(id: ship, to: 2)
        #expect(session.queue.map(\.description) == ["Zero", "Write", "Ship", "Review"])

        #expect(session.canMoveUp(id: zero) == false)
        #expect(session.canMoveDown(id: zero) == true)
        #expect(session.reorderDestinations(for: zero) == 1...3)
        session.moveDown(id: zero)
        #expect(session.queue.map(\.description) == ["Write", "Zero", "Ship", "Review"])

        _ = session.pause(now: start)
        #expect(session.isRunning == false)
        #expect(session.canReorder(id: write) == false)
        #expect(session.canMoveUp(id: session.queue[1].id) == false)
    }

    @Test func breakLetsEveryQueueRowMoveAndSkipFollowsTheNewOrder() {
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        _ = session.start(now: start)
        _ = session.markDone(now: start)
        #expect(session.phase == .breakTime)
        #expect(session.activeWorkIndex() == nil)
        #expect(session.canReorder(id: session.queue[0].id) == true)
        #expect(session.canReorder(id: session.queue[1].id) == true)
        session.reorder(id: session.queue[1].id, to: 0)
        #expect(session.queue.map(\.description) == ["Review", "Write"])
        #expect(session.queue.first { $0.count > 0 }?.description == "Review")
        #expect(session.queue.first { $0.count > 0 }?.id != session.activeItemID)
        _ = session.skipBreak(now: start)
        #expect(session.activeItem?.description == "Review")
    }

    @Test func reorderRecalculatesFinishTimes() {
        var session = Session()
        session.addItem(description: "A", intensity: .regular, count: 1)
        session.addItem(description: "B", intensity: .regular, count: 2)
        let first = session.queue[0].id
        let second = session.queue[1].id
        session.reorder(id: second, to: 0)
        let dates = session.finishDates(at: start)
        #expect(dates[second] == start.addingTimeInterval(55 * 60))
        #expect(dates[first] == start.addingTimeInterval(85 * 60))
    }

    @Test func gapMovesWhenThePointerCrossesANeighborMidpoint() {
        #expect(QueueDrop.gapIndex(pointerY: 100, rowHeight: 40, gap: 2, lower: 0, upper: 5) == 2)
        #expect(QueueDrop.gapIndex(pointerY: 59, rowHeight: 40, gap: 2, lower: 0, upper: 5) == 1)
        #expect(QueueDrop.gapIndex(pointerY: 141, rowHeight: 40, gap: 2, lower: 0, upper: 5) == 3)
        #expect(QueueDrop.gapIndex(pointerY: 200, rowHeight: 40, gap: 0, lower: 0, upper: 5) == 4)
        #expect(QueueDrop.gapIndex(pointerY: 10, rowHeight: 40, gap: 0, lower: 2, upper: 4) == 2)
        #expect(QueueDrop.gapIndex(pointerY: 400, rowHeight: 40, gap: 1, lower: 2, upper: 3) == 3)
    }

    @Test func releasingAboveTheListKeepsTheSnappedSlot() {
        #expect(QueueDrop.releaseLandsInQueue(pointerX: 80, pointerY: -80, listWidth: 300, listHeight: 160))
        #expect(QueueDrop.releaseLandsInQueue(pointerX: 80, pointerY: -400, listWidth: 300, listHeight: 160))
        #expect(QueueDrop.releaseLandsInQueue(pointerX: 40, pointerY: 20, listWidth: 300, listHeight: 160))
        #expect(QueueDrop.releaseLandsInQueue(pointerX: 40, pointerY: 200, listWidth: 300, listHeight: 160) == false)
        #expect(QueueDrop.releaseLandsInQueue(pointerX: -80, pointerY: -20, listWidth: 300, listHeight: 160) == false)
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
        #expect(session.history.isEmpty)
        #expect(session.didMigrateHistory == false)
    }

    @Test func finishingRecordsOneHistoryEvent() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .focus, count: 1)
        let beginning = HistoryClock.date(2026, 9, 24, 10, 0)
        _ = session.start(now: beginning, calendar: calendar)
        _ = session.stop(now: beginning, calendar: calendar)
        #expect(session.history.isEmpty)

        _ = session.start(now: beginning, calendar: calendar)
        let finished = beginning.addingTimeInterval(50 * 60)
        #expect(session.markDone(now: finished, calendar: calendar) == .workDone)
        #expect(session.history.count == 1)
        #expect(session.history[0].taskName == "Write")
        #expect(session.history[0].mode == .focus)
        #expect(session.history[0].workMinutes == 50)
        #expect(session.history[0].workedSeconds == 50 * 60)
        #expect(session.done[0].workedSeconds == 50 * 60)
        #expect(session.phaseDuration == 10 * 60)
        #expect(session.history[0].queueItemId == session.done[0].sourceID)
        #expect(session.history[0].timestamp == finished)

        let skipped = finished.addingTimeInterval(60)
        let before = session.history.count
        #expect(session.skipBreak(now: skipped, calendar: calendar) == .breakOver)
        #expect(session.history.count == before)
    }

    @Test func idleMidnightClearsDoneAndKeepsHistory() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let evening = HistoryClock.date(2026, 9, 24, 23, 0)
        _ = session.start(now: evening, calendar: calendar)
        let doneAt = evening.addingTimeInterval(25 * 60)
        _ = session.reconcile(now: doneAt, calendar: calendar)
        _ = session.reconcile(now: doneAt.addingTimeInterval(5 * 60), calendar: calendar)
        #expect(session.phase == .idle)
        #expect(session.done.count == 1)
        #expect(session.history.count == 1)

        let nextMorning = HistoryClock.date(2026, 9, 25, 0, 5)
        session.refreshDoneDay(now: nextMorning, calendar: calendar)
        #expect(session.done.isEmpty)
        #expect(session.history.count == 1)
        #expect(session.groupedHistory(calendar: calendar).map(\.pomodoros) == [1])
        let yesterday = calendar.startOfDay(for: doneAt)
        #expect(session.groupedHistory(calendar: calendar)[0].day == yesterday)
    }

    @Test func workAcrossMidnightClearsDoneThenRecordsToday() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let late = HistoryClock.date(2026, 9, 24, 23, 40)
        _ = session.start(now: late, calendar: calendar)
        let justAfterMidnight = HistoryClock.date(2026, 9, 25, 0, 1)
        session.refreshDoneDay(now: justAfterMidnight, calendar: calendar)
        #expect(session.phase == .work)
        #expect(session.done.isEmpty)

        let finished = late.addingTimeInterval(25 * 60)
        _ = session.reconcile(now: finished, calendar: calendar)
        #expect(session.done.count == 1)
        #expect(session.done[0].count == 1)
        #expect(session.history.count == 1)
        let today = calendar.startOfDay(for: finished)
        #expect(session.groupedHistory(calendar: calendar)[0].day == today)
        #expect(session.groupedHistory(calendar: calendar)[0].workMinutes == 25)
        #expect(session.history[0].workedSeconds == 25 * 60)
        #expect(session.groupedHistory(calendar: calendar)[0].workedSeconds == 25 * 60)
    }

    @Test func breakAcrossMidnightClearsDoneWhenTheBreakEnds() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let startWork = HistoryClock.date(2026, 9, 24, 23, 33)
        _ = session.start(now: startWork, calendar: calendar)
        let breakStart = startWork.addingTimeInterval(25 * 60)
        _ = session.reconcile(now: breakStart, calendar: calendar)
        #expect(session.phase == .breakTime)
        #expect(session.done.count == 1)

        let afterMidnight = HistoryClock.date(2026, 9, 25, 0, 1)
        session.refreshDoneDay(now: afterMidnight, calendar: calendar)
        #expect(session.done.count == 1)
        #expect(session.history.count == 1)

        _ = session.skipBreak(now: afterMidnight, calendar: calendar)
        #expect(session.done.isEmpty)
        #expect(session.history.count == 1)
        #expect(calendar.isDate(session.history[0].timestamp, inSameDayAs: breakStart))
    }

    @Test func pausedRelaunchWaitsUntilIdleOrCompletion() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        let evening = HistoryClock.date(2026, 9, 24, 18, 0)
        _ = session.start(now: evening, calendar: calendar)
        _ = session.markDone(now: evening.addingTimeInterval(60), calendar: calendar)
        _ = session.skipBreak(now: evening.addingTimeInterval(120), calendar: calendar)
        _ = session.pause(now: evening.addingTimeInterval(180))
        #expect(session.phase == .work)
        #expect(session.done.count == 1)

        let saved = try! JSONEncoder().encode(session.snapshot(at: evening.addingTimeInterval(180)))
        var restored = try! JSONDecoder().decode(Session.self, from: saved)
        restored.restoreAsPaused()
        let morning = HistoryClock.date(2026, 9, 25, 9, 0)
        restored.refreshDoneDay(now: morning, calendar: calendar)
        #expect(restored.done.count == 1)
        #expect(restored.history.count == 1)

        _ = restored.markDone(now: morning, calendar: calendar)
        #expect(restored.done.count == 1)
        #expect(restored.done[0].description == "Write")
        #expect(restored.history.count == 2)
        #expect(restored.groupedHistory(calendar: calendar).map(\.day) == [
            calendar.startOfDay(for: morning),
            calendar.startOfDay(for: evening),
        ])
    }

    @Test func timeZoneChangeClearsIdleDone() {
        var origin = HistoryClock.calendar
        origin.timeZone = TimeZone(secondsFromGMT: 0)!
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let afternoon = HistoryClock.date(2026, 9, 24, 12, 0, calendar: origin)
        _ = session.start(now: afternoon, calendar: origin)
        _ = session.markDone(now: afternoon, calendar: origin)
        _ = session.skipBreak(now: afternoon.addingTimeInterval(60), calendar: origin)
        #expect(session.phase == .idle)
        #expect(session.done.count == 1)

        var ahead = origin
        ahead.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        let stillThatInstant = HistoryClock.date(2026, 9, 24, 20, 0, calendar: origin)
        session.refreshDoneDay(now: stillThatInstant, calendar: ahead)
        #expect(session.done.isEmpty)
        #expect(session.history.count == 1)
    }

    @Test func clearDoneAndDeletingTheQueueLeaveHistory() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .intense, count: 1)
        let beginning = HistoryClock.date(2026, 9, 24, 9, 0)
        _ = session.start(now: beginning, calendar: calendar)
        let id = session.queue[0].id
        _ = session.markDone(now: beginning, calendar: calendar)
        session.clearDone()
        #expect(session.done.isEmpty)
        #expect(session.history.count == 1)
        _ = session.skipBreak(now: beginning.addingTimeInterval(30), calendar: calendar)
        session.addItem(description: "Other", intensity: .regular, count: 1)
        _ = session.remove(id: id, now: beginning.addingTimeInterval(40), calendar: calendar)
        #expect(session.history.count == 1)
        #expect(session.history[0].queueItemId == id)
    }

    @Test func historyGroupsLikeDoneAndPushBackCopiesTheRow() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        session.addItem(description: "Review", intensity: .focus, count: 1)
        let beginning = HistoryClock.date(2026, 9, 24, 9, 0)
        _ = session.start(now: beginning, calendar: calendar)
        _ = session.markDone(now: beginning, calendar: calendar)
        session.updateDescription(id: session.queue[0].id, description: "Write more")
        _ = session.skipBreak(now: beginning.addingTimeInterval(10), calendar: calendar)
        _ = session.markDone(now: beginning.addingTimeInterval(20), calendar: calendar)
        _ = session.skipBreak(now: beginning.addingTimeInterval(30), calendar: calendar)
        _ = session.markDone(now: beginning.addingTimeInterval(40), calendar: calendar)

        let day = session.groupedHistory(calendar: calendar)[0]
        #expect(day.pomodoros == 3)
        #expect(day.workMinutes == 25 + 25 + 50)
        #expect(day.rows.map(\.taskName) == ["Write more", "Review"])
        #expect(day.rows.map(\.count) == [2, 1])
        #expect(day.rows.map(\.mode) == [.regular, .focus])

        let writeID = day.rows[0].queueItemId
        session.requeueHistory(queueItemId: writeID, day: day.day, calendar: calendar)
        #expect(session.queue.map(\.description) == ["Write more"])
        #expect(session.queue[0].count == 2)
        #expect(session.queue[0].intensity == .regular)
        #expect(session.queue[0].id != writeID)
        #expect(session.history.count == 3)
    }

    @Test func tourSampleStaysOutOfHistory() {
        let sample = Session.tourSample()
        #expect(sample.phase == .idle)
        #expect(sample.isRunning == false)
        #expect(sample.history.isEmpty)
        #expect(sample.queue.map(\.id) == [TourSample.outline, TourSample.emails, TourSample.contract])
        #expect(sample.queue.map(\.description) == ["Write project outline", "Answer emails", "Review contract"])
        #expect(sample.queue.map(\.intensity) == [.focus, .regular, .intense])
        #expect(sample.queue.map(\.count) == [2, 1, 1])
        #expect(sample.done.map(\.description) == ["Plan the week"])
        #expect(sample.done.map(\.intensity) == [.regular])
        #expect(sample.done.map(\.count) == [1])
        #expect(sample.done[0].workedSeconds == 25 * 60)
    }

    @Test func existingDoneMigratesOnce() throws {
        let calendar = HistoryClock.calendar
        let source = UUID()
        let row = UUID()
        let json = """
        {"isRunning":false,"phase":"idle","phaseDuration":0,"queue":[],"remaining":0,"done":[{"id":"\(row.uuidString)","intensity":"focus","description":"Write","count":2,"sourceID":"\(source.uuidString)"}]}
        """
        var session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        let launched = HistoryClock.date(2026, 9, 24, 8, 0)
        session.migrateHistoryIfNeeded(now: launched, calendar: calendar)
        #expect(session.didMigrateHistory)
        #expect(session.doneDay == calendar.startOfDay(for: launched))
        #expect(session.done.count == 1)
        #expect(session.history.count == 2)
        #expect(session.history.allSatisfy {
            $0.queueItemId == source && $0.taskName == "Write" && $0.mode == .focus && $0.workMinutes == 50 && $0.timestamp == launched
        })
        session.migrateHistoryIfNeeded(now: launched.addingTimeInterval(3600), calendar: calendar)
        #expect(session.history.count == 2)
        session.migrateWorkedSecondsIfNeeded()
        #expect(session.didMigrateWorkedSeconds)
        #expect(session.history.count == 2)
        #expect(session.history.allSatisfy { $0.workedSeconds == 50 * 60 })
        #expect(session.done[0].workedSeconds == 50 * 60 * 2)
        session.migrateWorkedSecondsIfNeeded()
        #expect(session.history.count == 2)
        #expect(session.done[0].workedSeconds == 50 * 60 * 2)
    }

    @Test func missingWorkedSecondsMigrateOnceWithoutNewEvents() throws {
        let event = UUID()
        let source = UUID()
        let row = UUID()
        let json = """
        {"isRunning":false,"phase":"idle","phaseDuration":0,"queue":[],"remaining":0,"didMigrateHistory":true,"history":[{"id":"\(event.uuidString)","timestamp":100,"queueItemId":"\(source.uuidString)","taskName":"Write","mode":"regular","workMinutes":25}],"done":[{"id":"\(row.uuidString)","intensity":"regular","description":"Write","count":2,"sourceID":"\(source.uuidString)"}]}
        """
        var session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.didMigrateWorkedSeconds == false)
        #expect(session.history[0].workedSeconds == 0)
        #expect(session.done[0].workedSeconds == 0)
        session.migrateWorkedSecondsIfNeeded()
        #expect(session.didMigrateWorkedSeconds)
        #expect(session.history.count == 1)
        #expect(session.history[0].workedSeconds == 25 * 60)
        #expect(session.history[0].workMinutes == 25)
        #expect(session.done[0].count == 2)
        #expect(session.done[0].workedSeconds == 25 * 60 * 2)
        let saved = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(Session.self, from: saved)
        restored.migrateWorkedSecondsIfNeeded()
        #expect(restored.history.count == 1)
        #expect(restored.history[0].workedSeconds == 25 * 60)
        #expect(restored.done[0].workedSeconds == 25 * 60 * 2)
    }

    @Test func earlyFinishRecordsElapsedWorkAndAFullRunAddsToIt() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 2)
        let start = HistoryClock.date(2026, 9, 24, 9, 0)
        _ = session.start(now: start, calendar: calendar)
        let paused = start.addingTimeInterval(10 * 60)
        _ = session.pause(now: paused)
        #expect(session.remaining == 15 * 60)
        #expect(session.markDone(now: paused, calendar: calendar) == .workDone)
        #expect(session.history.count == 1)
        #expect(session.history[0].workMinutes == 25)
        #expect(session.history[0].workedSeconds == 10 * 60)
        #expect(session.done[0].count == 1)
        #expect(session.done[0].workedSeconds == 10 * 60)
        #expect(session.phase == .breakTime)
        #expect(session.phaseDuration == 5 * 60)
        #expect(TimeSpan.text(TimeInterval(session.done[0].workedSeconds)) == "10m")

        session.requeue(id: session.done[0].id)
        #expect(session.queue.last?.count == 1)
        #expect(session.queue.last?.workedSeconds == 0)

        _ = session.skipBreak(now: paused, calendar: calendar)
        let fullEnd = paused.addingTimeInterval(25 * 60)
        _ = session.reconcile(now: fullEnd, calendar: calendar)
        #expect(session.history[1].workedSeconds == 25 * 60)
        #expect(session.history[1].workMinutes == 25)
        #expect(session.done[0].count == 2)
        #expect(session.done[0].workedSeconds == 35 * 60)
        let day = session.groupedHistory(calendar: calendar)[0]
        #expect(day.pomodoros == 2)
        #expect(day.workedSeconds == 35 * 60)
        #expect(day.rows[0].count == 2)
        #expect(day.rows[0].workedSeconds == 35 * 60)
        #expect(TimeSpan.text(TimeInterval(day.workedSeconds)) == "35m")
    }

    @Test func shortFinishCountsAsOnePomodoro() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let start = HistoryClock.date(2026, 9, 24, 9, 0)
        _ = session.start(now: start, calendar: calendar)
        let paused = start.addingTimeInterval(20)
        _ = session.pause(now: paused)
        #expect(session.markDone(now: paused, calendar: calendar) == .workDone)
        #expect(session.history.count == 1)
        #expect(session.history[0].workedSeconds == 20)
        #expect(session.done[0].count == 1)
        #expect(session.done[0].workedSeconds == 20)
        #expect(TimeSpan.text(20) == "<1m")
        #expect(TimeSpan.text(40) == "1m")
        #expect(TimeSpan.text(0) == "0m")
        #expect(TimeSpan.text(30) == "1m")
        #expect(TimeSpan.text(75 * 60) == "1h 15m")
    }

    @Test func relaunchThenFinishKeepsOnlyTimeThatRan() {
        let calendar = HistoryClock.calendar
        var session = Session()
        session.addItem(description: "Write", intensity: .regular, count: 1)
        let start = HistoryClock.date(2026, 9, 24, 9, 0)
        _ = session.start(now: start, calendar: calendar)
        let paused = start.addingTimeInterval(10 * 60)
        _ = session.pause(now: paused)
        let saved = try! JSONEncoder().encode(session.snapshot(at: paused))
        var restored = try! JSONDecoder().decode(Session.self, from: saved)
        restored.restoreAsPaused()
        let later = HistoryClock.date(2026, 9, 24, 18, 0)
        #expect(restored.markDone(now: later, calendar: calendar) == .workDone)
        #expect(restored.history.count == 1)
        #expect(restored.history[0].workedSeconds == 10 * 60)
        #expect(restored.done[0].count == 1)
        #expect(restored.done[0].workedSeconds == 10 * 60)
        #expect(restored.phaseDuration == 5 * 60)
    }
}

private enum HistoryClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar = calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
