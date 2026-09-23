import AppKit
import SwiftUI
import SlimPomoCore

struct MenuBarLabel: View {
    var model: AppModel

    var body: some View {
        if model.session.phase == .idle {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .medium))
                .accessibilityLabel("SlimPomo")
        } else {
            HStack(spacing: 5) {
                Image(nsImage: ringImage(
                    fraction: model.session.elapsedFraction(at: model.now),
                    paused: !model.session.isRunning,
                    showsSmile: model.session.phase == .breakTime && model.session.isRunning
                ))
                .frame(width: Self.iconSide, height: Self.iconSide)
                .accessibilityHidden(true)
                Text(TimeFormat.menuMinutes(model.session.displayedRemaining(at: model.now)))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
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

    /// Fills the menu bar. 16pt leaves the face only a few pixels tall at 1x.
    private static let iconSide: CGFloat = 22

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

        func eye(dx: CGFloat) {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: center.x + dx * scale + (dx < 0 ? -0.5 : 0.5), y: center.y + 0.2 * scale + 1.5),
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
            withCenter: NSPoint(x: center.x, y: center.y + 0.7 * scale - 1.5),
            radius: 2.45 * scale,
            startAngle: 215,
            endAngle: 325,
            clockwise: false
        )
        smile.lineWidth = 1.3 * scale
        smile.lineCapStyle = .round
        smile.stroke()
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
