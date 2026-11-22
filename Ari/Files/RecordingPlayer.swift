import AVFoundation
import AriKit
import Observation

/// Plays a recording from your server: the copy this phone sent, or one downloaded once. It says
/// where it is, for the transcript to light the line being said.
@Observable
final class RecordingPlayer {
    enum State: Equatable {
        case fetching
        case ready
        /// Why it can't play, such as the audio having been deleted.
        case unavailable(String)
    }

    private(set) var state = State.fetching
    private(set) var isPlaying = false
    /// Seconds from the start.
    private(set) var time = 0.0
    private(set) var duration = 0.0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var ended: (any NSObjectProtocol)?
    /// Where to start once it's ready, from a moment Kumo quoted.
    @ObservationIgnored private var pending: Double?

    var fraction: Double { duration > 0 ? min(1, time / duration) : 0 }

    func load(_ recording: Attachment, from session: Session, duration known: Double?) async {
        duration = known ?? 0
        do {
            let file = try await session.recordingFile(recording)
            let asset = AVURLAsset(
                url: file, options: [AVURLAssetOverrideMIMETypeKey: recording.mediaType])
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            self.player = player
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.time = time.seconds }
            }
            ended = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isPlaying = false }
            }
            if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
                duration = seconds
            }
            state = .ready
            if let pending {
                seek(to: pending)
                self.pending = nil
            }
        } catch {
            state = .unavailable("The audio isn't on your server any more, or couldn't be fetched.")
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        isPlaying.toggle()
    }

    /// Goes to a moment, playing or not; before the audio is here, once it is.
    func seek(to seconds: Double) {
        guard let player else {
            pending = seconds
            time = seconds
            return
        }
        time = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero,
            toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        isPlaying = false
        if let observer { player?.removeTimeObserver(observer) }
        if let ended { NotificationCenter.default.removeObserver(ended) }
        observer = nil
        ended = nil
    }
}
