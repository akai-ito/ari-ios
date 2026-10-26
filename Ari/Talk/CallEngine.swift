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

        @ObservationIgnored private let session: Session
        @ObservationIgnored private let audio = AVAudioEngine()
        @ObservationIgnored private let voicePlayer = AVAudioPlayerNode()
        @ObservationIgnored private let tonePlayer = AVAudioPlayerNode()
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

        private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "talk")

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
            before = Set(session.conversation.entries.map(\.id))
            session.startCall(id: id)
            preparing = Task { await prepare() }
        }

        /// What CallKit asks before it activates the audio: a voice chat, with echo cancellation,
        /// through AirPods or the speaker.
        func configureAudioSession() {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.allowBluetoothHFP, .defaultToSpeaker, .duckOthers])
        }

        /// CallKit activated the audio: start listening.
        func audioActivated() {
            Task {
                await preparing?.value
                // Without recognition there's nothing to do but say why.
                guard phase == .connecting, transcriber != nil else { return }
                do {
                    try startAudio()
                    connectedAt = .now
                    phase = .listening
                    loops.append(Task { await self.run() })
                } catch {
                    Self.log.error("No microphone: \(error, privacy: .public)")
                    problem = "Ari couldn't use the microphone."
                }
            }
        }

        func audioDeactivated() {
            audio.stop()
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
            for loop in loops { loop.cancel() }
            voice?.stop()
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
            tap?.finish()
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
            let plain = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [plain])
            {
                log.info(
                    "Downloading speech recognition for \(locale.identifier, privacy: .public)")
                try await install.downloadAndInstall()
            }
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
            guard let transcriber else { throw CallError.notReady }
            let input = audio.inputNode
            try input.setVoiceProcessingEnabled(true)
            let micFormat = input.outputFormat(forBus: 0)

            let voice = Voice(player: voicePlayer)
            voice.finished = { [weak self] in self?.lastSound = .now }
            self.voice = voice
            audio.attach(voicePlayer)
            audio.connect(voicePlayer, to: audio.mainMixerNode, format: voice.format)
            let toneFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            audio.attach(tonePlayer)
            audio.connect(tonePlayer, to: audio.mainMixerNode, format: toneFormat)
            tone = WorkingTone.buffer(format: toneFormat)

            guard let analyzer else { throw CallError.notReady }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let target = analyzerFormat ?? micFormat
            let tap = MicrophoneTap(
                input: continuation, resampler: Resampler(from: micFormat, to: target))
            tap.muted = muted
            self.tap = tap
            _ = tap.record(to: newRecording(format: micFormat))
            input.installTap(onBus: 0, bufferSize: 4096, format: micFormat, block: tap.block())
            audio.prepare()
            try audio.start()
            voicePlayer.play()
            tonePlayer.play()

            loops.append(
                Task {
                    do {
                        try await analyzer.start(inputSequence: stream)
                    } catch {
                        self.problem = "Ari stopped hearing you."
                    }
                })
            loops.append(
                Task {
                    do {
                        for try await result in transcriber.results { self.heard(result) }
                    } catch {}
                })
        }

        // MARK: - Listening

        private func heard(_ result: DictationTranscriber.Result) {
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
                try? await Task.sleep(for: .milliseconds(150))
            }
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
            let old = tap.record(to: newRecording(format: audio.inputNode.outputFormat(forBus: 0)))
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
                tonePlayer.scheduleBuffer(tone)
                lastTone = .now
            }
        }

        enum CallError: Error { case notReady }
    }
#endif
