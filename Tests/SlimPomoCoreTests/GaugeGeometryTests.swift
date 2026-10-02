import Testing
@testable import SlimPomoCore

struct GaugeGeometryTests {
    @Test func levelMapsOntoTheInsideOfTheRing() {
        #expect(GaugeGeometry.meanY(level: 0) == 20.75)
        #expect(GaugeGeometry.meanY(level: 1) == 3.25)
        #expect(abs(GaugeGeometry.meanY(level: 0.30) - 15.5) < 1e-9)
        #expect(abs(GaugeGeometry.meanY(level: 0.55) - 11.125) < 1e-9)
        #expect(abs(GaugeGeometry.meanY(level: 0.70) - 8.5) < 1e-9)
    }

    @Test func modesUseTheTankLevels() {
        #expect(Intensity.allCases.map(\.gaugeFill) == [0.30, 0.55, 0.70])
        let means = Intensity.allCases.map { GaugeGeometry.meanY(level: $0.gaugeFill) }
        #expect(zip(means, [15.5, 11.125, 8.5]).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test func waveHasCrestsAtSixAndEighteenAndATroughBetween() {
        let mean = 10.0
        #expect(abs(GaugeGeometry.waveY(x: 6, mean: mean) - (mean - 1.4)) < 1e-9)
        #expect(abs(GaugeGeometry.waveY(x: 18, mean: mean) - (mean - 1.4)) < 1e-9)
        #expect(abs(GaugeGeometry.waveY(x: 12, mean: mean) - (mean + 1.4)) < 1e-9)
        #expect(abs(GaugeGeometry.waveY(x: 0, mean: mean) - (mean + 1.4)) < 1e-9)
    }

    @Test func driftingByOneWavelengthLooksTheSame() {
        for x in stride(from: 0.0, through: 24.0, by: 1.7) {
            let a = GaugeGeometry.waveY(x: x, mean: 8)
            let b = GaugeGeometry.waveY(x: x + GaugeGeometry.wavelength, mean: 8)
            #expect(abs(a - b) < 1e-9)
        }
    }

    @Test func samplesAreCloseEnoughAndCoverTheRange() {
        let points = GaugeGeometry.samples(mean: 0, from: -12, to: 36)
        #expect(points.first?.x == -12)
        #expect(points.last?.x == 36)
        for pair in zip(points, points.dropFirst()) {
            #expect(pair.1.x - pair.0.x <= 0.2 + 1e-9)
        }
    }
}
