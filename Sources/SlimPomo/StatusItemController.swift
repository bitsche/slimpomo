import AppKit
import Observation
import SwiftUI

/// Menu-bar item with an AppKit menu rebuilt every time it opens, so Start/Resume
/// enablement matches the timer instead of a stale SwiftUI menu.
final class StatusItemController: NSObject, NSMenuDelegate, @unchecked Sendable {
    @MainActor static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var didStart = false

    @MainActor
    func start() {
        guard !didStart else { return }
        didStart = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }
        statusItem = item
        syncIcon()
        track()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let action = MainActor.assumeIsolated { AppRuntime.model.session.menuAction }
        menu.removeAllItems()
        menu.addItem(item("Show Window", action: #selector(showWindow), enabled: true, key: ""))
        menu.addItem(item(action.title, action: #selector(performMenuAction), enabled: action.isEnabled, key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(quit), enabled: true, key: "q"))
    }

    private func item(_ title: String, action: Selector, enabled: Bool, key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.isEnabled = enabled
        return entry
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

    @MainActor
    @objc private func performMenuAction() {
        AppRuntime.model.performMenuAction()
    }

    @MainActor
    @objc private func quit() {
        AppRuntime.model.quit()
    }
}
