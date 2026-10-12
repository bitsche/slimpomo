import AppKit
import SwiftUI

/// The NOW row's "Done" pill: always visible, the rightmost element of the row. It finishes the current pomodoro through
/// the same path as "Mark as finished", running or paused.
///
/// At rest it is an outline in the row's accent (the mode's surface color while running, grey while paused). Under the pointer
/// it fills solid with the icon and text in the base color; pressed, the fill is 8% darker. A click fills it and scales the
/// check in for 150 ms (instant with Reduce Motion) before the pomodoro finishes.
struct DoneButton: View {
    var accent: Color
    var hovered: Bool
    var pressed: Bool
    /// The click is playing its 150 ms feedback.
    var confirming: Bool
    var reduceMotion: Bool
    var onHover: (Bool) -> Void
    var onPress: (Bool) -> Void
    var action: () -> Void

    static let help = "Finish this pomodoro (\u{2318}\u{21A9})"
    static let height: CGFloat = 24
    static let hitHeight: CGFloat = 28
    /// Space between the count's slot (or the hover cluster) and the button.
    static let gap: CGFloat = 6
    private static let leading: CGFloat = 8
    private static let trailing: CGFloat = 10
    private static let iconSize: CGFloat = 12
    private static let iconGap: CGFloat = 5

    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// Pill width: padding, icon, gap, and the label "Done".
    @MainActor
    static let width: CGFloat = {
        let label = ceil(("Done" as NSString).size(withAttributes: [.font: labelFont]).width)
        return leading + iconSize + iconGap + label + trailing
    }()

    private var solid: Bool { hovered || pressed || confirming }

    var body: some View {
        HStack(spacing: Self.iconGap) {
            DoneCheckMark()
                .stroke(solid ? Theme.bgBase : accent, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .id(confirming)
                .transition(reduceMotion ? .identity : .scale(scale: 0.4))
            Text("Done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(solid ? Theme.bgBase : accent)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.trailing)
        .frame(height: Self.height)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Self.height / 2, style: .continuous)
                    .fill(solid ? accent : Color.clear)
                if pressed {
                    RoundedRectangle(cornerRadius: Self.height / 2, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.height / 2, style: .continuous)
                .strokeBorder(accent.opacity(solid ? 1 : 0.47), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: confirming)
        .fixedSize()
        // A 28 pt tall hit area over the whole pill. It never takes keyboard focus.
        .overlay {
            DoneButtonHit(tip: Self.help, onHover: onHover, onPress: onPress, onClick: action)
                .frame(width: Self.width, height: Self.hitHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finish this pomodoro")
        .accessibilityHint("Counts one pomodoro as done and starts the break")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { action() }
    }
}

private struct DoneCheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.22))
        return path
    }
}

private struct DoneButtonHit: NSViewRepresentable {
    var tip: String
    var onHover: (Bool) -> Void
    var onPress: (Bool) -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> DoneButtonHitView {
        let view = DoneButtonHitView()
        view.setAccessibilityElement(false)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DoneButtonHitView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DoneButtonHitView) {
        view.onHover = onHover
        view.onPress = onPress
        view.onClick = onClick
        if view.toolTip != tip { view.toolTip = tip }
    }
}

/// Reports hover and press to the pill, takes the click on mouse up inside, and keeps the pointing hand.
final class DoneButtonHitView: PointingHandAnchorView {
    var onHover: ((Bool) -> Void)?
    var onPress: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    private var hovering = false
    private var pressing = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        guard !AppRuntime.model.isTouring else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
        syncHoverToPointer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            setHovering(false)
            setPressing(false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !AppRuntime.model.isTouring else { return }
        setHovering(true)
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard !AppRuntime.model.isTouring else { return }
        setPressing(true)
        NSCursor.pointingHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        setPressing(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressing = pressing
        setPressing(false)
        guard wasPressing, inside, !AppRuntime.model.isTouring else { return }
        onClick?()
    }

    /// The row can appear under a pointer that is already inside, so mouseEntered never fires.
    private func syncHoverToPointer() {
        guard let window, bounds.width > 0, bounds.height > 0, window.isVisible else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(bounds.contains(point) && !AppRuntime.model.isTouring)
    }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        let callback = onHover
        Task { @MainActor in callback?(value) }
    }

    private func setPressing(_ value: Bool) {
        guard pressing != value else { return }
        pressing = value
        let callback = onPress
        Task { @MainActor in callback?(value) }
    }
}
