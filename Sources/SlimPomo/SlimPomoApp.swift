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
}
