import AppKit
import SwiftUI
import SlimPomoCore

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
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
            window.minSize = WindowMetrics.minSize
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.tabbingMode = .disallowed
            let restored = window.setFrameAutosaveName(WindowMetrics.autosaveName)
            if !restored {
                window.setContentSize(WindowMetrics.defaultSize)
                window.center()
            }
            window.contentViewController = NSHostingController(rootView: MainWindow(model: model))
            window.delegate = self
            self.window = window
        }
        // The status-item menu is still tracking. Presenting on the next turn
        // lets that menu close before the window is ordered in front.
        Task { @MainActor in
            guard let window = self.window else { return }
            self.present(window)
        }
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

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
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
            Text("TODO · \(todoCount) / \(TimeFormat.span(todoWork))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
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
                Text("Nothing queued yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            IntensitySwitch(intensity: model.draftIntensity) {
                model.draftIntensity = model.draftIntensity.next
            }
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
            }
            VStack(spacing: 0) {
                ForEach(model.session.done) { item in
                    DoneLine(item: item, model: model)
                }
            }
        }
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
            return model.breakMessage ?? BreakMessages.all[0]
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
        return "STOP"
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
            IntensitySwitch(intensity: item.intensity) {
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
                .accessibilityLabel(finish.map { "Finishes at \($0.formatted(date: .omitted, time: .shortened))" } ?? "No finish time")

            CountBadge(count: item.count) {
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

            CountBadge(count: item.count)

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
            .help("Put back in the queue")
            .accessibilityLabel("Push back")
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
    static let defaultSize = NSSize(width: 700, height: 650)
    static let minSize = NSSize(width: 640, height: 420)
    static let autosaveName = "SlimPomoMainWindow"
}

private enum Metrics {
    /// Wide enough for RESUME and FINISH at the card button's tracking.
    static let actionWidth: CGFloat = 132
    static let actionHeight: CGFloat = 34
    /// Wide enough for "regular" and "intense" without the control resizing.
    static let intensityWidth: CGFloat = 84
    static let intensityHeight: CGFloat = 26
    static let corner: CGFloat = 4
}

private struct IntensityMark: View {
    var intensity: Intensity

    var body: some View {
        Text(intensity.label.lowercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.12))
            .frame(width: Metrics.intensityWidth, height: Metrics.intensityHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .fill(fill)
            )
            .help(intensity.ratioTooltip)
    }

    private var fill: Color {
        switch intensity {
        case .regular:
            Color(red: 0.78, green: 0.84, blue: 0.80)
        case .focus:
            Color(red: 0.93, green: 0.80, blue: 0.58)
        case .intense:
            Color(red: 0.95, green: 0.64, blue: 0.60)
        }
    }
}

private struct IntensitySwitch: View {
    var intensity: Intensity
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            IntensityMark(intensity: intensity)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                .overlay {
                    HoverPlate(cornerRadius: Metrics.corner, color: NSColor(white: 0, alpha: 0.1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intensity.label), \(intensity.ratioTooltip)")
        .accessibilityHint("Cycles to \(intensity.next.label)")
    }
}

private struct CountBadge: View {
    var count: Int
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?

    init(count: Int, onIncrement: (() -> Void)? = nil, onDecrement: (() -> Void)? = nil) {
        self.count = count
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
            .help(onIncrement == nil ? "\(count) pomodoros" : "Click to add a pomodoro. Right-click to remove one.")
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
}
