#if os(iOS)
    import AVFoundation
    import Synchronization

    /// Ari's voice on a call: Apple's best on-device voice, a sentence at a time. It plays through
    /// the call's own audio engine rather than the system's speech output, so echo cancellation
    /// keeps Ari from hearing itself, and you can talk over it.
    final class Voice {
        /// The sentence playing, if any.
        private(set) var current: String?
        var isSpeaking: Bool { current != nil || !queue.isEmpty }
        /// Called when the last queued sentence has played.
        var finished: () -> Void = {}

        private let synthesizer = AVSpeechSynthesizer()
        private let player: AVAudioPlayerNode
        private let speaker: Speaker
        private let voice: AVSpeechSynthesisVoice?
        private var queue: [String] = []

        /// The format the player is connected with.
        let format: AVAudioFormat

        init(player: AVAudioPlayerNode) {
            self.player = player
            voice = Self.best()
            let rate = (voice?.audioFileSettings[AVSampleRateKey] as? Double) ?? 22_050
            format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            speaker = Speaker(player: player, format: format)
        }

        /// The best voice for this phone's language: premium, then enhanced, then any, preferring
        /// its region.
        static func best(for locale: Locale = .current) -> AVSpeechSynthesisVoice? {
            let language = locale.language.languageCode?.identifier ?? "en"
            let region = locale.region?.identifier
            let voices = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice)
            }
            return voices.max { a, b in
                score(a, region: region) < score(b, region: region)
            }
        }

        private static func score(_ voice: AVSpeechSynthesisVoice, region: String?) -> Int {
            let quality =
                switch voice.quality {
                case .premium: 30
                case .enhanced: 20
                default: 0
                }
            let local = region.map { voice.language.hasSuffix($0) } == true ? 5 : 0
            return quality + local
        }

        func say(_ sentence: String) {
            let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return }
            queue.append(sentence)
            if current == nil { next() }
        }

        /// Stops at once, dropping what's queued: you started talking.
        func stop() {
            queue = []
            current = nil
            speaker.cancel()
            synthesizer.stopSpeaking(at: .immediate)
            // A player whose engine has gone can't be touched at all.
            guard player.engine != nil else { return }
            player.stop()
            player.play()
        }

        private func next() {
            guard !queue.isEmpty else {
                current = nil
                finished()
                return
            }
            let sentence = queue.removeFirst()
            current = sentence
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            let take = speaker.begin { [weak self] in
                Task { @MainActor in
                    guard let self, self.current == sentence else { return }
                    self.next()
                }
            }
            synthesizer.write(utterance, toBufferCallback: take)
        }
    }

    nonisolated private final class Sentence: @unchecked Sendable {
        var resampler: Resampler?
    }

    /// Schedules synthesised audio on the player as it arrives, off the main actor.
    nonisolated private final class Speaker: @unchecked Sendable {
        private let player: AVAudioPlayerNode
        private let format: AVAudioFormat
        /// Bumped by every sentence and every stop, so audio from an older one is dropped.
        private let generation = Mutex(0)

        init(player: AVAudioPlayerNode, format: AVAudioFormat) {
            self.player = player
            self.format = format
        }

        func cancel() {
            generation.withLock { $0 += 1 }
        }

        /// A callback for one sentence's audio; `done` runs once it has all played.
        func begin(done: @escaping @Sendable () -> Void) -> @Sendable (AVAudioBuffer) -> Void {
            let mine = generation.withLock { generation in
                generation += 1
                return generation
            }
            let sentence = Sentence()
            return { [self] buffer in
                guard generation.withLock({ $0 == mine }),
                    let pcm = buffer as? AVAudioPCMBuffer
                else { return }
                guard pcm.frameLength > 0 else {
                    // The end of the sentence: say so once what's scheduled has played.
                    let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
                    silence.frameLength = 1
                    player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack) { _ in
                        done()
                    }
                    return
                }
                // One sentence's audio arrives in order, on one queue.
                let converter = sentence.resampler ?? Resampler(from: pcm.format, to: format)
                sentence.resampler = converter
                if let converted = converter.convert(pcm) { player.scheduleBuffer(converted) }
            }
        }
    }
#endif
