import AppKit

/// Menu-bar tank drawn from the reference SVG paths. Coordinates are SVG (y down).
enum MenuBarGlyph {
    static let side: CGFloat = 18
    /// `y = 13.25 − 7.8 × level`, the reference water line.
    static let waterTravel: CGFloat = 7.8

    static func waterY(_ level: Double) -> CGFloat {
        let t = CGFloat(min(1, max(0, level)))
        return 13.25 - waterTravel * t
    }

    /// Redraw steps of 0.5 pt along the water line.
    static func waterStep(_ fraction: Double) -> Int {
        let pt = CGFloat(min(1, max(0, fraction))) * waterTravel
        return Int((pt / 0.5).rounded(.down))
    }

    static func render(kind: MenuBarIconKey.Kind, level: Double, color: NSColor, pixels: Int) -> CGImage? {
        let width = pixels
        let height = pixels
        let scale = CGFloat(pixels) / side
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(kind: kind, level: level, color: color, in: ctx)
        return ctx.makeImage()
    }

    static func image(kind: MenuBarIconKey.Kind, level: Double, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        for pixels in [Int(side), Int(side) * 2] {
            guard let cg = render(kind: kind, level: level, color: color, pixels: pixels) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: side, height: side)
            image.addRepresentation(rep)
        }
        return image
    }

    static func pngData(kind: MenuBarIconKey.Kind, level: Double, pixels: Int) -> Data? {
        guard let cg = render(kind: kind, level: level, color: .black, pixels: pixels) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(kind: MenuBarIconKey.Kind, level: Double, color: NSColor, in ctx: CGContext) {
        let ink = color.cgColor
        switch kind {
        case .idle:
            strokeTank(ink, in: ctx)
            stroke(SVGPath.path("M4 12.5 q1.25 -1.2 2.5 0 t2.5 0 t2.5 0 t2.5 0"), width: 1.5, color: ink, in: ctx)
        case .work, .workPaused:
            let alpha: CGFloat = kind == .workPaused ? 0.40 : 1
            fillWater(level: level, alpha: alpha, color: color, in: ctx)
            strokeTank(ink, in: ctx)
            if kind == .workPaused {
                stroke(SVGPath.path("M7 6 V12 M11 6 V12"), width: 1.8, color: ink, in: ctx)
            }
        case .breakRunning:
            fill(SVGPath.path("M5.5 10.5 a3.5 3.5 0 0 1 7 0Z"), color: ink, in: ctx)
            stroke(SVGPath.path("M2.5 13.5 q1.6 -1.3 3.2 0 t3.2 0 t3.2 0 t3.2 0"), width: 1.5, color: ink, in: ctx)
        case .breakPaused:
            stroke(SVGPath.path("M2.5 13.5 q1.6 -1.3 3.2 0 t3.2 0 t3.2 0 t3.2 0"), width: 1.5, color: ink, in: ctx)
            stroke(SVGPath.path("M7 4.5 V10.5 M11 4.5 V10.5"), width: 1.8, color: ink, in: ctx)
        }
    }

    private static func strokeTank(_ color: CGColor, in ctx: CGContext) {
        stroke(tankPath(), width: 1.5, color: color, in: ctx)
    }

    private static func fillWater(level: Double, alpha: CGFloat, color: NSColor, in ctx: CGContext) {
        let y = waterY(level)
        let text = String(format: "M0 %.4f q2 -1.4 4 0 t4 0 t4 0 t4 0 t4 0 V18 H0Z", y)
        ctx.saveGState()
        ctx.addPath(tankPath())
        ctx.clip()
        fill(SVGPath.path(text), color: color.withAlphaComponent(alpha).cgColor, in: ctx)
        ctx.restoreGState()
    }

    private static func tankPath() -> CGPath {
        CGPath(roundedRect: CGRect(x: 2.5, y: 2.5, width: 13, height: 13), cornerWidth: 3, cornerHeight: 3, transform: nil)
    }

    private static func fill(_ path: CGPath, color: CGColor, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
}

/// The SVG path commands the reference icons use: M, q, t, V, H, Z, a.
enum SVGPath {
    static func path(_ d: String) -> CGPath {
        let chars = Array(d)
        var index = 0
        let built = CGMutablePath()
        var command: Character = " "
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl = CGPoint.zero
        var prevQuad = false

        func skip() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" {
                index += 1
            }
        }

        func readNumber() -> CGFloat? {
            skip()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter { return nil }
            var end = index
            if chars[end] == "+" || chars[end] == "-" { end += 1 }
            var dotted = false
            var sawDigit = false
            while end < chars.count {
                let ch = chars[end]
                if ch.isNumber {
                    sawDigit = true
                    end += 1
                } else if ch == ".", !dotted {
                    dotted = true
                    end += 1
                } else {
                    break
                }
            }
            guard sawDigit, end > index else { return nil }
            let text = String(chars[index..<end])
            index = end
            return CGFloat(Double(text) ?? 0)
        }

        while index < chars.count {
            skip()
            guard index < chars.count else { break }
            if chars[index].isLetter {
                command = chars[index]
                index += 1
            }
            switch command {
            case "M":
                guard let x = readNumber(), let y = readNumber() else { return built }
                current = CGPoint(x: x, y: y)
                start = current
                built.move(to: current)
                command = "L"
                prevQuad = false
            case "L":
                guard let x = readNumber(), let y = readNumber() else { return built }
                current = CGPoint(x: x, y: y)
                built.addLine(to: current)
                prevQuad = false
            case "q":
                guard let dx1 = readNumber(), let dy1 = readNumber(), let dx = readNumber(), let dy = readNumber() else { return built }
                let control = CGPoint(x: current.x + dx1, y: current.y + dy1)
                let end = CGPoint(x: current.x + dx, y: current.y + dy)
                built.addQuadCurve(to: end, control: control)
                lastControl = control
                current = end
                prevQuad = true
            case "t":
                guard let dx = readNumber(), let dy = readNumber() else { return built }
                let end = CGPoint(x: current.x + dx, y: current.y + dy)
                let control = prevQuad
                    ? CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
                    : current
                built.addQuadCurve(to: end, control: control)
                lastControl = control
                current = end
                prevQuad = true
            case "V":
                guard let y = readNumber() else { return built }
                current.y = y
                built.addLine(to: current)
                prevQuad = false
            case "H":
                guard let x = readNumber() else { return built }
                current.x = x
                built.addLine(to: current)
                prevQuad = false
            case "Z", "z":
                built.closeSubpath()
                current = start
                prevQuad = false
                command = " "
            case "a":
                guard let rx = readNumber(), let ry = readNumber(),
                      readNumber() != nil,
                      let large = readNumber(), let sweep = readNumber(),
                      let dx = readNumber(), let dy = readNumber() else { return built }
                let end = CGPoint(x: current.x + dx, y: current.y + dy)
                addArc(built, from: current, to: end, rx: rx, ry: ry, large: large != 0, sweep: sweep != 0)
                current = end
                prevQuad = false
            default:
                return built
            }
        }
        return built
    }

    /// SVG endpoint-to-center arc, sampled so the raster matches the reference.
    private static func addArc(
        _ path: CGMutablePath,
        from: CGPoint,
        to: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        large: Bool,
        sweep: Bool
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, from != to else {
            path.addLine(to: to)
            return
        }
        let dx = (from.x - to.x) / 2
        let dy = (from.y - to.y) / 2
        var x1p = dx
        var y1p = dy
        var lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lam > 1 {
            let s = sqrt(lam)
            rx *= s
            ry *= s
            lam = 1
        }
        let sign: CGFloat = (large == sweep) ? -1 : 1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = sign * sqrt(den == 0 ? 0 : num / den)
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cxp + (from.x + to.x) / 2
        let cy = cyp + (from.y + to.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(min(1, max(-1, len == 0 ? 0 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, dtheta > 0 { dtheta -= 2 * .pi }
        if sweep, dtheta < 0 { dtheta += 2 * .pi }
        let steps = max(8, Int(ceil(abs(dtheta) / (2 * .pi) * 48)))
        for step in 1...steps {
            let t = theta1 + dtheta * CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t)))
        }
    }
}

#if SLIMPOMO_DEV
enum MenuBarGlyphExport {
    static let states: [(name: String, kind: MenuBarIconKey.Kind, level: Double)] = [
        ("idle", .idle, 0),
        ("work-running-10", .work, 0.10),
        ("work-running-45", .work, 0.45),
        ("work-running-90", .work, 0.90),
        ("work-paused-45", .workPaused, 0.45),
        ("break-running", .breakRunning, 0),
        ("break-paused", .breakPaused, 0),
    ]

    /// Writes each reference state at 1× and 2×, then exits. Returns true when this launch is an export.
    static func performIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-exportMenuBarIcons"), index + 1 < args.count else { return false }
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for state in states {
                for scale in [1, 2] {
                    let pixels = Int(MenuBarGlyph.side) * scale
                    guard let data = MenuBarGlyph.pngData(kind: state.kind, level: state.level, pixels: pixels) else {
                        fputs("Could not render \(state.name)\n", stderr)
                        exit(1)
                    }
                    let suffix = scale == 2 ? "@2x" : ""
                    let url = directory.appendingPathComponent("menubar-\(state.name)\(suffix).png")
                    try data.write(to: url)
                }
            }
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
        exit(0)
    }
}
#endif
