import AppKit
import Observation

/// Menu-bar item. A click opens the window or brings it forward.
final class StatusItemController: NSObject, @unchecked Sendable {
    @MainActor static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var didStart = false

    @MainActor
    func start() {
        guard !didStart else { return }
        didStart = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(showWindow)
        }
        statusItem = item
        syncIcon()
        track()
    }

    @MainActor
    private func track() {
        withObservationTracking {
            _ = AppRuntime.model.session.phase
            _ = AppRuntime.model.session.isRunning
            _ = AppRuntime.model.session.queue.map(\.count)
            _ = AppRuntime.model.now
        } onChange: {
            Task { @MainActor in
                self.syncIcon()
                self.track()
            }
        }
    }

    @MainActor
    private func syncIcon() {
        statusItem?.button?.image = MenuBarLabel.statusImage(model: AppRuntime.model)
    }

    @MainActor
    @objc private func showWindow() {
        AppRuntime.model.showWindow()
    }
}
