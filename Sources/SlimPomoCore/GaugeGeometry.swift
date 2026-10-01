import Foundation

/// Depth gauge "tank" geometry in a 24 × 24 viewBox, drawn at 20 pt. Y runs down, as in the reference SVG.
public enum GaugeGeometry {
    public static let viewBox = 24.0
    public static let center = 12.0
    public static let radius = 9.5
    public static let ringWidth = 1.5
    public static let crestWidth = 1.3
    /// Wave height above and below the mean line.
    public static let amplitude = 1.4
    public static let wavelength = 12.0
    /// The wave is centered on a crest at this x, so crests sit at 6 and 18.
    public static let crestX = 6.0
    /// Water line at 100% and at 0%: the inside edge of the ring.
    public static let yFull = 3.25
    public static let yEmpty = 20.75
    public static let sampleStep = 0.2
    /// Seconds for the running task's wave to drift one wavelength.
    public static let driftSeconds = 3.0

    /// `y = 20.75 − level × 17.5`
    public static func meanY(level: Double) -> Double {
        let clamped = min(max(level, 0), 1)
        return yEmpty - clamped * (yEmpty - yFull)
    }

    /// `y(x) = mean − 1.4 · cos(2π (x − 6) / 12)`
    public static func waveY(x: Double, mean: Double) -> Double {
        mean - amplitude * cos(2 * Double.pi * (x - crestX) / wavelength)
    }

    /// Points along the wave from `start` to `end`, at most `sampleStep` apart.
    public static func samples(mean: Double, from start: Double, to end: Double) -> [(x: Double, y: Double)] {
        guard end > start else { return [] }
        let steps = Int(((end - start) / sampleStep).rounded(.up))
        return (0...steps).map { index in
            let x = min(end, start + Double(index) * sampleStep)
            return (x, waveY(x: x, mean: mean))
        }
    }
}
