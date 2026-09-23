import AppKit
import SwiftUI
import SlimPomoCore

struct MenuBarLabel: View {
    var model: AppModel

    var body: some View {
        if model.session.phase == .idle {
            Image(systemName: "timer")
                .font(.system(size: Self.iconSide, weight: .medium))
                .accessibilityLabel("SlimPomo")
        } else {
            HStack(spacing: 4) {
                Image(nsImage: ringImage(
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

    private func ringImage(fraction: Double, paused: Bool, showsSmile: Bool) -> NSImage {
        let size = NSSize(width: Self.iconSide, height: Self.iconSide)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = rect.width / 16
            let line = 1.85 * scale
            let inset = rect.insetBy(dx: 1.15 * scale, dy: 1.15 * scale)
            NSColor.black.withAlphaComponent(0.28).setStroke()
            let track = NSBezierPath(ovalIn: inset)
            track.lineWidth = line
            track.stroke()

            let clamped = min(1, max(0, fraction))
            if clamped >= 0.999 {
                NSColor.black.setStroke()
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
                NSColor.black.setStroke()
                arc.stroke()
            }

            if paused {
                drawPauseBars(in: rect, scale: scale)
            } else if showsSmile {
                drawRelaxedFace(in: rect, scale: scale)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawPauseBars(in rect: NSRect, scale: CGFloat) {
        NSColor.black.setFill()
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

    private func drawRelaxedFace(in rect: NSRect, scale: CGFloat) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        NSColor.black.setStroke()

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
        let width = showsCounter ? icon + spacing + digitWidth : icon
        let ring = MenuBarLabel(model: model).ringImage(
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
        let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: icon, weight: .medium))
        symbol?.isTemplate = false
        let image = NSImage(size: NSSize(width: width, height: icon), flipped: false) { _ in
            if showsCounter {
                ring.draw(in: NSRect(x: 0, y: 0, width: icon, height: icon))
                minutes.draw(
                    at: NSPoint(x: icon + spacing, y: (icon - textSize.height) / 2),
                    withAttributes: attributes
                )
            } else {
                symbol?.draw(in: NSRect(x: 0, y: 0, width: icon, height: icon))
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
        let minutes = max(0, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(remainder)m"
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
