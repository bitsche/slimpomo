import AppKit
import SwiftUI

@MainActor
enum AppRuntime {
    static let model = AppModel()
}

@main
struct SlimPomoApp: App {
    @NSApplicationDelegateAdaptor(SlimPomoDelegate.self) var delegate

    var body: some Scene {
        // SwiftUI requires a scene. This one stays out of the menu bar;
        // the status item and the main window are AppKit.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}

final class SlimPomoDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            StatusItemController.shared.start()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            TourMenu.claimShortcut()
            AppRuntime.model.showWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            TourMenu.claimShortcut()
        }
    }
}

/// The system Help item is bound to ⌘?, and with no help book it shows "help isn't available".
/// That binding is what a German keyboard sends for command-shift-ß. Point it at the tour instead.
@MainActor
enum TourMenu {
    private static let target = TourMenuTarget()

    static func claimShortcut() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items {
            claim(in: item.submenu)
        }
        claim(in: NSApp.helpMenu)
    }

    private static func claim(in menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            let opensSystemHelp = item.action == #selector(NSApplication.showHelp(_:))
            if item.keyEquivalent == "?" || opensSystemHelp {
                item.title = "Tour"
                item.action = #selector(TourMenuTarget.showTour(_:))
                item.target = target
                item.keyEquivalent = "?"
                item.keyEquivalentModifierMask = .command
            }
            claim(in: item.submenu)
        }
    }
}

private final class TourMenuTarget: NSObject {
    @objc func showTour(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard NSApp.keyWindow != nil else { return }
            AppRuntime.model.replayTour()
        }
    }
}
