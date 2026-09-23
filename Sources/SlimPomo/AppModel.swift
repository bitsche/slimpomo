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
    var breakMessage: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let bell: Bell
    @ObservationIgnored private let windows = MainWindowController()
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = Store()
        self.store = store
        bell = Bell()
        now = Date()
        var loaded = store.load() ?? Session()
        loaded.normalize()
        loaded.restoreAsPaused()
        session = loaded
        syncBreakMessage()
        store.save(loaded)
    }

    func refresh() {
        tick()
        ensureTicker()
    }

    func start() {
        apply { $0.start(now: now) }
    }

    func pause() {
        apply { $0.pause(now: now) }
    }

    func resume() {
        apply { $0.resume(now: now) }
    }

    func markDone() {
        apply { $0.markDone(now: now) }
    }

    func stop() {
        apply { $0.stop() }
    }

    func skipBreak() {
        apply { $0.skipBreak(now: now) }
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
        windows.show(model: self)
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
        let effect = change(&session)
        if effect == .playBell {
            bell.play()
        }
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        ensureTicker()
    }

    private func tick() {
        now = Date()
        let effect = session.reconcile(now: now)
        if effect == .playBell {
            bell.play()
        }
        syncBreakMessage()
        store.save(session.snapshot(at: now))
        if !session.isRunning {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func syncBreakMessage() {
        if session.phase == .breakTime {
            if breakMessage == nil {
                breakMessage = BreakMessages.pick()
            }
        } else {
            breakMessage = nil
        }
    }

    private func ensureTicker() {
        guard session.isRunning else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }
}
