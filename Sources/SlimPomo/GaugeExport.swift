#if SLIMPOMO_DEV
import AppKit
import SlimPomoCore

/// Writes the depth gauges as PNGs, at 1× (20 px) and 2× (40 px), so they can be compared with the reference images.
/// `muted` is the Dive gauge at the 60% a Done or History row uses.
enum GaugeExport {
    static let gauges: [(name: String, intensity: Intensity, opacity: CGFloat)] = [
        ("dip", .regular, 1),
        ("dive", .focus, 1),
        ("deep", .intense, 1),
        ("muted", .focus, 0.6),
    ]

    static func render(intensity: Intensity, opacity: CGFloat, pixels: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let scale = CGFloat(pixels) / CGFloat(GaugeGeometry.viewBox)
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        TankGaugeArt.draw(intensity: intensity, opacity: opacity, in: ctx)
        return ctx.makeImage()
    }

    /// Returns true when this launch is an export. The process exits when it is done.
    static func performIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-exportGauges"), index + 1 < args.count else { return false }
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for gauge in gauges {
                for scale in [1, 2] {
                    guard let image = render(intensity: gauge.intensity, opacity: gauge.opacity, pixels: 20 * scale),
                          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    else {
                        fputs("Could not render \(gauge.name)\n", stderr)
                        exit(1)
                    }
                    let suffix = scale == 2 ? "@2x" : ""
                    try data.write(to: directory.appendingPathComponent("gauge-C-tank-\(gauge.name)\(suffix).png"))
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
