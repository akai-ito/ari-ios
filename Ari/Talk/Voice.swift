#if os(iOS)
    import AVFoundation
    import AriKit
    import os

    /// Ari's voice on a call: the server's voice, a sentence at a time. Each sentence is fetched
    /// while the one before plays, so there's no gap between them. It plays through the call's own
    /// audio engine, so echo cancellation keeps Ari from hearing itself, and you can talk over it.
    /// There's no other voice: if the server can't speak, the call ends and says why.
    final class Voice {
        /// The sentence playing, if any.
        var current: String? { playing.first }
        var isSpeaking: Bool { !queue.isEmpty || fetching || !playing.isEmpty }
        /// Called when the last queued sentence has played.
        var finished: () -> Void = {}
        /// Called when the server couldn't say a sentence, with why.
        var failed: (RequestError) -> Void = { _ in }

        /// The server's voice: 24 kHz mono. The player is connected at it.
        static let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let format = Voice.format

        private let player: AVAudioPlayerNode
        private let speak: (String) async throws(RequestError) -> Data
        private let speaker: Speaker
        private var queue: [String] = []
        private var fetching = false
        private var playing: [String] = []
        /// Bumped by every stop, so a sentence fetched or played for an older one is dropped.
        private var generation = 0
        private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "talk")

        init(
            player: AVAudioPlayerNode, speak: @escaping (String) async throws(RequestError) -> Data
        ) {
            self.player = player
            self.speak = speak
            speaker = Speaker(player: player)
        }

        func say(_ sentence: String) {
            let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return }
            queue.append(sentence)
            fetchNext()
        }

        /// Stops at once, dropping what's queued: you started talking.
        func stop() {
            generation += 1
            queue = []
            fetching = false
            playing = []
            // A player whose engine has gone can't be touched at all.
            guard player.engine != nil else { return }
            player.stop()
            player.play()
        }

        /// Fetches the next sentence and schedules it, then the one after, while it plays.
        private func fetchNext() {
            guard !fetching, !queue.isEmpty else { return }
            fetching = true
            let sentence = queue.removeFirst()
            let mine = generation
            Task {
                let buffer: AVAudioPCMBuffer
                do throws(RequestError) {
                    buffer = try Self.decode(try await speak(sentence))
                } catch {
                    guard mine == generation else { return }
                    Self.log.error("The server's voice failed: \(error, privacy: .public)")
                    stop()
                    failed(error)
                    return
                }
                guard mine == generation else { return }
                fetching = false
                if player.engine != nil {
                    playing.append(sentence)
                    speaker.schedule(buffer) {
                        Task { @MainActor in self.played(mine) }
                    }
                }
                fetchNext()
                if !isSpeaking { finished() }
            }
        }

        private func played(_ mine: Int) {
            guard mine == generation, !playing.isEmpty else { return }
            playing.removeFirst()
            if !isSpeaking { finished() }
        }

        /// A WAV from the server as audio the player takes.
        private static func decode(_ wav: Data) throws(RequestError) -> AVAudioPCMBuffer {
            let url = FileManager.default.temporaryDirectory.appending(
                path: "voice-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            guard (try? wav.write(to: url)) != nil,
                let file = try? AVAudioFile(
                    forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                file.processingFormat.sampleRate == format.sampleRate,
                file.processingFormat.channelCount == 1,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                (try? file.read(into: buffer)) != nil
            else {
                throw .unreadable("The server's voice couldn't be played.")
            }
            return buffer
        }
    }

    /// Schedules a sentence's audio on the player, off the main actor, since the player calls back
    /// on its own thread.
    nonisolated private final class Speaker: @unchecked Sendable {
        private let player: AVAudioPlayerNode

        init(player: AVAudioPlayerNode) {
            self.player = player
        }

        /// `done` runs once the sentence has played.
        func schedule(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) {
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in done() }
        }
    }
#endif
