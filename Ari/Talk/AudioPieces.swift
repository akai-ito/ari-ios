#if os(iOS)
    import AVFoundation
    import Synchronization

    /// Converts audio from one format to another, such as the microphone's to the stream's.
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

    /// How loud the call is right now, for Ari's dots to breathe with: your voice as you speak, and
    /// Ari's as it plays. The audio threads report; the presence reads it once a frame.
    nonisolated final class CallLevel: @unchecked Sendable {
        enum Side { case you, ari }

        private let levels = Mutex<(you: Float, ari: Float)>((0, 0))
        /// What the presence last drew: read and eased on the main thread only.
        private var shown = 0.0

        /// How loud Ari's voice is as it plays, from 0.
        var ari: Float { levels.withLock { $0.ari } }

        func report(_ side: Side, rms: Float) {
            levels.withLock { levels in
                if side == .you { levels.you = rms } else { levels.ari = rms }
            }
        }

        /// From 0 to 1, quick to rise and slow to fall, so the dots breathe rather than flicker:
        /// silence below -50 dB, full by -12.
        func breath() -> Double {
            let loudest = levels.withLock { max($0.you, $0.ari) }
            let decibels = 20 * log10(max(Double(loudest), 1e-5))
            let target = min(max((decibels + 50) / 38, 0), 1)
            shown += (target - shown) * (target > shown ? 0.3 : 0.06)
            return shown
        }

        /// The tap for Ari's voice, on its player: the level as it's heard, not as it arrives.
        func voiceTap() -> AVAudioNodeTapBlock {
            { [self] buffer, _ in report(.ari, rms: Self.rms(buffer)) }
        }

        static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
                return 0
            }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                let sample = samples[index * buffer.stride]
                sum += sample * sample
            }
            return (sum / Float(buffer.frameLength)).squareRoot()
        }
    }

    /// While Ari is speaking, your voice goes up only when it's clearly louder than Ari's own sound
    /// coming back, and stays open a moment after, so words aren't clipped. What it holds back goes
    /// as silence: the server's timing carries on, but it never hears Ari as you.
    nonisolated struct EchoGate {
        /// Ari counts as speaking above this level.
        static let ariSpeaking: Float = 0.003
        /// You must be louder than about -30 dBFS…
        static let floor: Float = 0.03
        /// …and than half of Ari's own level.
        static let overAri: Float = 0.5
        /// How long the gate stays open after you were last loud enough, in seconds.
        static let hold = 0.35

        private var open = 0.0

        mutating func passes(you: Float, ari: Float, seconds: Double) -> Bool {
            guard ari > Self.ariSpeaking else {
                open = 0
                return true
            }
            if you > max(Self.floor, ari * Self.overAri) {
                open = Self.hold
            } else {
                open -= seconds
            }
            return open > 0
        }
    }

    /// What the microphone's tap does on the audio thread: turns your voice into the stream's
    /// format (16-bit PCM, mono, 16 kHz) and sends it in 40 ms frames, silence included, since the
    /// server times your pauses. While muted, nothing goes.
    nonisolated final class MicrophoneStream: @unchecked Sendable {
        /// What the tap has seen, for saying why Ari hears nothing.
        struct Counts: Sendable {
            var buffers = 0
            var sent = 0
            var failed = 0
            /// The loudest sample since the last look, 0 to 1.
            var peak: Float = 0
        }

        /// The stream's format for your voice.
        static let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        /// 40 ms at 16 kHz, 16-bit.
        private static let frameBytes = 1_280

        private let muted = Mutex(false)
        private let counted = Mutex(Counts())
        private let pending = Mutex(Data())
        private let resampler: Resampler
        private let level: CallLevel
        /// Touched only on the audio thread.
        private var gate = EchoGate()
        private let send: @Sendable (Data) -> Void
        /// The microphone's sample rate in one channel: some iPhones report several channels.
        let mono: AVAudioFormat

        init(
            microphone: AVAudioFormat, level: CallLevel, send: @escaping @Sendable (Data) -> Void
        ) {
            mono = AVAudioFormat(standardFormatWithSampleRate: microphone.sampleRate, channels: 1)!
            resampler = Resampler(from: mono, to: Self.format)
            self.level = level
            self.send = send
        }

        var isMuted: Bool {
            get { muted.withLock { $0 } }
            set {
                muted.withLock { $0 = newValue }
                pending.withLock { $0 = Data() }
            }
        }

        /// What the tap has seen so far; the peak starts again.
        func counts() -> Counts {
            counted.withLock { counts in
                defer { counts.peak = 0 }
                return counts
            }
        }

        func take(_ buffer: AVAudioPCMBuffer) {
            guard let mono = firstChannel(of: buffer) else {
                counted.withLock { $0.failed += 1 }
                return
            }
            let rms = CallLevel.rms(mono)
            // Muted, Ari doesn't breathe with you either.
            level.report(.you, rms: isMuted ? 0 : rms)
            guard !isMuted else { return }
            guard let converted = resampler.convert(mono), let samples = converted.int16ChannelData
            else {
                counted.withLock { $0.failed += 1 }
                return
            }
            let seconds = Double(mono.frameLength) / mono.format.sampleRate
            let passes = gate.passes(you: rms, ari: level.ari, seconds: seconds)
            let count = Int(converted.frameLength) * 2
            let bytes = passes ? Data(bytes: samples[0], count: count) : Data(count: count)
            let frames = pending.withLock { pending -> [Data] in
                pending.append(bytes)
                var frames: [Data] = []
                while pending.count >= Self.frameBytes {
                    frames.append(Data(pending.prefix(Self.frameBytes)))
                    pending.removeFirst(Self.frameBytes)
                }
                return frames
            }
            for frame in frames { send(frame) }
            counted.withLock { $0.sent += frames.count }
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

        /// The block for the input node's tap, made off the main actor: the audio thread calls it.
        func block() -> AVAudioNodeTapBlock {
            { [self] buffer, _ in take(buffer) }
        }
    }

    /// Short, soft sounds Ari makes on a call: the chime when your turn ends, and the tone in the
    /// gaps while Ari works, so silence never sounds like a dropped call.
    nonisolated enum CallSounds {
        /// Two quick rising notes: Ari has your turn.
        static func chime(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            buffer(format: format, notes: [(659.25, 0.09), (987.77, 0.14)], loudness: 0.07)
        }

        /// Two gentle notes, quiet under speech: Ari is working.
        static func tone(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            buffer(format: format, notes: [(587.33, 0.16), (880, 0.22)], loudness: 0.08)
        }

        private static func buffer(
            format: AVAudioFormat, notes: [(frequency: Double, seconds: Double)], loudness: Double
        ) -> AVAudioPCMBuffer? {
            let rate = format.sampleRate
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
                    // A gentle rise and a longer fall.
                    let envelope = min(1, t / 0.02) * exp(-t * 9)
                    let sample = Float(loudness * envelope * sin(2 * .pi * note.frequency * t))
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
