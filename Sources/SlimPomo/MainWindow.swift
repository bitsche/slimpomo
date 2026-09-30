import AppKit
import SwiftUI
import SlimPomoCore

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var acceptsSizeSaves = false
    private var sizeSaveTask: Task<Void, Never>?

    func show(model: AppModel) {
        NSApp.setActivationPolicy(.accessory)
        let created = window == nil
        if created {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: WindowMetrics.defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SlimPomo"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Palette.canvasNS
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.tabbingMode = .disallowed
            window.alphaValue = 0
            let hosting = NSHostingController(rootView: MainWindow(model: model))
            // SwiftUI's default sizing options replace the restored frame with the
            // view's intrinsic size, which the minimum then clamps to 450×550.
            hosting.sizingOptions = []
            window.contentViewController = hosting
            enforceMinimumSize(of: window)
            window.delegate = self
            self.window = window
            window.acceptsMouseMovedEvents = model.isTouring
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

    /// The hosting view uses Auto Layout, so `minSize` alone does not stop a drag.
    private func enforceMinimumSize(of window: NSWindow) {
        window.minSize = WindowMetrics.minSize
        window.contentMinSize = WindowMetrics.minSize
        guard let content = window.contentView else { return }
        let existing = content.constraints.contains { $0.identifier == WindowMetrics.minConstraintID }
        guard !existing else { return }
        let width = content.widthAnchor.constraint(greaterThanOrEqualToConstant: WindowMetrics.minSize.width)
        let height = content.heightAnchor.constraint(greaterThanOrEqualToConstant: WindowMetrics.minSize.height)
        width.identifier = WindowMetrics.minConstraintID
        height.identifier = WindowMetrics.minConstraintID
        width.priority = .required
        height.priority = .required
        width.isActive = true
        height.isActive = true
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, WindowMetrics.minSize.width),
            height: max(frameSize.height, WindowMetrics.minSize.height)
        )
    }

    private func applySavedFrame(to window: NSWindow) {
        var frame = window.frame
        frame.size = Self.resolvedWindowSize()
        window.setFrame(frame, display: false)
        window.center()
    }

    private func present(_ window: NSWindow) {
        closeSettingsWindows()
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
            self.closeSettingsWindows()
            window.level = .normal
            window.orderFrontRegardless()
        }
    }

    private func closeSettingsWindows() {
        for candidate in NSApp.windows where candidate !== window && candidate.title.hasSuffix("Settings") {
            candidate.orderOut(nil)
            candidate.close()
        }
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor in
            TourMenu.claimShortcut()
            AppRuntime.model.stopAlarm()
        }
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
            forKey: WindowMetrics.sizeKey
        )
    }

    private static func resolvedWindowSize() -> NSSize {
        let fallback = fitToScreen(WindowMetrics.defaultSize)
        guard let raw = UserDefaults.standard.dictionary(forKey: WindowMetrics.sizeKey),
              let width = (raw["width"] as? NSNumber)?.doubleValue,
              let height = (raw["height"] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite
        else { return fallback }
        let screen = NSScreen.main?.visibleFrame.size ?? fallback
        if width > screen.width || height > screen.height {
            return fallback
        }
        // A saved edge below the minimum is raised: width to 450, height to 550.
        return fitToScreen(NSSize(width: width, height: height))
    }

    private static func fitToScreen(_ size: NSSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? size
        let maxWidth = max(WindowMetrics.minSize.width, screen.width)
        let maxHeight = max(WindowMetrics.minSize.height, screen.height)
        return NSSize(
            width: min(max(size.width, WindowMetrics.minSize.width), maxWidth),
            height: min(max(size.height, WindowMetrics.minSize.height), maxHeight)
        )
    }
}

enum Palette {
    static let canvas = Color(red: 0.145, green: 0.145, blue: 0.145)
    static let canvasNS = NSColor(srgbRed: 0.145, green: 0.145, blue: 0.145, alpha: 1)
    static let card = Color(red: 0.73, green: 0.32, blue: 0.30)
    static let cardBreak = Color(red: 0.73, green: 0.84, blue: 0.74)
    static let breakInk = Color(red: 0.16, green: 0.24, blue: 0.18)
    static let hairline = Color.white.opacity(0.16)
    static let field = Color.white.opacity(0.38)
    static let muted = Color.white.opacity(0.55)
    static let hover = NSColor(white: 1, alpha: 0.14)
}

struct MainWindow: View {
    @Bindable var model: AppModel
    @FocusState private var draftFocused: Bool

    private var shown: Session { model.windowSession }

    var body: some View {
        VStack(spacing: 0) {
            timerCard
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)
                .tourTarget(.timerCard)

            todoHeader
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                addRow
                    .padding(.horizontal, 14)
                listScroller
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .accessibilityHidden(model.isTouring)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                let frames = Dictionary(uniqueKeysWithValues: anchors.map { target, anchor in
                    (target, proxy[anchor])
                })
                TourOverlay(model: model, viewport: proxy.size, frames: frames)
                    .allowsHitTesting(model.isTouring)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.refresh()
        }
        .onChange(of: model.textFocusNonce) { _, _ in
            draftFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var timerCard: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(clockParts.0)
                Text(":")
                    .padding(.bottom, 4)
                Text(clockParts.1)
            }
            .font(.system(size: 64, weight: .ultraLight).monospacedDigit())
            .foregroundStyle(cardInk)
            .accessibilityLabel(clockText)

            Text(taskLine)
                .font(.system(size: 13))
                .foregroundStyle(cardInk.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(onBreak ? 2 : 1)
                .padding(.horizontal, 12)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: model.reduceMotion ? 0.12 : 0.16), value: taskLine)

            if let sessionSubtitle {
                Text(sessionSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(cardInk.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: model.reduceMotion ? 0.12 : 0.16), value: sessionSubtitle)
            }

            HStack(spacing: 18) {
                cardButton(primaryTitle, enabled: !primaryDisabled, help: primaryHelp) {
                    model.performMenuAction()
                }
                cardButton(secondaryTitle, enabled: secondaryEnabled, help: secondaryHelp) {
                    secondaryAction()
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(onBreak ? Palette.cardBreak : Palette.card)
        )
        #if SLIMPOMO_DEV
        .overlay(alignment: .topTrailing) {
            DevBadge(color: cardInk.opacity(0.5))
                .padding(.top, 8)
                .padding(.trailing, 10)
        }
        #endif
    }

    private var todoHeader: some View {
        SectionHeader(
            label: "TODO",
            stats: SectionStats.pomodoros(todoCount, seconds: todoWork),
            help: "Pomodoros still in the queue, and the work time they add up to"
        ) {
            SquareIconButton(systemName: "questionmark.circle", slot: IconMetrics.column, help: "Tour") {
                model.replayTour()
            }
            .tourTarget(.tourButton)
            SquareIconButton(systemName: "clock.arrow.circlepath", slot: IconMetrics.column, help: "History") {
                model.showHistory()
            }
            .tourTarget(.historyButton)
        }
    }

    private var listScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsDepthHint {
                        DepthHint(model: model)
                    }
                    if !shown.queue.isEmpty {
                        queueRows
                            .padding(.top, showsDepthHint ? 18 : 0)
                    }
                    if !shown.later.isEmpty {
                        laterBlock
                            .padding(.top, showsDepthHint || !shown.queue.isEmpty ? 18 : 0)
                    }
                    if !shown.done.isEmpty {
                        doneBlock
                            .padding(.top, showsDepthHint || !shown.queue.isEmpty || !shown.later.isEmpty ? 18 : 0)
                            .tourTarget(.doneSection)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, showsDepthHint ? 7 : 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    ScrollOffsetProbe { offset in
                        model.noteListScroll(offset: offset)
                    }
                    .frame(height: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDisabled(model.isTouring)
            .onChange(of: model.tourScrollRequest) { _, _ in
                guard let target = model.tour?.step.anchor else { return }
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                model.scheduleTourScrollFinish()
            }
            .onChange(of: model.scrollQueueItemID) { _, id in
                guard let id else { return }
                model.scrollQueueItemID = nil
                Task { @MainActor in
                    if model.queueRowIsOffscreen(id) {
                        withAnimation(QueueMotion.slide(model.reduceMotion)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    draftFocused = true
                }
            }
            .overlay(alignment: .top) {
                scrollEdge
            }
            .overlay(alignment: .topLeading) {
                queueDragFloat
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A hairline and a short shadow while list content sits under the add row.
    private var scrollEdge: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 10)
        }
        .opacity(model.listsScrolled ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: model.listsScrolled)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var queueRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedQueue.enumerated()), id: \.element.id) { index, item in
                let held = model.queueDrag?.itemID == item.id
                QueueLine(
                    item: item,
                    isCurrent: item.id == shown.activeItemID && shown.phase != .idle,
                    finish: shown.finishDates(at: model.now)[item.id],
                    model: model,
                    gripVisible: model.tourGripItemID == item.id
                        || (model.tour == nil && model.hoveredQueueID == item.id && model.session.canReorder(id: item.id)),
                    showsDivider: index < displayedQueue.count - 1
                )
                .id(item.id)
                .opacity(held ? 0 : 1)
                .overlay {
                    if held {
                        QueueGapOutline(
                            height: model.queueDrag?.rowHeight ?? 48,
                            visible: model.queueDrag?.showsOutline ?? false
                        )
                    }
                }
                .accessibilityHidden(held)
                .allowsHitTesting(!held)
            }
        }
        .animation(
            model.suppressQueueAnimation || model.tour != nil ? nil : QueueMotion.slide(model.reduceMotion),
            value: displayedQueue.map(\.id)
        )
        .background {
            QueueListAnchor { anchor in
                model.attachQueueList(anchor)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: RowGrid.spacing) {
            ModeMenu(model: model, describesHint: showsDepthHint)
                .frame(width: RowGrid.gauge, alignment: .leading)
                .tourTarget(.addChip)
            TextField(
                "Describe the task, press Return to add",
                text: model.isTouring ? .constant("") : $model.draftDescription
            )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($draftFocused)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .stroke(Palette.field, lineWidth: 1)
                )
                .onSubmit {
                    model.addDraftItem()
                    draftFocused = true
                }
                .tourTarget(.addField)
        }
        .padding(.leading, RowGrid.leading)
        .padding(.trailing, RowGrid.trailing)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var laterBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label: "LATER", stats: SectionStats.tasks(shown.later.count)) {
                SquareIconButton(
                    systemName: "chevron.right",
                    size: 11,
                    weight: .semibold,
                    opacity: 0.7,
                    slot: IconMetrics.column,
                    help: model.laterExpanded ? "Collapse later" : "Expand later"
                ) {
                    model.toggleLaterExpanded()
                }
                .rotationEffect(.degrees(model.laterExpanded ? 90 : 0))
                .animation(model.reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.laterExpanded)
            }
            if model.laterExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.laterGroups().enumerated()), id: \.element.day) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(laterHeading(group.day))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.muted)
                                .padding(.leading, RowGrid.leading)
                                .padding(.top, groupIndex == 0 ? 4 : 12)
                                .padding(.bottom, 2)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                LaterLine(item: item, model: model, showsDivider: index < group.items.count - 1)
                            }
                        }
                    }
                }
                .animation(QueueMotion.slide(model.reduceMotion), value: shown.later.map(\.id))
            }
        }
    }

    private func laterHeading(_ day: String) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           day == CalendarDay.stamp(tomorrow, calendar: calendar) {
            return "Tomorrow"
        }
        guard let date = CalendarDay.date(day, calendar: calendar) else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var doneBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label: "DONE", stats: SectionStats.pomodoros(doneCount, seconds: TimeInterval(doneSeconds))) {
                SquareIconButton(
                    systemName: "trash",
                    size: 11,
                    weight: .medium,
                    opacity: 0.7,
                    slot: IconMetrics.column,
                    help: "Clear the done list"
                ) {
                    model.clearDone()
                }
            }
            DoneRows(items: shown.done, model: model)
        }
    }

    private var doneCount: Int {
        shown.done.reduce(0) { $0 + max(0, $1.count) }
    }

    private var doneSeconds: Int {
        shown.done.reduce(0) { $0 + max(0, $1.workedSeconds) }
    }

    private var todoCount: Int {
        shown.queue.reduce(0) { $0 + max(0, $1.count) }
    }

    private var todoWork: TimeInterval {
        shown.queue.reduce(0) { total, item in
            total + TimeInterval(max(0, item.count)) * item.intensity.workDuration
        }
    }

    private var clockParts: (String, String) {
        let total = max(0, Int(clockSeconds.rounded(.down)))
        return (String(total / 60), String(format: "%02d", total % 60))
    }

    private var clockText: String {
        "\(clockParts.0):\(clockParts.1)"
    }

    /// Session order, or the in-progress order while a row is held. The held id never leaves the list.
    private var displayedQueue: [QueueItem] {
        let queue = shown.queue
        guard let drag = model.queueDrag else { return queue }
        let ids = QueueDrop.workingOrder(ids: queue.map(\.id), moving: drag.itemID, to: drag.gapIndex)
        let byID = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    @ViewBuilder
    private var queueDragFloat: some View {
        if let drag = model.queueDrag,
           let item = model.session.queue.first(where: { $0.id == drag.itemID }) {
            QueueLine(
                item: item,
                isCurrent: item.id == model.session.activeItemID && model.session.phase != .idle,
                finish: model.session.finishDates(at: model.now)[item.id],
                model: model,
                gripVisible: true,
                floating: true
            )
            .frame(width: max(drag.rowWidth, 1))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.canvas)
            )
            .scaleEffect(drag.lifted && !model.reduceMotion ? 1.02 : 1)
            .shadow(
                color: .black.opacity(drag.lifted && !model.reduceMotion ? 0.32 : 0),
                radius: drag.lifted && !model.reduceMotion ? 12 : 0,
                y: drag.lifted && !model.reduceMotion ? 6 : 0
            )
            .offset(x: drag.visualX, y: drag.visualY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var clockSeconds: TimeInterval {
        if shown.phase == .idle {
            return shown.queue.first { $0.count > 0 }?.intensity.workDuration ?? 0
        }
        return shown.displayedRemaining(at: model.now)
    }

    private var onBreak: Bool {
        shown.phase == .breakTime
    }

    private var showsDepthHint: Bool {
        shown.queue.isEmpty && !model.depthHintDismissed
    }

    private var cardInk: Color {
        onBreak ? Palette.breakInk : .white
    }

    private var taskLine: String {
        if onBreak {
            let message = model.breakMessage ?? BreakMessages.five[0]
            return "Break · \(message)"
        }
        if shown.phase != .idle {
            if let active = shown.activeItem, !active.description.isEmpty {
                return active.description
            }
            if !shown.activeDescription.isEmpty {
                return shown.activeDescription
            }
            return "Untitled"
        }
        if let next = shown.queue.first(where: { $0.count > 0 }) {
            return next.description.isEmpty ? "Untitled" : next.description
        }
        return "Add a task to begin"
    }

    private var sessionSubtitle: String? {
        if onBreak {
            guard let next = shown.queue.first(where: { $0.count > 0 }) else {
                return "Next: nothing queued"
            }
            let name = named(next)
            if next.id == shown.activeItemID {
                return "Next: back to \(name)"
            }
            return "Next: \(name)"
        }
        guard let item = subtitleItem else { return nil }
        let work = shown.phase == .work
            ? Int(shown.phaseDuration / 60)
            : item.intensity.mode.workMinutes
        let rest = shown.phase == .work
            ? Int((shown.lockedBreakDuration ?? item.intensity.breakDuration) / 60)
            : item.intensity.mode.breakMinutes
        return "\(item.intensity.label) · \(work) min work, then \(rest) min break"
    }

    private var subtitleItem: QueueItem? {
        if shown.phase == .work {
            return shown.activeItem
        }
        if shown.phase == .idle {
            return shown.queue.first { $0.count > 0 }
        }
        return nil
    }

    private func named(_ item: QueueItem) -> String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var primaryTitle: String {
        if shown.phase == .idle {
            return "START"
        }
        return shown.isRunning ? "PAUSE" : "RESUME"
    }

    private var primaryHelp: String {
        switch primaryTitle {
        case "PAUSE": "Pause"
        case "RESUME": "Resume"
        default: "Start the next pomodoro"
        }
    }

    private var primaryDisabled: Bool {
        shown.phase == .idle && !shown.hasWorkQueued
    }

    private var secondaryTitle: String {
        if shown.phase == .breakTime {
            return "SKIP"
        }
        if shown.phase == .work, !shown.isRunning {
            return "FINISH"
        }
        return "RESET"
    }

    private var secondaryEnabled: Bool {
        shown.phase == .work || shown.phase == .breakTime
    }

    private var secondaryHelp: String {
        switch secondaryTitle {
        case "FINISH": "Finish this pomodoro and start its break"
        case "SKIP": "End the break and continue the queue"
        default: "Reset this pomodoro without finishing it"
        }
    }

    private func secondaryAction() {
        if model.session.phase == .breakTime {
            model.skipBreak()
        } else if model.session.phase == .work, !model.session.isRunning {
            model.markDone()
        } else {
            model.stop()
        }
    }

    private var cardHover: NSColor {
        onBreak
            ? NSColor(srgbRed: 0.1, green: 0.16, blue: 0.12, alpha: 0.14)
            : NSColor(white: 1, alpha: 0.16)
    }

    private func cardButton(_ title: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(cardInk.opacity(enabled ? 0.95 : 0.35))
                .frame(width: Metrics.actionWidth, height: Metrics.actionHeight)
                .modifier(FullHit(cornerRadius: Metrics.corner, hover: enabled ? cardHover : nil))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .stroke(cardInk.opacity(enabled ? 0.75 : 0.28), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

private struct SectionTitleHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

private struct QueueGapOutline: View {
    var height: CGFloat
    var visible: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(height: height)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

/// Fixed columns shared by Queue, LATER, Done, and History.
enum RowGrid {
    static let gauge: CGFloat = 80
    /// 56 pt clips a 12-hour short time ("12:50 AM" is 58 pt at 13 pt).
    static let clock: CGFloat = 60
    static let count: CGFloat = 40
    static let action: CGFloat = 28
    static let spacing: CGFloat = 8
    static let height: CGFloat = 40
    /// Room for the drag grip before the gauge.
    static let leading: CGFloat = 18
    static let trailing: CGFloat = 8
}

enum SectionStats {
    static func pomodoros(_ count: Int, seconds: TimeInterval) -> String {
        let noun = count == 1 ? "pomodoro" : "pomodoros"
        return "\(count) \(noun) · \(TimeFormat.span(seconds))"
    }

    static func tasks(_ count: Int) -> String {
        count == 1 ? "1 task" : "\(count) tasks"
    }
}

enum WorkedGaugeCopy {
    static func help(intensity: Intensity, count: Int, seconds: Int) -> String {
        if count <= 1 {
            let minutes = max(0, Int((Double(seconds) / 60).rounded()))
            return "\(intensity.label) · worked \(minutes) of \(intensity.mode.workMinutes) min"
        }
        return "\(intensity.label) · \(count) pomodoros · \(TimeFormat.span(TimeInterval(seconds))) worked"
    }
}

struct SectionHeader<Buttons: View>: View {
    var label: String
    var stats: String
    var help: String? = nil
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        HStack(spacing: RowGrid.spacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    labelText
                    statsText
                        .fixedSize(horizontal: true, vertical: false)
                }
                labelText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SectionTitleHelp(text: help))

            HStack(spacing: 2) {
                buttons()
            }
            .fixedSize()
        }
        .padding(.leading, RowGrid.leading)
        .padding(.trailing, RowGrid.trailing)
        .padding(.bottom, 2)
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var statsText: some View {
        Text(stats)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Palette.muted.opacity(0.7))
            .lineLimit(1)
    }
}

struct ListRow<Gauge: View, Name: View, Clock: View, Count: View, Action: View>: View {
    var showsDivider = false
    @ViewBuilder var gauge: () -> Gauge
    @ViewBuilder var name: () -> Name
    @ViewBuilder var clock: () -> Clock
    @ViewBuilder var count: () -> Count
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: RowGrid.spacing) {
            gauge()
                .frame(width: RowGrid.gauge, alignment: .leading)
                .layoutPriority(1)
            name()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
            clock()
                .frame(width: RowGrid.clock, alignment: .trailing)
                .layoutPriority(1)
            count()
                .frame(width: RowGrid.count, alignment: .center)
                .layoutPriority(1)
            action()
                .frame(width: RowGrid.action, alignment: .center)
                .layoutPriority(1)
        }
        .frame(height: RowGrid.height)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, RowGrid.gauge + RowGrid.spacing)
            }
        }
        .padding(.leading, RowGrid.leading)
        .padding(.trailing, RowGrid.trailing)
    }
}

private struct QueueLine: View {
    var item: QueueItem
    var isCurrent: Bool
    var finish: Date?
    var model: AppModel
    var gripVisible: Bool
    var floating = false
    var showsDivider = false

    @FocusState private var descriptionFocused: Bool

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var pinned: Bool {
        model.session.phase == .work && item.id == model.session.activeItemID
    }

    var body: some View {
        ListRow(showsDivider: showsDivider) {
            IntensitySwitch(
                intensity: item.intensity,
                locked: model.session.phase != .idle && item.id == model.session.activeItemID,
                reduceMotion: model.reduceMotion
            ) {
                model.updateIntensity(id: item.id, intensity: item.intensity.next)
            }
        } name: {
            TextField("Short description", text: descriptionBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($descriptionFocused)
                .onSubmit { model.commitDescriptionDraft(id: item.id) }
                .onChange(of: descriptionFocused) { _, focused in
                    if !focused { model.commitDescriptionDraft(id: item.id) }
                }
                .onChange(of: model.textFocusNonce) { _, _ in
                    descriptionFocused = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        } clock: {
            FinishClock(text: finishText, help: finishHelp, fadesWithText: true)
                .animation(QueueMotion.slide(model.reduceMotion), value: finishText)
        } count: {
            CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min") {
                guard item.count < Session.maxPomodoros else { return }
                model.setCount(id: item.id, count: item.count + 1)
            } onDecrement: {
                guard item.count > 1 else { return }
                model.setCount(id: item.id, count: item.count - 1)
            }
            .tourTarget(item.id == TourSample.outline ? .taskCount : nil)
        } action: {
            rowMenu
        }
        .background(isCurrent ? Color.white.opacity(0.05) : Color.clear)
        .overlay(alignment: .leading) {
            grip
                .padding(.leading, 1)
        }
        .onHover { hovering in
            guard !floating else { return }
            model.setQueueHover(item.id, hovering: hovering)
        }
    }

    private var grip: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .opacity(gripVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: gripVisible)
                .accessibilityHidden(true)
            if !floating {
                QueueGrip(
                    enabled: model.session.canReorder(id: item.id),
                    toolTip: pinned ? "The running task can't be moved." : nil,
                    onPress: { model.beginQueueDrag(id: item.id) }
                )
            }
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity)
        .tourTarget(item.id == TourSample.emails && !floating ? .reorderGrip : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reorder \(taskName)")
        .accessibilityHidden(!model.session.canReorder(id: item.id))
    }

    private var rowMenu: some View {
            EllipsisMenuButton(
                help: "Mark finished, reorder, snooze, or delete",
                label: "Actions for \(taskName)"
            ) {
                let snoozeLocked = !model.session.canSnooze(id: item.id)
                return [
                    .item("Mark as finished", enabled: item.count != 0) { model.markFinished(id: item.id) },
                    .separator,
                    .item("Move up", enabled: model.session.canMoveUp(id: item.id)) { model.moveUp(id: item.id) },
                    .item("Move down", enabled: model.session.canMoveDown(id: item.id)) { model.moveDown(id: item.id) },
                ] + Snooze.offers(on: model.now).map { offer in
                    .item(offer.title, enabled: !snoozeLocked) { model.snooze(id: item.id, returnDay: offer.returnDay) }
                } + [
                    .separator,
                    .item("Delete") { model.remove(id: item.id) },
                ]
            }
    }

    private var finishText: String {
        ClockFormat.time(finish)
    }

    private var finishHelp: String {
        guard let finish else { return "No finish time yet" }
        return "Work ends at \(ClockFormat.time(finish)), when the break starts"
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { model.descriptionDraft(for: item) },
            set: { model.setDescriptionDraft(id: item.id, text: $0) }
        )
    }
}

private struct LaterLine: View {
    var item: LaterItem
    var model: AppModel
    var showsDivider = false

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    var body: some View {
        ListRow(showsDivider: showsDivider) {
            DepthGauge(intensity: item.intensity, reduceMotion: model.reduceMotion)
                .opacity(0.55)
        } name: {
            TruncatingName(text: taskName, color: Palette.muted)
        } clock: {
            Color.clear.accessibilityHidden(true)
        } count: {
            CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min")
                .opacity(0.55)
                .allowsHitTesting(false)
        } action: {
            EllipsisMenuButton(
                help: "Return, reschedule, or delete",
                label: "Actions for \(taskName)"
            ) {
                [
                    .item("Back to queue") { model.returnLater(id: item.id) },
                ] + Snooze.offers(on: model.now, excluding: item.returnDay).map { offer in
                    MenuEntry.item(offer.title) { model.retargetLater(id: item.id, returnDay: offer.returnDay) }
                } + [
                    .separator,
                    .item("Delete") { model.deleteLater(id: item.id) },
                ]
            }
        }
    }
}

private struct MenuEntry {
    var title = ""
    var enabled = true
    var separator = false
    var action: () -> Void = {}

    static func item(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, enabled: enabled, action: action)
    }

    static var separator: MenuEntry { MenuEntry(separator: true) }
}

private final class MenuActionTarget: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire(_ sender: Any?) {
        action()
    }
}

private enum PopUpMenu {
    static func show(_ entries: [MenuEntry]) {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        for entry in entries {
            if entry.separator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(MenuActionTarget.fire(_:)), keyEquivalent: "")
            let target = MenuActionTarget(entry.action)
            targets.append(target)
            item.target = target
            item.isEnabled = entry.enabled
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = targets
    }
}

private struct EllipsisMenuButton: View {
    var help: String
    var label: String
    var entries: () -> [MenuEntry]

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: IconMetrics.side, height: IconMetrics.side)
            .overlay {
                IconPlate(toolTip: help, onLeft: { PopUpMenu.show(entries()) })
            }
            .fixedSize()
            .iconSlot(IconMetrics.column)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { PopUpMenu.show(entries()) }
    }
}

/// Done rows keep a stable id. A new id fades or slides in; an existing id moves.
private struct DoneRows: View {
    var items: [QueueItem]
    var model: AppModel

    private var order: [UUID] { items.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DoneLine(item: item, model: model, showsDivider: index < items.count - 1)
                    .transition(rowTransition)
            }
        }
        .animation(listAnimation, value: order)
    }

    /// One animation for the order change. Reduce Motion fades a new row and does not slide.
    private var listAnimation: Animation? {
        guard model.tour == nil, !model.reduceMotion else { return nil }
        return .easeOut(duration: 0.2)
    }

    private var rowTransition: AnyTransition {
        if model.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.2))
        }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

private struct DoneLine: View {
    var item: QueueItem
    var model: AppModel
    var showsDivider = false

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    /// Changes when the row's clock, worked time, or count changes.
    private var fadeToken: String {
        "\(item.count)|\(item.workedSeconds)|\(item.finishedAt?.timeIntervalSinceReferenceDate ?? -1)"
    }

    var body: some View {
        row
    }

    private var row: some View {
        let stack = ListRow(showsDivider: showsDivider) {
            DepthGauge(
                intensity: item.intensity,
                reduceMotion: model.reduceMotion,
                caption: TimeFormat.span(TimeInterval(item.workedSeconds)),
                captionHelp: WorkedGaugeCopy.help(intensity: item.intensity, count: item.count, seconds: item.workedSeconds),
                colorOpacity: 0.6
            )
        } name: {
            TruncatingName(text: taskName, color: Palette.muted)
        } clock: {
            FinishClock(text: ClockFormat.time(item.finishedAt), help: FinishClock.finishedHelp(item.finishedAt))
        } count: {
            CountText(count: item.count)
        } action: {
            SquareIconButton(
                systemName: "arrow.uturn.backward",
                weight: .semibold,
                opacity: 0.9,
                slot: IconMetrics.column,
                help: "Copy to the end of the queue"
            ) {
                model.requeue(id: item.id)
            }
        }
        return Group {
            if model.reduceMotion {
                stack
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: fadeToken)
            } else {
                stack
            }
        }
    }
}

private struct ScrollOffsetProbe: NSViewRepresentable {
    var onOffset: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollOffsetProbeView {
        let view = ScrollOffsetProbeView()
        view.onOffset = onOffset
        return view
    }

    func updateNSView(_ nsView: ScrollOffsetProbeView, context: Context) {
        nsView.onOffset = onOffset
    }
}

private final class ScrollOffsetProbeView: NSView {
    var onOffset: ((CGFloat) -> Void)?
    private var observing = false

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeClip()
        report()
    }

    override func layout() {
        super.layout()
        observeClip()
        report()
    }

    private func observeClip() {
        guard !observing, let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: clip
        )
        observing = true
    }

    @objc private func clipBoundsChanged() {
        report()
    }

    /// Distance of this view below the visible top. Negative once the content has moved up.
    private func report() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let origin = clip.convert(bounds.origin, from: self)
        let yFromTop = clip.isFlipped
            ? origin.y - clip.bounds.minY
            : clip.bounds.maxY - origin.y
        onOffset?(yFromTop)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private enum WindowMetrics {
    static let defaultSize = NSSize(width: 550, height: 600)
    static let minSize = NSSize(width: 450, height: 550)
    static let sizeKey = "SlimPomo.windowSize"
    static let minConstraintID = "SlimPomo.minSize"
}

enum Metrics {
    /// Wide enough for RESUME and FINISH at the card button's tracking.
    static let actionWidth: CGFloat = 132
    static let actionHeight: CGFloat = 34
    static let corner: CGFloat = 4
}

struct DepthGauge: View {
    var intensity: Intensity
    var showsChevron = false
    var reduceMotion = false
    /// When a parent control supplies the tooltip, the gauge stays quiet so the two don't compete.
    var showsTooltip = true
    /// Replaces the minutes mark. Done and History pass the worked time.
    var caption: String? = nil
    /// Replaces the summary tooltip and the spoken label when set.
    var captionHelp: String? = nil
    /// Share of the mode color that shows. Done and History use 0.6.
    var colorOpacity: Double = 1

    static let diameter: CGFloat = 20
    static let hitHeight: CGFloat = 28
    /// Inset so the circle sits inside the hover, the same on every row.
    static let pad: CGFloat = 4

    /// Slightly lighter than the window background, so the empty part of the circle reads as a bowl.
    private static let bowl = Color(white: 0.2)

    private var label: String { caption ?? intensity.workMark }
    private var ink: Color { intensity.chipColor.opacity(colorOpacity) }
    private var tip: String { captionHelp ?? intensity.summary }
    private var spokenLabel: String { captionHelp ?? intensity.spoken }

    var body: some View {
        HStack(spacing: 6) {
            bowlMark
            Text(label)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(ink)
                .contentTransition(reduceMotion ? .identity : .opacity)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Self.pad)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: intensity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .modifier(GaugeTooltip(text: showsTooltip ? tip : nil))
    }

    private var bowlMark: some View {
        ZStack {
            Circle()
                .fill(Self.bowl)
            DepthWater(level: intensity.waterLevel)
                .fill(ink)
                .clipShape(Circle())
            Circle()
                .strokeBorder(ink, lineWidth: 1.5)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }
}

/// Applies a tooltip only when there is one, so an empty help string never appears.
private struct GaugeTooltip: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

private struct DepthWater: Shape {
    var level: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = min(max(level, 0), 1)
        let height = rect.height * fraction
        return Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
    }
}

private struct IntensitySwitch: View {
    var intensity: Intensity
    var locked: Bool = false
    var reduceMotion = false
    var action: () -> Void

    private static let lockedHelp = "Intensity can't be changed while the timer is running"

    var body: some View {
        Button(action: action) {
            DepthGauge(intensity: intensity, reduceMotion: reduceMotion, showsTooltip: false)
                .opacity(locked ? 0.4 : 1)
                .frame(height: DepthGauge.hitHeight)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if locked {
                        DeniedCursor()
                    } else {
                        HoverPlate(cornerRadius: 6, color: NSColor(white: 1, alpha: 0.06))
                    }
                }
                .overlay {
                    if !locked {
                        PointingCursor()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .fixedSize()
        .help(locked ? Self.lockedHelp : intensity.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(intensity.spoken)
        .accessibilityHint(locked ? Self.lockedHelp : "Click to change")
    }
}

private struct ModeMenu: View {
    @Bindable var model: AppModel
    var describesHint: Bool
    @FocusState private var focused: Bool

    private var hot: Bool { model.depthControlHot }

    var body: some View {
        Button {
            model.showDepthPicker()
        } label: {
            DepthGauge(intensity: model.draftIntensity, showsChevron: true, reduceMotion: model.reduceMotion)
                .frame(height: DepthGauge.hitHeight)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    HoverPlate(cornerRadius: 6, color: NSColor(white: 1, alpha: 0.06))
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2)
                    }
                }
                .overlay { PointingCursor() }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, value in
            model.depthChipFocused = value
        }
        .onHover { model.depthChipHover = $0 }
        .animation(.easeOut(duration: 0.12), value: hot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.draftIntensity.spoken)
        .accessibilityHint(describesHint ? DepthHint.sentence : "Click to change")
        .accessibilityIdentifier("depth-picker")
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $model.modePickerOpen, arrowEdge: .bottom) {
            ModeChoices(model: model)
        }
    }
}

private struct DepthHint: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    static let sentence = "Pick how deep you want to go — longer sessions get longer breaks."
    private static let arrowWidth: CGFloat = 12

    private var hot: Bool { model.depthControlHot }

    var body: some View {
        Button {
            model.showDepthPicker()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("↑")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: Self.arrowWidth)
                Text(Self.sentence)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(hot ? Color.white.opacity(0.92) : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, RowGrid.leading + DepthGauge.pad + DepthGauge.diameter / 2 - Self.arrowWidth / 2)
        .padding(.trailing, 8)
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, value in
            model.depthHintFocused = value
        }
        .onHover { model.depthHintHover = $0 }
        .overlay { PointingCursor() }
        .animation(.easeOut(duration: 0.12), value: hot)
        .accessibilityIdentifier("depth-hint")
        .accessibilityLabel(Self.sentence)
    }
}

private struct ModeChoices: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Intensity.allCases, id: \.self) { mode in
                ModeChoiceButton(mode: mode, highlighted: model.modeHighlight == mode) {
                    choose(mode)
                }
            }
        }
        .padding(6)
        .frame(width: 320)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onMoveCommand { direction in
            switch direction {
            case .down, .right:
                move(1)
            case .up, .left:
                move(-1)
            default:
                break
            }
        }
        .onKeyPress(.return) {
            choose(model.modeHighlight)
            return .handled
        }
        .onExitCommand {
            model.modePickerOpen = false
        }
    }

    private func move(_ delta: Int) {
        let modes = Intensity.allCases
        guard let index = modes.firstIndex(of: model.modeHighlight) else { return }
        let next = min(max(0, index + delta), modes.count - 1)
        model.modeHighlight = modes[next]
    }

    private func choose(_ mode: Intensity) {
        let changed = mode != model.draftIntensity
        model.setDraftIntensity(mode)
        if changed { model.noteDepthChanged() }
        model.modePickerOpen = false
    }
}

private struct ModeChoiceButton: View {
    var mode: Intensity
    var highlighted: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                DepthGauge(intensity: mode, reduceMotion: true, showsTooltip: false)
                Text(mode.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                Text("\(mode.mode.workMinutes) min + \(mode.mode.breakMinutes) min break")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(highlighted ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .focusEffectDisabled()
        .overlay { HoverPlate(cornerRadius: 4, color: NSColor(white: 1, alpha: 0.12)) }
        .overlay { PointingCursor() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.spoken)
    }
}

enum ClockFormat {
    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct FinishClock: View {
    var text: String
    var help: String
    var fadesWithText = false

    var body: some View {
        Text(text)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .layoutPriority(1)
            .contentTransition(fadesWithText ? .opacity : .identity)
            .help(help)
            .accessibilityLabel(help)
    }

    static func finishedHelp(_ date: Date?) -> String {
        guard let date else { return "No finish time yet" }
        return "Finished at \(ClockFormat.time(date))"
    }
}

struct TruncatingName: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
    }
}

struct CountText: View {
    var count: Int

    var body: some View {
        Text("×\(max(0, count))")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("\(count) pomodoros")
    }
}

enum IconMetrics {
    static let side: CGFloat = 28
    static let radius: CGFloat = 6
    static let hover = NSColor(white: 1, alpha: 0.06)
    static let pressed = NSColor(white: 1, alpha: 0.10)
    static let ring: CGFloat = 22
    /// Layout slot the header icons used before they filled the action column.
    static let header = CGSize(width: 22, height: 18)
    static let count = CGSize(width: 22, height: 22)
    /// The shared action column. The 28 pt hit fills it.
    static let column = CGSize(width: 28, height: 28)
}

extension View {
    /// Reports the icon's existing slot. The 28 pt control stays centered and overflows that slot.
    func iconSlot(_ slot: CGSize) -> some View {
        IconSlotLayout(slot: slot) { self }
    }
}

private struct IconSlotLayout: Layout {
    var slot: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        slot
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: IconMetrics.side, height: IconMetrics.side)
        )
    }
}

struct SquareIconButton: View {
    var systemName: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var opacity: Double = 0.75
    var slot: CGSize = IconMetrics.header
    var help: String
    var action: () -> Void

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Color.white.opacity(opacity))
            .frame(width: IconMetrics.side, height: IconMetrics.side)
            .overlay {
                IconPlate(toolTip: help, onLeft: action)
            }
            .fixedSize()
            .iconSlot(slot)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { action() }
    }
}

struct CountBadge: View {
    var count: Int
    var detail: String
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?

    init(count: Int, detail: String, onIncrement: (() -> Void)? = nil, onDecrement: (() -> Void)? = nil) {
        self.count = count
        self.detail = detail
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
    }

    private var interactive: Bool { onIncrement != nil || onDecrement != nil }

    private var tip: String {
        interactive ? "\(detail). Click to add a pomodoro, right-click to remove one." : detail
    }

    var body: some View {
        Group {
            if interactive {
                Text("\(max(0, count))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: IconMetrics.side, height: IconMetrics.side)
                    .overlay {
                        IconPlate(
                            shape: .circle,
                            toolTip: tip,
                            drawsRing: true,
                            onLeft: { onIncrement?() },
                            onRight: { onDecrement?() }
                        )
                    }
                    .fixedSize()
                    .iconSlot(IconMetrics.count)
            } else {
                Text("\(max(0, count))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: IconMetrics.count.width, height: IconMetrics.count.height)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1).allowsHitTesting(false))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) pomodoros")
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityAction(named: "Add pomodoro") { onIncrement?() }
        .accessibilityAction(named: "Remove pomodoro") { onDecrement?() }
        .help(tip)
    }
}

struct IconPlate: NSViewRepresentable {
    enum Shape {
        case square
        case circle
    }

    var shape: Shape = .square
    var toolTip: String? = nil
    var swallowsCursor = false
    var drawsRing = false
    var onLeft: (() -> Void)? = nil
    var onRight: (() -> Void)? = nil

    func makeNSView(context: Context) -> PlateView {
        let view = PlateView()
        view.setAccessibilityElement(false)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PlateView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: PlateView) {
        view.shape = shape
        view.drawsRing = drawsRing
        view.onLeft = onLeft
        view.onRight = onRight
        view.toolTip = toolTip
        if view.swallowsCursor != swallowsCursor {
            view.swallowsCursor = swallowsCursor
            view.syncMonitor()
        }
        view.needsDisplay = true
    }

    final class PlateView: NSView {
        var shape: IconPlate.Shape = .square
        var drawsRing = false
        var swallowsCursor = false
        var onLeft: (() -> Void)?
        var onRight: (() -> Void)?
        private var monitor: Any?
        private var hovering = false
        private var pressed = false
        private var tourObserver: NSObjectProtocol?

        override var isOpaque: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            discardCursorRects()
            guard !touring else { return }
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func cursorUpdate(with event: NSEvent) {
            guard !touring else { return }
            NSCursor.pointingHand.set()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            watchTour()
            guard !touring else {
                setHovering(false)
                return
            }
            setHovering(true)
            NSCursor.pointingHand.set()
        }

        override func mouseExited(with event: NSEvent) {
            setHovering(false)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            watchTour()
            syncMonitor()
            window?.invalidateCursorRects(for: self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                removeMonitor()
                setHovering(false)
                setPressed(false)
            }
        }

        func syncMonitor() {
            removeMonitor()
            guard swallowsCursor, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate]) { [weak self] event in
                guard let self else { return event }
                let eventWindow = event.window
                let location = event.locationInWindow
                guard let eventWindow, self.window === eventWindow else { return event }
                if self.touring {
                    self.setHovering(false)
                    return event
                }
                let point = self.convert(location, from: nil)
                let inside = self.bounds.contains(point) && !self.isHiddenOrHasHiddenAncestor
                guard inside else {
                    self.setHovering(false)
                    return event
                }
                self.setHovering(true)
                NSCursor.pointingHand.set()
                return nil
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            if let fill = pressed ? IconMetrics.pressed : (hovering ? IconMetrics.hover : nil) {
                fill.setFill()
                hitPath.fill()
            }
            guard drawsRing else { return }
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let ring = NSBezierPath(ovalIn: centered(IconMetrics.ring))
            ring.lineWidth = 1
            ring.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            if onLeft == nil && onRight == nil {
                setPressed(true)
                forwardClick(event)
                setPressed(false)
                return
            }
            setPressed(true)
        }

        override func mouseUp(with event: NSEvent) {
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            setPressed(false)
            guard inside else { return }
            onLeft?()
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let onRight else {
                super.rightMouseDown(with: event)
                return
            }
            setPressed(true)
            onRight()
        }

        override func rightMouseUp(with event: NSEvent) {
            setPressed(false)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            onRight == nil ? super.menu(for: event) : nil
        }

        private var hitPath: NSBezierPath {
            switch shape {
            case .square:
                NSBezierPath(roundedRect: bounds, xRadius: IconMetrics.radius, yRadius: IconMetrics.radius)
            case .circle:
                NSBezierPath(ovalIn: bounds)
            }
        }

        private func centered(_ side: CGFloat) -> NSRect {
            NSRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            )
        }

        private var touring: Bool { AppRuntime.model.isTouring }

        private func setHovering(_ hovering: Bool) {
            guard self.hovering != hovering else { return }
            self.hovering = hovering
            needsDisplay = true
        }

        private func setPressed(_ pressed: Bool) {
            guard self.pressed != pressed else { return }
            self.pressed = pressed
            needsDisplay = true
        }

        private func forwardClick(_ event: NSEvent) {
            guard let window else { return }
            isHidden = true
            let hit = window.contentView?.hitTest(event.locationInWindow)
            let button = hit.flatMap { nearestButton(from: $0) }
            if let button {
                button.mouseDown(with: event)
            } else if let hit, hit !== self {
                hit.mouseDown(with: event)
            }
            isHidden = false
        }

        private func nearestButton(from view: NSView) -> NSButton? {
            var current: NSView? = view
            while let candidate = current {
                if let button = candidate as? NSButton { return button }
                current = candidate.superview
            }
            return nil
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func watchTour() {
            guard tourObserver == nil else { return }
            tourObserver = NotificationCenter.default.addObserver(
                forName: .slimpomoTourInteraction,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setHovering(false)
                    self?.setPressed(false)
                }
            }
        }

        isolated deinit {
            removeMonitor()
            if let tourObserver {
                NotificationCenter.default.removeObserver(tourObserver)
            }
        }
    }
}

struct FullHit: ViewModifier {
    var cornerRadius: CGFloat
    var hover: NSColor?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.001))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if let hover {
                    HoverPlate(cornerRadius: cornerRadius, color: hover)
                }
            }
    }
}

private struct PointingCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> PointingCursorView {
        PointingCursorView()
    }

    func updateNSView(_ nsView: PointingCursorView, context: Context) {}

    final class PointingCursorView: NSView {
        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: AppRuntime.model.isTouring ? .arrow : .pointingHand)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }
    }
}

private struct DeniedCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> DeniedCursorView {
        DeniedCursorView()
    }

    func updateNSView(_ nsView: DeniedCursorView, context: Context) {}

    final class DeniedCursorView: NSView {
        override var isOpaque: Bool { false }

        override func resetCursorRects() {
            guard !AppRuntime.model.isTouring else { return }
            addCursorRect(bounds, cursor: .arrow)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseDown(with event: NSEvent) {}
    }
}

struct HoverPlate: NSViewRepresentable {
    var cornerRadius: CGFloat
    var color: NSColor
    var activeDuringTour = false

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.cornerRadius = cornerRadius
        view.color = color
        view.activeDuringTour = activeDuringTour
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.color = color
        nsView.activeDuringTour = activeDuringTour
        nsView.needsDisplay = true
    }
}

final class HoverTrackingView: NSView {
    var cornerRadius: CGFloat = 4
    var color: NSColor = .white.withAlphaComponent(0.14)
    var activeDuringTour = false
    private var hovering = false
    private var pushedCursor = false

    override var isOpaque: Bool { false }

    /// The button underneath receives the click. This view only paints the hover wash.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        watchTour()
        if AppRuntime.model.isTouring, !activeDuringTour {
            clearHover()
            return
        }
        hovering = true
        needsDisplay = true
        guard !pushedCursor else { return }
        NSCursor.pointingHand.push()
        pushedCursor = true
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            clearHover()
        } else {
            watchTour()
        }
    }

    private var tourObserver: NSObjectProtocol?

    private func watchTour() {
        guard tourObserver == nil else { return }
        tourObserver = NotificationCenter.default.addObserver(
            forName: .slimpomoTourInteraction,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearHover()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    private func clearHover() {
        hovering = false
        needsDisplay = true
        guard pushedCursor else { return }
        NSCursor.pop()
        pushedCursor = false
    }
}

private extension Intensity {
    var next: Intensity {
        switch self {
        case .regular: .focus
        case .focus: .intense
        case .intense: .regular
        }
    }

    var chipColor: Color {
        if self == .regular { return Palette.cardBreak }
        return Color(red: mode.red, green: mode.green, blue: mode.blue)
    }

    /// Share of the circle that is water. Deep dive stops short of the rim.
    var waterLevel: CGFloat {
        switch self {
        case .regular: 1.0 / 3.0
        case .focus: 2.0 / 3.0
        case .intense: 7.0 / 8.0
        }
    }

    var spoken: String {
        "Intensity: \(label), \(mode.workMinutes) minutes work, \(mode.breakMinutes) minutes break"
    }
}
