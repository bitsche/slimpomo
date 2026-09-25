import AppKit
import Foundation
import Observation
import SwiftUI
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
    var reduceMotion = false
    var queueDrag: QueueDragController?
    @ObservationIgnored var queueListAnchor: QueueListAnchorView?
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
    @ObservationIgnored private var queueDragMonitor: Any?
    @ObservationIgnored private var queueScrollTask: Task<Void, Never>?
    @ObservationIgnored private var queueSettleTask: Task<Void, Never>?
    @ObservationIgnored private weak var queueScrollView: NSScrollView?
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
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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

    func commitAllDescriptionDrafts() {
        for id in Array(descriptionDrafts.keys) {
            commitDescriptionDraft(id: id)
        }
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
        guard session.canMoveUp(id: id) else { return }
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.moveUp(id: id)
                return .none
            }
        }
    }

    func moveDown(id: UUID) {
        guard session.canMoveDown(id: id) else { return }
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.moveDown(id: id)
                return .none
            }
        }
    }

    func attachQueueList(_ anchor: QueueListAnchorView) {
        queueListAnchor = anchor
        queueScrollView = anchor.enclosingScrollView
    }

    func beginQueueDrag(id: UUID) {
        guard queueDrag == nil, session.canReorder(id: id) else { return }
        guard let index = session.queue.firstIndex(where: { $0.id == id }),
              let anchor = queueListAnchor,
              let pointer = pointerInQueueList()
        else { return }
        let rowHeight = queueRowHeight(anchor: anchor)
        guard rowHeight > 1 else { return }
        commitAllDescriptionDrafts()
        releaseTextFocus()
        let rowTop = CGFloat(index) * rowHeight
        let origin = viewportPoint(forListPoint: CGPoint(x: 0, y: rowTop))
        let drag = QueueDragController(
            itemID: id,
            originIndex: index,
            gapIndex: index,
            rowHeight: rowHeight,
            rowWidth: anchor.bounds.width,
            visualX: origin.x,
            visualY: origin.y,
            grabOffset: pointer.y - rowTop
        )
        queueDrag = drag
        let snapped = session.nearestReorderDestination(for: id, proposed: index) ?? index
        if snapped != index {
            withAnimation(QueueMotion.slide(reduceMotion)) {
                drag.gapIndex = snapped
            }
        }
        if !reduceMotion {
            withAnimation(QueueMotion.lift(reduceMotion)) {
                drag.lifted = true
            }
        }
        NSCursor.closedHand.set()
        installQueueDragMonitor()
    }

    func trackQueueDrag() {
        guard let drag = queueDrag, drag.phase == .dragging else { return }
        guard let pointer = pointerInQueueList(), let anchor = queueListAnchor else { return }
        let rowHeight = queueRowHeight(anchor: anchor)
        drag.rowHeight = rowHeight
        drag.rowWidth = anchor.bounds.width
        if let range = session.reorderDestinations(for: drag.itemID) {
            let next = QueueDrop.gapIndex(
                pointerY: pointer.y,
                rowHeight: rowHeight,
                gap: drag.gapIndex,
                lower: range.lowerBound,
                upper: range.upperBound
            )
            if next != drag.gapIndex {
                withAnimation(QueueMotion.slide(reduceMotion)) {
                    drag.gapIndex = next
                }
            }
        }
        let rowTop = pointer.y - drag.grabOffset
        let origin = viewportPoint(forListPoint: CGPoint(x: 0, y: rowTop))
        drag.visualX = origin.x
        drag.visualY = origin.y
        NSCursor.closedHand.set()
    }

    func endQueueDrag() {
        guard let drag = queueDrag, drag.phase == .dragging else { return }
        stopQueueDragTracking()
        let inside = pointerIsInsideQueue()
        let moved = drag.gapIndex != drag.originIndex
        settleQueueDrag(drop: inside && moved)
    }

    @discardableResult
    func cancelQueueDrag() -> Bool {
        guard let drag = queueDrag else { return false }
        if drag.phase == .settling, !drag.drop { return true }
        queueSettleTask?.cancel()
        stopQueueDragTracking()
        settleQueueDrag(drop: false)
        return true
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
        reconcileQueueDrag()
    }

    private func tick() {
        now = Date()
        session.refreshDoneDay(now: now)
        let effect = session.reconcile(now: now)
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        reconcileQueueDrag()
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
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                }
            }
        )
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
            if event.keyCode == 53 {
                let handled = MainActor.assumeIsolated {
                    AppRuntime.model.cancelQueueDrag()
                }
                if handled { return nil }
            }
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

    private func reconcileQueueDrag() {
        guard let drag = queueDrag else { return }
        guard session.queue.contains(where: { $0.id == drag.itemID }) else {
            clearQueueDrag()
            return
        }
        if session.phase == .work, session.activeItemID == drag.itemID {
            if drag.phase == .settling, !drag.drop { return }
            queueSettleTask?.cancel()
            stopQueueDragTracking()
            settleQueueDrag(drop: false)
            return
        }
        guard let range = session.reorderDestinations(for: drag.itemID) else {
            clearQueueDrag()
            return
        }
        if drag.phase == .dragging {
            trackQueueDrag()
            if !range.contains(drag.gapIndex) {
                let nearest = min(max(drag.gapIndex, range.lowerBound), range.upperBound)
                withAnimation(QueueMotion.slide(reduceMotion)) {
                    drag.gapIndex = nearest
                }
            }
            return
        }
        if drag.drop, !range.contains(drag.gapIndex) {
            queueSettleTask?.cancel()
            settleQueueDrag(drop: false)
        }
    }

    private func settleQueueDrag(drop: Bool) {
        guard let drag = queueDrag else { return }
        let index = drop ? drag.gapIndex : drag.originIndex
        let target = viewportPoint(forListPoint: CGPoint(x: 0, y: CGFloat(index) * drag.rowHeight))
        if !drop, drag.gapIndex != drag.originIndex {
            withAnimation(QueueMotion.slide(reduceMotion)) {
                drag.gapIndex = drag.originIndex
            }
        }
        withAnimation(QueueMotion.settle(reduceMotion)) {
            drag.phase = .settling
            drag.drop = drop
            drag.lifted = false
            drag.visualX = target.x
            drag.visualY = target.y
        }
        NSCursor.arrow.set()
        if let anchor = queueListAnchor {
            anchor.window?.invalidateCursorRects(for: anchor)
        }
        let delay = reduceMotion ? 140 : 300
        queueSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.finishSettledDrag()
        }
    }

    private func finishSettledDrag() {
        guard let drag = queueDrag, drag.phase == .settling else { return }
        let drop = drag.drop
        let id = drag.itemID
        let destination = drag.gapIndex
        queueDrag = nil
        guard drop else { return }
        apply { session in
            session.reorder(id: id, to: destination)
            return .none
        }
    }

    private func clearQueueDrag() {
        queueSettleTask?.cancel()
        queueSettleTask = nil
        stopQueueDragTracking()
        queueDrag = nil
        NSCursor.arrow.set()
    }

    private func stopQueueDragTracking() {
        if let queueDragMonitor {
            NSEvent.removeMonitor(queueDragMonitor)
            self.queueDragMonitor = nil
        }
        queueScrollTask?.cancel()
        queueScrollTask = nil
    }

    private func installQueueDragMonitor() {
        stopQueueDragTracking()
        queueDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            let isUp = event.type == .leftMouseUp
            MainActor.assumeIsolated {
                if isUp {
                    AppRuntime.model.endQueueDrag()
                } else {
                    AppRuntime.model.trackQueueDrag()
                }
            }
            return event
        }
        startQueueAutoScroll()
    }

    private func startQueueAutoScroll() {
        queueScrollTask?.cancel()
        queueScrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self else { return }
                guard self.queueDrag?.phase == .dragging else { return }
                self.stepQueueAutoScroll()
                self.trackQueueDrag()
            }
        }
    }

    private func stepQueueAutoScroll() {
        guard queueDrag?.phase == .dragging, let drag = queueDrag, let scroll = queueScrollView else { return }
        let clip = scroll.contentView
        let visible = clip.bounds.height
        guard visible > 1 else { return }
        let edge: CGFloat = 52
        let maxStep: CGFloat = 16
        var delta: CGFloat = 0
        if drag.visualY < edge {
            let distance = min(1, max(0, (edge - drag.visualY) / edge))
            delta = -maxStep * distance * distance
        } else if drag.visualY + drag.rowHeight > visible - edge {
            let overlap = drag.visualY + drag.rowHeight - (visible - edge)
            let distance = min(1, max(0, overlap / edge))
            delta = maxStep * distance * distance
        }
        guard abs(delta) > 0.15 else { return }
        var origin = clip.bounds.origin
        let before = origin
        if clip.isFlipped {
            origin.y += delta
        } else {
            origin.y -= delta
        }
        let docHeight = scroll.documentView?.frame.height ?? 0
        let maxOffset = max(0, docHeight - visible)
        origin.y = min(max(origin.y, 0), maxOffset)
        guard origin != before else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    private func queueRowHeight(anchor: QueueListAnchorView) -> CGFloat {
        let count = max(session.queue.count, 1)
        let height = anchor.bounds.height / CGFloat(count)
        return height > 1 ? height : 48
    }

    private func pointerInQueueList() -> CGPoint? {
        guard let anchor = queueListAnchor, let window = anchor.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return anchor.convert(inWindow, from: nil)
    }

    private func pointerIsInsideQueue() -> Bool {
        guard let anchor = queueListAnchor, let window = anchor.window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inAnchor = anchor.convert(inWindow, from: nil)
        return QueueDrop.releaseLandsInQueue(
            pointerX: inAnchor.x,
            pointerY: inAnchor.y,
            listWidth: anchor.bounds.width,
            listHeight: anchor.bounds.height
        )
    }

    private func viewportPoint(forListPoint point: CGPoint) -> CGPoint {
        guard let anchor = queueListAnchor, let clip = queueScrollView?.contentView else {
            return CGPoint(x: 14, y: point.y)
        }
        let converted = clip.convert(point, from: anchor)
        if clip.isFlipped {
            return CGPoint(
                x: converted.x - clip.bounds.origin.x,
                y: converted.y - clip.bounds.origin.y
            )
        }
        return CGPoint(
            x: converted.x - clip.bounds.origin.x,
            y: clip.bounds.maxY - converted.y
        )
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
