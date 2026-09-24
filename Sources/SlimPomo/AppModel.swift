import AppKit
import Foundation
import Observation
import SlimPomoCore

@MainActor
@Observable
final class AppModel {
    var session: Session
    var now: Date
    var draftDescription = ""
    var draftIntensity = Intensity.regular
    var descriptionDrafts: [UUID: String] = [:]
    var hoveredQueueID: UUID?
    var modePickerOpen = false
    var modeHighlight = Intensity.regular
    var depthHintDismissed = false
    var depthChipHover = false
    var depthHintHover = false
    var depthChipFocused = false
    var depthHintFocused = false
    var breakMessage: String?
    /// Bumped when a click lands outside a text field, so open editors resign.
    var textFocusNonce = 0
    @ObservationIgnored private var lastBreakMessage: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let bell: Bell
    @ObservationIgnored private let windows = MainWindowController()
    @ObservationIgnored private let historyWindows = HistoryWindowController()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?
    @ObservationIgnored private var dayObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var focusMonitor: Any?
    @ObservationIgnored private var historyCache: [HistoryDay] = []
    @ObservationIgnored private var historyCacheCount = -1
    @ObservationIgnored private var historyCacheZone = ""

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = Store()
        self.store = store
        bell = Bell()
        let moment = Date()
        now = moment
        var loaded = store.load() ?? Session()
        #if SLIMPOMO_DEV
        DevLaunch.apply(to: &loaded, now: moment)
        #endif
        loaded.normalize()
        loaded.restoreAsPaused()
        loaded.migrateHistoryIfNeeded(now: moment)
        loaded.refreshDoneDay(now: moment)
        session = loaded
        if let raw = UserDefaults.standard.string(forKey: Self.draftIntensityKey),
           let saved = Intensity(rawValue: raw) {
            draftIntensity = saved
        }
        modeHighlight = draftIntensity
        depthHintDismissed = UserDefaults.standard.bool(forKey: Self.depthHintKey)
        syncBreakMessage()
        store.save(loaded)
        observeDayChanges()
        scheduleMidnight()
        installKeyMonitor()
        installFocusMonitor()
    }

    /// Ends editing when a click misses every text field. Buttons still receive the click.
    func releaseTextFocus() {
        textFocusNonce &+= 1
    }

    func setDraftIntensity(_ intensity: Intensity) {
        draftIntensity = intensity
        modeHighlight = intensity
        UserDefaults.standard.set(intensity.rawValue, forKey: Self.draftIntensityKey)
    }

    func showDepthPicker() {
        modeHighlight = draftIntensity
        modePickerOpen = true
    }

    func noteDepthChanged() {
        guard !depthHintDismissed else { return }
        depthHintDismissed = true
        UserDefaults.standard.set(true, forKey: Self.depthHintKey)
    }

    var depthControlHot: Bool {
        depthChipHover || depthHintHover || depthChipFocused || depthHintFocused
    }

    func refresh() {
        tick()
        ensureTicker()
    }

    func start() {
        stopAlarm()
        apply { $0.start(now: now) }
    }

    func pause() {
        stopAlarm()
        apply { $0.pause(now: now) }
    }

    func resume() {
        stopAlarm()
        apply { $0.resume(now: now) }
    }

    func markDone() {
        stopAlarm()
        apply { $0.markDone(now: now) }
    }

    func stop() {
        stopAlarm()
        apply { $0.stop() }
    }

    func skipBreak() {
        stopAlarm()
        apply { $0.skipBreak(now: now) }
    }

    func stopAlarm() {
        bell.stop()
    }

    func descriptionDraft(for item: QueueItem) -> String {
        descriptionDrafts[item.id] ?? item.description
    }

    func setDescriptionDraft(id: UUID, text: String) {
        descriptionDrafts[id] = text
    }

    func commitDescriptionDraft(id: UUID) {
        guard let current = descriptionDrafts.removeValue(forKey: id) else { return }
        updateDescription(id: id, description: current.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func addDraftItem() {
        addItem(description: draftDescription, intensity: draftIntensity, count: 1)
        if !draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftDescription = ""
        }
    }

    func addItem(description: String, intensity: Intensity, count: Int) {
        apply { session in
            session.addItem(description: description, intensity: intensity, count: count)
            return .none
        }
    }

    func updateDescription(id: UUID, description: String) {
        apply { session in
            session.updateDescription(id: id, description: description)
            return .none
        }
    }

    func updateIntensity(id: UUID, intensity: Intensity) {
        apply { session in
            session.updateIntensity(id: id, intensity: intensity)
            return .none
        }
    }

    func setCount(id: UUID, count: Int) {
        apply { session in
            session.setCount(id: id, count: count)
            return .none
        }
    }

    func remove(id: UUID) {
        if hoveredQueueID == id {
            hoveredQueueID = nil
        }
        descriptionDrafts[id] = nil
        apply { $0.remove(id: id, now: now) }
    }

    func setQueueHover(_ id: UUID, hovering: Bool) {
        if hovering {
            hoveredQueueID = id
        } else if hoveredQueueID == id {
            hoveredQueueID = nil
        }
    }

    func moveUp(id: UUID) {
        apply { session in
            session.moveUp(id: id)
            return .none
        }
    }

    func moveDown(id: UUID) {
        apply { session in
            session.moveDown(id: id)
            return .none
        }
    }

    func requeue(id: UUID) {
        apply { session in
            session.requeue(id: id)
            return .none
        }
    }

    func requeueHistory(queueItemId: UUID, day: Date) {
        apply { session in
            session.requeueHistory(queueItemId: queueItemId, day: day)
            return .none
        }
    }

    func clearDone() {
        apply { session in
            session.clearDone()
            return .none
        }
    }

    func performMenuAction() {
        switch session.phase {
        case .idle:
            start()
        case .work, .breakTime:
            if !session.isRunning {
                resume()
            }
        }
    }

    func showWindow() {
        stopAlarm()
        windows.show(model: self)
    }

    func showHistory() {
        historyWindows.show(model: self)
    }

    var historyDays: [HistoryDay] {
        let zone = Calendar.current.timeZone.identifier
        if historyCacheCount != session.history.count || historyCacheZone != zone {
            historyCache = session.groupedHistory()
            historyCacheCount = session.history.count
            historyCacheZone = zone
        }
        return historyCache
    }

    func quit() {
        tickTask?.cancel()
        tickTask = nil
        now = Date()
        var paused = session.snapshot(at: now)
        paused.restoreAsPaused()
        session = paused
        store.save(session)
        NSApplication.shared.terminate(nil)
    }

    private func apply(_ change: (inout Session) -> SessionEffect) {
        now = Date()
        session.refreshDoneDay(now: now)
        let effect = change(&session)
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        ensureTicker()
    }

    private func tick() {
        now = Date()
        session.refreshDoneDay(now: now)
        let effect = session.reconcile(now: now)
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
    }

    private func refreshDoneDay() {
        now = Date()
        let previousDay = session.doneDay
        let previousDone = session.done
        session.refreshDoneDay(now: now)
        guard session.doneDay != previousDay || session.done != previousDone else { return }
        store.save(session.snapshot(at: now))
    }

    private func observeDayChanges() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
        ]
        for name in names {
            dayObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDoneDay()
                    self?.scheduleMidnight()
                }
            })
        }
        dayObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDoneDay()
                    self?.scheduleMidnight()
                }
            }
        )
    }

    private func scheduleMidnight() {
        midnightTask?.cancel()
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        let delay = max(1, next.timeIntervalSinceNow)
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.refreshDoneDay()
            self.scheduleMidnight()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard NSApp.keyWindow != nil else { return false }
                switch key {
                case "y":
                    AppRuntime.model.showHistory()
                    return true
                case "w":
                    NSApp.keyWindow?.performClose(nil)
                    return true
                default:
                    return false
                }
            }
            return handled ? nil : event
        }
    }

    private func installFocusMonitor() {
        focusMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let point = event.locationInWindow
            let windowNumber = event.windowNumber
            let shouldRelease = MainActor.assumeIsolated { () -> Bool in
                guard NSApp.windows.contains(where: { $0.firstResponder is NSTextView }) else { return false }
                guard let window = NSApp.window(withWindowNumber: windowNumber) else { return false }
                guard let hit = window.contentView?.hitTest(point) else { return true }
                return !viewContainsTextInput(hit)
            }
            guard shouldRelease else { return event }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppRuntime.model.releaseTextFocus()
                }
            }
            return event
        }
    }

    private func syncBreakMessage() {
        if session.phase == .breakTime {
            if breakMessage == nil {
                let next = BreakMessages.pick(
                    breakDuration: session.phaseDuration,
                    avoiding: lastBreakMessage
                )
                breakMessage = next
                lastBreakMessage = next
            }
        } else {
            breakMessage = nil
        }
    }

    private static let draftIntensityKey = "SlimPomo.draftIntensity"
    private static let depthHintKey = "SlimPomo.depthHintDismissed"

    private func ensureTicker() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            var idleSteps = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                if self.session.isRunning {
                    idleSteps = 0
                    self.tick()
                } else if !self.session.queue.isEmpty {
                    // Finish clocks are "if the queue started now", so they move
                    // with the wall clock while nothing is running.
                    idleSteps += 1
                    if idleSteps >= 10 {
                        idleSteps = 0
                        self.now = Date()
                    }
                }
            }
        }
    }
}

@MainActor
private func viewContainsTextInput(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let view = current {
        if view is NSTextView || view is NSTextField { return true }
        current = view.superview
    }
    return false
}
