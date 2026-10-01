import AppKit
import SwiftUI

extension View {
    /// Pointing hand while `enabled`. Disabled controls keep the arrow.
    /// One app-wide monitor applies it, so hover overlays and the tank cannot replace it.
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

/// Plain button style that uses the shared pointing-hand cursor.
/// The hit shape matches the label's bounds, including its padding.
struct PointingHandButtonStyle: ButtonStyle {
    var enabled = true
    var shape: PointingHandShape = .rectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape.shape)
            .pointingHandCursor(enabled: enabled)
    }
}

enum PointingHandShape {
    case rectangle
    case capsule

    var shape: AnyShape {
        switch self {
        case .rectangle: AnyShape(Rectangle())
        case .capsule: AnyShape(Capsule())
        }
    }
}

private struct PointingHandCursor: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            PointingHandAnchor(enabled: enabled)
                .allowsHitTesting(false)
        }
    }
}

private struct PointingHandAnchor: NSViewRepresentable {
    var enabled: Bool

    func makeNSView(context: Context) -> PointingHandAnchorView {
        let view = PointingHandAnchorView()
        view.enabled = enabled
        return view
    }

    func updateNSView(_ nsView: PointingHandAnchorView, context: Context) {
        nsView.enabled = enabled
        if nsView.window != nil {
            PointingHand.register(nsView, enabled: enabled)
        }
    }
}

/// Invisible registration view. It does not take clicks; the monitor reads its frame.
final class PointingHandAnchorView: NSView {
    var enabled = true

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            PointingHand.unregister(self)
        } else {
            PointingHand.register(self, enabled: enabled)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            PointingHand.unregister(self)
        }
    }

    isolated deinit {
        PointingHand.unregister(self)
    }
}

/// Sets the pointing hand for every registered control and swallows `cursorUpdate`
/// so a later view cannot put the arrow back. `mouseMoved` is left alone.
/// Touched only on the main thread: the monitor, and anchor views moving in or out of a window.
enum PointingHand {
    static func install() {
        Center.shared.install()
    }

    static func register(_ view: PointingHandAnchorView, enabled: Bool) {
        Center.shared.register(view, enabled: enabled)
    }

    static func unregister(_ view: PointingHandAnchorView) {
        Center.shared.unregister(view)
    }
}

private final class Center: @unchecked Sendable {
    static let shared = Center()

    private struct Entry {
        weak var view: PointingHandAnchorView?
        var enabled: Bool
    }

    private var monitor: Any?
    private var entries: [ObjectIdentifier: Entry] = [:]

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate]) { event in
            let touring = MainActor.assumeIsolated { AppRuntime.model.isTouring }
            if touring { return event }
            let windowNumber = event.windowNumber
            let point = event.locationInWindow
            let claim = MainActor.assumeIsolated { () -> Claim in
                Center.shared.claim(windowNumber: windowNumber, point: point)
            }
            switch claim {
            case .hand:
                NSCursor.pointingHand.set()
            case .arrow:
                NSCursor.arrow.set()
            case .pass:
                return event
            }
            // Swallow only cursorUpdate. mouseMoved must still reach hover tracking.
            return event.type == .cursorUpdate ? nil : event
        }
    }

    func register(_ view: PointingHandAnchorView, enabled: Bool) {
        entries[ObjectIdentifier(view)] = Entry(view: view, enabled: enabled)
    }

    func unregister(_ view: PointingHandAnchorView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
    }

    private enum Claim {
        case hand, arrow, pass
    }

    private func claim(windowNumber: Int, point: NSPoint) -> Claim {
        guard let window = NSApp.window(withWindowNumber: windowNumber) else { return .pass }
        if let hit = window.contentView?.hitTest(point), keepsOwnCursor(hit) {
            return .pass
        }
        let inOurWindow = entries.values.contains { $0.view?.window === window }
        prune()
        var best: (area: CGFloat, enabled: Bool)?
        for entry in entries.values {
            guard let view = entry.view, view.window === window, painted(view) else { continue }
            let local = view.convert(point, from: nil)
            guard view.bounds.contains(local), view.bounds.width > 1, view.bounds.height > 1 else { continue }
            let area = view.bounds.width * view.bounds.height
            if best == nil || area < best!.area {
                best = (area, entry.enabled)
            }
        }
        guard let best else {
            // Still showing the hand after the pointer left a control. Put the arrow
            // back without touching a resize cursor or an I-beam.
            if inOurWindow, NSCursor.current == NSCursor.pointingHand {
                return .arrow
            }
            return .pass
        }
        return best.enabled ? .hand : .arrow
    }

    /// A hidden control (opacity 0) must not claim the cursor. A disabled control stays visible.
    private func painted(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if view.isHidden || view.alphaValue < 0.05 { return false }
            if let layer = view.layer, layer.opacity < 0.05 { return false }
            current = view.superview
        }
        return true
    }

    private func keepsOwnCursor(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if view is QueueGripView || view is NSTextView || view is NSTextField { return true }
            current = view.superview
        }
        return false
    }

    private func prune() {
        entries = entries.filter { $0.value.view != nil }
    }
}
