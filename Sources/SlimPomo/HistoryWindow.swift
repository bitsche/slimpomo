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
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Palette.canvasNS
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

    var body: some View {
        Group {
            if model.historyDays.isEmpty {
                Text("Finished pomodoros show up here, day by day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.historyDays.enumerated()), id: \.element.id) { index, day in
                            HistoryDaySection(day: day, now: model.now, model: model)
                                .padding(.top, index == 0 ? 0 : 18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        #if SLIMPOMO_DEV
        .overlay(alignment: .topTrailing) {
            DevBadge(color: Palette.muted)
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        #endif
    }
}

private struct HistoryDaySection: View {
    var day: HistoryDay
    var now: Date
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label: HistoryDayTitle.text(for: day.day, now: now), stats: stats) {
                EmptyView()
            }
            VStack(spacing: 0) {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                    HistoryLine(
                        day: day.day,
                        row: row,
                        model: model,
                        showsDivider: index < day.rows.count - 1
                    )
                }
            }
        }
    }

    private var stats: String {
        SectionStats.pomodoros(day.pomodoros, seconds: TimeInterval(day.workedSeconds))
    }
}

private struct HistoryLine: View {
    var day: Date
    var row: HistoryRow
    var model: AppModel
    var showsDivider = false

    var body: some View {
        ListRow(showsDivider: showsDivider) {
            DepthGauge(
                intensity: row.mode,
                reduceMotion: model.reduceMotion,
                caption: TimeFormat.span(TimeInterval(row.workedSeconds)),
                captionHelp: WorkedGaugeCopy.help(intensity: row.mode, count: row.count, seconds: row.workedSeconds),
                colorOpacity: 0.6
            )
        } name: {
            TruncatingName(
                text: row.taskName.isEmpty ? "Untitled" : row.taskName,
                color: Palette.muted
            )
        } clock: {
            FinishClock(text: ClockFormat.time(row.finishedAt), help: FinishClock.finishedHelp(row.finishedAt))
        } count: {
            CountText(count: row.count)
        } action: {
            SquareIconButton(
                systemName: "arrow.uturn.backward",
                weight: .semibold,
                opacity: 0.9,
                slot: IconMetrics.column,
                help: "Copy to the end of the queue"
            ) {
                model.requeueHistory(queueItemId: row.queueItemId, day: day)
            }
        }
    }
}

enum HistoryDayTitle {
    static func text(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "EEE d MMM" : "EEE d MMM yyyy"
        return formatter.string(from: day)
    }
}
