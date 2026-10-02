import Foundation
import Testing
@testable import SlimPomoCore

struct TagTests {
    @Test func aTagIsTheLabelInUpperCaseWhateverItsSpelling() {
        #expect(TaskName.tag(of: "NIQO: write") == "NIQO")
        #expect(TaskName.tag(of: "Niqo: write") == "NIQO")
        #expect(TaskName.tag(of: "niqo:   write") == "NIQO")
        #expect(TaskName.tag(of: "write the report") == nil)
        #expect(TaskName.tag(of: "NIQO:") == nil)
    }

    @Test func newTagsTakeTheFirstUnusedColor() {
        var palette = TagPalette()
        #expect(palette.assign("NIQO") == 0)
        #expect(palette.assign("ANTI") == 1)
        #expect(palette.assign("NIQO") == 0)
        palette.set("NIQO", colorIndex: 4)
        #expect(palette.assign("ACME") == 0)
        #expect(palette.assign("BETA") == 2)
        #expect(palette.colorIndex(for: "ANTI") == 1)
        #expect(palette.colorIndex(for: "NIQO") == 4)
    }

    @Test func aSeventhTagReusesTheColorAssignedLongestAgo() {
        var palette = TagPalette()
        for tag in ["A", "B", "C", "D", "E", "F"] { palette.assign(tag) }
        #expect(palette.assign("G") == 0)
        #expect(palette.assign("H") == 1)
        #expect(palette.assign("I") == 2)
        #expect(palette.colorIndex(for: "A") == 0)
        #expect(palette.colorIndex(for: "B") == 1)
    }

    @Test func aChosenColorCountsAsTheNewestAssignment() {
        var palette = TagPalette()
        for tag in ["A", "B", "C", "D", "E", "F"] { palette.assign(tag) }
        palette.set("A", colorIndex: 0)
        #expect(palette.assign("G") == 1)
    }

    @Test func invalidColorIndexIsIgnored() {
        var palette = TagPalette()
        palette.assign("A")
        palette.set("A", colorIndex: 9)
        palette.set("A", colorIndex: -1)
        #expect(palette.colorIndex(for: "A") == 0)
    }

    @Test func paletteSurvivesEncoding() throws {
        var palette = TagPalette()
        palette.assign("A")
        palette.assign("B")
        palette.set("A", colorIndex: 3)
        let copy = try JSONDecoder().decode(TagPalette.self, from: JSONEncoder().encode(palette))
        #expect(copy == palette)
    }

    @Test func existingTagsAreColoredInOrderOfFirstAppearance() throws {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        var s = try sessionWithHistory([
            event("Late: x", at: late),
            event("Early: x", at: early),
        ])
        s.addItem(description: "queue: a", intensity: .regular, count: 1)
        s.addItem(description: "Early: again", intensity: .regular, count: 1)
        s.addItem(description: "plain", intensity: .regular, count: 1)
        #expect(s.tagsByFirstAppearance() == ["EARLY", "LATE", "QUEUE"])
        var palette = TagPalette()
        palette.assign(all: s.tagsByFirstAppearance())
        #expect(palette.colorIndex(for: "EARLY") == 0)
        #expect(palette.colorIndex(for: "LATE") == 1)
        #expect(palette.colorIndex(for: "QUEUE") == 2)
    }

    @Test func breakdownSortsBiggestFirstAndOtherLast() {
        let rows = [
            row("ANTI: a", 4_500),
            row("NIQO: a", 6_000),
            row("niqo: b", 3_000),
            row("untagged", 9_000),
        ]
        let breakdown = TagBreakdown(rows: rows)
        #expect(breakdown.all == [
            TagTime(tag: "NIQO", seconds: 9_000),
            TagTime(tag: "ANTI", seconds: 4_500),
            TagTime(tag: nil, seconds: 9_000),
        ])
        #expect(breakdown.hidden.isEmpty)
    }

    @Test func breakdownShowsFourThenCountsTheRest() {
        let rows = (1...6).map { row("T\($0): x", $0 * 600) } + [row("plain", 100)]
        let breakdown = TagBreakdown(rows: rows)
        #expect(breakdown.shown.map(\.tag) == ["T6", "T5", "T4", "T3"])
        #expect(breakdown.hidden.map(\.tag) == ["T2", "T1", nil])
    }

    @Test func aDayWithOnlyUntaggedWorkHasNoBreakdown() {
        #expect(TagBreakdown(rows: [row("a", 600), row("b", 600)]).all.isEmpty)
        #expect(TagBreakdown(rows: []).all.isEmpty)
    }

    @Test func onlyTaggedWorkHasNoOtherEntry() {
        let breakdown = TagBreakdown(rows: [row("A: x", 600)])
        #expect(breakdown.all == [TagTime(tag: "A", seconds: 600)])
    }

    private func sessionWithHistory(_ events: [HistoryEvent]) throws -> Session {
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Session())) as? [String: Any] ?? [:]
        var object = base
        object["history"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(events))
        object["didMigrateHistory"] = true
        return try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func row(_ name: String, _ seconds: Int) -> HistoryRow {
        HistoryRow(queueItemId: UUID(), taskName: name, mode: .regular, count: 1, workedSeconds: seconds, finishedAt: Date())
    }

    private func event(_ name: String, at: Date) -> HistoryEvent {
        HistoryEvent(id: UUID(), timestamp: at, queueItemId: UUID(), taskName: name, mode: .regular, workMinutes: 25, workedSeconds: 1500)
    }
}

struct NextStartTests {
    @Test func nextStartIsTheFirstTaskWithPomodorosWhileIdle() {
        var s = Session()
        s.addItem(description: "A", intensity: .regular, count: 1)
        s.addItem(description: "B", intensity: .regular, count: 1)
        #expect(s.nextStartID == s.queue[0].id)
        s.setCount(id: s.queue[0].id, count: 0)
        #expect(s.nextStartID == s.queue[1].id)
        s.setCount(id: s.queue[1].id, count: 0)
        #expect(s.nextStartID == nil)
    }

    @Test func nextStartIsNilWhileWorkingAndPointsAtTheNextTaskInABreak() {
        var s = Session()
        s.addItem(description: "A", intensity: .regular, count: 1)
        s.addItem(description: "B", intensity: .regular, count: 1)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = s.start(now: start)
        #expect(s.nextStartID == nil)
        _ = s.markDone(now: start.addingTimeInterval(60))
        #expect(s.phase == .breakTime)
        #expect(s.nextStartID == s.queue.first { $0.description == "B" }?.id)
    }
}
