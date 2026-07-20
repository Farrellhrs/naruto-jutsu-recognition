import AVFoundation

/// Tiny SFX player for jutsu casts.
final class SoundFX {
    static let shared = SoundFX()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
    }

    func play(_ jutsu: Jutsu) {
        guard let file = jutsu.soundFile else { return }
        if let cached = players[file] {
            cached.currentTime = 0
            cached.play()
            return
        }
        guard let url = Bundle.main.url(forResource: file, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = 0.9
        players[file] = player
        player.play()
    }
}
