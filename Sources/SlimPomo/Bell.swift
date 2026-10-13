import AVFoundation
import SlimPomoCore

/// Plays the work-done and break-over sounds. Starting audio can block for seconds while the output device wakes up
/// (Bluetooth headphones, a sleeping interface), so the players are loaded and driven on their own serial queue and
/// the main thread, which draws the UI, never waits for them.
final class Bell: @unchecked Sendable {
    private enum Sound: CaseIterable {
        case workDone
        case breakOver

        var file: String {
            switch self {
            case .workDone: "glow-work-done"
            case .breakOver: "glow-break-over"
            }
        }
    }

    private let queue = DispatchQueue(label: "app.slimpomo.bell", qos: .userInitiated)
    /// Touched only on `queue`.
    private var players: [Sound: AVAudioPlayer] = [:]

    init() {
        queue.async { [self] in
            for sound in Sound.allCases {
                players[sound] = Self.load(sound.file)
            }
        }
    }

    func play(_ effect: SessionEffect) {
        let sound: Sound
        switch effect {
        case .none:
            return
        case .workDone:
            sound = .workDone
        case .breakOver:
            sound = .breakOver
        }
        queue.async { [self] in
            stopAll()
            guard let player = players[sound] else { return }
            player.currentTime = 0
            player.play()
        }
    }

    func stop() {
        queue.async { [self] in
            stopAll()
        }
    }

    private func stopAll() {
        for player in players.values where player.isPlaying {
            player.stop()
        }
    }

    private static func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            fputs("Deeeep: unable to load \(name).wav\n", stderr)
            return nil
        }
        player.volume = 1
        player.prepareToPlay()
        return player
    }
}
