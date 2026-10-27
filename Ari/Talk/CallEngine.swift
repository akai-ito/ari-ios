#if os(iOS)
    import AVFoundation
    import AriKit
    import Speech
    import UIKit
    import os

    /// One call with Ari: listens on the phone, steered by your vocabulary, ends your turn when you
    /// pause, corrects names conservatively, sends what you said with its recording, and speaks
    /// Ari's notes and replies as they come. You can talk over Ari, and it stops.
    @Observable
    final class CallEngine {
        enum Phase: Equatable {
            /// Getting the microphone, the recogniser and your vocabulary ready.
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
        /// What you're saying, live.
        private(set) var hearing = ""
        /// What Ari is saying now.
        private(set) var saying = ""
        /// What you said last, as sent.
        private(set) var lastSaid = ""
        private(set) var muted = false
        private(set) var connectedAt: Date?
        /// Something that stops the call working, in plain words.
        private(set) var problem: String?
        /// Whether your vocabulary steers the recogniser this call.
        private(set) var isSteered = false
        /// What the microphone and the recogniser are doing, when it helps to know: in debug
        /// builds, and whenever Ari has heard nothing for a while.
        private(set) var diagnostics: String?

        @ObservationIgnored private let session: Session
        /// Made once CallKit has activated the call's audio, and made again when iOS changes it.
        @ObservationIgnored private var audio: AVAudioEngine?
        @ObservationIgnored private var tonePlayer: AVAudioPlayerNode?
        /// Where the microphone's audio goes to the recogniser, whichever engine it comes from.
        @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
        @ObservationIgnored private var engineObserver: (any NSObjectProtocol)?
        @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []
        @ObservationIgnored private var engineStarts = 0
        /// Whether Ari can hear you over its own voice: iOS cancels the speaker's echo, or the sound
        /// is in your ears. Otherwise Ari doesn't listen while it speaks, or it would hear itself.
        @ObservationIgnored private var hearsOverItself = false
        /// When Ari last stopped speaking, so the tail of its voice isn't heard as yours.
        @ObservationIgnored private var spokeUntil = Date.distantPast
        @ObservationIgnored private var lastBuffers = 0
        @ObservationIgnored private var silentChecks = 0
        @ObservationIgnored private var pendingRestart: Task<Void, Never>?
        @ObservationIgnored private var voice: Voice?
        @ObservationIgnored private var tone: AVAudioPCMBuffer?
        @ObservationIgnored private var transcriber: DictationTranscriber?
        @ObservationIgnored private var analyzer: SpeechAnalyzer?
        /// The format the recogniser works in.
        @ObservationIgnored private var analyzerFormat: AVAudioFormat?
        @ObservationIgnored private var tap: MicrophoneTap?
        @ObservationIgnored private var preparing: Task<Void, Never>?
        @ObservationIgnored private let warming: Task<Void, Never>?
        @ObservationIgnored private var loops: [Task<Void, Never>] = []
        @ObservationIgnored private var corrector = Corrector(vocabulary: Vocabulary(terms: []))
        /// This turn's finished pieces, and the piece still changing.
        @ObservationIgnored private var finals = ""
        @ObservationIgnored private var volatile = ""
        @ObservationIgnored private var lastHeard = Date.distantPast
        @ObservationIgnored private var finishing = false
        @ObservationIgnored private var recording: URL?
        /// Ari's messages from before the call, which it doesn't speak.
        @ObservationIgnored private var before: Set<MessageID> = []
        @ObservationIgnored private var feeds: [MessageID: SentenceFeed] = [:]
        @ObservationIgnored private var spoken: Set<MessageID> = []
        @ObservationIgnored private var lastSound = Date()
        @ObservationIgnored private var lastTone = Date.distantPast
        @ObservationIgnored private var lastStatus: String?
        @ObservationIgnored private var lastCheck = Date.distantPast
        @ObservationIgnored private var results = 0
        @ObservationIgnored private var microphone = ""

        nonisolated private static let log = Logger(
            subsystem: "io.github.akai-ito.ari", category: "talk")

        /// Asks Talk to end the call, with why: set by Talk.
        var ended: (String?) -> Void = { _ in }

        /// Whether a call is on, so nothing else takes its audio.
        private(set) static var isOn = false

        /// How long a pause ends your turn, from Settings.
        static var pause: Double {
            let saved = UserDefaults.standard.double(forKey: "talk.pause")
            return saved > 0 ? saved : 1.5
        }

        /// - Parameter warming: Getting ready ahead of the call, which this one waits for rather
        ///   than doing the same work alongside it.
        init(session: Session, uuid: UUID = UUID(), after warming: Task<Void, Never>? = nil) {
            self.session = session
            self.warming = warming
            self.uuid = uuid
            id = CallID(uuid.uuidString.lowercased())
        }

        // MARK: - Lifecycle

        /// The call is starting: get the recogniser and your vocabulary ready while CallKit
        /// connects.
        func start() {
            Self.isOn = true
            before = Set(session.conversation.entries.map(\.id))
            session.startCall(id: id)
            preparing = Task { await prepare() }
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
            Task {
                await preparing?.value
                // The engine starts from the main queue, outside Swift's concurrency: AVFAudio
                // waits on queues of its own while it starts.
                DispatchQueue.main.async { MainActor.assumeIsolated { self.listen() } }
            }
        }

        private func listen() {
            switch phase {
            case .connecting:
                // Without recognition there's nothing to do but say why.
                guard transcriber != nil else { return }
                do {
                    try startAudio()
                    connectedAt = .now
                    phase = .listening
                    loops.append(Task { await self.run() })
                } catch {
                    Self.log.error("No microphone: \(error, privacy: .public)")
                    problem = "Ari couldn't use the microphone."
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

        func setMuted(_ muted: Bool) {
            self.muted = muted
            tap?.muted = muted
        }

        /// The call is over: what you were saying goes, then the call ends on the server.
        func end() async {
            guard phase != .ended else { return }
            if !muted, !(finals + volatile).trimmingCharacters(in: .whitespaces).isEmpty {
                await finishTurn()
            }
            phase = .ended
            Self.isOn = false
            for loop in loops { loop.cancel() }
            stopEngine()
            for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
            input?.finish()
            await analyzer?.cancelAndFinishNow()
            if let recording { try? FileManager.default.removeItem(at: recording) }
            session.endCall(id)
        }

        // MARK: - Getting ready

        /// Gets speech recognition and your vocabulary's model ready ahead of a call, when Ari
        /// opens: the speech model downloads once, and the vocabulary's model is kept until the
        /// vocabulary changes. Returns what a call needs.
        @discardableResult
        static func warmUp(_ session: Session) async throws
            -> (locale: Locale, vocabulary: Vocabulary, model: SFSpeechLanguageModel.Configuration?)
        {
            let locale =
                await DictationTranscriber.supportedLocale(equivalentTo: .current)
                ?? Locale(identifier: "en-GB")
            // The speech model stays installed for Ari only while Ari reserves its language.
            if !(await AssetInventory.reservedLocales.contains(locale)) {
                let reserved = try await AssetInventory.reserve(locale: locale)
                log.info("Reserved \(locale.identifier, privacy: .public): \(reserved)")
            }
            let plain = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [plain])
            {
                log.info(
                    "Downloading speech recognition for \(locale.identifier, privacy: .public)")
                try await install.downloadAndInstall()
            }
            let status = await AssetInventory.status(forModules: [plain])
            log.info("Speech model: \(String(describing: status), privacy: .public)")
            // The vocabulary's model builds on the speech model, so it comes second.
            let vocabulary = await session.vocabulary() ?? Vocabulary(terms: [])
            let model = await LanguageModel.configuration(for: vocabulary, locale: locale)
            log.info("\(vocabulary.terms.count) terms; steered: \(model != nil, privacy: .public)")
            return (locale, vocabulary, model)
        }

        private func prepare() async {
            await warming?.value
            do {
                let (locale, vocabulary, model) = try await Self.warmUp(session)
                corrector = Corrector(
                    vocabulary: vocabulary, isWord: Self.isWord, refused: Refusals.load())
                isSteered = model != nil
                let transcriber = DictationTranscriber(
                    locale: locale,
                    contentHints: model.map { [.customizedLanguage(modelConfiguration: $0)] } ?? [],
                    transcriptionOptions: [.punctuation],
                    reportingOptions: [.volatileResults, .frequentFinalization],
                    attributeOptions: [])
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber])
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.prepareToAnalyze(in: format)
                self.transcriber = transcriber
                self.analyzer = analyzer
                analyzerFormat = format
                Self.log.info("Ready")
            } catch {
                Self.log.error("Not ready: \(error, privacy: .public)")
                problem =
                    "Ari couldn't get speech recognition ready. It downloads once, so check the "
                    + "connection and try again."
            }
        }

        private static let checker = UITextChecker()

        /// Whether the dictionary knows a word, so it's never "corrected" into a name.
        nonisolated private static func isWord(_ word: String) -> Bool {
            MainActor.assumeIsolated {
                let range = NSRange(location: 0, length: word.utf16.count)
                let language = Locale.current.identifier
                return checker.rangeOfMisspelledWord(
                    in: word, range: range, startingAt: 0, wrap: false,
                    language: UITextChecker.availableLanguages.contains(language)
                        ? language : "en_GB"
                ).location == NSNotFound
            }
        }

        private func startAudio() throws {
            guard let transcriber, let analyzer else { throw CallError.notReady }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            input = continuation
            try startEngine()
            observeSession()

            loops.append(
                Task {
                    do {
                        try await analyzer.start(inputSequence: stream)
                    } catch {
                        Self.log.error("Analyzer stopped: \(error, privacy: .public)")
                        self.problem = "Ari stopped hearing you."
                    }
                })
            loops.append(
                Task {
                    do {
                        for try await result in transcriber.results { self.heard(result) }
                        Self.log.info("Recognition ended")
                    } catch {
                        Self.log.error("Recognition failed: \(error, privacy: .public)")
                        self.problem = "Ari stopped hearing you."
                    }
                })
        }

        /// A fresh engine: the microphone into the recogniser and your turn's recording, and Ari's
        /// voice and tone out.
        private func startEngine() throws {
            guard let input else { throw CallError.notReady }
            stopEngine()
            let audio = AVAudioEngine()
            self.audio = audio
            let microphone = audio.inputNode
            let micFormat = microphone.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                throw CallError.noMicrophone
            }

            let voicePlayer = AVAudioPlayerNode()
            let tonePlayer = AVAudioPlayerNode()
            let session = session
            let voice = Voice(player: voicePlayer) { text throws(RequestError) in
                try await session.speak(text)
            }
            voice.finished = { [weak self] in self?.finishedSpeaking() }
            voice.failed = { [weak self] _ in self?.voiceFailed() }
            self.voice = voice
            self.tonePlayer = tonePlayer
            audio.attach(voicePlayer)
            audio.connect(voicePlayer, to: audio.mainMixerNode, format: voice.format)
            let toneFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            audio.attach(tonePlayer)
            audio.connect(tonePlayer, to: audio.mainMixerNode, format: toneFormat)
            tone = WorkingTone.buffer(format: toneFormat)

            let target = analyzerFormat ?? micFormat
            let tap = MicrophoneTap(input: input, microphone: micFormat, recogniser: target)
            tap.muted = muted
            self.tap = tap
            lastBuffers = 0
            hearsOverItself = Self.hearsOverItself()
            self.microphone =
                "\(Int(micFormat.sampleRate / 1000)) kHz, \(micFormat.channelCount) ch"
                + (hearsOverItself ? "" : ", listens only while Ari is quiet")
            _ = tap.record(to: newRecording(format: tap.mono))
            microphone.installTap(onBus: 0, bufferSize: 4096, format: micFormat, block: tap.block())
            audio.prepare()
            try audio.start()
            voicePlayer.play()
            tonePlayer.play()
            engineStarts += 1
            // The first check on the microphone comes after a second and a half, not three: a
            // fresh engine sometimes gives nothing until it's made again.
            lastCheck = .now - 1.5
            Self.log.info(
                "Engine \(self.engineStarts) running: \(audio.isRunning); microphone \(micFormat, privacy: .public) → recogniser \(target, privacy: .public); \(Self.describeSession(), privacy: .public)"
            )
            engineObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartSoon(because: "iOS changed the audio") }
            }
            if !audio.isRunning { restartSoon(because: "the engine stopped as it started") }
        }

        /// Whether the route keeps Ari's voice out of the microphone: iOS cancels the built-in
        /// speaker's echo, or the sound is in AirPods or headphones.
        nonisolated private static func hearsOverItself() -> Bool {
            let session = AVAudioSession.sharedInstance()
            let speaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
            return !speaker || session.isEchoCancelledInputEnabled
        }

        /// The server couldn't say a sentence: the call ends, rather than going on without Ari's
        /// voice.
        private func voiceFailed() {
            problem = "Ari's voice stopped on your server, so the call ended."
            ended(problem)
        }

        /// Ari's voice went quiet. Without echo cancellation, what the recogniser still holds is
        /// Ari's own words: it's flushed and dropped before Ari listens again.
        private func finishedSpeaking() {
            lastSound = .now
            guard !hearsOverItself else { return }
            spokeUntil = .distantFuture
            Task {
                try? await analyzer?.finalize(through: nil)
                finals = ""
                volatile = ""
                hearing = ""
                spokeUntil = .now + 0.3
            }
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
            // The voice's player belongs to this engine: it goes with it.
            voice?.stop()
            voice = nil
            tonePlayer = nil
            audio?.inputNode.removeTap(onBus: 0)
            audio?.stop()
            audio = nil
            if let old = tap?.record(to: nil) { old.close() }
            if let recording { try? FileManager.default.removeItem(at: recording) }
            recording = nil
        }

        private func restartEngine(because reason: String) {
            guard phase != .ended, phase != .connecting else { return }
            guard engineStarts < 8 else {
                problem = "Ari can't get any sound from the microphone."
                return
            }
            Self.log.info("Restarting the engine: \(reason, privacy: .public)")
            do {
                try startEngine()
            } catch {
                Self.log.error("Engine didn't restart: \(error, privacy: .public)")
                problem = "Ari couldn't use the microphone."
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
            return "\(session.category.rawValue)/\(session.mode.rawValue), input "
                + (session.isInputAvailable ? "available" : "unavailable")
                + " [\(inputs)] → [\(outputs)]"
        }

        // MARK: - Listening

        private func heard(_ result: DictationTranscriber.Result) {
            results += 1
            // Without echo cancellation the microphone hears Ari's voice from the speaker: what it
            // hears while Ari speaks, and just after, is Ari's.
            let speaking = voice?.isSpeaking == true || Date.now < spokeUntil
            guard hearsOverItself || !speaking else {
                if result.isFinal { volatile = "" }
                return
            }
            let text = String(result.text.characters)
            if result.isFinal {
                finals += text
                volatile = ""
            } else {
                volatile = text
            }
            hearing = (finals + volatile).trimmingCharacters(in: .whitespaces)
            guard !hearing.isEmpty else { return }
            lastHeard = .now
            // Talking over Ari stops it: two words, so a cough doesn't.
            if let voice, voice.isSpeaking, hearing.split(separator: " ").count >= 2 {
                voice.stop()
                saying = ""
            }
        }

        /// The whole call's rhythm, a few times a second: your turn ending, Ari's words to speak,
        /// and the tone in the gaps.
        private func run() async {
            while !Task.isCancelled, phase != .ended {
                if !finishing, !muted, !hearing.isEmpty,
                    Date.now.timeIntervalSince(lastHeard) >= Self.pause
                {
                    await finishTurn()
                }
                speakWhatsNew()
                fillTheGap()
                checkHearing()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        /// Every few seconds: what the microphone and the recogniser are doing, in the log, and on
        /// screen while Ari hears nothing.
        private func checkHearing() {
            guard let tap, Date.now.timeIntervalSince(lastCheck) >= 3 else { return }
            lastCheck = .now
            let counts = tap.counts()
            let level = counts.peak > 0 ? Int(20 * log10(counts.peak)) : -99
            let running = audio?.isRunning == true
            let summary =
                "Mic \(microphone) · engine \(running ? "on" : "off") · in \(counts.buffers)"
                + " · level \(level) dB · fed \(counts.fed) · failed \(counts.failed)"
                + " · heard \(results)" + (isSteered ? " · steered" : "")
            Self.log.info("\(summary, privacy: .public)")
            // No sound at all from the microphone: a fresh engine, twice, then say so.
            if counts.buffers == lastBuffers {
                silentChecks += 1
                if silentChecks <= 2 {
                    restartEngine(because: "no sound from the microphone")
                } else {
                    problem = "Ari can't get any sound from the microphone."
                }
            } else {
                silentChecks = 0
                lastBuffers = counts.buffers
            }
            #if DEBUG
                diagnostics = summary
            #else
                let quiet = connectedAt.map { Date.now.timeIntervalSince($0) > 8 } ?? false
                diagnostics = quiet && results == 0 ? summary : nil
            #endif
        }

        /// Your pause ended your turn: what you said goes, corrected and with its recording.
        private func finishTurn() async {
            finishing = true
            defer { finishing = false }
            try? await analyzer?.finalize(through: nil)
            for _ in 0..<10 where !volatile.isEmpty {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let said = (finals + volatile).split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            finals = ""
            volatile = ""
            hearing = ""
            guard !said.isEmpty else { return }

            let audio = closeRecording()
            let (text, corrections) = corrector.correct(said)
            lastSaid = text
            session.send(
                text, spoken: SendSpoken(call: id, audio: audio, corrections: corrections))
            lastSound = .now
            phase = .working
        }

        private func newRecording(format: AVAudioFormat) -> AVAudioFile? {
            let url = FileManager.default.temporaryDirectory.appending(
                path: "talk-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 32_000,
            ]
            guard
                let file = try? AVAudioFile(
                    forWriting: url, settings: settings, commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved)
            else { return nil }
            recording = url
            return file
        }

        /// Ends this turn's recording and starts the next; the finished one uploads.
        private func closeRecording() -> AttachmentID? {
            guard let tap, let finished = recording else { return nil }
            let old = tap.record(to: newRecording(format: tap.mono))
            old?.close()
            defer { try? FileManager.default.removeItem(at: finished) }
            guard let bytes = try? Data(contentsOf: finished), !bytes.isEmpty else { return nil }
            let time = Date.now.formatted(.dateTime.hour().minute().second())
            let attachment = PendingAttachment(
                name: "You at \(time).m4a", mediaType: "audio/mp4", bytes: bytes)
            session.attach(attachment)
            return attachment.id
        }

        // MARK: - Ari's side

        /// Speaks Ari's notes once written, and its replies a sentence at a time as they stream,
        /// up to the line that leaves the rest for the chat.
        private func speakWhatsNew() {
            guard let voice else { return }
            for entry in session.conversation.entries.suffix(8)
            where entry.role == .agent && !before.contains(entry.id) && !spoken.contains(entry.id) {
                let ended = entry.outcome != nil
                switch entry.kind {
                case .note:
                    guard ended else { continue }
                    if entry.outcome == .completed {
                        voice.say(SpokenText.spoken(from: entry.text))
                    }
                    spoken.insert(entry.id)
                case .reply:
                    var feed = feeds[entry.id] ?? SentenceFeed()
                    for sentence in feed.next(from: entry.text, finished: ended) {
                        voice.say(sentence)
                    }
                    feeds[entry.id] = feed
                    if ended { spoken.insert(entry.id) }
                default:
                    spoken.insert(entry.id)
                }
            }
            if let current = voice.current {
                saying = current
                lastSound = .now
            }
            let working = session.conversation.turn != nil
            phase =
                voice.isSpeaking ? .speaking : working || finishing ? .working : .listening
            if phase == .listening { saying = "" }
        }

        /// While Ari works in silence: a soft tone every few seconds, and after a longer quiet
        /// stretch, what it's doing, once for each new thing.
        private func fillTheGap() {
            guard phase == .working, let voice, !voice.isSpeaking else { return }
            let quiet = Date.now.timeIntervalSince(lastSound)
            if quiet > 12, let label = session.conversation.turn?.status?.label,
                label != lastStatus
            {
                lastStatus = label
                voice.say(label)
                return
            }
            if quiet > 5, Date.now.timeIntervalSince(lastTone) > 6, let tone {
                tonePlayer?.scheduleBuffer(tone)
                lastTone = .now
            }
        }

        enum CallError: Error { case notReady, noMicrophone }
    }
#endif
