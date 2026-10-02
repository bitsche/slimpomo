import AppKit
import SwiftUI
import SlimPomoCore

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var acceptsSizeSaves = false
    private var sizeSaveTask: Task<Void, Never>?

    func show(model: AppModel) {
        NSApp.setActivationPolicy(.accessory)
        let created = window == nil
        if created {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: HistoryMetrics.defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "History"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Theme.bgBaseNS
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.tabbingMode = .disallowed
            window.alphaValue = 0
            let hosting = NSHostingController(rootView: HistoryWindow(model: model))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            enforceMinimumSize(of: window)
            window.delegate = self
            self.window = window
            applySavedFrame(to: window)
        }
        Task { @MainActor in
            guard let window = self.window else { return }
            if created {
                window.contentView?.layoutSubtreeIfNeeded()
                enforceMinimumSize(of: window)
                applySavedFrame(to: window)
            }
            self.present(window)
            window.alphaValue = 1
            self.acceptsSizeSaves = true
        }
    }

    private func present(_ window: NSWindow) {
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            guard let window = self.window else { return }
            window.level = .normal
            window.orderFrontRegardless()
        }
    }

    private func applySavedFrame(to window: NSWindow) {
        var frame = window.frame
        frame.size = Self.resolvedWindowSize()
        window.setFrame(frame, display: false)
        window.center()
    }

    private func enforceMinimumSize(of window: NSWindow) {
        window.minSize = HistoryMetrics.minSize
        let contentMin = window.contentRect(forFrameRect: NSRect(origin: .zero, size: HistoryMetrics.minSize)).size
        window.contentMinSize = contentMin
        guard let content = window.contentView else { return }
        let existing = content.constraints.contains { $0.identifier == HistoryMetrics.minConstraintID }
        guard !existing else { return }
        let width = content.widthAnchor.constraint(greaterThanOrEqualToConstant: contentMin.width)
        let height = content.heightAnchor.constraint(greaterThanOrEqualToConstant: contentMin.height)
        width.identifier = HistoryMetrics.minConstraintID
        height.identifier = HistoryMetrics.minConstraintID
        width.priority = .required
        height.priority = .required
        width.isActive = true
        height.isActive = true
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, HistoryMetrics.minSize.width),
            height: max(frameSize.height, HistoryMetrics.minSize.height)
        )
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            self.scheduleSizeSave()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.sizeSaveTask?.cancel()
            self.saveWindowSize()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func scheduleSizeSave() {
        guard acceptsSizeSaves else { return }
        sizeSaveTask?.cancel()
        sizeSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.saveWindowSize()
        }
    }

    private func saveWindowSize() {
        guard let window else { return }
        let size = window.frame.size
        UserDefaults.standard.set(
            ["width": Double(size.width), "height": Double(size.height)],
            forKey: HistoryMetrics.sizeKey
        )
    }

    private static func resolvedWindowSize() -> NSSize {
        let fallback = fitToScreen(HistoryMetrics.defaultSize)
        guard let raw = UserDefaults.standard.dictionary(forKey: HistoryMetrics.sizeKey),
              let width = (raw["width"] as? NSNumber)?.doubleValue,
              let height = (raw["height"] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite
        else { return fallback }
        if width < HistoryMetrics.minSize.width || height < HistoryMetrics.minSize.height {
            return fallback
        }
        let screen = NSScreen.main?.visibleFrame.size ?? fallback
        if width > screen.width || height > screen.height {
            return fallback
        }
        return NSSize(width: width, height: height)
    }

    private static func fitToScreen(_ size: NSSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? size
        let maxWidth = max(HistoryMetrics.minSize.width, screen.width)
        let maxHeight = max(HistoryMetrics.minSize.height, screen.height)
        return NSSize(
            width: min(max(size.width, HistoryMetrics.minSize.width), maxWidth),
            height: min(max(size.height, HistoryMetrics.minSize.height), maxHeight)
        )
    }
}

private enum HistoryMetrics {
    static let defaultSize = NSSize(width: 420, height: 600)
    static let minSize = NSSize(width: 360, height: 400)
    static let sizeKey = "SlimPomo.historyWindowSize"
    static let minConstraintID = "SlimPomo.historyMinSize"
}

struct HistoryWindow: View {
    var model: AppModel

    private var historyDays: [HistoryDay] { model.historyDays }

    /// History has its own tag column, as wide as the widest tag on any day.
    private var tagColumn: CGFloat {
        TagStyle.columnWidth(for: historyDays.lazy.flatMap { $0.rows }.map(\.taskName))
    }

    var body: some View {
        Group {
            if model.historyDays.isEmpty {
                Text("Finished pomodoros show up here, day by day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(historyDays.enumerated()), id: \.element.id) { index, day in
                            HistoryDaySection(day: day, now: model.now, model: model)
                                .padding(.top, index == 0 ? 0 : 14 - RowGrid.doneGap)
                        }
                    }
                    .padding(.horizontal, PageInset.horizontal)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.tagColumn, tagColumn)
        .background(Theme.bgBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct HistoryDaySection: View {
    var day: HistoryDay
    var now: Date
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label: HistoryDayTitle.text(for: day.day, now: now), stats: TimeFormat.span(TimeInterval(day.workedSeconds))) {
                EmptyView()
            }
            let breakdown = TagBreakdown(rows: day.rows)
            if !breakdown.all.isEmpty {
                TagBreakdownLine(breakdown: breakdown, model: model)
            }
            VStack(spacing: 0) {
                ForEach(day.rows, id: \.id) { row in
                    HistoryLine(day: day.day, row: row, model: model)
                }
            }
            .padding(.top, 6)
        }
    }

}

private struct HistoryLine: View {
    var day: Date
    var row: HistoryRow
    var model: AppModel

    @Environment(\.tagColumn) private var tagColumn

    private var rowTag: String? { TaskName.tag(of: row.taskName) }
    private var revealed: Bool {
        model.hoveredHistoryID == hoverID
    }

    private var hoverID: String {
        "\(day.timeIntervalSinceReferenceDate)-\(row.id)"
    }

    var body: some View {
        ListRow(height: RowGrid.doneHeight, tagWidth: tagColumn) {
            DepthGauge(
                intensity: row.mode,
                reduceMotion: model.reduceMotion,
                showsMark: false,
                captionHelp: WorkedGaugeCopy.help(intensity: row.mode, count: row.count, seconds: row.workedSeconds),
                colorOpacity: 0.6
            )
        } tag: {
            if let rowTag {
                TagLabel(tag: rowTag, model: model, strength: TagStyle.doneStrength, focusable: false)
            }
        } name: {
            TruncatingName(
                text: row.taskName.isEmpty ? "Untitled" : row.taskName,
                color: Theme.textSecondary
            )
        } rest: {
            HStack(spacing: 0) {
                WorkedMark(seconds: row.workedSeconds, intensity: row.mode)
                    .frame(width: RowGrid.workedWidth, alignment: .trailing)
                CountSlot(count: row.count, revealed: revealed)
                Color.clear.frame(width: RowGrid.edgeExtra, height: 1)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(revealed ? Theme.bgCard : Color.clear)
        }
        .overlay(alignment: .trailing) {
            FadeOverlay(
                shown: revealed,
                reduceMotion: model.reduceMotion,
                fill: Theme.bgCard,
                trailingInset: RowGrid.doneRestWidth
            ) {
                HStack(spacing: 8) {
                    FinishClock(text: ClockFormat.time(row.finishedAt), help: FinishClock.finishedHelp(row.finishedAt))
                    SquareIconButton(
                        systemName: "arrow.uturn.backward",
                        weight: .semibold,
                        tint: Theme.link,
                        slot: IconMetrics.column,
                        help: "Copy to the end of the queue"
                    ) {
                        model.requeueHistory(rowID: row.id, day: day)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, RowGrid.doneGap)
        .onHover { model.setHistoryHover(hoverID, hovering: $0) }
        .accessibilityAction(named: "Copy to the end of the queue") {
            model.requeueHistory(rowID: row.id, day: day)
        }
    }
}
