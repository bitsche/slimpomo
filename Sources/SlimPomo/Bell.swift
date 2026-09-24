import AppKit
import SlimPomoCore

@MainActor
final class Bell {
    private let workDone: NSSound?
    private let breakOver: NSSound?

    init() {
        workDone = Self.load("kalimba-work-done-short")
        breakOver = Self.load("kalimba-break-over-short")
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
              let sound = NSSound(contentsOf: url, byReference: true) else {
            fputs("SlimPomo: unable to load \(name).wav\n", stderr)
            return nil
        }
        sound.volume = 0.9
        return sound
    }
}
