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

/// One held task, from the moment the grip is pressed until the list has settled.
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

struct QueueGrip: NSViewRepresentable {
    var enabled: Bool
    var toolTip: String?

    var onPress: () -> Void

    func makeNSView(context: Context) -> QueueGripView {
        let view = QueueGripView()
        view.onPress = onPress
        return view
    }

    func updateNSView(_ nsView: QueueGripView, context: Context) {
        nsView.enabled = enabled
        nsView.toolTip = toolTip
        nsView.onPress = onPress
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class QueueGripView: NSView {
    var enabled = false
    var onPress: (() -> Void)?

    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        guard enabled, !AppRuntime.model.isTouring else { return }
        addCursorRect(bounds, cursor: .openHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        onPress?()
    }
}
