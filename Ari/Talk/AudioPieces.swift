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
            let given = Given()
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                let first = !given.value
                given.value = true
                status.pointee = first ? .haveData : .noDataNow
                return first ? buffer : nil
            }
            return error == nil && converted.frameLength > 0 ? converted : nil
        }
    }

    /// Whether the converter has had its buffer, within one synchronous conversion.
    nonisolated private final class Given: @unchecked Sendable {
        var value = false
    }

    /// What the microphone's tap does on the audio thread: feeds the recogniser and writes your
    /// turn's recording. The call swaps the recording between turns from the main actor.
    nonisolated final class MicrophoneTap: @unchecked Sendable {
        private struct State {
            var recording: AVAudioFile?
            var muted = false
        }

        private let state = Mutex(State())
        private let input: AsyncStream<AnalyzerInput>.Continuation
        private let resampler: Resampler

        init(input: AsyncStream<AnalyzerInput>.Continuation, resampler: Resampler) {
            self.input = input
            self.resampler = resampler
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
            let recording = state.withLock { $0.muted ? nil : Optional($0.recording) }
            guard let recording else {
                // Muted: the recogniser hears silence, so it isn't left waiting mid-word.
                if let silent = AVAudioPCMBuffer(
                    pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
                {
                    silent.frameLength = buffer.frameLength
                    feed(silent)
                }
                return
            }
            try? recording?.write(from: buffer)
            feed(buffer)
        }

        private func feed(_ buffer: AVAudioPCMBuffer) {
            if let converted = resampler.convert(buffer) {
                input.yield(AnalyzerInput(buffer: converted))
            }
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
