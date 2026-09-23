import AppKit
import SlimPomoCore

@MainActor
final class Bell {
    private let sound: NSSound?

    init() {
        sound = NSSound(data: Chime.wavData())
        sound?.volume = 0.9
        if sound == nil {
            fputs("SlimPomo: unable to load the bell sound\n", stderr)
        }
    }

    func play() {
        guard let sound else { return }
        if sound.isPlaying {
            sound.stop()
        }
        sound.currentTime = 0
        sound.play()
    }
}
