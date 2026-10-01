import AppKit
import SlimPomoCore

@MainActor
final class Bell {
    private let workDone: NSSound?
    private let breakOver: NSSound?

    init() {
        workDone = Self.load("glow-work-done")
        breakOver = Self.load("glow-break-over")
    }

    func play(_ effect: SessionEffect) {
        let sound: NSSound?
        switch effect {
        case .none:
            return
        case .workDone:
            sound = workDone
        case .breakOver:
            sound = breakOver
        }
        stop()
        sound?.currentTime = 0
        sound?.play()
    }

    func stop() {
        workDone?.stop()
        breakOver?.stop()
    }

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false) else {
            fputs("Deeeep: unable to load \(name).wav\n", stderr)
            return nil
        }
        sound.volume = 1
        _ = sound.duration
        return sound
    }
}
