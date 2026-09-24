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

private enum Palette {
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

    var body: some View {
        VStack(spacing: 14) {
            timerCard
                .padding(.horizontal, 14)
                .padding(.top, 6)

            todoHeader
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    queueBlock
                    if !model.session.done.isEmpty {
                        doneBlock
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            model.refresh()
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

            if let sessionSubtitle {
                Text(sessionSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(cardInk.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
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
    }

    private var todoHeader: some View {
        HStack(spacing: 12) {
            hairline
            Text(todoTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
                .help("Pomodoros still in the queue, and the work time they add up to")
            hairline
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
                .padding(.bottom, 14)

            if model.session.queue.isEmpty {
                Text("Pick how deep you want to go — longer sessions get longer breaks.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.session.queue.enumerated()), id: \.element.id) { index, item in
                        QueueLine(
                            item: item,
                            isFirst: index == 0,
                            isLast: index == model.session.queue.count - 1,
                            isCurrent: item.id == model.session.activeItemID && model.session.phase != .idle,
                            finish: model.session.finishDates(at: model.now)[item.id],
                            model: model
                        )
                    }
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            ModeMenu(model: model)
            TextField("Press Return to add a task", text: $model.draftDescription)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .stroke(Palette.field, lineWidth: 1)
                )
                .onSubmit { model.addDraftItem() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var doneBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                hairline
                Text("DONE · \(model.session.done.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize()
                hairline
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
                ForEach(model.session.done) { item in
                    DoneLine(item: item, model: model)
                }
            }
        }
    }

    private var todoTitle: String {
        let noun = todoCount == 1 ? "pomodoro" : "pomodoros"
        return "TODO · \(todoCount) \(noun) · \(TimeFormat.span(todoWork)) work"
    }

    private var todoCount: Int {
        model.session.queue.reduce(0) { $0 + max(0, $1.count) }
    }

    private var todoWork: TimeInterval {
        model.session.queue.reduce(0) { total, item in
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

    private var clockSeconds: TimeInterval {
        if model.session.phase == .idle {
            return model.session.queue.first { $0.count > 0 }?.intensity.workDuration ?? 0
        }
        return model.session.displayedRemaining(at: model.now)
    }

    private var onBreak: Bool {
        model.session.phase == .breakTime
    }

    private var cardInk: Color {
        onBreak ? Palette.breakInk : .white
    }

    private var taskLine: String {
        if onBreak {
            let message = model.breakMessage ?? BreakMessages.five[0]
            return "Break · \(message)"
        }
        if model.session.phase != .idle {
            if let active = model.session.activeItem, !active.description.isEmpty {
                return active.description
            }
            if !model.session.activeDescription.isEmpty {
                return model.session.activeDescription
            }
            return "Untitled"
        }
        if let next = model.session.queue.first(where: { $0.count > 0 }) {
            return next.description.isEmpty ? "Untitled" : next.description
        }
        return "Add a task to begin"
    }

    private var sessionSubtitle: String? {
        if onBreak {
            if let name = nextWorkName {
                return "Next: back to \(name)"
            }
            return "Next: nothing queued"
        }
        guard let item = subtitleItem else { return nil }
        let work = model.session.phase == .work
            ? Int(model.session.phaseDuration / 60)
            : item.intensity.mode.workMinutes
        let rest = model.session.phase == .work
            ? Int((model.session.lockedBreakDuration ?? item.intensity.breakDuration) / 60)
            : item.intensity.mode.breakMinutes
        return "\(item.intensity.label) · \(work) min work, then \(rest) min break"
    }

    private var subtitleItem: QueueItem? {
        if model.session.phase == .work {
            return model.session.activeItem
        }
        if model.session.phase == .idle {
            return model.session.queue.first { $0.count > 0 }
        }
        return nil
    }

    private var nextWorkName: String? {
        if let active = model.session.activeItem, active.count > 0 {
            return named(active)
        }
        if let next = model.session.queue.first(where: { $0.count > 0 }) {
            return named(next)
        }
        return nil
    }

    private func named(_ item: QueueItem) -> String {
        item.description.isEmpty ? "Untitled" : item.description
    }

    private var primaryTitle: String {
        if model.session.phase == .idle {
            return "START"
        }
        return model.session.isRunning ? "PAUSE" : "RESUME"
    }

    private var primaryHelp: String {
        switch primaryTitle {
        case "PAUSE": "Pause"
        case "RESUME": "Resume"
        default: "Start the next pomodoro"
        }
    }

    private var primaryDisabled: Bool {
        model.session.phase == .idle && !model.session.hasWorkQueued
    }

    private var secondaryTitle: String {
        if model.session.phase == .breakTime {
            return "SKIP"
        }
        if model.session.phase == .work, !model.session.isRunning {
            return "FINISH"
        }
        return "RESET"
    }

    private var secondaryEnabled: Bool {
        model.session.phase == .work || model.session.phase == .breakTime
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

private struct QueueLine: View {
    var item: QueueItem
    var isFirst: Bool
    var isLast: Bool
    var isCurrent: Bool
    var finish: Date?
    var model: AppModel

    @FocusState private var descriptionFocused: Bool

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

            Text(finishText)
                .font(.system(size: 13, design: .monospaced).monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(width: 52, alignment: .trailing)
                .help(finishHelp)
                .accessibilityLabel(finishHelp)

            CountBadge(count: item.count, detail: "\(item.count) × \(item.intensity.mode.workMinutes) min") {
                guard item.count < Session.maxPomodoros else { return }
                model.setCount(id: item.id, count: item.count + 1)
            } onDecrement: {
                guard item.count > 1 else { return }
                model.setCount(id: item.id, count: item.count - 1)
            }
            rowMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isCurrent ? Color.white.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var rowMenu: some View {
        Menu {
            Button("Move up") { model.moveUp(id: item.id) }
                .disabled(isFirst)
            Button("Move down") { model.moveDown(id: item.id) }
                .disabled(isLast)

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

            Spacer(minLength: 8)

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
        .padding(.horizontal, 8)
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

private enum Metrics {
    /// Wide enough for RESUME and FINISH at the card button's tracking.
    static let actionWidth: CGFloat = 132
    static let actionHeight: CGFloat = 34
    /// Fixed so 25′, 50′, and 75′ occupy the same chip, including the ratio bar.
    static let intensityWidth: CGFloat = 64
    static let intensityHeight: CGFloat = 34
    static let corner: CGFloat = 4
}

private struct IntensityMark: View {
    var intensity: Intensity
    var helpText: String?

    init(intensity: Intensity, helpText: String? = nil) {
        self.intensity = intensity
        self.helpText = helpText
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(intensity.workMark)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
            SessionRatioBar(intensity: intensity)
        }
        .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.12))
        .frame(width: Metrics.intensityWidth, height: Metrics.intensityHeight)
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

    var body: some View {
        Button {
            model.modeHighlight = model.draftIntensity
            model.modePickerOpen = true
        } label: {
            IntensityMark(intensity: model.draftIntensity)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                .overlay {
                    HoverPlate(cornerRadius: Metrics.corner, color: NSColor(white: 0, alpha: 0.1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.draftIntensity.summary)
        .accessibilityHint("Shows every mode")
        .popover(isPresented: $model.modePickerOpen, arrowEdge: .bottom) {
            ModeChoices(model: model)
        }
    }
}

private struct ModeChoices: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Intensity.allCases, id: \.self) { mode in
                Button {
                    choose(mode)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(mode.chipColor)
                            .frame(width: 8, height: 16)
                        Text(mode.label.lowercased())
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 64, alignment: .leading)
                        Text("\(mode.mode.workMinutes) min + \(mode.mode.breakMinutes) break")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(model.modeHighlight == mode ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
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
        model.setDraftIntensity(mode)
        model.modePickerOpen = false
    }
}

private struct CountBadge: View {
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

private struct FullHit: ViewModifier {
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

private struct DeniedCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> DeniedCursorView {
        DeniedCursorView()
    }

    func updateNSView(_ nsView: DeniedCursorView, context: Context) {}

    final class DeniedCursorView: NSView {
        override var isOpaque: Bool { false }

        override func resetCursorRects() {
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
