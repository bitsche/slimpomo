import AppKit
import SwiftUI
import SlimPomoCore

enum MenuBarTourIcon: CaseIterable {
    case idle
    case running
    case paused
    case onBreak
}

struct MenuBarLabel: View {
    var model: AppModel

    var body: some View {
        if model.session.phase == .idle {
            Image(nsImage: Self.waitingImage())
                .frame(width: Self.waitingSide, height: Self.waitingSide)
                .accessibilityLabel("SlimPomo")
        } else {
            HStack(spacing: 4) {
                Image(nsImage: Self.ringImage(
                    fraction: model.session.elapsedFraction(at: model.now),
                    paused: !model.session.isRunning,
                    showsSmile: model.session.phase == .breakTime && model.session.isRunning
                ))
                .frame(width: Self.iconSide, height: Self.iconSide)
                .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    Text("88")
                        .hidden()
                    Text(TimeFormat.menuMinutes(model.session.displayedRemaining(at: model.now)))
                }
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .accessibilityHidden(true)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        let minutes = TimeFormat.menuMinutes(model.session.displayedRemaining(at: model.now))
        let phase = model.session.phase == .breakTime ? "Break" : "Work"
        let state = model.session.isRunning ? phase : "\(phase) paused"
        return "\(state), \(minutes) minutes left"
    }

    private static let iconSide: CGFloat = 18
    /// The idle artwork is authored on a 22×22 canvas.
    private static let waitingSide: CGFloat = 22

    /// Idle menu-bar glyph, drawn from Resources/MenuBarIcon.svg as a template image.
    private static func waitingImage() -> NSImage {
        let side = waitingSide
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawMenuTomato(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let menuTomatoPaths = [
        "M11.75 3.6L11.85 1.45C11.9 0.85 12.3 0.55 12.9 0.6L13.25 0.65C13.6 0.7 13.65 1.05 13.5 1.35L13.35 3.6ZM12.3 2.8C11.2 1.8 9.8 1.35 8.55 1.65C9.05 2.9 10.5 3.7 12.3 4ZM12.8 2.8C13.9 1.8 15.3 1.35 16.55 1.65C16.05 2.9 14.6 3.7 12.8 4Z",
        "M8.79 11.53C8.2 10.39 7.42 9.04 7.42 6.5C7.42 4.2 9.65 2.85 12.55 2.85C15.45 2.85 17.68 4.2 17.68 6.5C17.68 8.07 17.38 9.19 17.02 10.08Z",
        "M4.4 13.85L16.25 11.75C17 11.65 17 14.4 16.2 14.36L4.95 16.35Z",
        "M16.88 15.79C17.31 16.28 17.68 16.85 17.68 17.7C17.68 19.95 15.55 21.4 12.55 21.4C9.55 21.4 7.42 19.95 7.42 17.7C7.42 17.62 7.42 17.54 7.43 17.46Z",
    ]

    private static func drawMenuTomato(in rect: NSRect, color: NSColor = .black) {
        color.setFill()
        for data in menuTomatoPaths {
            svgPath(data, in: rect).fill()
        }
    }

    /// Absolute M, L, C, and Z commands. SVG y points down; the image y points up.
    private static func svgPath(_ data: String, in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let tokens = svgTokens(data)
        let viewBox: CGFloat = 22
        var index = 0
        func number() -> CGFloat {
            let value = CGFloat(Double(tokens[index]) ?? 0)
            index += 1
            return value
        }
        func point() -> NSPoint {
            let x = number()
            let y = number()
            return NSPoint(
                x: rect.minX + x * rect.width / viewBox,
                y: rect.maxY - y * rect.height / viewBox
            )
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M":
                path.move(to: point())
            case "L":
                path.line(to: point())
            case "C":
                let control1 = point()
                let control2 = point()
                path.curve(to: point(), controlPoint1: control1, controlPoint2: control2)
            case "Z", "z":
                path.close()
            default:
                break
            }
        }
        return path
    }

    private static func svgTokens(_ data: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[MLCZ]|-?\d*\.?\d+"#) else { return [] }
        let range = NSRange(data.startIndex..., in: data)
        return regex.matches(in: data, range: range).compactMap { match in
            Range(match.range, in: data).map { String(data[$0]) }
        }
    }

    private static func ringImage(fraction: Double, paused: Bool, showsSmile: Bool, color: NSColor = .black) -> NSImage {
        let size = NSSize(width: iconSide, height: iconSide)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = rect.width / 16
            let line = 1.85 * scale
            let inset = rect.insetBy(dx: 1.15 * scale, dy: 1.15 * scale)
            color.withAlphaComponent(0.28).setStroke()
            let track = NSBezierPath(ovalIn: inset)
            track.lineWidth = line
            track.stroke()

            let clamped = min(1, max(0, fraction))
            if clamped >= 0.999 {
                color.setStroke()
                let full = NSBezierPath(ovalIn: inset)
                full.lineWidth = line
                full.stroke()
            } else if clamped > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: NSPoint(x: rect.midX, y: rect.midY),
                    radius: inset.width / 2,
                    startAngle: 90,
                    endAngle: 90 - (360 * clamped),
                    clockwise: true
                )
                arc.lineWidth = line
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }

            if paused {
                drawPauseBars(in: rect, scale: scale, color: color)
            } else if showsSmile {
                drawRelaxedFace(in: rect, scale: scale, color: color)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The four menu-bar states, drawn with the same paths the status item uses.
    static func tourIcon(_ kind: MenuBarTourIcon) -> NSImage {
        let color = NSColor.white
        let image: NSImage
        switch kind {
        case .idle:
            let side = waitingSide
            image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                drawMenuTomato(in: rect, color: color)
                return true
            }
        case .running:
            image = ringImage(fraction: 0.62, paused: false, showsSmile: false, color: color)
        case .paused:
            image = ringImage(fraction: 0.62, paused: true, showsSmile: false, color: color)
        case .onBreak:
            image = ringImage(fraction: 0.4, paused: false, showsSmile: true, color: color)
        }
        image.isTemplate = false
        return image
    }

    private static func drawPauseBars(in rect: NSRect, scale: CGFloat, color: NSColor = .black) {
        color.setFill()
        let barWidth = 1.7 * scale
        let barHeight = 6.4 * scale
        let gap = 1.25 * scale
        let originX = rect.midX - (barWidth * 2 + gap) / 2
        let originY = rect.midY - barHeight / 2
        for index in 0..<2 {
            let bar = NSBezierPath(
                roundedRect: NSRect(
                    x: originX + CGFloat(index) * (barWidth + gap),
                    y: originY,
                    width: barWidth,
                    height: barHeight
                ),
                xRadius: 0.7 * scale,
                yRadius: 0.7 * scale
            )
            bar.fill()
        }
    }

    private static func drawRelaxedFace(in rect: NSRect, scale: CGFloat, color: NSColor = .black) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        color.setStroke()

        let nudge = rect.width / 22
        func eye(dx: CGFloat) {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(
                    x: center.x + dx * scale + (dx < 0 ? -0.5 : 0.5) * nudge,
                    y: center.y + 0.2 * scale + 1.5 * nudge
                ),
                radius: 1.45 * scale,
                startAngle: 15,
                endAngle: 165,
                clockwise: false
            )
            path.lineWidth = 1.25 * scale
            path.lineCapStyle = .round
            path.stroke()
        }
        eye(dx: -2.05)
        eye(dx: 2.05)

        let smile = NSBezierPath()
        smile.appendArc(
            withCenter: NSPoint(x: center.x, y: center.y + 0.7 * scale - 1.5 * nudge),
            radius: 2.45 * scale,
            startAngle: 215,
            endAngle: 325,
            clockwise: false
        )
        smile.lineWidth = 1.3 * scale
        smile.lineCapStyle = .round
        smile.stroke()
    }

    /// Menu-bar image. While a timer is showing, the width stays wide enough for two digits
    /// so the icon does not shift between 20, 19, and 9.
    static func statusImage(model: AppModel) -> NSImage {
        let icon = iconSide
        let spacing: CGFloat = 4
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let digitWidth = ceil(("88" as NSString).size(withAttributes: [.font: font]).width)
        let showsCounter = model.session.phase != .idle
        let width = showsCounter ? icon + spacing + digitWidth : waitingSide
        let height = showsCounter ? icon : waitingSide
        let ring = ringImage(
            fraction: model.session.elapsedFraction(at: model.now),
            paused: !model.session.isRunning,
            showsSmile: model.session.phase == .breakTime && model.session.isRunning
        )
        ring.isTemplate = false
        let minutes = TimeFormat.menuMinutes(model.session.displayedRemaining(at: model.now)) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = minutes.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if showsCounter {
                ring.draw(in: NSRect(x: 0, y: 0, width: icon, height: icon))
                minutes.draw(
                    at: NSPoint(x: icon + spacing, y: (icon - textSize.height) / 2),
                    withAttributes: attributes
                )
            } else {
                drawMenuTomato(in: NSRect(x: 0, y: 0, width: waitingSide, height: waitingSide))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum TimeFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func menuMinutes(_ seconds: TimeInterval) -> String {
        let remaining = max(0, seconds)
        guard remaining > 0 else { return "0" }
        return String(Int((remaining / 60).rounded(.up)))
    }

    static func span(_ seconds: TimeInterval) -> String {
        TimeSpan.text(seconds)
    }
}

struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 2
    var tint: Color = .primary

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
