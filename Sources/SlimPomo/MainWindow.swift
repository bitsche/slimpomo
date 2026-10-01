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
            window.title = "Deeeep"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Theme.bgBaseNS
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
            window.acceptsMouseMovedEvents = true
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

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var draftFocused = false
    @State private var draftContentHeight: CGFloat = 0
    @FocusState private var clearDoneFocused: Bool
    @State private var doneFlashOn = false
    @State private var doneFlashNonce = 0

    private var shown: Session { model.windowSession }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                WaterTank(
                    session: shown,
                    now: model.now,
                    reduceMotion: model.reduceMotion,
                    taskLine: tankTaskLine
                )
                timerControls
                    .padding(.top, 10)
            }
            .padding(.horizontal, PageInset.horizontal)
            .padding(.top, 12)
            .tourTarget(.timerCard)

            todoHeader
                .padding(.horizontal, PageInset.horizontal)
                .padding(.top, 14)

            VStack(spacing: 0) {
                addRow
                    .padding(.horizontal, PageInset.horizontal)
                    .padding(.top, 6)
                listScroller
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bgBase.ignoresSafeArea())
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
        .onChange(of: doneCompletions) { old, new in
            guard new > old, !model.isTouring, !model.isExpanded(.done) else { return }
            doneFlashNonce += 1
        }
        .task(id: doneFlashNonce) {
            guard doneFlashNonce > 0 else { return }
            doneFlashOn = true
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { doneFlashOn = false }
        }
    }

    /// Finished pomodoros today. A rise while Done is collapsed flashes the header stats.
    private var doneCompletions: Int {
        shown.done.reduce(0) { $0 + $1.count }
    }

    private var timerControls: some View {
        HStack(alignment: .center, spacing: 16) {
            TankPill(
                title: primaryTitle,
                enabled: !primaryDisabled,
                fill: pillRGB,
                help: primaryHelp
            ) {
                model.performMenuAction()
            }
            TankLink(
                title: secondaryTitle,
                enabled: secondaryEnabled,
                help: secondaryHelp,
                action: secondaryAction
            )
            Spacer(minLength: 0)
        }
    }

    private var todoHeader: some View {
        SectionHeader(
            label: "TODO",
            stats: todoStats,
            help: todoStats.isEmpty ? nil : "Work still in the queue, and when the last task would finish"
        ) {
            SquareIconButton(systemName: "questionmark.circle", size: 15, slot: IconMetrics.column, help: "Tour") {
                model.replayTour()
            }
            .tourTarget(.tourButton)
            SquareIconButton(systemName: "clock.arrow.circlepath", size: 15, slot: IconMetrics.column, help: "History") {
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
                            .padding(.top, showsDepthHint ? 18 : 8)
                    }
                    if !shown.later.isEmpty {
                        laterBlock
                            .padding(.top, shown.queue.isEmpty ? 14 : 14 - RowGrid.gap)
                            .tourTarget(.laterSection)
                    }
                    if !shown.done.isEmpty {
                        doneBlock
                            .padding(.top, doneHeaderGap)
                            .tourTarget(.doneSection)
                    }
                }
                .padding(.top, showsDepthHint ? 7 : 0)
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
                .fill(Theme.lineSubtle)
                .frame(height: 1)
            LinearGradient(
                colors: [Theme.bgBase.opacity(0.9), Theme.bgBase.opacity(0)],
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
            ForEach(displayedQueue) { item in
                let held = model.queueDrag?.itemID == item.id
                QueueLine(
                    item: item,
                    isCurrent: item.id == shown.activeItemID && shown.phase != .idle,
                    finish: shown.finishDates(at: model.now)[item.id],
                    model: model,
                    gripVisible: model.tourGripItemID == item.id
                        || (model.tour == nil && model.hoveredQueueID == item.id && model.session.canReorder(id: item.id))
                        || (model.tourQueueRevealID == item.id && model.session.canReorder(id: item.id))
                )
                .id(item.id)
                .opacity(held ? 0 : 1)
                .overlay(alignment: .top) {
                    if held {
                        RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous)
                            .stroke(Theme.lineField, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .padding(.horizontal, PageInset.horizontal)
                            .padding(.bottom, RowGrid.gap)
                            .opacity((model.queueDrag?.showsOutline ?? false) ? 1 : 0)
                            .accessibilityHidden(true)
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
        HStack(alignment: .top, spacing: RowGrid.spacing) {
            ModeMenu(model: model, describesHint: showsDepthHint)
                .tourTarget(.addChip)
                .frame(height: RowGrid.height)
            ZStack(alignment: .leading) {
                NameEditor(
                    text: draftBinding,
                    color: Theme.textPrimaryRGB.nsColor,
                    focus: $draftFocused,
                    fieldLabel: "New task",
                    onHeight: { height in
                        withAnimation(growthAnimation) { draftContentHeight = height }
                    },
                    onSubmit: {
                        model.addDraftItem()
                        draftFocused = true
                    },
                    onCancel: { draftFocused = false }
                )
                .frame(height: NameFieldMetrics.fieldHeight(content: draftContentHeight, font: NameFieldMetrics.font()))
                .overlay(alignment: .leading) {
                    if addPlaceholderVisible {
                        Text("Describe the task, press Return to add")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsHitTesting(false)
                    }
                }
                .tourTarget(.addField)
            }
            .padding(.vertical, (RowGrid.height - NameFieldMetrics.lineHeight(NameFieldMetrics.font())) / 2)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: RowGrid.height)
        .background(
            RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous)
                .fill(Theme.bgField)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous)
                .stroke(
                    draftFocused ? Theme.surface(model.draftIntensity) : Theme.lineField,
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        )
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.isTouring ? "" : model.draftDescription },
            set: { value in
                if !model.isTouring { model.draftDescription = value }
            }
        )
    }

    /// 150 ms, and none with Reduce Motion, so the rows below follow the field smoothly or not at all.
    private var growthAnimation: Animation? {
        model.reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    private var laterBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleSectionHeader(
                label: "LATER",
                stats: "\(shown.later.count)",
                spoken: "Later, \(Self.tasks(shown.later.count))",
                expanded: laterOpen,
                reduceMotion: model.reduceMotion,
                onToggle: { model.toggleSection(.later) }
            ) {
                EmptyView()
            }
            .padding(.horizontal, PageInset.horizontal)
            if laterOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.laterGroups().enumerated()), id: \.element.day) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(laterHeading(group.day))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Theme.textMuted)
                                .padding(.leading, PageInset.horizontal + RowGrid.leading)
                                .padding(.top, groupIndex == 0 ? 0 : 10)
                                .padding(.bottom, 4)
                            ForEach(group.items) { item in
                                LaterLine(item: item, model: model)
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .animation(QueueMotion.slide(model.reduceMotion), value: shown.later.map(\.id))
            }
        }
    }

    private static func tasks(_ count: Int) -> String {
        count == 1 ? "1 task" : "\(count) tasks"
    }

    /// The tour starts with the sample row visible. The header can still collapse it.
    private var laterOpen: Bool { model.isExpanded(.later) }

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
        let items = shown.mergedDone()
        let open = model.isExpanded(.done)
        let visible = model.doneListExpanded ? items : Array(items.prefix(3))
        let hidden = max(0, items.count - 3)
        let worked = TimeFormat.span(TimeInterval(doneSeconds))
        let trashShown = model.doneHeaderHovered || model.doneSectionFocused || clearDoneFocused
        return VStack(alignment: .leading, spacing: 0) {
            CollapsibleSectionHeader(
                label: "DONE",
                stats: worked,
                statsHighlighted: doneFlashOn,
                spoken: "Done, \(Self.tasks(items.count)), \(worked) worked",
                expanded: open,
                reduceMotion: model.reduceMotion,
                menu: [.item("Clear Done") { model.clearDone() }],
                onToggle: { model.toggleSection(.done) },
                onFocus: { model.doneSectionFocused = $0 }
            ) {
                SquareIconButton(
                    systemName: "trash",
                    size: 15,
                    weight: .medium,
                    opacity: trashShown ? 1 : 0,
                    slot: IconMetrics.column,
                    help: "Clear the done list"
                ) {
                    model.clearDone()
                }
                .allowsHitTesting(trashShown)
                .focusable()
                .focused($clearDoneFocused)
                .onKeyPress(.return) {
                    model.clearDone()
                    return .handled
                }
                .onKeyPress(.space) {
                    model.clearDone()
                    return .handled
                }
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: trashShown)
            }
            .padding(.horizontal, PageInset.horizontal)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.2), value: doneFlashOn)
            if open {
                DoneRows(items: visible, model: model)
                    .padding(.top, 6)
                if hidden > 0 {
                    MoreDoneLink(hidden: hidden, expanded: model.doneListExpanded) {
                        model.toggleDoneList()
                    } onFocus: { focused in
                        model.doneSectionFocused = focused
                    }
                }
            }
        }
        .background {
            SectionHover { model.doneHeaderHovered = $0 }
        }
    }

    private var doneSeconds: Int {
        shown.done.reduce(0) { $0 + max(0, $1.workedSeconds) }
    }

    private var todoWork: TimeInterval {
        shown.queue.reduce(0) { total, item in
            total + TimeInterval(max(0, item.count)) * item.intensity.workDuration
        }
    }

    /// Remaining planned work, and when the last queued task with pomodoros left would finish.
    private var todoStats: String {
        guard todoWork > 0, let last = shown.queue.last(where: { $0.count > 0 }) else { return "" }
        let finishes = shown.finishDates(at: model.now)
        guard let doneBy = finishes[last.id] else { return TimeFormat.span(todoWork) }
        return "\(TimeFormat.span(todoWork)) · done by \(ClockFormat.time(doneBy))"
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
            .scaleEffect(drag.lifted && !model.reduceMotion ? 1.02 : 1)
            .shadow(
                color: Theme.dragShadow.opacity(drag.lifted && !model.reduceMotion ? 1 : 0),
                radius: drag.lifted && !model.reduceMotion ? 8 : 0,
                y: drag.lifted && !model.reduceMotion ? 3 : 0
            )
            .offset(x: drag.visualX, y: drag.visualY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var showsDepthHint: Bool {
        shown.queue.isEmpty && !model.depthHintDismissed
    }

    /// The system prompt color ignores the theme, so the empty field draws its own.
    private var addPlaceholderVisible: Bool {
        !draftFocused && (model.isTouring || model.draftDescription.isEmpty)
    }

    /// 4 pt when DONE follows a collapsed LATER header. Otherwise 14 pt from the previous content, after that row's gap.
    private var doneHeaderGap: CGFloat {
        if !shown.later.isEmpty && !laterOpen { return 4 }
        if !shown.queue.isEmpty || (!shown.later.isEmpty && laterOpen) {
            return 14 - RowGrid.gap
        }
        return 14
    }

    private var tankTaskLine: TankTaskLine {
        if shown.phase == .breakTime {
            let message = model.breakMessage ?? BreakMessages.five[0]
            return TankTaskLine(text: "Break · \(message)")
        }
        if shown.phase == .work {
            if let active = shown.activeItem, !active.description.isEmpty {
                return TankTaskLine(text: active.description, isTask: true)
            }
            if !shown.activeDescription.isEmpty {
                return TankTaskLine(text: shown.activeDescription, isTask: true)
            }
            return TankTaskLine(text: "Untitled")
        }
        if let next = shown.queue.first(where: { $0.count > 0 }) {
            return TankTaskLine(lead: "Next:", text: named(next), isTask: true)
        }
        return TankTaskLine(text: "Nothing queued")
    }

    private var pillRGB: ThemeRGB {
        shown.phase == .breakTime ? Theme.breakPillRGB : Theme.surfaceRGB(pillMode)
    }

    private var pillMode: Intensity {
        if shown.phase == .work || shown.phase == .breakTime {
            return shown.activeItem?.intensity ?? .regular
        }
        return shown.queue.first { $0.count > 0 }?.intensity ?? .regular
    }

    private func named(_ item: QueueItem) -> String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var primaryTitle: String {
        if shown.phase == .idle {
            return "Start"
        }
        return shown.isRunning ? "Pause" : "Resume"
    }

    private var primaryHelp: String {
        switch primaryTitle {
        case "Pause": "Pause"
        case "Resume": "Resume"
        default: "Start the next pomodoro"
        }
    }

    private var primaryDisabled: Bool {
        shown.phase == .idle && !shown.hasWorkQueued
    }

    private var secondaryTitle: String {
        if shown.phase == .breakTime {
            return "Skip"
        }
        if shown.phase == .work, !shown.isRunning {
            return "Finish"
        }
        return "Reset"
    }

    private var secondaryEnabled: Bool {
        shown.phase == .work || shown.phase == .breakTime
    }

    private var secondaryHelp: String {
        switch secondaryTitle {
        case "Finish": "Finish this pomodoro and start its break"
        case "Skip": "End the break and continue the queue"
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

}

private struct TankPill: View {
    var title: String
    var enabled: Bool
    var fill: ThemeRGB
    var help: String
    var action: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Button(action: { ClickOnce.perform(action) }) {
            ZStack {
                Text("Resume").hidden()
                Text("Pause").hidden()
                Text("Start").hidden()
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.bgBase)
            .padding(.horizontal, 22)
            .frame(minWidth: 96, minHeight: 28, maxHeight: 28)
        }
        .buttonStyle(TankPillStyle(fill: fill, enabled: enabled))
        .disabled(!enabled)
        .pointingHandCursor(enabled: enabled)
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            ControlHit(shape: .capsule, enabled: enabled, action: { ClickOnce.perform(action) })
        }
        .overlay {
            if focused && enabled {
                Capsule()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
        .help(help)
        .accessibilityLabel(title)
    }
}

private struct TankPillStyle: ButtonStyle {
    var fill: ThemeRGB
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                PillFill(rgb: fill, pressed: configuration.isPressed && enabled, enabled: enabled)
            }
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.35)
    }
}

/// Capsule fill. Hover brightens by 6%. Press darkens by 8%. Disabled draws flat.
private struct PillFill: NSViewRepresentable {
    var rgb: ThemeRGB
    var pressed: Bool
    var enabled: Bool

    func makeNSView(context: Context) -> PillFillView {
        let view = PillFillView()
        view.rgb = rgb
        view.pressed = pressed
        view.tracksHover = enabled
        return view
    }

    func updateNSView(_ view: PillFillView, context: Context) {
        view.rgb = rgb
        view.tracksHover = enabled
        if !view.holding {
            view.pressed = pressed
        }
        view.needsDisplay = true
    }
}

final class PillFillView: NSView {
    var rgb = Theme.diveSurfaceRGB
    var pressed = false
    var tracksHover = true {
        didSet {
            if !tracksHover { hovering = false }
        }
    }

    /// True while ControlHit is holding the mouse, so a timer refresh cannot clear the press.
    var holding = false
    private var hovering = false

    override var isOpaque: Bool { false }
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
        guard tracksHover, !AppRuntime.model.isTouring else { return }
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    fileprivate var pillPath: NSBezierPath {
        let radius = bounds.height / 2
        return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shift: CGFloat = pressed ? -0.08 : (hovering ? 0.06 : 0)
        NSColor(
            srgbRed: min(1, max(0, rgb.r + shift)),
            green: min(1, max(0, rgb.g + shift)),
            blue: min(1, max(0, rgb.b + shift)),
            alpha: 1
        ).setFill()
        pillPath.fill()
    }
}

/// A click can reach both the SwiftUI button and the hit view. The second one, in the same instant, is ignored.
@MainActor
private enum ClickOnce {
    static var last: TimeInterval = 0

    static func perform(_ action: () -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - last < 0.05 { return }
        last = now
        action()
    }
}

/// Clear click target over the pill or the link. The whole visible shape hits, and this view never touches the cursor.
private struct ControlHit: NSViewRepresentable {
    enum Shape {
        case capsule
        case rectangle
    }

    var shape: Shape
    var enabled: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> ControlHitView {
        let view = ControlHitView()
        view.shape = shape
        view.enabled = enabled
        view.onAction = action
        return view
    }

    func updateNSView(_ view: ControlHitView, context: Context) {
        view.shape = shape
        view.enabled = enabled
        view.onAction = action
    }

    final class ControlHitView: NSView {
        var shape: ControlHit.Shape = .rectangle
        var enabled = true
        var onAction: (() -> Void)?

        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled else { return nil }
            let local = convert(point, from: superview)
            switch shape {
            case .capsule:
                let radius = bounds.height / 2
                return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(local) ? self : nil
            case .rectangle:
                return bounds.contains(local) ? self : nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            fill(holding: true, pressed: true)
        }

        override func mouseUp(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            let inside: Bool
            switch shape {
            case .capsule:
                let radius = bounds.height / 2
                inside = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(local)
            case .rectangle:
                inside = bounds.contains(local)
            }
            fill(holding: false, pressed: false)
            if inside {
                onAction?()
            }
        }

        private func fill(holding: Bool, pressed: Bool) {
            guard let fill = nearestFill() else { return }
            fill.holding = holding
            fill.pressed = pressed
            fill.needsDisplay = true
        }

        private func nearestFill() -> PillFillView? {
            var view: NSView? = superview
            for _ in 0..<8 {
                if let found = view.flatMap(Self.findFill) {
                    return found
                }
                view = view?.superview
            }
            return nil
        }

        private static func findFill(in view: NSView) -> PillFillView? {
            if let fill = view as? PillFillView { return fill }
            for child in view.subviews {
                if let found = findFill(in: child) { return found }
            }
            return nil
        }
    }
}

private struct TankLink: View {
    var title: String
    var enabled: Bool
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: { ClickOnce.perform(action) }) {
            Text(title)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(enabled ? Theme.link : Theme.linkDisabled)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .overlay(alignment: .bottom) {
                    if enabled {
                        HoverUnderline()
                    }
                }
        }
        .buttonStyle(PointingHandButtonStyle(enabled: enabled))
        .disabled(!enabled)
        .overlay {
            ControlHit(shape: .rectangle, enabled: enabled, action: { ClickOnce.perform(action) })
        }
        .help(help)
        .accessibilityLabel(title)
    }
}

/// A 1 pt underline that appears only while the pointer is over the link.
private struct HoverUnderline: NSViewRepresentable {
    var color: NSColor = Theme.linkRGB.nsColor

    func makeNSView(context: Context) -> HoverUnderlineView {
        let view = HoverUnderlineView()
        view.color = color
        return view
    }

    func updateNSView(_ nsView: HoverUnderlineView, context: Context) {
        nsView.color = color
    }

    final class HoverUnderlineView: NSView {
        var color: NSColor = Theme.linkRGB.nsColor
        private var hovering = false

        override var isOpaque: Bool { false }

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
            hovering = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            hovering = false
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard hovering else { return }
            color.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: bounds.minX, y: 1))
            line.line(to: NSPoint(x: bounds.maxX, y: 1))
            line.lineWidth = 1
            line.stroke()
        }
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

/// Shared row metrics. The name fills the space after the gauge. Hover controls overlay the end.
enum RowGrid {
    /// 20 pt gauge plus an 8 pt gap before the name.
    static let gauge: CGFloat = 28
    static let spacing: CGFloat = 8
    static let height: CGFloat = 36
    static let doneHeight: CGFloat = 30
    static let radius: CGFloat = 10
    /// Space between queue and LATER cards. Included in every queue row so a drag stride stays even.
    static let gap: CGFloat = 5
    static let doneGap: CGFloat = 2
    /// Card padding. The window inset is separate, so every edge lines up at 20 pt.
    static let leading: CGFloat = 8
    static let trailing: CGFloat = 8
}

/// Window inset shared by the tank, headers, the add field, and every row.
enum PageInset {
    static let horizontal: CGFloat = 20
}

/// The reorder grip sits in the 20 pt gutter, 6 pt from the window edge.
enum GripMetrics {
    static let width: CGFloat = 14
    static let height: CGFloat = 28
    static let x: CGFloat = 6
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

/// Label and stats of a section header. The stats drop out first when the row is too narrow.
struct SectionTitle: View {
    var label: String
    var stats: String
    var statsColor: Color = Theme.textMuted

    var body: some View {
        Group {
            if stats.isEmpty {
                labelText
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        labelText
                        statsText
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    labelText
                }
            }
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textHeaderLabel)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var statsText: some View {
        Text(stats)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(statsColor)
            .lineLimit(1)
    }
}

struct SectionHeader<Buttons: View>: View {
    var label: String
    var stats: String
    var help: String? = nil
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        HStack(spacing: RowGrid.spacing) {
            SectionTitle(label: label, stats: stats)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SectionTitleHelp(text: help))
        }
        .frame(height: 24)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                buttons()
            }
        }
    }
}

/// The header of a section that collapses. The whole 24 pt row is one button: label, stats, empty space, and chevron.
/// Controls passed as `accessory` sit left of the chevron and take their own clicks.
private struct CollapsibleSectionHeader<Accessory: View>: View {
    var label: String
    var stats: String
    var statsHighlighted = false
    /// What a screen reader says first, such as "Later, 4 tasks".
    var spoken: String
    var expanded: Bool
    var reduceMotion: Bool
    /// Also offered on right-click and as accessibility actions.
    var menu: [MenuEntry] = []
    var onToggle: () -> Void
    var onFocus: ((Bool) -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var focused: Bool

    private static var edge: CGFloat { 6 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onToggle) {
                HStack(spacing: RowGrid.spacing) {
                    SectionTitle(label: label, stats: stats, statsColor: statsHighlighted ? Theme.link : Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    chevron
                }
                .padding(.horizontal, Self.edge)
                .frame(height: 24)
                .contentShape(Rectangle())
                .overlay {
                    HoverPlate(cornerRadius: 6, color: Theme.headerHoverWashNS)
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.link, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(PointingHandButtonStyle())
            .padding(.horizontal, -Self.edge)
            .focused($focused)
            .focusEffectDisabled()
            .onChange(of: focused) { _, value in onFocus?(value) }
            .help(expanded ? "Collapse \(label.lowercased())" : "Expand \(label.lowercased())")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(spoken), \(expanded ? "expanded" : "collapsed")")
            .accessibilityHint(expanded ? "Hides the list" : "Shows the list")
            .accessibilityAddTraits(.isButton)
            .rowActions(menu)

            HStack(spacing: 2) {
                accessory()
            }
            .padding(.trailing, IconMetrics.column.width + 2)
        }
        .frame(height: 24)
        .background {
            if !menu.isEmpty {
                RowMenuClick(entries: { menu })
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
            .frame(width: IconMetrics.column.width, height: 24)
            .accessibilityHidden(true)
    }
}

private struct RowCard: ViewModifier {
    var fill: Color
    var bar: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                if let bar {
                    HStack(spacing: 0) {
                        bar.frame(width: 3)
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
    }
}

struct ListRow<Gauge: View, Name: View, Rest: View>: View {
    /// Nil lets the row grow with its content. Only a queue row that is being edited does.
    var height: CGFloat? = RowGrid.height
    var alignment: VerticalAlignment = .center
    @ViewBuilder var gauge: () -> Gauge
    @ViewBuilder var name: () -> Name
    @ViewBuilder var rest: () -> Rest

    var body: some View {
        HStack(alignment: alignment, spacing: 0) {
            gauge()
                .frame(width: RowGrid.gauge, alignment: .leading)
            name()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
            rest()
        }
        .padding(.horizontal, RowGrid.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
    }
}

/// Right-aligned hover controls. A 24 pt fade lets the name disappear under them.
struct HoverCluster<Content: View>: View {
    var shown: Bool
    var reduceMotion: Bool
    var fill: Color
    var cornerRadius: CGFloat = RowGrid.radius
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.leading, 28)
        .padding(.trailing, RowGrid.trailing)
        .frame(maxHeight: .infinity)
        .background {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [fill.opacity(0), fill],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                fill
            }
            .allowsHitTesting(false)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
        )
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: shown)
    }
}

struct WorkedMark: View {
    var seconds: Int
    var intensity: Intensity

    var body: some View {
        Text(TimeFormat.span(TimeInterval(seconds)))
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.surface(intensity).opacity(0.6))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct QueueLine: View {
    var item: QueueItem
    var isCurrent: Bool
    var finish: Date?
    var model: AppModel
    var gripVisible: Bool
    var floating = false

    @State private var editorContent: CGFloat = 0
    @State private var editCaret: Int?

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var isEditing: Bool {
        !floating && model.editingQueueID == item.id
    }

    private var pinned: Bool {
        model.session.phase == .work && item.id == model.session.activeItemID
    }

    private var showsWorkBar: Bool {
        isCurrent && model.windowSession.phase == .work
    }

    private var pointerHover: Bool {
        !floating && model.tour == nil && model.hoveredQueueID == item.id
    }

    private var revealed: Bool {
        floating || pointerHover || model.tourQueueRevealID == item.id
    }

    private var cardHovered: Bool {
        !showsWorkBar && (pointerHover || model.tourQueueRevealID == item.id)
    }

    var body: some View {
        card
            .padding(.horizontal, PageInset.horizontal)
            .overlay(alignment: .leading) {
                grip
                    .offset(x: GripMetrics.x)
            }
            .padding(.bottom, floating ? 0 : RowGrid.gap)
            .onHover { hovering in
                guard !floating else { return }
                model.setQueueHover(item.id, hovering: hovering)
            }
    }

    private var nameInk: Color { showsWorkBar ? Theme.textStrong : Theme.textPrimary }

    private var growthAnimation: Animation? {
        model.reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    private var card: some View {
        ListRow(height: isEditing ? nil : RowGrid.height, alignment: isEditing ? .top : .center) {
            IntensitySwitch(
                intensity: item.intensity,
                locked: model.session.phase != .idle && item.id == model.session.activeItemID,
                reduceMotion: model.reduceMotion,
                showsMark: false
            ) {
                model.updateIntensity(id: item.id, intensity: item.intensity.next)
            }
            .frame(height: RowGrid.height)
        } name: {
            if isEditing {
                editorField
            } else {
                TaskNameLabel(
                    text: nameShown,
                    color: nameInk,
                    semibold: showsWorkBar,
                    placeholder: "Short description",
                    onEdit: editHandler
                )
            }
        } rest: {
            if !isEditing, item.count == 0 || item.count >= 2 {
                CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min") {
                    addPomodoro()
                } onDecrement: {
                    removePomodoro()
                }
                .padding(.leading, 8)
            }
        }
        .onChange(of: model.textFocusNonce) { _, _ in
            if isEditing { finishEditing(save: true) }
        }
        .modifier(RowCard(fill: showsWorkBar ? Theme.bgCardActive : (cardHovered ? Theme.bgCardHover : Theme.bgCard), bar: showsWorkBar ? Theme.surface(item.intensity) : nil))
        .overlay(alignment: .trailing) {
            HoverCluster(
                shown: revealed && !isEditing,
                reduceMotion: model.reduceMotion,
                fill: showsWorkBar ? Theme.bgCardActive : Theme.bgCardHover
            ) {
                FinishClock(text: finishText, help: finishHelp, fadesWithText: true)
                    .animation(QueueMotion.slide(model.reduceMotion), value: finishText)
                CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min") {
                    addPomodoro()
                } onDecrement: {
                    removePomodoro()
                }
                .accessibilityHidden(item.count == 0 || item.count >= 2)
                .tourTarget(item.id == TourSample.outline ? .taskCount : nil)
                rowMenu
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: cardHovered)
        .animation(.easeOut(duration: 0.15), value: showsWorkBar)
        .background {
            if !floating {
                RowMenuClick(entries: menuEntries)
            }
        }
        .rowActions(menuEntries())
        .accessibilityAction(named: "Add pomodoro") { addPomodoro() }
        .accessibilityAction(named: "Remove pomodoro") { removePomodoro() }
    }

    /// The name as a field: `bgField`, a 1 pt border in the task's mode color, and the raw text.
    /// It starts at the row's height and grows to four lines. The gauge stays level with the first line.
    private var editorField: some View {
        let font = NameFieldMetrics.font(semibold: showsWorkBar)
        return NameEditor(
            text: descriptionBinding,
            semibold: showsWorkBar,
            color: (showsWorkBar ? Theme.textStrongRGB : Theme.textPrimaryRGB).nsColor,
            autoFocus: true,
            caret: editCaret,
            fieldLabel: "Task name",
            onHeight: { height in
                withAnimation(growthAnimation) { editorContent = height }
            },
            onSubmit: { finishEditing(save: true) },
            onCancel: { finishEditing(save: false) },
            onEnd: { finishEditing(save: true) }
        )
        .frame(height: NameFieldMetrics.fieldHeight(content: editorContent, font: font))
        .padding(.horizontal, 6)
        .padding(.vertical, (RowGrid.height - 6 - NameFieldMetrics.lineHeight(font)) / 2)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.bgField)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.surface(item.intensity), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.leading, -6)
        .padding(.trailing, -4)
        .padding(.vertical, 3)
    }

    private var editHandler: ((CGFloat?) -> Void)? {
        if floating || model.isTouring { return nil }
        return { x in beginEditing(at: x) }
    }

    private func beginEditing(at x: CGFloat?) {
        guard !floating, model.tour == nil else { return }
        editorContent = 0
        editCaret = x.map { NameCaret.offset(in: item.description, x: $0, semibold: showsWorkBar) }
        withAnimation(growthAnimation) {
            model.beginNameEdit(id: item.id)
        }
    }

    private func finishEditing(save: Bool) {
        guard model.editingQueueID == item.id else { return }
        withAnimation(growthAnimation) {
            model.endNameEdit(id: item.id, save: save)
        }
    }

    private var grip: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.link)
                .opacity(gripVisible ? 1 : 0)
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: gripVisible)
                .accessibilityHidden(true)
            if !floating {
                QueueGrip(
                    enabled: model.session.canReorder(id: item.id) && model.editingQueueID == nil,
                    toolTip: pinned ? "The running task can't be moved." : nil,
                    onPress: { model.beginQueueDrag(id: item.id) }
                )
            }
        }
        .frame(width: GripMetrics.width, height: GripMetrics.height)
        .allowsHitTesting(!floating && model.session.canReorder(id: item.id) && model.editingQueueID == nil)
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
            menuEntries()
        }
        .tourTarget(item.id == TourSample.outline && !floating ? .rowMenu : nil)
    }

    private func menuEntries() -> [MenuEntry] {
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
            .item("Delete", destructive: true) { model.remove(id: item.id) },
        ]
    }

    private func addPomodoro() {
        guard item.count < Session.maxPomodoros else { return }
        model.setCount(id: item.id, count: item.count + 1)
    }

    private func removePomodoro() {
        guard item.count > 1 else { return }
        model.setCount(id: item.id, count: item.count - 1)
    }

    private var finishText: String {
        ClockFormat.time(finish)
    }

    private var finishHelp: String {
        guard let finish else { return "No finish time yet" }
        return "Work ends at \(ClockFormat.time(finish)), when the break starts"
    }

    private var nameShown: String { model.descriptionDraft(for: item) }

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

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var revealed: Bool {
        (model.tour == nil && model.hoveredLaterID == item.id) || model.tourLaterRevealID == item.id
    }

    var body: some View {
        ListRow {
            DepthGauge(intensity: item.intensity, reduceMotion: model.reduceMotion, showsMark: false)
        } name: {
            TruncatingName(text: taskName, color: Theme.textPrimary)
        } rest: {
            if item.count >= 2 {
                CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min")
                    .allowsHitTesting(false)
                    .padding(.leading, 8)
            }
        }
        .modifier(RowCard(fill: Theme.bgCard))
        .overlay(alignment: .trailing) {
            HoverCluster(shown: revealed, reduceMotion: model.reduceMotion, fill: Theme.bgCard) {
                CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min")
                    .allowsHitTesting(false)
                    .accessibilityHidden(item.count >= 2)
                EllipsisMenuButton(
                    help: "Return, reschedule, or delete",
                    label: "Actions for \(taskName)"
                ) {
                    menuEntries()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RowGrid.radius, style: .continuous))
        .opacity(0.6)
        .background { RowMenuClick(entries: menuEntries) }
        .rowActions(menuEntries())
        .onHover { model.setLaterHover(item.id, hovering: $0) }
        .padding(.horizontal, PageInset.horizontal)
        .padding(.bottom, RowGrid.gap)
    }

    private func menuEntries() -> [MenuEntry] {
        [
            .item("Back to queue") { model.returnLater(id: item.id) },
        ] + Snooze.offers(on: model.now, excluding: item.returnDay).map { offer in
            MenuEntry.item(offer.title) { model.retargetLater(id: item.id, returnDay: offer.returnDay) }
        } + [
            .separator,
            .item("Delete", destructive: true) { model.deleteLater(id: item.id) },
        ]
    }
}

private struct MenuEntry {
    var title = ""
    var enabled = true
    var destructive = false
    var separator = false
    var action: () -> Void = {}

    static func item(_ title: String, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, enabled: enabled, destructive: destructive, action: action)
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
        menu.appearance = NSAppearance(named: .darkAqua)
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
            if entry.destructive && entry.enabled {
                item.attributedTitle = NSAttributedString(
                    string: entry.title,
                    attributes: [
                        .foregroundColor: Theme.destructiveNS,
                        .font: NSFont.menuFont(ofSize: 0),
                    ]
                )
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = targets
    }
}

/// Fades secondary row content without giving up its column.
struct RestFade: ViewModifier {
    var shown: Bool
    var reduceMotion: Bool
    /// A hidden control stays out of the click path. VoiceOver can still use it.
    var blocksClicksWhenHidden = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown || !blocksClicksWhenHidden)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: shown)
    }
}

private extension View {
    func rowActions(_ entries: [MenuEntry]) -> some View {
        modifier(RowActions(entries: entries))
    }
}

private struct RowActions: ViewModifier {
    var entries: [MenuEntry]

    func body(content: Content) -> some View {
        content.accessibilityActions {
            let named = entries.filter { !$0.separator }
            ForEach(Array(named.enumerated()), id: \.offset) { _, entry in
                Button(entry.title) { // cursor-exempt: VoiceOver action, not a visible control
                    guard entry.enabled else { return }
                    entry.action()
                }
            }
        }
    }
}

/// Right-click anywhere on the row opens the same menu as •••. A count circle and an open text field keep their own right-click.
private struct RowMenuClick: NSViewRepresentable {
    var entries: () -> [MenuEntry]

    func makeNSView(context: Context) -> RowMenuClickView {
        let view = RowMenuClickView()
        view.entries = entries
        return view
    }

    func updateNSView(_ view: RowMenuClickView, context: Context) {
        view.entries = entries
    }
}

private final class RowMenuClickView: NSView {
    var entries: () -> [MenuEntry] = { [] }
    private var monitor: Any?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let consume = MainActor.assumeIsolated { () -> Bool in
                self?.handle(event) ?? false
            }
            return consume ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return false }
        if claimsRightClick(event) { return false }
        PopUpMenu.show(entries())
        return true
    }

    private func claimsRightClick(_ event: NSEvent) -> Bool {
        guard let hit = window?.contentView?.hitTest(event.locationInWindow) else { return false }
        var view: NSView? = hit
        while let current = view {
            if let plate = current as? IconPlate.PlateView, plate.onRight != nil {
                return true
            }
            if current is NSTextView {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Tracks the pointer over a whole section, including rows that have their own hover.
private struct SectionHover: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> SectionHoverView {
        let view = SectionHoverView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: SectionHoverView, context: Context) {
        nsView.onHover = onHover
    }

    final class SectionHoverView: NSView {
        var onHover: ((Bool) -> Void)?

        override var isOpaque: Bool { false }
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
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}

private struct MoreDoneLink: View {
    var hidden: Int
    var expanded: Bool
    var action: () -> Void
    var onFocus: (Bool) -> Void

    @FocusState private var focused: Bool

    private var title: String {
        expanded ? "Show less" : "Show \(hidden) more"
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .overlay(alignment: .bottom) {
                    HoverUnderline(color: Theme.textMutedRGB.nsColor)
                }
        }
        .buttonStyle(PointingHandButtonStyle())
        .padding(.leading, PageInset.horizontal + RowGrid.leading)
        .focused($focused)
        .onChange(of: focused) { _, value in onFocus(value) }
        .accessibilityLabel(title)
    }
}

private struct EllipsisMenuButton: View {
    var help: String
    var label: String
    var entries: () -> [MenuEntry]

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.link)
            .frame(width: IconMetrics.side, height: IconMetrics.side)
            .contentShape(Rectangle())
            .overlay {
                IconPlate(toolTip: help, onLeft: { PopUpMenu.show(entries()) })
            }
            .fixedSize()
            .iconSlot(IconMetrics.column)
            .pointingHandCursor()
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
            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                DoneLine(item: item, model: model)
                    .transition(rowTransition)
            }
        }
        .animation(listAnimation, value: order)
    }

    /// One animation for the order change. Reduce Motion fades a new row and does not slide.
    private var listAnimation: Animation? {
        guard model.tour == nil, !model.reduceMotion, !model.suppressDoneAnimation else { return nil }
        return .easeOut(duration: 0.2)
    }

    private var rowTransition: AnyTransition {
        if model.reduceMotion || model.suppressDoneAnimation {
            return .opacity.animation(.easeOut(duration: 0.2))
        }
        let removal: AnyTransition = model.doneListExpanded
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: removal
        )
    }
}

private struct DoneLine: View {
    var item: QueueItem
    var model: AppModel

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var revealed: Bool {
        (model.tour == nil && model.hoveredDoneID == item.id) || model.tourDoneRevealID == item.id
    }

    /// Changes when the row's clock, worked time, or count changes.
    private var fadeToken: String {
        "\(item.count)|\(item.workedSeconds)|\(item.finishedAt?.timeIntervalSinceReferenceDate ?? -1)"
    }

    var body: some View {
        row
    }

    private var row: some View {
        let stack = ListRow(height: RowGrid.doneHeight) {
            DepthGauge(
                intensity: item.intensity,
                reduceMotion: model.reduceMotion,
                showsMark: false,
                captionHelp: WorkedGaugeCopy.help(intensity: item.intensity, count: item.count, seconds: item.workedSeconds),
                colorOpacity: 0.6
            )
        } name: {
            TruncatingName(text: taskName, color: Theme.textSecondary)
        } rest: {
            WorkedMark(seconds: item.workedSeconds, intensity: item.intensity)
                .padding(.leading, 8)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(revealed ? Theme.bgCard : Color.clear)
        }
        .overlay(alignment: .trailing) {
            HoverCluster(
                shown: revealed,
                reduceMotion: model.reduceMotion,
                fill: Theme.bgCard,
                cornerRadius: 8
            ) {
                FinishClock(
                    text: ClockFormat.time(item.finishedAt),
                    help: FinishClock.finishedHelp(item.finishedAt),
                    color: Theme.textTertiary
                )
                WorkedMark(seconds: item.workedSeconds, intensity: item.intensity)
                    .accessibilityHidden(true)
                CountText(count: item.count)
                SquareIconButton(
                    systemName: "arrow.uturn.backward",
                    weight: .semibold,
                    tint: Theme.link,
                    slot: IconMetrics.column,
                    help: "Copy to the end of the queue",
                    onFocus: { model.doneSectionFocused = $0 }
                ) {
                    model.requeue(id: item.id)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { model.setDoneHover(item.id, hovering: $0) }
        .accessibilityAction(named: "Copy to the end of the queue") { model.requeue(id: item.id) }
        .padding(.horizontal, PageInset.horizontal)
        .padding(.bottom, RowGrid.doneGap)
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

struct DepthGauge: View {
    var intensity: Intensity
    var showsChevron = false
    var reduceMotion = false
    /// When a parent control supplies the tooltip, the gauge stays quiet so the two don't compete.
    var showsTooltip = true
    /// Replaces the minutes mark. Done and History pass the worked time.
    var caption: String? = nil
    /// Queue and LATER hide the minutes. The add row, Done, and History keep a label.
    var showsMark: Bool = true
    /// Replaces the summary tooltip and the spoken label when set.
    var captionHelp: String? = nil
    /// Share of the mode color that shows. Done rows use 0.6.
    var colorOpacity: Double = 1
    /// Add-row chip uses 11 pt. Queue rows use 12.
    var markSize: CGFloat = 12

    static let diameter: CGFloat = 20
    static let hitHeight: CGFloat = 28
    /// The list column supplies the gap. The circle itself is not inset.
    static let pad: CGFloat = 0

    private var label: String { caption ?? intensity.workMark }
    private var ink: Color { Theme.surface(intensity).opacity(colorOpacity) }
    private var tip: String { captionHelp ?? intensity.summary }
    private var spokenLabel: String { captionHelp ?? intensity.spoken }

    var body: some View {
        HStack(spacing: 6) {
            bowlMark
            if showsMark {
                Text(label)
                    .font(.system(size: markSize).monospacedDigit())
                    .foregroundStyle(ink)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink)
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
                .fill(Theme.gaugeInner)
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
        let stroke: CGFloat = 1.5
        let inner = max(0, rect.height - stroke * 2)
        let water = inner * fraction
        let top = rect.minY + stroke + (inner - water)
        return Path(CGRect(x: rect.minX, y: top, width: rect.width, height: rect.maxY - top))
    }
}

private struct IntensitySwitch: View {
    var intensity: Intensity
    var locked: Bool = false
    var reduceMotion = false
    var showsMark = true
    var action: () -> Void

    private static let lockedHelp = "Intensity can't be changed while the timer is running"

    var body: some View {
        Button(action: action) {
            DepthGauge(intensity: intensity, reduceMotion: reduceMotion, showsTooltip: false, showsMark: showsMark)
                .opacity(locked ? 0.4 : 1)
                .frame(height: DepthGauge.hitHeight)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if locked {
                        DeniedCursor()
                    } else {
                        HoverPlate(cornerRadius: 6, color: Theme.hoverWashNS)
                    }
                }
        }
        .buttonStyle(PointingHandButtonStyle(enabled: !locked))
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
            DepthGauge(intensity: model.draftIntensity, showsChevron: true, reduceMotion: model.reduceMotion, markSize: 11)
                .frame(height: DepthGauge.hitHeight)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    HoverPlate(cornerRadius: 6, color: Theme.hoverWashNS)
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.link, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PointingHandButtonStyle())
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
            .foregroundStyle(hot ? Theme.textPrimary : Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PointingHandButtonStyle())
        .padding(.leading, PageInset.horizontal + 10 + DepthGauge.diameter / 2 - Self.arrowWidth / 2)
        .padding(.trailing, 8)
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, value in
            model.depthHintFocused = value
        }
        .onHover { model.depthHintHover = $0 }
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
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                Text("\(mode.mode.workMinutes) min + \(mode.mode.breakMinutes) min break")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(highlighted ? Theme.bgCardHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PointingHandButtonStyle())
        .contentShape(Rectangle())
        .focusEffectDisabled()
        .overlay { HoverPlate(cornerRadius: 4, color: Theme.hoverWashNS) }
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
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(fadesWithText ? .opacity : .identity)
            .help(help)
            .accessibilityLabel(help)
    }

    static func finishedHelp(_ date: Date?) -> String {
        guard let date else { return "No finish time yet" }
        return "Finished at \(ClockFormat.time(date))"
    }
}

/// A read-only task name on one line. It keeps the muted project label whole and shortens the rest with "…".
struct TruncatingName: View {
    var text: String
    var color: Color

    var body: some View {
        TaskNameLabel(text: text, color: color)
    }
}

/// A task name on one line: the project label in muted small caps, then the rest of the name.
/// A name that does not fit shows its full text as a tooltip. With `onEdit`, a click on the name opens the editor.
struct TaskNameLabel: View {
    var text: String
    var color: Color
    var semibold = false
    /// Drawn in place of an empty name.
    var placeholder: String? = nil
    /// Called with the click's x in the name, or nil from the keyboard or VoiceOver.
    var onEdit: ((CGFloat?) -> Void)? = nil

    @State private var restWidth: CGFloat = 0

    private var parts: TaskName.Parts { TaskName.split(text) }

    private var truncated: Bool {
        guard restWidth > 1 else { return false }
        let drawn = (parts.rest as NSString).size(withAttributes: [.font: NameFieldMetrics.font(semibold: semibold)]).width
        return drawn > restWidth + 0.5
    }

    var body: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            .overlay {
                if let onEdit {
                    NameClickArea(toolTip: truncated ? text : nil, onActivate: onEdit)
                }
            }
            .modifier(GaugeTooltip(text: onEdit == nil && truncated ? text : nil))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.isEmpty ? (placeholder ?? "") : text)
            .accessibilityAddTraits(onEdit == nil ? [] : .isButton)
            .accessibilityHint(onEdit == nil ? "" : "Edit the task name")
            .accessibilityActions {
                if let onEdit {
                    Button("Edit task name") { onEdit(nil) } // cursor-exempt: VoiceOver action, not a visible control
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if text.isEmpty, let placeholder {
            Text(placeholder)
                .font(.system(size: 13, weight: semibold ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            HStack(spacing: 0) {
                if let prefix = parts.prefix {
                    Text(prefix)
                        .font(.system(size: 11).monospacedDigit().smallCaps())
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.trailing, LabelStyle.gap)
                }
                Text(parts.rest)
                    .font(.system(size: 13, weight: semibold ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { restWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, width in restWidth = width }
                        }
                    }
            }
        }
    }
}

struct CountText: View {
    var count: Int

    var body: some View {
        Text("×\(max(0, count))")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(count) pomodoros")
    }
}

enum IconMetrics {
    static let side: CGFloat = 28
    static let radius: CGFloat = 6
    static let hover = Theme.hoverWashNS
    static let pressed = Theme.pressedWashNS
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
    var opacity: Double = 1
    var tint: Color = Theme.textMuted
    var slot: CGSize = IconMetrics.header
    var help: String
    var onFocus: ((Bool) -> Void)? = nil
    var action: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint.opacity(opacity))
            .frame(width: IconMetrics.side, height: IconMetrics.side)
            .contentShape(Rectangle())
            .overlay {
                IconPlate(toolTip: help, onLeft: action)
            }
            .fixedSize()
            .iconSlot(slot)
            .pointingHandCursor()
            .focusable(onFocus != nil)
            .focused($focused)
            .onChange(of: focused) { _, value in onFocus?(value) }
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
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: IconMetrics.side, height: IconMetrics.side)
                    .contentShape(Circle())
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
                    .iconSlot(IconMetrics.column)
                    .pointingHandCursor()
            } else {
                Text("\(max(0, count))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textStrong)
                    .frame(width: IconMetrics.count.width, height: IconMetrics.count.height)
                    .overlay(Circle().stroke(Theme.countRing, lineWidth: 1.5).allowsHitTesting(false))
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
            updateTrackingAreas()
            syncHoverToPointer()
            window?.invalidateCursorRects(for: self)
        }

        /// The hover cluster appears under a pointer that is already inside, so mouseEntered never fires.
        private func syncHoverToPointer() {
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let inside = bounds.contains(point) && !isHiddenOrHasHiddenAncestor && window.isVisible
            if touring || !inside {
                setHovering(false)
            } else {
                setHovering(true)
            }
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
            Theme.countRingNS.setStroke()
            let ring = NSBezierPath(ovalIn: centered(IconMetrics.ring))
            ring.lineWidth = 1.5
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
    var color: NSColor = Theme.hoverWashNS
    var activeDuringTour = false
    private var hovering = false

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

    /// Share of the gauge's inner height that is water.
    var waterLevel: CGFloat { CGFloat(gaugeFill) }

    var spoken: String {
        "Intensity: \(label), \(mode.workMinutes) minutes work, \(mode.breakMinutes) minutes break"
    }
}
