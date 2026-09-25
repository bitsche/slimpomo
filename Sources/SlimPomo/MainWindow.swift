import AppKit
import SwiftUI
import SlimPomoCore

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var acceptsSizeSaves = false
    private var sizeSaveTask: Task<Void, Never>?

    func show(model: AppModel) {
        NSApp.setActivationPolicy(.regular)
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
            // view's intrinsic size, which the minimum then clamps to 400×450.
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
            let another = NSApp.windows.contains { $0 !== self.window && $0.isVisible }
            if !another {
                NSApp.setActivationPolicy(.accessory)
            }
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
        if width < WindowMetrics.minSize.width || height < WindowMetrics.minSize.height {
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
        VStack(spacing: 14) {
            timerCard
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .tourTarget(.timerCard)

            todoHeader
                .padding(.horizontal, 18)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        queueBlock
                        if !shown.done.isEmpty {
                            doneBlock
                                .tourTarget(.doneSection)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDisabled(model.isTouring)
                .onChange(of: model.tourScrollRequest) { _, _ in
                    guard let target = model.tour?.step.anchor else { return }
                    withAnimation(model.reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    model.scheduleTourScrollFinish()
                }
            }
            .overlay(alignment: .topLeading) {
                queueDragFloat
            }
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
                    primaryAction()
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
        centeredSectionTitle(
            todoTitle,
            help: "Pomodoros still in the queue, and the work time they add up to"
        ) {
            Button {
                model.replayTour()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 22, height: 18)
                    .modifier(FullHit(cornerRadius: Metrics.corner, hover: Palette.hover))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Tour")
            .accessibilityLabel("Tour")
            .tourTarget(.tourButton)
            Button {
                model.showHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 22, height: 18)
                    .modifier(FullHit(cornerRadius: Metrics.corner, hover: Palette.hover))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("History")
            .accessibilityLabel("History")
            .tourTarget(.historyButton)
        }
    }

    /// The title stays on the window's center line. Trailing buttons sit over the right rule
    /// instead of pushing the title off that line.
    private func centeredSectionTitle<Buttons: View>(
        _ title: String,
        help: String? = nil,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        HStack(spacing: 12) {
            hairline
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
                .modifier(SectionTitleHelp(text: help))
            hairline
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 12) {
                buttons()
            }
            .padding(.leading, 12)
            .background(Palette.canvas)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }

    private var queueBlock: some View {
        VStack(spacing: 0) {
            addRow
                .padding(.bottom, showsDepthHint ? 7 : 14)

            if showsDepthHint {
                DepthHint(model: model)
            }
            if !shown.queue.isEmpty {
                VStack(spacing: 0) {
                    ForEach(queueSlots) { slot in
                        switch slot.kind {
                        case .item(let item):
                            QueueLine(
                                item: item,
                                isCurrent: item.id == shown.activeItemID && shown.phase != .idle,
                                finish: shown.finishDates(at: model.now)[item.id],
                                model: model,
                                gripVisible: model.tourGripItemID == item.id
                                    || (model.tour == nil && model.hoveredQueueID == item.id && model.session.canReorder(id: item.id))
                            )
                        case .gap:
                            QueueGapOutline(
                                height: model.queueDrag?.rowHeight ?? 48,
                                visible: model.queueDrag?.showsOutline ?? false
                            )
                        }
                    }
                }
                .animation(QueueMotion.slide(model.reduceMotion), value: model.queueDrag?.gapIndex)
                .animation(
                    model.queueDrag == nil && model.tour == nil ? QueueMotion.slide(model.reduceMotion) : nil,
                    value: shown.queue.map(\.id)
                )
                .background {
                    QueueListAnchor { anchor in
                        model.attachQueueList(anchor)
                    }
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            ModeMenu(model: model, describesHint: showsDepthHint)
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
                .onSubmit { model.addDraftItem() }
                .tourTarget(.addField)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var doneBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            centeredSectionTitle(doneTitle) {
                Button {
                    model.clearDone()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 22, height: 18)
                        .modifier(FullHit(cornerRadius: Metrics.corner, hover: Palette.hover))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Clear the done list")
                .accessibilityLabel("Clear the done list")
            }
            VStack(spacing: 0) {
                ForEach(shown.done) { item in
                    DoneLine(item: item, model: model)
                }
            }
        }
    }

    private var doneTitle: String {
        let count = shown.done.reduce(0) { $0 + max(0, $1.count) }
        let noun = count == 1 ? "pomodoro" : "pomodoros"
        let seconds = shown.done.reduce(0) { $0 + max(0, $1.workedSeconds) }
        return "DONE · \(count) \(noun) · \(TimeFormat.span(TimeInterval(seconds))) work"
    }

    private var todoTitle: String {
        let noun = todoCount == 1 ? "pomodoro" : "pomodoros"
        return "TODO · \(todoCount) \(noun) · \(TimeFormat.span(todoWork)) work"
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

    private struct QueueSlot: Identifiable {
        enum Kind {
            case item(QueueItem)
            case gap
        }

        var id: UUID
        var kind: Kind
    }

    private var queueSlots: [QueueSlot] {
        let queue = shown.queue
        guard let drag = model.queueDrag,
              let from = queue.firstIndex(where: { $0.id == drag.itemID }) else {
            return queue.map { QueueSlot(id: $0.id, kind: .item($0)) }
        }
        var rest = queue
        rest.remove(at: from)
        let gapAt = min(max(drag.gapIndex, 0), rest.count)
        var slots = rest.map { QueueSlot(id: $0.id, kind: .item($0)) }
        slots.insert(QueueSlot(id: QueueDragController.gapID, kind: .gap), at: gapAt)
        return slots
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

    private func primaryAction() {
        if model.session.phase == .idle {
            model.start()
        } else if model.session.isRunning {
            model.pause()
        } else {
            model.resume()
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

private struct QueueLine: View {
    var item: QueueItem
    var isCurrent: Bool
    var finish: Date?
    var model: AppModel
    var gripVisible: Bool
    var floating = false

    @FocusState private var descriptionFocused: Bool

    private var taskName: String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var pinned: Bool {
        model.session.phase == .work && item.id == model.session.activeItemID
    }

    var body: some View {
        HStack(spacing: 10) {
            IntensitySwitch(
                intensity: item.intensity,
                locked: model.session.phase != .idle && item.id == model.session.activeItemID
            ) {
                model.updateIntensity(id: item.id, intensity: item.intensity.next)
            }

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

            Text(finishText)
                .font(.system(size: 13, design: .monospaced).monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(width: 52, alignment: .trailing)
                .help(finishHelp)
                .accessibilityLabel(finishHelp)
                .contentTransition(.opacity)
                .animation(QueueMotion.slide(model.reduceMotion), value: finishText)

            CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min") {
                guard item.count < Session.maxPomodoros else { return }
                model.setCount(id: item.id, count: item.count + 1)
            } onDecrement: {
                guard item.count > 1 else { return }
                model.setCount(id: item.id, count: item.count - 1)
            }
            .tourTarget(item.id == TourSample.outline ? .taskCount : nil)
            rowMenu
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(isCurrent ? Color.white.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
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
        Menu {
            Button("Move up") { model.moveUp(id: item.id) }
                .disabled(!model.session.canMoveUp(id: item.id))
            Button("Move down") { model.moveDown(id: item.id) }
                .disabled(!model.session.canMoveDown(id: item.id))

            Divider()

            Button("Delete", role: .destructive) {
                model.remove(id: item.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 22)
                .modifier(FullHit(cornerRadius: Metrics.corner, hover: Palette.hover))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reorder or delete")
    }

    private var finishText: String {
        guard let finish else { return "—" }
        return finish.formatted(date: .omitted, time: .shortened)
    }

    private var finishHelp: String {
        guard let finish else { return "No finish time yet" }
        let clock = finish.formatted(date: .omitted, time: .shortened)
        return "Work ends at \(clock), when the break starts"
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { model.descriptionDraft(for: item) },
            set: { model.setDescriptionDraft(id: item.id, text: $0) }
        )
    }
}

private struct DoneLine: View {
    var item: QueueItem
    var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            IntensityMark(intensity: item.intensity)
                .opacity(0.7)

            Text(item.description.isEmpty ? "Untitled" : item.description)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 8)

            WorkedTimeLabel(seconds: item.workedSeconds)

            CountBadge(count: item.count, detail: "\(item.count) finished × \(item.intensity.mode.workMinutes) min")

            Button {
                model.requeue(id: item.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 22)
                    .modifier(FullHit(cornerRadius: Metrics.corner, hover: Palette.hover))
            }
            .buttonStyle(.plain)
            .help("Copy to the end of the queue")
            .accessibilityLabel("Copy to the end of the queue")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }
}

private enum WindowMetrics {
    static let defaultSize = NSSize(width: 550, height: 600)
    static let minSize = NSSize(width: 400, height: 450)
    static let sizeKey = "SlimPomo.windowSize"
    static let minConstraintID = "SlimPomo.minSize"
}

enum Metrics {
    /// Wide enough for RESUME and FINISH at the card button's tracking.
    static let actionWidth: CGFloat = 132
    static let actionHeight: CGFloat = 34
    /// Fixed so 25′, 50′, and 75′ occupy the same chip, including the ratio bar.
    static let intensityWidth: CGFloat = 64
    static let intensityHeight: CGFloat = 34
    static let corner: CGFloat = 4
}

struct IntensityMark: View {
    var intensity: Intensity
    var helpText: String?
    var showsMenuChevron = false

    init(intensity: Intensity, helpText: String? = nil, showsMenuChevron: Bool = false) {
        self.intensity = intensity
        self.helpText = helpText
        self.showsMenuChevron = showsMenuChevron
    }

    private static let ink = Color(red: 0.16, green: 0.13, blue: 0.12)

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(intensity.workMark)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                if showsMenuChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Self.ink.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            SessionRatioBar(intensity: intensity)
        }
        .foregroundStyle(Self.ink)
        .frame(minWidth: Metrics.intensityWidth, maxWidth: Metrics.intensityWidth)
        .frame(height: Metrics.intensityHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .fill(intensity.chipColor)
        )
        .help(helpText ?? intensity.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText ?? intensity.summary)
    }
}

private struct SessionRatioBar: View {
    var intensity: Intensity

    var body: some View {
        GeometryReader { geo in
            let full = max(0, geo.size.width - 8)
            let length = full * intensity.sessionScale / Intensity.intense.sessionScale
            let work = length * intensity.workShare
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: work)
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: max(0, length - work))
            }
            .frame(width: full, height: 3, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct IntensitySwitch: View {
    var intensity: Intensity
    var locked: Bool = false
    var action: () -> Void

    private static let lockedHelp = "Intensity can't be changed while the timer is running"

    var body: some View {
        Button(action: action) {
            IntensityMark(intensity: intensity, helpText: locked ? Self.lockedHelp : nil)
                .opacity(locked ? 0.45 : 1)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                .overlay {
                    if locked {
                        DeniedCursor()
                    } else {
                        HoverPlate(cornerRadius: Metrics.corner, color: NSColor(white: 0, alpha: 0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(locked ? Self.lockedHelp : intensity.summary)
        .accessibilityHint(locked ? "" : "Cycles to \(intensity.next.workMark)")
    }
}

private struct ModeMenu: View {
    @Bindable var model: AppModel
    var describesHint: Bool
    @FocusState private var focused: Bool

    private var hot: Bool { model.depthControlHot }
    private static let ink = Color(red: 0.16, green: 0.13, blue: 0.12)

    var body: some View {
        Button {
            model.showDepthPicker()
        } label: {
            IntensityMark(intensity: model.draftIntensity, showsMenuChevron: true)
                .accessibilityHidden(true)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .fill(Color.white.opacity(hot ? 0.2 : 0))
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .strokeBorder(Self.ink.opacity(hot ? 0.4 : 0), lineWidth: 1)
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: Metrics.corner + 1, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .overlay { PointingCursor() }
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, value in
            model.depthChipFocused = value
        }
        .onHover { model.depthChipHover = $0 }
        .animation(.easeOut(duration: 0.12), value: hot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session length: \(model.draftIntensity.mode.workMinutes) minutes")
        .accessibilityHint(describesHint ? DepthHint.sentence : "Shows every mode")
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
        .padding(.leading, 8 + Metrics.intensityWidth / 2 - Self.arrowWidth / 2)
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
                Button {
                    choose(mode)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(mode.chipColor)
                            .frame(width: 8, height: 16)
                        Text(mode.label)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .frame(width: 72, alignment: .leading)
                        Text("\(mode.mode.workMinutes) min + \(mode.mode.breakMinutes) break")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(model.modeHighlight == mode ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .focusEffectDisabled()
                .accessibilityLabel(mode.summary)
            }
        }
        .padding(6)
        .frame(width: 268)
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

struct WorkedTimeLabel: View {
    var seconds: Int

    var body: some View {
        Text(TimeFormat.span(TimeInterval(seconds)))
            .font(.system(size: 13, design: .monospaced).monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .frame(width: 68, alignment: .trailing)
            .layoutPriority(1)
            .accessibilityLabel("\(TimeFormat.span(TimeInterval(seconds))) worked")
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

    var body: some View {
        Text("\(max(0, count))")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background {
                if onIncrement != nil || onDecrement != nil {
                    Circle().fill(Color.white.opacity(0.001))
                }
            }
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1).allowsHitTesting(false))
            .overlay {
                if onIncrement != nil || onDecrement != nil {
                    MouseClick(onLeft: { onIncrement?() }, onRight: { onDecrement?() })
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) pomodoros")
            .accessibilityAddTraits(onIncrement == nil ? [] : .isButton)
            .accessibilityAction(named: "Add pomodoro") { onIncrement?() }
            .accessibilityAction(named: "Remove pomodoro") { onDecrement?() }
            .help(onIncrement == nil ? detail : "\(detail). Click to add a pomodoro, right-click to remove one.")
    }
}

private struct MouseClick: NSViewRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onLeft = onLeft
        view.onRight = onRight
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onLeft = onLeft
        nsView.onRight = onRight
    }

    final class ClickView: NSView {
        var onLeft: (() -> Void)?
        var onRight: (() -> Void)?
        private var hovering = false
        private var pushedCursor = false

        override var isOpaque: Bool { false }

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
            if AppRuntime.model.isTouring {
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

        override func draw(_ dirtyRect: NSRect) {
            guard hovering else { return }
            NSColor(white: 1, alpha: 0.16).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
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

        private func clearHover() {
            hovering = false
            needsDisplay = true
            guard pushedCursor else { return }
            NSCursor.pop()
            pushedCursor = false
        }

        override func mouseDown(with event: NSEvent) {
            onLeft?()
        }

        override func rightMouseDown(with event: NSEvent) {
            onRight?()
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
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
            addCursorRect(bounds, cursor: .operationNotAllowed)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseDown(with event: NSEvent) {}
    }
}

private struct HoverPlate: NSViewRepresentable {
    var cornerRadius: CGFloat
    var color: NSColor

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.cornerRadius = cornerRadius
        view.color = color
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.color = color
        nsView.needsDisplay = true
    }
}

private final class HoverTrackingView: NSView {
    var cornerRadius: CGFloat = 4
    var color: NSColor = .white.withAlphaComponent(0.14)
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
        if AppRuntime.model.isTouring {
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
        Color(red: mode.red, green: mode.green, blue: mode.blue)
    }
}
