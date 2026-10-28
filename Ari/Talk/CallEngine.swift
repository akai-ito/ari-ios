#if os(iOS)
    import AVFoundation
    import AriKit
    import UIKit
    import os

    /// One call with Ari: your voice streams to the server, which decides when your turn has ended,
    /// recognises your words and streams Ari's voice back. The phone plays it, chimes when your
    /// turn ends, keeps a soft tone in the gaps while Ari works, and shows captions of both sides.
    /// You can talk over Ari, and it stops.
    @Observable
    final class CallEngine {
        enum Phase: Equatable {
            /// Starting the call, the microphone and the stream.
            case connecting
            /// Your turn.
            case listening
            /// Ari is on it, quietly.
            case working
            case speaking
            case ended
        }

        let id: CallID
        /// CallKit's name for it: the same UUID.
        let uuid: UUID
        private(set) var phase = Phase.connecting
        /// You're speaking, as the server hears it, before any words come through.
        private(set) var isHearing = false
        /// What you're saying, live, as the server recognises it.
        private(set) var hearing = ""
        /// What Ari is saying now.
        private(set) var saying = ""
        /// What you said last, as sent.
        private(set) var lastSaid = ""
        private(set) var muted = false
        private(set) var connectedAt: Date?
        /// Something that stops the call working, in plain words.
        private(set) var problem: String?
        /// What the microphone and the stream are doing, when it helps to know: in debug builds,
        /// and whenever the server has heard nothing for a while.
        private(set) var diagnostics: String?

        /// Asks Talk to end the call, with why: set by Talk.
        var ended: (String?) -> Void = { _ in }

        /// Whether a call is on, so nothing else takes its audio.
        private(set) static var isOn = false

        @ObservationIgnored private let session: Session
        @ObservationIgnored private var stream: CallStream?
        /// Made once CallKit has activated the call's audio, and made again when iOS changes it.
        @ObservationIgnored private var audio: AVAudioEngine?
        @ObservationIgnored private var playback: CallPlayback?
        @ObservationIgnored private var soundPlayer: AVAudioPlayerNode?
        @ObservationIgnored private var microphoneStream: MicrophoneStream?
        /// How loud the call is, for Ari's dots to breathe with.
        @ObservationIgnored let level = CallLevel()
        @ObservationIgnored private var chime: AVAudioPCMBuffer?
        @ObservationIgnored private var tone: AVAudioPCMBuffer?
        @ObservationIgnored private var engineObserver: (any NSObjectProtocol)?
        @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []
        @ObservationIgnored private var engineStarts = 0
        @ObservationIgnored private var lastBuffers = 0
        @ObservationIgnored private var silentChecks = 0
        @ObservationIgnored private var pendingRestart: Task<Void, Never>?
        @ObservationIgnored private var loops: [Task<Void, Never>] = []
        @ObservationIgnored private var lastSound = Date()
        @ObservationIgnored private var lastTone = Date.distantPast
        @ObservationIgnored private var lastCheck = Date.distantPast
        @ObservationIgnored private var heardCount = 0
        @ObservationIgnored private var microphone = ""

        nonisolated private static let log = Logger(
            subsystem: "io.github.akai-ito.ari", category: "talk")

        init(session: Session, uuid: UUID = UUID()) {
            self.session = session
            self.uuid = uuid
            id = CallID(uuid.uuidString.lowercased())
        }

        // MARK: - Lifecycle

        /// The call is starting: the server hears of it while CallKit connects.
        func start() {
            Self.isOn = true
            session.startCall(id: id)
        }

        /// What CallKit asks before it activates the audio: playing and recording, through AirPods
        /// or the speaker, with iOS cancelling the speaker's echo where the iPhone can.
        ///
        /// Not the voice chat mode with the engine's own voice processing: under CallKit that made
        /// a second voice processor, and the engine never ran (`kAudioUnitErr_MultipleVoiceProcessors`).
        func configureAudioSession() {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(
                    .playAndRecord, mode: .default,
                    options: [.allowBluetoothHFP, .defaultToSpeaker, .duckOthers])
                if audioSession.isEchoCancelledInputAvailable {
                    try audioSession.setPrefersEchoCancelledInput(true)
                }
                Self.log.info(
                    "Echo cancellation available: \(audioSession.isEchoCancelledInputAvailable)")
            } catch {
                Self.log.error("Audio session refused: \(error, privacy: .public)")
            }
        }

        /// CallKit activated the audio: start listening, or listen again after an interruption.
        func audioActivated() {
            Self.log.info("Audio activated: \(Self.describeSession(), privacy: .public)")
            // The engine starts from the main queue, outside Swift's concurrency: AVFAudio waits on
            // queues of its own while it starts.
            DispatchQueue.main.async { MainActor.assumeIsolated { self.listen() } }
        }

        private func listen() {
            switch phase {
            case .connecting:
                do {
                    try startEngine()
                    observeSession()
                    connectStream()
                    connectedAt = .now
                    phase = .listening
                    loops.append(Task { await self.run() })
                } catch {
                    Self.log.error("No microphone: \(error, privacy: .public)")
                    problem = "Ari couldn't use the microphone."
                    ended(problem)
                }
            case .ended:
                return
            default:
                restartEngine(because: "the audio came back")
            }
        }

        func audioDeactivated() {
            Self.log.info("Audio deactivated")
            audio?.stop()
        }

        /// Muting pauses your turn: the server keeps it, and it carries on when you unmute.
        func setMuted(_ muted: Bool) {
            self.muted = muted
            microphoneStream?.isMuted = muted
            stream?.send(muted ? .mute : .unmute)
        }

        /// The call is over: the server ends it and keeps what you said.
        func end() async {
            guard phase != .ended else { return }
            phase = .ended
            Self.isOn = false
            for loop in loops { loop.cancel() }
            stream?.end()
            stopEngine()
            for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
            session.endCall(id)
        }

        // MARK: - The stream

        /// Connects the call's stream once the server has the call, and follows it until it ends.
        private func connectStream() {
            let call = id
            let stream = session.callStream(call)
            self.stream = stream
            loops.append(
                Task {
                    // The stream opens on a call the server has started.
                    for _ in 0..<100 where session.conversation[call: call] == nil {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    stream.start()
                    for await event in stream.events { handle(event) }
                    guard phase != .ended else { return }
                    // The server ended it, or the connection couldn't be kept.
                    problem = stream.endReason
                    ended(stream.endReason)
                })
        }

        private func handle(_ event: CallStreamEvent) {
            switch event {
            case .state(let state):
                isHearing = state == .hearing
                if state != .speaking { playback?.close() }
                switch state {
                case .listening, .hearing:
                    phase = .listening
                case .turnEnded:
                    // Ari has your turn: the chime, at once.
                    if let chime { soundPlayer?.scheduleBuffer(chime) }
                    lastSound = .now
                    phase = .working
                case .working:
                    phase = .working
                case .speaking:
                    phase = .speaking
                default:
                    break
                }
            case .heard(let text, let final, _):
                heardCount += 1
                if final {
                    lastSaid = text
                    hearing = ""
                } else {
                    hearing = text
                }
            case .saying(let id, let text):
                playback?.begin(id)
                saying = text
                lastSound = .now
            case .audio(let pcm):
                playback?.append(pcm)
                lastSound = .now
            case .stopPlayback:
                playback?.stop()
                saying = ""
            case .problem, .unknown:
                break
            }
            if phase == .listening { saying = "" }
        }

        // MARK: - The engine

        /// A fresh engine: the microphone to the stream, and Ari's voice and the call's sounds out.
        private func startEngine() throws {
            stopEngine()
            let audio = AVAudioEngine()
            self.audio = audio
            let input = audio.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                throw CallError.noMicrophone
            }

            let voicePlayer = AVAudioPlayerNode()
            let soundPlayer = AVAudioPlayerNode()
            let playback = CallPlayback(player: voicePlayer)
            playback.played = { [weak self] id, cut in
                self?.stream?.send(.played(id: id, cut: cut))
            }
            self.playback = playback
            self.soundPlayer = soundPlayer
            audio.attach(voicePlayer)
            audio.connect(voicePlayer, to: audio.mainMixerNode, format: CallPlayback.format)
            let soundFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            audio.attach(soundPlayer)
            audio.connect(soundPlayer, to: audio.mainMixerNode, format: soundFormat)
            chime = CallSounds.chime(format: soundFormat)
            tone = CallSounds.tone(format: soundFormat)

            let microphoneStream = MicrophoneStream(microphone: micFormat, level: level) {
                [weak self] frame in
                Task { @MainActor in self?.stream?.send(audio: frame) }
            }
            microphoneStream.isMuted = muted
            self.microphoneStream = microphoneStream
            lastBuffers = 0
            microphone = "\(Int(micFormat.sampleRate / 1000)) kHz, \(micFormat.channelCount) ch"
            input.installTap(
                onBus: 0, bufferSize: 2048, format: micFormat, block: microphoneStream.block())
            voicePlayer.installTap(onBus: 0, bufferSize: 1024, format: nil, block: level.voiceTap())
            audio.prepare()
            try audio.start()
            voicePlayer.play()
            soundPlayer.play()
            engineStarts += 1
            // The first check on the microphone comes after a second and a half: a fresh engine
            // sometimes gives nothing until it's made again.
            lastCheck = .now - 1.5
            Self.log.info(
                "Engine \(self.engineStarts) running: \(audio.isRunning); microphone \(micFormat, privacy: .public); \(Self.describeSession(), privacy: .public)"
            )
            engineObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartSoon(because: "iOS changed the audio") }
            }
            if !audio.isRunning { restartSoon(because: "the engine stopped as it started") }
        }

        /// Restarts the engine once the audio has settled, however many changes arrive meanwhile.
        private func restartSoon(because reason: String) {
            pendingRestart?.cancel()
            pendingRestart = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.restartEngine(because: reason) }
                }
            }
        }

        private func stopEngine() {
            if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
            engineObserver = nil
            // The players belong to this engine: they go with it.
            playback?.stop()
            playback = nil
            soundPlayer = nil
            audio?.inputNode.removeTap(onBus: 0)
            audio?.stop()
            audio = nil
        }

        private func restartEngine(because reason: String) {
            guard phase != .ended, phase != .connecting else { return }
            guard engineStarts < 8 else {
                problem = "Ari can't get any sound from the microphone."
                ended(problem)
                return
            }
            Self.log.info("Restarting the engine: \(reason, privacy: .public)")
            do {
                try startEngine()
            } catch {
                Self.log.error("Engine didn't restart: \(error, privacy: .public)")
                problem = "Ari couldn't use the microphone."
                ended(problem)
            }
        }

        /// Interruptions and route changes, in the log.
        private func observeSession() {
            let center = NotificationCenter.default
            sessionObservers = [
                center.addObserver(
                    forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
                ) { note in
                    let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 99
                    Self.log.info("Audio interrupted: \(kind)")
                },
                center.addObserver(
                    forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
                ) { note in
                    let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 99
                    Self.log.info(
                        "Audio route changed (\(reason)): \(Self.describeSession(), privacy: .public)"
                    )
                },
            ]
        }

        nonisolated private static func describeSession() -> String {
            let session = AVAudioSession.sharedInstance()
            let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
            let outputs = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            return "\(session.category.rawValue)/\(session.mode.rawValue), echo cancelled "
                + "\(session.isEchoCancelledInputEnabled), input "
                + (session.isInputAvailable ? "available" : "unavailable")
                + " [\(inputs)] → [\(outputs)]"
        }

        // MARK: - The rhythm

        /// A few times a second: the tone in the gaps while Ari works, and a look at the microphone.
        private func run() async {
            while !Task.isCancelled, phase != .ended {
                fillTheGap()
                checkMicrophone()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        /// While Ari works in silence, a soft tone every few seconds. Words come from the server,
        /// and only when they're worth hearing.
        private func fillTheGap() {
            guard phase == .working, playback?.isPlaying != true, let tone else { return }
            if Date.now.timeIntervalSince(lastSound) > 4, Date.now.timeIntervalSince(lastTone) > 6 {
                soundPlayer?.scheduleBuffer(tone)
                lastTone = .now
            }
        }

        /// Every few seconds: what the microphone and the stream are doing, in the log, and on
        /// screen while the server hears nothing. A microphone that gives no sound at all gets a
        /// fresh engine, twice, then the call ends and says why.
        private func checkMicrophone() {
            guard let microphoneStream, Date.now.timeIntervalSince(lastCheck) >= 3 else { return }
            lastCheck = .now
            let counts = microphoneStream.counts()
            let level = counts.peak > 0 ? Int(20 * log10(counts.peak)) : -99
            let running = audio?.isRunning == true
            let summary =
                "Mic \(microphone) · engine \(running ? "on" : "off") · in \(counts.buffers)"
                + " · level \(level) dB · sent \(counts.sent) · failed \(counts.failed)"
                + " · heard \(heardCount)"
            Self.log.info("\(summary, privacy: .public)")
            if counts.buffers == lastBuffers, !muted {
                silentChecks += 1
                if silentChecks <= 2 {
                    restartEngine(because: "no sound from the microphone")
                } else {
                    problem = "Ari can't get any sound from the microphone."
                    ended(problem)
                }
            } else {
                silentChecks = 0
                lastBuffers = counts.buffers
            }
            #if DEBUG
                diagnostics = summary
            #else
                let quiet = connectedAt.map { Date.now.timeIntervalSince($0) > 8 } ?? false
                diagnostics = quiet && heardCount == 0 ? summary : nil
            #endif
        }

        enum CallError: Error { case noMicrophone }
    }
#endif
