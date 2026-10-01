import AppKit
import Foundation
import Observation
import SwiftUI
import SlimPomoCore

/// Sections whose header collapses and expands the rows under it.
enum ListSection {
    case later
    case done
}

@MainActor
@Observable
final class AppModel {
    var session: Session
    var now: Date
    var draftDescription = ""
    var draftIntensity = Intensity.regular
    var descriptionDrafts: [UUID: String] = [:]
    /// Add-field editor state. Kept here because this build has no `@State` macro.
    var draftFocused = false
    var draftContentHeight: CGFloat = 0
    /// Done header stats flash: the nonce restarts the 600 ms flash, `doneFlashOn` is the flash itself.
    var doneFlashOn = false
    var doneFlashNonce = 0
    /// Height and first caret of the queue name editor. Only one row edits at a time.
    var editorContent: CGFloat = 0
    var editCaret: Int?
    var hoveredQueueID: UUID?
    var hoveredLaterID: UUID?
    var hoveredDoneID: UUID?
    var hoveredHistoryID: String?
    var doneHeaderHovered = false
    /// The pointer is on the trash button, which paints its own hover instead of the header wash.
    var doneTrashHovered = false
    /// True while keyboard focus is on a control inside Done other than the trash button.
    var doneSectionFocused = false
    /// The full Done list. Not saved, so a relaunch starts with the latest three.
    var doneListExpanded = false
    var suppressDoneAnimation = false
    var modePickerOpen = false
    var modeHighlight = Intensity.regular
    var depthHintDismissed = false
    var laterExpanded = true
    var doneExpanded = true
    /// The queue row whose name is open for editing. Its text lives in `descriptionDrafts` until saved.
    var editingQueueID: UUID?
    var depthChipHover = false
    var depthHintHover = false
    var depthChipFocused = false
    var depthHintFocused = false
    var breakMessage: String?
    /// Bumped when a click lands outside a text field, so open editors resign.
    var textFocusNonce = 0
    var reduceMotion = false
    var queueDrag: QueueDragController?
    /// True for the frame that commits a drag, so the list does not animate a second time.
    var suppressQueueAnimation = false
    /// True while the queue, LATER, or Done has scrolled under the add row.
    var listsScrolled = false
    /// Set when a new queue row should be brought into view. Cleared by the list.
    var scrollQueueItemID: UUID?
    /// Sample queue shown while the tour is up. Never written to the store.
    var tourSample: Session?
    var tour: TourProgress?
    var tourFrames: [TourTarget: CGRect] = [:]
    var tourViewport = CGSize.zero
    var tourCardSize = CGSize.zero
    var tourScrollRequest = 0
    /// LATER starts open during the tour so the sample row is visible. The chevron changes this, and the choice is saved.
    var tourLaterExpanded = true
    /// Done starts open during the tour so the sample row is visible. Same rule as LATER.
    var tourDoneExpanded = true
    @ObservationIgnored private var tourHoldSpotlight = false
    @ObservationIgnored private var tourScrollStep: TourStep?
    @ObservationIgnored private var tourScrollTask: Task<Void, Never>?
    @ObservationIgnored var queueListAnchor: QueueListAnchorView?
    @ObservationIgnored private var lastBreakMessage: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let bell: Bell
    @ObservationIgnored private let windows = MainWindowController()
    @ObservationIgnored private let historyWindows = HistoryWindowController()
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var idleTickSteps = 0
    @ObservationIgnored private var midnightTask: Task<Void, Never>?
    @ObservationIgnored private var dayObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var tourCursorMonitor: Any?
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
        let launchArgs = ProcessInfo.processInfo.arguments
        if launchArgs.contains("-resetTour") || launchArgs.contains("-resetAll") {
            store.clearTourSeen()
        }
        #endif
        loaded.normalize()
        loaded.restoreAsPaused()
        loaded.migrateHistoryIfNeeded(now: moment)
        loaded.migrateWorkedSecondsIfNeeded()
        loaded.refreshDoneDay(now: moment)
        loaded.orderDoneNewestFirst()
        loaded.migrateLaterOrderIfNeeded()
        loaded.returnDueLater(now: moment)
        session = loaded
        if let raw = UserDefaults.standard.string(forKey: Self.draftIntensityKey),
           let saved = Intensity(rawValue: raw) {
            draftIntensity = saved
        }
        modeHighlight = draftIntensity
        depthHintDismissed = UserDefaults.standard.bool(forKey: Self.depthHintKey)
        if UserDefaults.standard.object(forKey: Self.laterExpandedKey) != nil {
            laterExpanded = UserDefaults.standard.bool(forKey: Self.laterExpandedKey)
        }
        if UserDefaults.standard.object(forKey: Self.doneExpandedKey) != nil {
            doneExpanded = UserDefaults.standard.bool(forKey: Self.doneExpandedKey)
        }
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        syncBreakMessage()
        store.save(loaded)
        store.flush()
        observeDayChanges()
        scheduleMidnight()
        installKeyMonitor()
        installFocusMonitor()
        installTourCursorMonitor()
        PointingHand.install()
        if !store.tourSeen {
            beginTour()
        }
    }

    var isTouring: Bool { tour != nil }

    /// What the main window draws. The menu bar and the saved session stay on `session`.
    var windowSession: Session { tourSample ?? session }

    var tourGripItemID: UUID? {
        guard tour?.step == .reorder else { return nil }
        return TourSample.emails
    }

    /// Sample row whose hover-only details the current tour step is pointing at.
    var tourQueueRevealID: UUID? {
        switch tour?.step {
        case .count, .markFinished:
            TourSample.outline
        case .reorder:
            TourSample.emails
        default:
            nil
        }
    }

    var tourLaterRevealID: UUID? {
        tour?.step == .later ? TourSample.notes : nil
    }

    var tourDoneRevealID: UUID? {
        guard tour?.step == .done else { return nil }
        return windowSession.mergedDone().first?.id
    }

    /// Ends editing when a click misses every text field. Buttons still receive the click.
    func releaseTextFocus() {
        textFocusNonce &+= 1
    }

    func setDraftIntensity(_ intensity: Intensity) {
        guard tour == nil else { return }
        draftIntensity = intensity
        modeHighlight = intensity
        UserDefaults.standard.set(intensity.rawValue, forKey: Self.draftIntensityKey)
    }

    func showDepthPicker() {
        guard tour == nil else { return }
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

    func markFinished(id: UUID) {
        if session.phase == .work, session.activeItemID == id {
            markDone()
            return
        }
        apply { $0.markFinished(id: id, now: now) }
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

    func descriptionDraft(id: UUID, fallback: String) -> String {
        descriptionDrafts[id] ?? fallback
    }

    func setDescriptionDraft(id: UUID, text: String) {
        descriptionDrafts[id] = text
    }

    private func savedDescription(of id: UUID) -> String? {
        session.queue.first { $0.id == id }?.description ?? session.later.first { $0.id == id }?.description
    }

    /// Saves the open edit. A name that ends up empty is ignored and the old text stays.
    func commitDescriptionDraft(id: UUID) {
        guard let current = descriptionDrafts.removeValue(forKey: id) else { return }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let saved = savedDescription(of: id), saved != trimmed else { return }
        if session.queue.contains(where: { $0.id == id }) {
            updateDescription(id: id, description: trimmed)
        } else {
            updateLaterDescription(id: id, description: trimmed)
        }
    }

    func commitAllDescriptionDrafts() {
        for id in Array(descriptionDrafts.keys) {
            commitDescriptionDraft(id: id)
        }
        editingQueueID = nil
    }

    /// Opens a queue or LATER name for editing with its raw text. Another open edit is saved first.
    func beginNameEdit(id: UUID) {
        guard tour == nil, queueDrag == nil, editingQueueID != id,
              let text = savedDescription(of: id)
        else { return }
        if let open = editingQueueID {
            commitDescriptionDraft(id: open)
        }
        descriptionDrafts[id] = text
        editingQueueID = id
    }

    /// Closes the open edit. Cancel drops the typed text; the old name stays.
    func endNameEdit(id: UUID, save: Bool) {
        guard editingQueueID == id else { return }
        if save {
            commitDescriptionDraft(id: id)
        } else {
            descriptionDrafts[id] = nil
        }
        editingQueueID = nil
    }

    func addDraftItem() {
        guard tour == nil else { return }
        let countBefore = session.queue.count
        addItem(description: draftDescription, intensity: draftIntensity, count: 1)
        if session.queue.count > countBefore {
            scrollQueueItemID = session.queue.last?.id
        }
        if !draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftDescription = ""
        }
    }

    func noteListScroll(offset: CGFloat) {
        let scrolled = offset < -0.5
        guard listsScrolled != scrolled else { return }
        listsScrolled = scrolled
    }

    /// True when the row is missing or any part of it sits outside the list scroller.
    func queueRowIsOffscreen(_ id: UUID) -> Bool {
        guard let anchor = queueListAnchor,
              let clip = anchor.enclosingScrollView?.contentView,
              let index = session.queue.firstIndex(where: { $0.id == id })
        else { return true }
        let rowHeight = DragMetrics.stride
        let first = DragMetrics.queueTopPadding
        let top = clip.convert(CGPoint(x: 0, y: first + CGFloat(index) * rowHeight), from: anchor)
        let bottom = clip.convert(CGPoint(x: 0, y: first + CGFloat(index + 1) * rowHeight), from: anchor)
        let minY = min(top.y, bottom.y)
        let maxY = max(top.y, bottom.y)
        return minY < clip.bounds.minY + 1 || maxY > clip.bounds.maxY - 1
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

    func updateLaterDescription(id: UUID, description: String) {
        apply { session in
            session.updateLaterDescription(id: id, description: description)
            return .none
        }
    }

    func updateLaterIntensity(id: UUID, intensity: Intensity) {
        apply { session in
            session.updateLaterIntensity(id: id, intensity: intensity)
            return .none
        }
    }

    func setLaterCount(id: UUID, count: Int) {
        apply { session in
            session.setLaterCount(id: id, count: count)
            return .none
        }
    }

    func setCount(id: UUID, count: Int) {
        apply { session in
            session.setCount(id: id, count: count)
            return .none
        }
    }

    func isExpanded(_ section: ListSection) -> Bool {
        switch section {
        case .later: isTouring ? tourLaterExpanded : laterExpanded
        case .done: isTouring ? tourDoneExpanded : doneExpanded
        }
    }

    /// The choice is saved per section. During the tour it also changes the tour's own copy.
    func toggleSection(_ section: ListSection) {
        switch section {
        case .later:
            if isTouring {
                tourLaterExpanded.toggle()
                laterExpanded = tourLaterExpanded
            } else {
                laterExpanded.toggle()
            }
            hoveredLaterID = nil
            UserDefaults.standard.set(laterExpanded, forKey: Self.laterExpandedKey)
        case .done:
            if isTouring {
                tourDoneExpanded.toggle()
                doneExpanded = tourDoneExpanded
            } else {
                doneExpanded.toggle()
            }
            hoveredDoneID = nil
            UserDefaults.standard.set(doneExpanded, forKey: Self.doneExpandedKey)
        }
    }

    func snooze(id: UUID, returnDay: String) {
        descriptionDrafts[id] = nil
        if hoveredQueueID == id {
            hoveredQueueID = nil
        }
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.snooze(id: id, returnDay: returnDay, now: now)
                return .none
            }
        }
    }

    func returnLater(id: UUID) {
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.returnLater(id: id)
                return .none
            }
        }
    }

    func retargetLater(id: UUID, returnDay: String) {
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.retargetLater(id: id, returnDay: returnDay, now: now)
                return .none
            }
        }
    }

    func deleteLater(id: UUID) {
        withAnimation(QueueMotion.slide(reduceMotion)) {
            apply { session in
                session.deleteLater(id: id)
                return .none
            }
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

    func setLaterHover(_ id: UUID, hovering: Bool) {
        if hovering {
            hoveredLaterID = id
        } else if hoveredLaterID == id {
            hoveredLaterID = nil
        }
    }

    func setDoneHover(_ id: UUID, hovering: Bool) {
        if hovering {
            hoveredDoneID = id
        } else if hoveredDoneID == id {
            hoveredDoneID = nil
        }
    }

    func setHistoryHover(_ id: String, hovering: Bool) {
        if hovering {
            hoveredHistoryID = id
        } else if hoveredHistoryID == id {
            hoveredHistoryID = nil
        }
    }

    func toggleDoneList() {
        suppressDoneAnimation = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            doneListExpanded.toggle()
        }
        Task { @MainActor in
            suppressDoneAnimation = false
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

    /// Where a task of this day may land, and what the list looks like around it. See `DragGeometry`.
    private enum DragLayout {
        case resting
        case planning
        case final
    }

    /// The queue and every LATER day as the drag logic sees them. `held` is left out of its region's count.
    private func dragRegions(layout: DragLayout, excluding held: UUID?) -> [DragRegionSpec] {
        let queue = session.queue.filter { $0.id != held }.count
        let open = layout == .planning || isExpanded(.later)
        var specs = [
            DragRegionSpec(
                id: .queue,
                items: queue,
                slots: held == nil ? 0...queue : session.queueSlots(excluding: held),
                showsZoneWhenEmpty: false
            )
        ]
        for day in planDays {
            let items = session.later.filter { $0.returnDay == day.day && $0.id != held }.count
            specs.append(DragRegionSpec(
                id: .day(day.day),
                items: items,
                slots: 0...items,
                showsZoneWhenEmpty: layout == .planning,
                visible: open
            ))
        }
        return specs
    }

    /// The days LATER offers while planning, plus any day that already holds tasks.
    var planDays: [PlanDay] {
        Snooze.planDays(on: now, existing: session.later.map(\.returnDay))
    }

    private func dragLayout(for drag: QueueDragController) -> DragLayout {
        drag.finalLayout ? .final : .planning
    }

    private func dragBlocks(for drag: QueueDragController) -> [DragBlock] {
        DragGeometry.blocks(dragRegions(layout: dragLayout(for: drag), excluding: drag.itemID), held: drag.slot.region)
    }

    /// Row ids of one region in the order they are drawn, with the held task at its slot and a nil for a drop zone.
    func dragRowIDs(region: DragRegionID, drag: QueueDragController) -> [UUID?] {
        var ids: [UUID?]
        switch region {
        case .queue:
            ids = session.queue.map(\.id).filter { $0 != drag.itemID }
        case .day(let day):
            ids = session.later.filter { $0.returnDay == day && $0.id != drag.itemID }.map(\.id)
        }
        if drag.slot.region == region {
            ids.insert(drag.itemID, at: min(max(0, drag.slot.index), ids.count))
        } else if ids.isEmpty, case .day = region, drag.isPlanning {
            ids = [nil]
        }
        return ids
    }

    /// Whether the LATER block exists while a task is held.
    var laterBlockShown: Bool {
        let shown = windowSession
        guard let drag = queueDrag else { return !shown.later.isEmpty }
        if drag.isPlanning { return true }
        var count = session.later.count
        if drag.source == .queue, drag.slot.region != .queue { count += 1 }
        if drag.source == .later, drag.slot.region == .queue { count -= 1 }
        return count > 0
    }

    /// Whether LATER's rows are on screen. A held task opens LATER for as long as it is held.
    var laterRowsShown: Bool {
        if let drag = queueDrag, drag.isPlanning { return true }
        return isExpanded(.later)
    }

    /// True while the list shows drop targets, so hover details and the depth hint step aside.
    var isDraggingRow: Bool { queueDrag != nil }

    func canDragRow(id: UUID) -> Bool {
        tour == nil && editingQueueID == nil && session.canDrag(id: id)
    }

    func beginQueueDrag(id: UUID) {
        guard tour == nil, queueDrag == nil, session.canDrag(id: id) else { return }
        let source: QueueDragController.Source
        let region: DragRegionID
        let index: Int
        if let position = session.queue.firstIndex(where: { $0.id == id }) {
            source = .queue
            region = .queue
            index = position
        } else if let later = session.later.first(where: { $0.id == id }) {
            let day = session.later.filter { $0.returnDay == later.returnDay }
            source = .later
            region = .day(later.returnDay)
            index = day.firstIndex { $0.id == id } ?? 0
        } else {
            return
        }
        guard let anchor = queueListAnchor, let pointer = pointerInQueueList() else { return }
        commitAllDescriptionDrafts()
        releaseTextFocus()
        let resting = DragGeometry.blocks(dragRegions(layout: .resting, excluding: nil), held: nil)
        guard let blockIndex = dragRegions(layout: .resting, excluding: nil).firstIndex(where: { $0.id == region }) else { return }
        let rowTop = DragGeometry.tops(resting)[blockIndex] + CGFloat(index) * DragMetrics.stride
        let origin = viewportPoint(forListPoint: CGPoint(x: 0, y: rowTop))
        let drag = QueueDragController(
            itemID: id,
            source: source,
            origin: DragSlot(region: region, index: index),
            rowWidth: anchor.bounds.width,
            visualX: origin.x,
            visualY: origin.y,
            grabOffset: pointer.y - rowTop
        )
        withAnimation(reduceMotion ? nil : QueueMotion.slide(false)) {
            queueDrag = drag
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
        drag.rowWidth = anchor.bounds.width
        let specs = dragRegions(layout: .planning, excluding: drag.itemID)
        let next = DragGeometry.resolve(pointerY: pointer.y, regions: specs, current: drag.slot)
        if next != drag.slot {
            withAnimation(QueueMotion.slide(reduceMotion)) {
                drag.slot = next
            }
        }
        let blocks = DragGeometry.blocks(specs, held: drag.slot.region)
        var highlighted: UUID?
        if let hit = DragGeometry.row(at: pointer.y, in: blocks) {
            let ids = dragRowIDs(region: hit.region, drag: drag)
            if hit.row < ids.count, let id = ids[hit.row], id != drag.itemID {
                highlighted = id
            }
        }
        if drag.highlightedID != highlighted {
            drag.highlightedID = highlighted
        }
        springLoadLater(pointerY: pointer.y, blocks: blocks, drag: drag)
        let rowTop = pointer.y - drag.grabOffset
        let origin = viewportPoint(forListPoint: CGPoint(x: 0, y: rowTop))
        drag.visualX = origin.x
        drag.visualY = origin.y
        NSCursor.closedHand.set()
    }

    /// Holding a task over a collapsed LATER header for 0.6 s opens it for good.
    private func springLoadLater(pointerY: CGFloat, blocks: [DragBlock], drag: QueueDragController) {
        guard !laterExpanded, let header = DragGeometry.laterHeader(blocks), header.contains(pointerY) else {
            drag.springStart = nil
            return
        }
        guard let start = drag.springStart else {
            drag.springStart = Date()
            return
        }
        guard Date().timeIntervalSince(start) >= 0.6 else { return }
        drag.springStart = nil
        setLaterExpanded(true)
    }

    private func setLaterExpanded(_ expanded: Bool) {
        guard laterExpanded != expanded else { return }
        laterExpanded = expanded
        if isTouring { tourLaterExpanded = expanded }
        UserDefaults.standard.set(expanded, forKey: Self.laterExpandedKey)
    }

    func endQueueDrag() {
        guard let drag = queueDrag, drag.phase == .dragging else { return }
        stopQueueDragTracking()
        let inside = pointerIsInsideDropArea(drag: drag)
        settleQueueDrag(drop: inside && drag.slot != drag.origin)
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

    func requeueHistory(rowID: String, day: Date) {
        apply { session in
            session.requeueHistory(rowID: rowID, day: day)
            return .none
        }
    }

    func clearDone() {
        doneHeaderHovered = false
        doneSectionFocused = false
        apply { session in
            session.clearDone()
            return .none
        }
    }

    /// Start, Pause, or Resume. The window button and the status-item menu both use this.
    func performMenuAction() {
        if session.phase == .idle {
            start()
        } else if session.isRunning {
            pause()
        } else {
            resume()
        }
    }

    func showWindow() {
        stopAlarm()
        windows.show(model: self)
    }

    func showHistory() {
        guard tour == nil else { return }
        historyWindows.show(model: self)
    }

    var historyDays: [HistoryDay] {
        let zone = Calendar.current.timeZone.identifier
        let count = session.history.count
        if historyCacheZone != zone || historyCacheCount < 0 || count < historyCacheCount {
            historyCache = session.groupedHistory()
        } else if count > historyCacheCount {
            session.mergingNewHistory(into: &historyCache, from: historyCacheCount)
        }
        historyCacheCount = count
        historyCacheZone = zone
        return historyCache
    }

    func quit() {
        tickTimer?.invalidate()
        tickTimer = nil
        now = Date()
        var paused = session.snapshot(at: now)
        paused.restoreAsPaused()
        session = paused
        store.save(session)
        store.flush()
        NSApplication.shared.terminate(nil)
    }

    private func apply(_ change: (inout Session) -> SessionEffect) {
        guard tour == nil else { return }
        now = Date()
        session.refreshDoneDay(now: now)
        bringBackDueLater(animated: true)
        let effect = change(&session)
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        ensureTicker()
        reconcileQueueDrag()
        dropStaleNameEdit()
    }

    /// A row that left the queue (finished, deleted, snoozed) takes its open edit with it.
    private func dropStaleNameEdit() {
        guard let open = editingQueueID,
              !session.queue.contains(where: { $0.id == open }),
              !session.later.contains(where: { $0.id == open })
        else { return }
        descriptionDrafts[open] = nil
        editingQueueID = nil
    }

    private func tick() {
        now = Date()
        session.refreshDoneDay(now: now)
        bringBackDueLater(animated: true)
        let effect = session.reconcile(now: now)
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        reconcileQueueDrag()
        dropStaleNameEdit()
    }

    private func refreshDoneDay() {
        now = Date()
        let previousDay = session.doneDay
        let previousDone = session.done
        session.refreshDoneDay(now: now)
        bringBackDueLater(animated: true)
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
                    self?.catchUpVisibleClock()
                }
            }
        )
        let windowNames: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in windowNames {
            dayObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWindow.didChangeOcclusionStateNotification {
                        let showing = NSApp.windows.contains { window in
                            window.occlusionState.contains(.visible) && !window.isMiniaturized
                        }
                        guard showing else { return }
                    }
                    self.catchUpVisibleClock()
                }
            })
        }
    }

    /// Digits follow `now`. Showing the window or waking must not wait for the next timer fire.
    private func catchUpVisibleClock() {
        now = Date()
        guard session.isRunning else { return }
        let effect = session.reconcile(now: now)
        guard effect != .none else { return }
        bell.play(effect)
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        ensureTicker()
    }

    private func bringBackDueLater(animated: Bool) {
        let returned: Bool
        if animated {
            returned = withAnimation(QueueMotion.slide(reduceMotion)) {
                self.session.returnDueLater(now: self.now)
            }
        } else {
            returned = session.returnDueLater(now: now)
        }
        guard returned else { return }
        store.save(session.snapshot(at: now))
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

    func beginTour() {
        tourScrollTask?.cancel()
        if queueDrag != nil {
            cancelQueueDrag()
        }
        releaseTextFocus()
        commitAllDescriptionDrafts()
        modePickerOpen = false
        tourSample = Session.tourSample()
        tourHoldSpotlight = false
        tourScrollStep = nil
        tourCardSize = .zero
        tourLaterExpanded = true
        tourDoneExpanded = true
        tour = TourProgress(step: .welcome, spotlight: nil)
        syncTourCursors()
    }

    func replayTour() {
        beginTour()
        showWindow()
    }

    func endTour() {
        guard tour != nil else { return }
        tourScrollTask?.cancel()
        store.markTourSeen()
        tourHoldSpotlight = false
        tour = nil
        tourSample = nil
        descriptionDrafts = descriptionDrafts.filter { id, _ in
            session.queue.contains { $0.id == id }
        }
        syncTourCursors()
    }

    /// Background controls keep their cursor rects, and those rects ignore the overlay.
    /// While the tour is up, force the arrow, and the pointing hand only over tour controls.
    private func installTourCursorMonitor() {
        tourCursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate]) { event in
            let touring = MainActor.assumeIsolated { AppRuntime.model.isTouring }
            guard touring else { return event }
            let hand = MainActor.assumeIsolated { () -> Bool in
                guard let window = event.window else { return false }
                return TourPointers.contains(event.locationInWindow, in: window)
            }
            if hand {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            // Swallow the event so the view underneath cannot replace the cursor afterwards.
            return nil
        }
    }

    private func syncTourCursors() {
        for window in NSApp.windows {
            window.acceptsMouseMovedEvents = true
            window.resetCursorRects()
        }
        NSCursor.arrow.set()
        NotificationCenter.default.post(name: .slimpomoTourInteraction, object: nil)
    }

    func tourAdvance() {
        guard let step = tour?.step else { return }
        if step == .welcome {
            setTourStep(.addTask)
        } else if step == .again {
            endTour()
        } else if let next = step.next {
            setTourStep(next)
        }
    }

    func tourBack() {
        guard let step = tour?.step, step != .welcome else { return }
        if step == .addTask {
            setTourStep(.welcome)
        } else if let previous = step.previous {
            setTourStep(previous)
        }
    }

    func noteTourFrames(_ frames: [TourTarget: CGRect], viewport: CGSize) {
        guard tour != nil else { return }
        tourFrames = frames
        tourViewport = viewport
        guard !tourHoldSpotlight else { return }
        followTourTarget()
    }

    func noteTourCardSize(_ size: CGSize) {
        guard abs(tourCardSize.width - size.width) > 0.5 || abs(tourCardSize.height - size.height) > 0.5 else { return }
        tourCardSize = size
    }

    func scheduleTourScrollFinish() {
        tourScrollTask?.cancel()
        let delay = reduceMotion ? 160 : 340
        tourScrollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.tourHoldSpotlight = false
            if let step = self.tour?.step {
                self.tourScrollStep = step
            }
            self.syncSpotlight(animated: true)
        }
    }

    func handleTourKey(_ event: NSEvent) -> Bool {
        guard isTouring else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            if flags.contains(.command),
               !flags.contains(.shift),
               let key = event.charactersIgnoringModifiers?.lowercased(),
               key == "y" || key == "w" {
                return true
            }
            return false
        }
        switch event.keyCode {
        case 53:
            endTour()
        case 36, 76, 124:
            tourAdvance()
        case 123:
            tourBack()
        default:
            break
        }
        return true
    }

    private func setTourStep(_ step: TourStep) {
        guard tour != nil else { return }
        tourScrollTask?.cancel()
        tourHoldSpotlight = false
        tour?.step = step
        followTourTarget()
    }

    private func followTourTarget() {
        guard let step = tour?.step else { return }
        guard let target = step.anchor else {
            tourHoldSpotlight = false
            syncSpotlight(animated: true)
            return
        }
        guard let frame = tourFrames[target], tourViewport.height > 1 else { return }
        let offscreen = step.scrolls && (frame.minY < 4 || frame.maxY > tourViewport.height - 4)
        if offscreen {
            guard tourScrollStep != step else { return }
            tourScrollStep = step
            tourHoldSpotlight = true
            tourScrollRequest += 1
            return
        }
        tourScrollStep = step
        tourHoldSpotlight = false
        syncSpotlight(animated: true)
    }

    private func syncSpotlight(animated: Bool) {
        guard tour != nil else { return }
        let next = tour?.step.anchor.flatMap { tourFrames[$0] }
        guard !Self.rectsMatch(tour?.spotlight, next) else { return }
        let apply = { self.tour?.spotlight = next }
        if animated {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private static func rectsMatch(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.minX - right.minX) < 0.5
                && abs(left.minY - right.minY) < 0.5
                && abs(left.width - right.width) < 0.5
                && abs(left.height - right.height) < 0.5
        default:
            return false
        }
    }

    /// ⌘?. Shift is part of producing "?" on every layout: slash on a US keyboard, ß on a German one.
    /// `charactersIgnoringModifiers` keeps Shift, so the typed character is "?", not the base key.
    private static func isTourShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return false }
        let typed = event.charactersIgnoringModifiers ?? ""
        if typed == "?" || event.characters == "?" { return true }
        guard flags.contains(.shift) else { return false }
        return typed == "/" || typed == "ß" || typed == "ẞ"
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isTourShortcut(event) {
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard NSApp.keyWindow != nil else { return false }
                    AppRuntime.model.replayTour()
                    return true
                }
                if handled { return nil }
            }
            if MainActor.assumeIsolated({ AppRuntime.model.isTouring }) {
                let handled = MainActor.assumeIsolated {
                    AppRuntime.model.handleTourKey(event)
                }
                return handled ? nil : event
            }
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
    private static let laterExpandedKey = "SlimPomo.laterExpanded"
    private static let doneExpandedKey = "SlimPomo.doneExpanded"

    private func ensureTicker() {
        guard tickTimer == nil else { return }
        // `.common` keeps firing while a status-item menu is tracking events.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func handleTick() {
        if session.isRunning {
            idleTickSteps = 0
            tick()
        } else if !session.queue.isEmpty {
            // Finish clocks are "if the queue started now", so they move
            // with the wall clock while nothing is running.
            idleTickSteps += 1
            if idleTickSteps >= 10 {
                idleTickSteps = 0
                now = Date()
            }
        } else {
            return
        }
        // The menu tracks events in its own run-loop mode, so refresh the icon
        // here instead of waiting for a main-queue task that would not run.
        StatusItemController.shared.refreshAppearance()
    }

    private func reconcileQueueDrag() {
        guard let drag = queueDrag else { return }
        let present = drag.source == .queue
            ? session.queue.contains { $0.id == drag.itemID }
            : session.later.contains { $0.id == drag.itemID }
        guard present else {
            clearQueueDrag()
            return
        }
        guard session.canDrag(id: drag.itemID) else {
            if drag.phase == .settling, !drag.drop { return }
            queueSettleTask?.cancel()
            stopQueueDragTracking()
            settleQueueDrag(drop: false)
            return
        }
        let allowed = dragRegions(layout: .planning, excluding: drag.itemID)
            .first { $0.id == drag.slot.region }?.slots
        if let allowed, !allowed.contains(drag.slot.index) {
            let nearest = min(max(drag.slot.index, allowed.lowerBound), allowed.upperBound)
            withAnimation(QueueMotion.slide(reduceMotion)) {
                drag.slot.index = nearest
            }
        }
        if drag.phase == .dragging {
            trackQueueDrag()
        }
    }

    private func settleQueueDrag(drop: Bool) {
        guard let drag = queueDrag else { return }
        let slot = drop ? drag.slot : drag.origin
        if drop, case .day = slot.region {
            setLaterExpanded(true)
        }
        let specs = dragRegions(layout: .final, excluding: drag.itemID)
        let blocks = DragGeometry.blocks(specs, held: slot.region)
        let blockIndex = specs.firstIndex { $0.id == slot.region } ?? 0
        let rowTop = DragGeometry.tops(blocks)[blockIndex] + CGFloat(slot.index) * DragMetrics.stride
        let target = viewportPoint(forListPoint: CGPoint(x: 0, y: rowTop))
        withAnimation(QueueMotion.settle(reduceMotion)) {
            drag.slot = slot
            drag.phase = .settling
            drag.drop = drop
            drag.finalLayout = true
            drag.highlightedID = nil
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
        let slot = drag.slot
        let source = drag.source
        // The floating row is already on the gap, and the list already has its final layout.
        // Commit that order with no animation, in the same update that removes the floating copy.
        suppressQueueAnimation = true
        queueDrag = nil
        if drop {
            apply { session in
                switch (source, slot.region) {
                case (.queue, .queue):
                    session.reorder(id: id, to: slot.index)
                case (.queue, .day(let day)):
                    session.snooze(id: id, returnDay: day, now: now, position: slot.index)
                case (.later, .queue):
                    session.returnLater(id: id, to: slot.index)
                case (.later, .day(let day)):
                    session.moveLater(id: id, toDay: day, position: slot.index, now: now)
                }
                return .none
            }
        }
        Task { @MainActor in
            self.suppressQueueAnimation = false
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

    private func pointerInQueueList() -> CGPoint? {
        guard let anchor = queueListAnchor, let window = anchor.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return anchor.convert(inWindow, from: nil)
    }

    /// A release below the last row, off to the side, or above the list is not a drop.
    private func pointerIsInsideDropArea(drag: QueueDragController) -> Bool {
        guard let anchor = queueListAnchor, let window = anchor.window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inAnchor = anchor.convert(inWindow, from: nil)
        let bottom = DragGeometry.bottom(dragBlocks(for: drag))
        guard QueueDrop.releaseLandsInQueue(
            pointerX: inAnchor.x,
            pointerY: inAnchor.y,
            listWidth: anchor.bounds.width,
            listHeight: bottom
        ) else { return false }
        guard let clip = queueScrollView?.contentView else { return true }
        let inClip = clip.convert(inWindow, from: nil)
        let yFromTop = clip.isFlipped
            ? inClip.y - clip.bounds.minY
            : clip.bounds.maxY - inClip.y
        return QueueDrop.pointerIsInScrollArea(yFromTop: yFromTop)
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
        if view is NSTextView || view is NSTextField || view is NameClickAreaView { return true }
        current = view.superview
    }
    return false
}
