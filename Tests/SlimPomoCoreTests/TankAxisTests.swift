import Testing
@testable import SlimPomoCore

struct TankAxisTests {
    let height = 150.0

    @Test func levelMapsToHeightFromTheTop() {
        #expect(TankAxis.y(level: 0, height: height) == height - TankAxis.emptyInset)
        #expect(TankAxis.y(level: 1, height: height) == TankAxis.fullInset)
        let middle = (TankAxis.fullInset + (height - TankAxis.emptyInset)) / 2
        #expect(abs(TankAxis.y(level: 0.5, height: height) - middle) < 0.000_001)
        #expect(TankAxis.y(level: 0, height: height) == 142)
        #expect(TankAxis.y(level: 1, height: height) == 12)
        #expect(TankAxis.y(level: 0.5, height: height) == 77)
    }

    @Test func levelIsClampedAndRisesTowardTheTop() {
        #expect(TankAxis.y(level: -1, height: height) == TankAxis.y(level: 0, height: height))
        #expect(TankAxis.y(level: 2, height: height) == TankAxis.y(level: 1, height: height))
        #expect(TankAxis.y(level: 0.8, height: height) < TankAxis.y(level: 0.2, height: height))
    }

    @Test func fiftyMinuteSessionReachesTheMiddleTickAtTwentyFiveRemaining() {
        let total = 50.0 * 60
        func level(remaining: Double) -> Double { 1 - remaining / total }
        #expect(TankAxis.y(level: level(remaining: 25 * 60), height: height) == TankAxis.y(level: 0.5, height: height))
        #expect(TankAxis.y(level: level(remaining: 0), height: height) == TankAxis.y(level: 1, height: height))
        #expect(TankAxis.y(level: level(remaining: 9 * 60), height: height) > TankAxis.y(level: 1, height: height))
    }

    @Test func tickLevelsAreTopMiddleAndBottom() {
        #expect(TankAxis.tickLevels == [1.0, 0.5, 0.0])
    }
}
