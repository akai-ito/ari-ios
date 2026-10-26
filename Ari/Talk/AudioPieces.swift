#if os(iOS)
    import AVFoundation
    import Speech
    import Synchronization

    /// Converts audio from one format to another, such as the microphone's to the recogniser's.
    nonisolated final class Resampler: @unchecked Sendable {
        let output: AVAudioFormat
        private let converter: AVAudioConverter?

        init(from input: AVAudioFormat, to output: AVAudioFormat) {
            self.output = output
            converter = input == output ? nil : AVAudioConverter(from: input, to: output)
        }

        func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let converter else { return buffer }
            let ratio = output.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity)
            else { return nil }
            // The converter asks for input until told there's no more for now: this buffer, once.
            // It asks within this call, on this thread, so the buffer is never shared.
            let given = Given()
            nonisolated(unsafe) let input = buffer
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                let first = !given.value
                given.value = true
                status.pointee = first ? .haveData : .noDataNow
                return first ? input : nil
            }
            return error == nil && converted.frameLength > 0 ? converted : nil
        }
    }

    /// Whether the converter has had its buffer, within one synchronous conversion.
    nonisolated private final class Given: @unchecked Sendable {
        var value = false
    }

    /// What the microphone's tap does on the audio thread: feeds the recogniser and writes your
    /// turn's recording, in mono. The call swaps the recording between turns from the main actor.
    nonisolated final class MicrophoneTap: @unchecked Sendable {
        private struct State {
            var recording: AVAudioFile?
            var muted = false
        }

        /// What the tap has seen, for saying why Ari hears nothing.
        struct Counts: Sendable {
            var buffers = 0
            var fed = 0
            var failed = 0
            /// The loudest sample in the last second or so, 0 to 1.
            var peak: Float = 0
        }

        private let state = Mutex(State())
        private let counted = Mutex(Counts())
        private let input: AsyncStream<AnalyzerInput>.Continuation
        private let resampler: Resampler
        /// The microphone's sample rate in one channel: with echo cancellation on, some iPhones
        /// report several channels, and converting those straight to the recogniser's one fails.
        let mono: AVAudioFormat

        init(
            input: AsyncStream<AnalyzerInput>.Continuation, microphone: AVAudioFormat,
            recogniser: AVAudioFormat
        ) {
            self.input = input
            mono = AVAudioFormat(standardFormatWithSampleRate: microphone.sampleRate, channels: 1)!
            resampler = Resampler(from: mono, to: recogniser)
        }

        /// What the tap has seen so far; the peak starts again.
        func counts() -> Counts {
            counted.withLock { counts in
                defer { counts.peak = 0 }
                return counts
            }
        }

        var muted: Bool {
            get { state.withLock(\.muted) }
            set { state.withLock { $0.muted = newValue } }
        }

        /// Starts a new recording, returning the one it replaces, now closed.
        func record(to file: AVAudioFile?) -> AVAudioFile? {
            state.withLock { state in
                defer { state.recording = file }
                return state.recording
            }
        }

        func take(_ buffer: AVAudioPCMBuffer) {
            guard let mono = firstChannel(of: buffer) else {
                counted.withLock { $0.failed += 1 }
                return
            }
            let (muted, recording) = state.withLock { ($0.muted, $0.recording) }
            if muted {
                // The recogniser hears silence, so it isn't left waiting mid-word.
                if let channel = mono.floatChannelData?[0] {
                    channel.update(repeating: 0, count: Int(mono.frameLength))
                }
            } else {
                try? recording?.write(from: mono)
            }
            feed(mono)
        }

        /// The buffer's first channel, as a buffer of its own in `mono`.
        private func firstChannel(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let source = buffer.floatChannelData?[0],
                let mono = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
                let target = mono.floatChannelData?[0]
            else { return nil }
            let frames = Int(buffer.frameLength)
            let stride = buffer.stride
            var peak: Float = 0
            for frame in 0..<frames {
                let sample = source[frame * stride]
                target[frame] = sample
                peak = max(peak, abs(sample))
            }
            mono.frameLength = buffer.frameLength
            counted.withLock { counts in
                counts.buffers += 1
                counts.peak = max(counts.peak, peak)
            }
            return mono
        }

        private func feed(_ buffer: AVAudioPCMBuffer) {
            guard let converted = resampler.convert(buffer) else {
                counted.withLock { $0.failed += 1 }
                return
            }
            input.yield(AnalyzerInput(buffer: converted))
            counted.withLock { $0.fed += 1 }
        }

        func finish() {
            input.finish()
        }

        /// The block for the input node's tap, made off the main actor: the audio thread calls it.
        func block() -> AVAudioNodeTapBlock {
            { [self] buffer, _ in take(buffer) }
        }
    }

    /// A short, soft two-note tone for the gaps while Ari works, so silence never sounds like a
    /// dropped call.
    nonisolated enum WorkingTone {
        static func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            let rate = format.sampleRate
            let notes: [(frequency: Double, seconds: Double)] = [(587.33, 0.16), (880, 0.22)]
            let frames = AVAudioFrameCount(notes.reduce(0) { $0 + $1.seconds } * rate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                let channels = buffer.floatChannelData
            else { return nil }
            buffer.frameLength = frames
            var frame = 0
            for note in notes {
                let count = Int(note.seconds * rate)
                for index in 0..<count {
                    let t = Double(index) / rate
                    // A gentle rise and a longer fall, quiet under speech.
                    let envelope = min(1, t / 0.02) * exp(-t * 9)
                    let sample = Float(0.08 * envelope * sin(2 * .pi * note.frequency * t))
                    for channel in 0..<Int(format.channelCount) {
                        channels[channel][frame + index] = sample
                    }
                }
                frame += count
            }
            return buffer
        }
    }
#endif
