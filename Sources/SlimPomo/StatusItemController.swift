import AppKit
import Observation
import SlimPomoCore

/// Menu-bar item. Left-click opens the status menu. Right-click and Control-click open the window.
final class StatusItemController: NSObject, NSMenuDelegate, @unchecked Sendable {
    @MainActor static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var didStart = false
    private var presentingMenu = false
    private var openMenuSnapshot: String?

    @MainActor
    func start() {
        guard !didStart else { return }
        didStart = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("SlimPomo")
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
                self.syncOpenMenu()
                self.track()
            }
        }
    }

    @MainActor
    func refreshAppearance() {
        syncIcon()
        syncOpenMenu()
    }

    @MainActor
    private func syncIcon() {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarLabel.statusImage(model: AppRuntime.model)
        button.setAccessibilityLabel("SlimPomo")
    }

    @MainActor
    @objc private func handleClick(_ sender: Any?) {
        if presentingMenu { return }
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp
        let controlClick = event?.modifierFlags.contains(.control) == true
        if rightClick || controlClick {
            AppRuntime.model.showWindow()
            return
        }
        AppRuntime.model.stopAlarm()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        presentingMenu = true
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    @MainActor
    @objc private func showWindowFromMenu(_ sender: Any?) {
        AppRuntime.model.showWindow()
    }

    @MainActor
    @objc private func performPrimaryFromMenu(_ sender: Any?) {
        AppRuntime.model.performMenuAction()
    }

    @MainActor
    @objc private func quitFromMenu(_ sender: Any?) {
        AppRuntime.model.quit()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.fill(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.statusItem?.menu = nil
            self.presentingMenu = false
            self.openMenuSnapshot = nil
        }
    }

    @MainActor
    private func syncOpenMenu() {
        guard let menu = statusItem?.menu, menu.items.count == 6 else { return }
        let content = AppRuntime.model.session.statusMenu(at: AppRuntime.model.now)
        let snapshot = content.statusLine + "\n" + content.actionTitle + (content.actionEnabled ? "1" : "0")
        guard snapshot != openMenuSnapshot else { return }
        openMenuSnapshot = snapshot
        menu.items[0].title = StatusMenuMetrics.fitted(content)
        menu.items[3].title = content.actionTitle
        menu.items[3].isEnabled = content.actionEnabled
    }

    @MainActor
    private func fill(_ menu: NSMenu) {
        let content = AppRuntime.model.session.statusMenu(at: AppRuntime.model.now)
        openMenuSnapshot = content.statusLine + "\n" + content.actionTitle + (content.actionEnabled ? "1" : "0")
        menu.removeAllItems()
        addItems(to: menu, statusTitle: StatusMenuMetrics.fitted(content), content: content)
    }

    @MainActor
    private func addItems(to menu: NSMenu, statusTitle: String, content: StatusMenuContent) {
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Window", action: #selector(showWindowFromMenu(_:)), keyEquivalent: "o")
        show.keyEquivalentModifierMask = .command
        show.target = self
        menu.addItem(show)

        let action = NSMenuItem(
            title: content.actionTitle,
            action: #selector(performPrimaryFromMenu(_:)),
            keyEquivalent: ""
        )
        action.target = self
        action.isEnabled = content.actionEnabled
        menu.addItem(action)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SlimPomo", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
    }
}

private enum StatusMenuMetrics {
    static func textWidth(_ string: String) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// Width of the real menu, including insets and the key-equivalent column.
    @MainActor
    static func menuWidth(statusTitle: String) -> CGFloat {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Window", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "o")
        show.keyEquivalentModifierMask = .command
        menu.addItem(show)
        let action = NSMenuItem(title: "Resume", action: nil, keyEquivalent: "")
        menu.addItem(action)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SlimPomo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        menu.update()
        return menu.size.width
    }

    @MainActor
    static func fitted(_ content: StatusMenuContent) -> String {
        let probe = String(repeating: "W", count: 80)
        let overhead = menuWidth(statusTitle: probe) - textWidth(probe)
        var budget = MenuTitleFit.maxMenuWidth - overhead
        var title = MenuTitleFit.line(
            prefix: content.statusPrefix,
            name: content.taskName,
            suffix: content.statusSuffix,
            maxWidth: budget,
            measure: textWidth
        )
        var width = menuWidth(statusTitle: title)
        var steps = 0
        while width > MenuTitleFit.maxMenuWidth, steps < 8 {
            budget -= width - MenuTitleFit.maxMenuWidth
            let next = MenuTitleFit.line(
                prefix: content.statusPrefix,
                name: content.taskName,
                suffix: content.statusSuffix,
                maxWidth: budget,
                measure: textWidth
            )
            if next == title { break }
            title = next
            width = menuWidth(statusTitle: title)
            steps += 1
        }
        return title
    }
}
