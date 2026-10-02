import AppKit
import SwiftUI
import SlimPomoCore

enum QueueMotion {
    static func slide(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2)
    }

    static func settle(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0)
    }

    static func lift(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.08)
    }
}

/// One held task, from the moment the row lifts until the list has settled.
/// The gap sits at `slot`; `highlightedID` is the one row under the pointer.
@MainActor
@Observable
final class QueueDragController {
    enum Source {
        case queue
        case later
    }

    let itemID: UUID
    let source: Source
    let origin: DragSlot
    var slot: DragSlot
    var rowHeight: CGFloat
    var rowWidth: CGFloat
    var visualX: CGFloat
    var visualY: CGFloat
    var grabOffset: CGFloat
    var lifted: Bool
    var phase: Phase
    /// True while the row is gliding into a new spot. False while it glides home.
    var drop: Bool
    /// Set on release. The list then lays out as it will after the drop: no drop zones, LATER as it will stay.
    var finalLayout: Bool
    /// The single row that shows the card hover while the pointer passes over it.
    var highlightedID: UUID?
    @ObservationIgnored var springStart: Date?
    /// The stretch of the list the pointer was in when the gap last changed region. See `DropMap.resolve`.
    @ObservationIgnored var carried: ClosedRange<CGFloat>?

    enum Phase: Equatable {
        case dragging
        case settling
    }

    init(
        itemID: UUID,
        source: Source,
        origin: DragSlot,
        rowWidth: CGFloat,
        visualX: CGFloat,
        visualY: CGFloat,
        grabOffset: CGFloat
    ) {
        self.itemID = itemID
        self.source = source
        self.origin = origin
        slot = origin
        rowHeight = DragMetrics.stride
        self.rowWidth = rowWidth
        self.visualX = visualX
        self.visualY = visualY
        self.grabOffset = grabOffset
        lifted = false
        phase = .dragging
        drop = false
        finalLayout = false
    }

    var showsOutline: Bool {
        phase == .dragging || !drop
    }

    /// LATER shows every day as a drop target while a row is held.
    var isPlanning: Bool { !finalLayout }
}

struct QueueListAnchor: NSViewRepresentable {
    var onAttach: (QueueListAnchorView) -> Void

    func makeNSView(context: Context) -> QueueListAnchorView {
        let view = QueueListAnchorView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: QueueListAnchorView, context: Context) {
        nsView.onAttach = onAttach
        nsView.onAttach?(nsView)
    }
}

final class QueueListAnchorView: NSView {
    var onAttach: ((QueueListAnchorView) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// Rows above this view receive clicks. It only marks the list's frame.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    override func layout() {
        super.layout()
        report()
    }

    private func report() {
        guard window != nil else { return }
        onAttach?(self)
    }
}

enum RowDrag {
    /// How far the pointer must move after pressing before a row lifts.
    static let threshold: CGFloat = 4
}

/// Lets a whole queue or LATER card start a drag. It sits behind the card, takes no clicks, and
/// watches the mouse itself, so controls and the name keep every event they get today.
struct RowDragSource: NSViewRepresentable {
    /// False for the running task, and while the tour runs.
    var movable: Bool
    /// Stretches measured from the row's right edge where a press belongs to a small hover control (−, +, •••).
    /// Everything else on the row, the gauge and the tag included, starts a drag once the pointer has moved.
    var controlZones: [ClosedRange<CGFloat>]
    var onBegin: (NSPoint) -> Void

    func makeNSView(context: Context) -> RowDragView {
        let view = RowDragView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: RowDragView, context: Context) {
        apply(to: nsView)
        nsView.refreshCursor()
    }

    private func apply(to view: RowDragView) {
        view.movable = movable
        view.controlZones = controlZones
        view.onBegin = onBegin
        view.kind = movable ? .openHand : .arrow
    }
}

/// Starts a drag once the pointer has moved `RowDrag.threshold` after a press on the row.
/// A press on a hover control, a text field, or a scroller never starts one.
final class RowDragView: PointingHandAnchorView {
    var movable = false
    var controlZones: [ClosedRange<CGFloat>] = []
    var onBegin: ((NSPoint) -> Void)?
    private var monitor: Any?
    /// Where the button went down, in window coordinates. Nil when this press cannot start a drag.
    private var pressedAt: NSPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        pressedAt = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    func refreshCursor() {
        if window != nil {
            PointingHand.register(self)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressedAt = pressStart(event)
        case .leftMouseDragged:
            guard let start = pressedAt else { return }
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard moved >= RowDrag.threshold else { return }
            pressedAt = nil
            onBegin?(start)
        default:
            pressedAt = nil
        }
    }

    private func pressStart(_ event: NSEvent) -> NSPoint? {
        guard let window, event.window === window, movable, !isHidden else { return nil }
        guard !event.modifierFlags.contains(.control) else { return nil }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local), visibleRect.contains(local) else { return nil }
        let fromRight = bounds.width - local.x
        guard !controlZones.contains(where: { $0.contains(fromRight) }) else { return nil }
        var view = window.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSTextView || current is NSTextField || current is NSScroller { return nil }
            view = current.superview
        }
        return event.locationInWindow
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
