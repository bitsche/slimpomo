import AppKit
import Foundation
import Observation
import SlimPomoCore

@MainActor
@Observable
final class AppModel {
    var session: Session
    var now: Date

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let bell: Bell
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = Store()
        self.store = store
        bell = Bell()
        now = Date()
        var loaded = store.load() ?? Session()
        loaded.restoreAsPaused()
        session = loaded
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

    func skipBreak() {
        apply { $0.skipBreak(now: now) }
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
        apply { $0.remove(id: id, now: now) }
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
        store.save(session.snapshot(at: now))
        ensureTicker()
    }

    private func tick() {
        now = Date()
        let effect = session.reconcile(now: now)
        if effect == .playBell {
            bell.play()
        }
        store.save(session.snapshot(at: now))
        if !session.isRunning {
            tickTask?.cancel()
            tickTask = nil
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
