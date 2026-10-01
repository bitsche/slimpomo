import AppKit
import Foundation

let states = [
    "idle",
    "work-running-10",
    "work-running-45",
    "work-running-90",
    "work-paused-45",
    "break-running-05",
    "break-running-50",
    "break-running-95",
    "break-paused-50",
]

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift scripts/compare-icons.swift <exported-dir> [reference-dir]\n", stderr)
    exit(2)
}

let exported = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let reference: URL
if CommandLine.arguments.count >= 3 {
    reference = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
} else {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    reference = root.appendingPathComponent("menubar-reference/png", isDirectory: true)
}

func alphas(at url: URL) -> (width: Int, height: Int, values: [UInt8])? {
    guard let data = try? Data(contentsOf: url),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var values = [UInt8]()
    values.reserveCapacity(width * height)
    var index = 3
    while index < bytes.count {
        values.append(bytes[index])
        index += 4
    }
    return (width, height, values)
}

var failed = false
for state in states {
    for suffix in ["", "@2x"] {
        let name = "menubar-\(state)\(suffix).png"
        let leftURL = exported.appendingPathComponent(name)
        let rightURL = reference.appendingPathComponent(name)
        guard let left = alphas(at: leftURL), let right = alphas(at: rightURL) else {
            print("\(state)\(suffix)  missing image")
            failed = true
            continue
        }
        guard left.width == right.width, left.height == right.height, left.values.count == right.values.count else {
            print("\(state)\(suffix)  size \(left.width)×\(left.height) vs \(right.width)×\(right.height)")
            failed = true
            continue
        }
        var total = 0.0
        var maxDelta = 0.0
        for pair in zip(left.values, right.values) {
            let delta = abs(Double(pair.0) - Double(pair.1)) / 255
            total += delta
            if delta > maxDelta { maxDelta = delta }
        }
        let mean = total / Double(left.values.count)
        let pass = mean <= 0.03 && maxDelta <= 0.25
        if !pass { failed = true }
        let mark = pass ? "pass" : "FAIL"
        print(String(format: "%@%@  mean %.2f%%  max %.2f%%  %@", state, suffix, mean * 100, maxDelta * 100, mark))
    }
}

exit(failed ? 1 : 0)
