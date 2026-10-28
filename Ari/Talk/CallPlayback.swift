#if os(iOS)
    import AVFoundation

    /// Ari's voice on a call, as the server streams it: each sentence's audio plays as it arrives,
    /// through the call's own audio engine, so echo cancellation keeps Ari from hearing itself.
    /// The server hears when each sentence has finished, or was cut because you talked over it.
    final class CallPlayback {
        /// The server's voice: 16-bit PCM, mono, 24 kHz. The player is connected at it, as floats.
        static let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

        /// A sentence finished playing, or was cut.
        var played: (_ id: String, _ cut: Bool) -> Void = { _, _ in }
        /// Whether any of Ari's voice is still to play.
        var isPlaying: Bool { !scheduled.isEmpty }

        private let player: AVAudioPlayerNode
        private let scheduler: Scheduler
        /// The sentence whose audio is arriving now.
        private var arriving: String?
        /// Sentences with audio scheduled and not yet played, in order.
        private var scheduled: [String] = []
        /// Bumped by every stop, so a sentence cut by it doesn't also report playing.
        private var generation = 0

        init(player: AVAudioPlayerNode) {
            self.player = player
            scheduler = Scheduler(player: player)
        }

        /// The server is about to send the sentence `id`: the one before is complete.
        func begin(_ id: String) {
            close()
            arriving = id
            scheduled.append(id)
        }

        /// Audio for the sentence arriving now.
        func append(_ pcm: Data) {
            guard arriving != nil, player.engine != nil, let buffer = Self.buffer(pcm) else {
                return
            }
            scheduler.schedule(buffer, done: nil)
        }

        /// No more audio is coming for the sentence arriving now, such as when Ari stops speaking:
        /// it reports once it has played.
        func close() {
            guard let id = arriving else { return }
            arriving = nil
            let mine = generation
            guard player.engine != nil else { return }
            let silence = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: 1)!
            silence.frameLength = 1
            scheduler.schedule(silence) {
                Task { @MainActor in
                    guard mine == self.generation, let index = self.scheduled.firstIndex(of: id)
                    else { return }
                    self.scheduled.remove(at: index)
                    self.played(id, false)
                }
            }
        }

        /// You talked over Ari: everything queued goes at once, and the server hears which
        /// sentences were cut.
        func stop() {
            generation += 1
            arriving = nil
            let cut = scheduled
            scheduled = []
            if player.engine != nil {
                player.stop()
                player.play()
            }
            for id in cut { played(id, true) }
        }

        /// 16-bit PCM, little-endian, as floats the player takes.
        private static func buffer(_ pcm: Data) -> AVAudioPCMBuffer? {
            let count = pcm.count / 2
            guard count > 0,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                let channel = buffer.floatChannelData?[0]
            else { return nil }
            pcm.withUnsafeBytes { raw in
                for index in 0..<count {
                    let sample = Int16(
                        littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                    channel[index] = Float(sample) / 32_768
                }
            }
            buffer.frameLength = AVAudioFrameCount(count)
            return buffer
        }
    }

    /// Schedules audio on the player, off the main actor, since the player calls back on its own
    /// thread.
    nonisolated private final class Scheduler: @unchecked Sendable {
        private let player: AVAudioPlayerNode

        init(player: AVAudioPlayerNode) {
            self.player = player
        }

        /// `done`, if any, runs once the buffer has played.
        func schedule(_ buffer: AVAudioPCMBuffer, done: (@Sendable () -> Void)?) {
            guard let done else { return player.scheduleBuffer(buffer) }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in done() }
        }
    }
#endif
