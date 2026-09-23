import Foundation

public enum Chime {
    public static func wavData() -> Data {
        let sampleRate = 44_100
        let duration = 0.85
        let count = Int(duration * Double(sampleRate))
        var samples = [Int16]()
        samples.reserveCapacity(count)

        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            let sample = 0.55 * tone(880, time, start: 0, decay: 4.2)
                + 0.20 * tone(1_760, time, start: 0, decay: 6.5)
                + 0.42 * tone(1_174.7, time, start: 0.16, decay: 4.0)
                + 0.14 * tone(2_349.3, time, start: 0.16, decay: 6.2)
            let clamped = max(-1, min(1, sample))
            samples.append(Int16(clamped * 32_000))
        }

        return wav(samples: samples, sampleRate: sampleRate)
    }

    private static func tone(_ frequency: Double, _ time: Double, start: Double, decay: Double) -> Double {
        let local = time - start
        guard local >= 0 else { return 0 }
        let attack = min(1, local / 0.006)
        return sin(2 * Double.pi * frequency * local) * attack * exp(-decay * local)
    }

    private static func wav(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + dataSize)
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * 2))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLE(UInt32(dataSize))
        for sample in samples {
            data.appendLE(sample)
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
