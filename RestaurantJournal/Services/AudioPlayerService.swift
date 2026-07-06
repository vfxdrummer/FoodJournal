import Foundation
import AVFoundation

/// Plays back recorded voice-note audio. Shared by the recorder's review step and the visit detail.
@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// The URL currently playing, or nil when stopped — drives play/stop button state.
    @Published var playingURL: URL?

    private var player: AVAudioPlayer?

    func isPlaying(_ url: URL) -> Bool { playingURL == url }

    /// Play if idle or a different note; stop if this same note is already playing.
    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
        } else {
            play(url)
        }
    }

    func play(_ url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            playingURL = url
        } catch {
            playingURL = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingURL = nil
        }
    }
}
