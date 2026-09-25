import AppKit
import SwiftUI
import SlimPomoCore

enum TourTarget: Hashable {
    case addField
    case addChip
    case taskCount
    case timerCard
    case reorderGrip
    case doneSection
    case historyButton
    case tourButton
}

enum TourStep: Hashable {
    case welcome
    case addTask
    case depth
    case count
    case timer
    case reorder
    case menuBar
    case done
    case history
    case again

    static let spotlight: [TourStep] = [
        .addTask, .depth, .count, .timer, .reorder, .menuBar, .done, .history, .again
    ]

    var anchor: TourTarget? {
        switch self {
        case .welcome, .menuBar: nil
        case .addTask: .addField
        case .depth: .addChip
        case .count: .taskCount
        case .timer: .timerCard
        case .reorder: .reorderGrip
        case .done: .doneSection
        case .history: .historyButton
        case .again: .tourButton
        }
    }

    /// Targets that live in the queue scroller and may sit below the fold.
    var scrolls: Bool {
        switch self {
        case .addTask, .depth, .count, .reorder, .done: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .welcome: "Welcome to SlimPomo"
        case .addTask: "Add a task"
        case .depth: "Choose how deep to go"
        case .count: "How many pomodoros"
        case .timer: "Start, pause, finish"
        case .reorder: "Drag to reorder"
        case .menuBar: "Glance at the menu bar"
        case .done: "Done today"
        case .history: "History"
        case .again: "See this again"
        }
    }

    var text: String {
        switch self {
        case .welcome:
            "A small Pomodoro timer that lives in your menu bar. Line up what you want to get done, choose how deep each task goes, and work through it one focused session at a time, with a real break after each. No accounts, no settings, nothing leaves this Mac."
        case .addTask:
            "Describe it in a few words and press Return. It joins the queue below."
        case .depth:
            Self.depthText
        case .count:
            "Click to add one (up to 5), right-click to remove one. The time beside it shows when the task's last pomodoro would end."
        case .timer:
            "START begins the first task that has pomodoros left. PAUSE freezes the clock. RESET drops a running session without counting it. While paused, FINISH counts it as done and records the time you actually worked. A break always follows, and SKIP ends it early."
        case .reorder:
            "Hover a task and drag the grip on its left to move it. A task that is running stays at the top and can't be moved. Or use ••• to move it to tomorrow or next Monday."
        case .menuBar:
            "SlimPomo lives up there. The tomato means idle, the ring fills as time passes, pause bars mean paused, and a smile means you're on a break. Click it for quick controls, right-click to open this window."
        case .done:
            "Finished tasks land here with the time you worked. The arrow puts a task back in the queue. Done starts fresh every night at midnight, and nothing is lost."
        case .history:
            "Every past day, with its pomodoros and work time. Open it here or with ⌘Y."
        case .again:
            "Click here or press ⌘? whenever you need a refresher."
        }
    }

    var nextTitle: String {
        if self == .welcome { return "Show me around" }
        if self == .again { return "Start working" }
        return "Next"
    }

    var next: TourStep? {
        guard let index = Self.spotlight.firstIndex(of: self) else { return nil }
        let following = Self.spotlight.index(after: index)
        guard following < Self.spotlight.endIndex else { return nil }
        return Self.spotlight[following]
    }

    var previous: TourStep? {
        guard let index = Self.spotlight.firstIndex(of: self), index > Self.spotlight.startIndex else { return nil }
        return Self.spotlight[Self.spotlight.index(before: index)]
    }

    private static var depthText: String {
        let dip = Intensity.regular.mode
        let dive = Intensity.focus.mode
        let deep = Intensity.intense.mode
        return "\(dip.name) is \(dip.workMinutes) min plus a \(dip.breakMinutes) min break. \(dive.name) is \(dive.workMinutes) + \(dive.breakMinutes). \(deep.name) is \(deep.workMinutes) + \(deep.breakMinutes). Your pick becomes the default for the next task. Click a chip in the queue to change it."
    }
}

struct TourProgress: Equatable {
    var step: TourStep
    var spotlight: CGRect?
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourTarget(_ target: TourTarget?) -> some View {
        modifier(TourTargetMark(target: target))
    }
}

private struct TourTargetMark: ViewModifier {
    var target: TourTarget?

    func body(content: Content) -> some View {
        if let target {
            content
                .id(target)
                .anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
        } else {
            content
        }
    }
}

struct TourOverlay: View {
    var model: AppModel
    var viewport: CGSize
    var frames: [TourTarget: CGRect]

    @AccessibilityFocusState private var cardFocused: Bool

    var body: some View {
        Group {
            if model.tour != nil {
                ZStack(alignment: .topLeading) {
                    dim
                    card
                }
                .frame(width: viewport.width, height: viewport.height)
            } else {
                Color.clear
            }
        }
        .onAppear { reportFrames() }
        .onChange(of: frames) { _, _ in reportFrames() }
        .onChange(of: viewport) { _, _ in reportFrames() }
        .onChange(of: model.tour?.step) { _, _ in
            cardFocused = true
        }
    }

    private func reportFrames() {
        model.noteTourFrames(frames, viewport: viewport)
    }

    private var dim: some View {
        Color.black.opacity(0.55)
            .overlay {
                if let hole = paddedSpotlight {
                    RoundedRectangle(cornerRadius: holeRadius(hole), style: .continuous)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .blendMode(.destinationOut)
                        .allowsHitTesting(false)
                        .id(model.reduceMotion ? model.tour?.step : nil)
                        .transition(.opacity)
                }
            }
            .compositingGroup()
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)
            .animation(
                model.reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3),
                value: model.reduceMotion ? model.tour?.step : nil
            )
            .animation(model.reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.tour?.spotlight)
    }

    private var card: some View {
        let width = cardWidth
        let measured = model.tourCardSize == .zero ? CGSize(width: width, height: 180) : model.tourCardSize
        let placement = TourPlacement.make(
            step: model.tour?.step ?? .welcome,
            hole: paddedSpotlight,
            card: CGSize(width: width, height: measured.height),
            viewport: viewport
        )
        return TourCard(model: model, width: width, focused: $cardFocused)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TourCardSizeKey.self, value: geo.size)
                }
            }
            .onPreferenceChange(TourCardSizeKey.self) { model.noteTourCardSize($0) }
            .id(model.reduceMotion ? model.tour?.step : nil)
            .transition(.opacity)
            .padding(.top, max(0, placement.origin.y))
            .padding(.leading, max(0, placement.origin.x))
            .animation(model.reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: placement.origin)
    }

    private var cardWidth: CGFloat {
        let cap: CGFloat = model.tour?.step == .welcome ? 340 : 300
        return min(cap, max(0, viewport.width - 24))
    }

    private var paddedSpotlight: CGRect? {
        guard let raw = model.tour?.spotlight else { return nil }
        return raw.insetBy(dx: -6, dy: -6)
    }

    private func holeRadius(_ hole: CGRect) -> CGFloat {
        let side = min(hole.width, hole.height)
        if side < 56 { return side / 2 }
        return 10
    }
}

private struct TourCardSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TourPlacement {
    var origin: CGPoint

    static func make(step: TourStep, hole: CGRect?, card: CGSize, viewport: CGSize) -> TourPlacement {
        let margin: CGFloat = 12
        if step == .welcome {
            return TourPlacement(origin: CGPoint(
                x: (viewport.width - card.width) / 2,
                y: max(margin, (viewport.height - card.height) / 2)
            ))
        }
        guard let hole else {
            return TourPlacement(origin: CGPoint(
                x: max(margin, (viewport.width - card.width) / 2),
                y: margin
            ))
        }
        let gap: CGFloat = 10
        let spaceAbove = hole.minY - margin
        let spaceBelow = viewport.height - hole.maxY - margin
        let below = spaceBelow >= card.height + gap || spaceBelow >= spaceAbove
        var y = below ? hole.maxY + gap : hole.minY - gap - card.height
        y = min(max(margin, y), max(margin, viewport.height - margin - card.height))
        var x = hole.midX - card.width / 2
        x = min(max(margin, x), max(margin, viewport.width - margin - card.width))
        return TourPlacement(origin: CGPoint(x: x, y: y))
    }
}

private struct TourCard: View {
    var model: AppModel
    var width: CGFloat
    var focused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        let step = model.tour?.step ?? .welcome
        let placement = arrowPlacement(step)
        VStack(alignment: .leading, spacing: 0) {
            if placement.showsArrow, placement.pointsUp {
                TourArrow(pointsUp: true)
                    .offset(x: placement.shift)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(step.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused(focused)
                    .accessibilityLabel("\(step.title). \(step.text)")

                Text(step.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)

                if step == .menuBar {
                    HStack(spacing: 16) {
                        ForEach(MenuBarTourIcon.allCases, id: \.self) { icon in
                            Image(nsImage: MenuBarLabel.tourIcon(icon))
                                .frame(width: 22, height: 22)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                }

                if step != .welcome {
                    HStack(spacing: 5) {
                        ForEach(TourStep.spotlight, id: \.self) { dot in
                            Circle()
                                .fill(Color.white.opacity(dot == step ? 0.92 : 0.28))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }

                if step == .welcome {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        TourButton(title: "Skip", prominent: false) { model.endTour() }
                        TourButton(title: step.nextTitle, prominent: true) { model.tourAdvance() }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button { model.endTour() } label: {
                            Text("Skip tour")
                                .font(.system(size: 12))
                                .underline()
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip tour")
                        .overlay { TourPointer() }
                        Spacer(minLength: 4)
                        TourButton(title: "Back", prominent: false) { model.tourBack() }
                        TourButton(title: step.nextTitle, prominent: true) { model.tourAdvance() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.22, green: 0.22, blue: 0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            if placement.showsArrow, !placement.pointsUp {
                TourArrow(pointsUp: false)
                    .offset(x: placement.shift)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .onAppear { focused.wrappedValue = true }
    }

    private func arrowPlacement(_ step: TourStep) -> (showsArrow: Bool, pointsUp: Bool, shift: CGFloat) {
        guard step != .welcome else { return (false, false, 0) }
        guard let hole = model.tour?.spotlight?.insetBy(dx: -6, dy: -6) else {
            return (true, true, 0)
        }
        let cardHeight = model.tourCardSize.height
        let viewport = model.tourViewport
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let spaceAbove = hole.minY - margin
        let spaceBelow = viewport.height - hole.maxY - margin
        let below = spaceBelow >= cardHeight + gap || spaceBelow >= spaceAbove
        let originX = min(max(margin, hole.midX - width / 2), max(margin, viewport.width - margin - width))
        let shift = min(max(hole.midX - (originX + width / 2), -width / 2 + 16), width / 2 - 16)
        return (true, below, shift)
    }
}

private struct TourArrow: View {
    var pointsUp: Bool

    var body: some View {
        Path { path in
            if pointsUp {
                path.move(to: CGPoint(x: 8, y: 0))
                path.addLine(to: CGPoint(x: 16, y: 8))
                path.addLine(to: CGPoint(x: 0, y: 8))
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 16, y: 0))
                path.addLine(to: CGPoint(x: 8, y: 8))
            }
            path.closeSubpath()
        }
        .fill(Color(red: 0.22, green: 0.22, blue: 0.22))
        .frame(width: 16, height: 8)
        .accessibilityHidden(true)
    }
}

extension Notification.Name {
    static let slimpomoTourInteraction = Notification.Name("SlimPomo.tourInteraction")
}

/// Buttons and links on the tour card. The window cursor stays an arrow everywhere else.
@MainActor
enum TourPointers {
    private final class Box {
        weak var view: TourPointerView?
        init(_ view: TourPointerView) { self.view = view }
    }

    private static var boxes: [Box] = []

    static func register(_ view: TourPointerView) {
        boxes.removeAll { $0.view == nil || $0.view === view }
        boxes.append(Box(view))
    }

    static func unregister(_ view: TourPointerView) {
        boxes.removeAll { $0.view == nil || $0.view === view }
    }

    static func contains(_ point: NSPoint, in window: NSWindow) -> Bool {
        boxes.removeAll { $0.view == nil }
        for box in boxes {
            guard let view = box.view, view.window === window else { continue }
            if view.bounds.contains(view.convert(point, from: nil)) {
                return true
            }
        }
        return false
    }
}

struct TourPointer: NSViewRepresentable {
    func makeNSView(context: Context) -> TourPointerView {
        TourPointerView()
    }

    func updateNSView(_ nsView: TourPointerView, context: Context) {}
}

final class TourPointerView: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            TourPointers.unregister(self)
        } else {
            TourPointers.register(self)
        }
    }
}

private struct TourButton: View {
    var title: String
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .foregroundStyle(Color.white.opacity(prominent ? 0.96 : 0.75))
                .padding(.horizontal, prominent ? 12 : 8)
                .padding(.vertical, 6)
                .background {
                    if prominent {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    }
                }
                .overlay {
                    if prominent {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .overlay { TourPointer() }
    }
}
