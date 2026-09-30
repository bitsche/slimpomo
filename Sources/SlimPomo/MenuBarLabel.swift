import AppKit
import SlimPomoCore

enum MenuBarTourIcon: CaseIterable {
    case idle
    case running
    case paused
    case onBreak
}

/// What the menu-bar image is showing. Equal values share one drawing.
struct MenuBarIconKey: Equatable {
    var kind: Kind
    var minutes: Int
    /// Work fill, counted in 0.5 pt steps. Other states stay at 0.
    var waterStep: Int

    enum Kind: Equatable {
        case idle
        case work
        case workPaused
        case breakRunning
        case breakPaused
    }
}

enum MenuBarLabel {
    /// Counter icon, same 18 pt slot the ring used.
    static let iconSide: CGFloat = 18
    /// Idle canvas, same 22 pt slot the waiting tomato used.
    private static let waitingSide: CGFloat = 22

    static func iconKey(session: Session, now: Date) -> MenuBarIconKey {
        let kind: MenuBarIconKey.Kind
        switch session.phase {
        case .idle:
            kind = .idle
        case .work:
            kind = session.isRunning ? .work : .workPaused
        case .breakTime:
            kind = session.isRunning ? .breakRunning : .breakPaused
        }
        let minutes = session.phase == .idle ? -1 : MenuClock.minutes(session.displayedRemaining(at: now))
        let waterStep = session.phase == .work ? MenuBarGlyph.waterStep(session.elapsedFraction(at: now)) : 0
        return MenuBarIconKey(kind: kind, minutes: minutes, waterStep: waterStep)
    }

    /// Menu-bar image. Idle is the icon alone. A running or paused timer reserves two digits.
    static func statusImage(session: Session, now: Date) -> NSImage {
        let key = iconKey(session: session, now: now)
        let minutes = key.minutes >= 0 ? String(key.minutes) : nil
        let level = session.phase == .work ? session.elapsedFraction(at: now) : 0
        return draw(kind: key.kind, level: level, minutes: minutes, color: .black, template: true)
    }

    /// The four menu-bar states, drawn with the same paths the status item uses.
    static func tourIcon(_ kind: MenuBarTourIcon) -> NSImage {
        let image: NSImage
        switch kind {
        case .idle:
            image = MenuBarGlyph.image(kind: .idle, level: 0, color: .white)
        case .running:
            image = MenuBarGlyph.image(kind: .work, level: 0.42, color: .white)
        case .paused:
            image = MenuBarGlyph.image(kind: .workPaused, level: 0.42, color: .white)
        case .onBreak:
            image = MenuBarGlyph.image(kind: .breakRunning, level: 0, color: .white)
        }
        image.isTemplate = false
        return image
    }

    /// Same length as the pre-tank status item: 18 pt icon, 4 pt gap, 14 pt semibold digits.
    /// Idle is the icon only, on the old 22 pt canvas, with no digit slot.
    private static func draw(
        kind: MenuBarIconKey.Kind,
        level: Double,
        minutes: String?,
        color: NSColor,
        template: Bool
    ) -> NSImage {
        let spacing: CGFloat = 4
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let digitWidth = ceil(("88" as NSString).size(withAttributes: [.font: font]).width)
        let showsCounter = minutes != nil
        let width = showsCounter ? iconSide + spacing + digitWidth : waitingSide
        let height = showsCounter ? iconSide : waitingSide
        let text = minutes.map { $0 as NSString }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = text?.size(withAttributes: attributes) ?? .zero
        let glyph = MenuBarGlyph.image(kind: kind, level: level, color: color)
        let glyphRect = showsCounter
            ? NSRect(x: 0, y: 0, width: iconSide, height: iconSide)
            : NSRect(
                x: (waitingSide - iconSide) / 2,
                y: (waitingSide - iconSide) / 2,
                width: iconSide,
                height: iconSide
            )
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            glyph.draw(in: glyphRect)
            if let text {
                text.draw(
                    at: NSPoint(x: iconSide + spacing, y: (iconSide - textSize.height) / 2),
                    withAttributes: attributes
                )
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

enum TimeFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func menuMinutes(_ seconds: TimeInterval) -> String {
        String(MenuClock.minutes(seconds))
    }

    static func span(_ seconds: TimeInterval) -> String {
        TimeSpan.text(seconds)
    }
}
