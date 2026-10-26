#if os(iOS)
    import AVFoundation
    import AriKit
    import CallKit
    import Foundation
    import Speech
    import os

    /// Talking with Ari: the call that's on, if any, registered with iOS as a call so it carries
    /// on locked and in your pocket, and AirPods controls work.
    @Observable
    final class Talk: NSObject {
        private(set) var call: CallEngine?
        /// Whether the call screen is up; the call carries on behind the chat when it isn't.
        var showsCall = false
        /// Why a call couldn't start, in plain words.
        private(set) var problem: String?

        @ObservationIgnored private let session: Session
        @ObservationIgnored private let provider: CXProvider
        @ObservationIgnored private let controller = CXCallController()
        /// Getting speech recognition ready since Ari opened.
        @ObservationIgnored private var warming: Task<Void, Never>?
        /// Asking for speech recognition, before the call starts.
        @ObservationIgnored private var starting = false

        private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "talk")

        init(session: Session) {
            self.session = session
            let configuration = CXProviderConfiguration()
            configuration.supportsVideo = false
            configuration.maximumCallGroups = 1
            configuration.maximumCallsPerCallGroup = 1
            configuration.supportedHandleTypes = [.generic]
            configuration.includesCallsInRecents = false
            provider = CXProvider(configuration: configuration)
            super.init()
            provider.setDelegate(self, queue: nil)
            // So the first call doesn't wait for the speech model or your vocabulary's.
            warming = Task { _ = try? await CallEngine.warmUp(session) }
        }

        /// You tapped Talk.
        func start() {
            if call != nil {
                showsCall = true
                return
            }
            guard !starting else { return }
            starting = true
            problem = nil
            Task {
                // Asked here in the chat, before the call: once CallKit has the screen, the
                // prompt never came and the call waited for it.
                let speech = await Self.askForSpeechRecognition()
                Self.log.info("Speech recognition: \(speech.rawValue, privacy: .public)")
                starting = false
                begin()
            }
        }

        /// Asks for speech recognition the first time, off the main actor: iOS answers on a queue
        /// of its own.
        nonisolated private static func askForSpeechRecognition() async
            -> SFSpeechRecognizerAuthorizationStatus
        {
            guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
                return SFSpeechRecognizer.authorizationStatus()
            }
            return await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
            }
        }

        private func begin() {
            let call = CallEngine(session: session, after: warming)
            self.call = call
            showsCall = true
            #if targetEnvironment(simulator)
                // The simulator never activates a call's audio, and ends a call whose audio the
                // app activates itself: there, the call runs without CallKit.
                call.configureAudioSession()
                call.start()
                try? AVAudioSession.sharedInstance().setActive(true)
                call.audioActivated()
            #else
                let handle = CXHandle(type: .generic, value: "Ari")
                let action = CXStartCallAction(call: call.uuid, handle: handle)
                action.contactIdentifier = "Ari"
                controller.request(CXTransaction(action: action)) { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.couldNotStart(error) }
                }
            #endif
        }

        /// You tapped End, on the call screen or the lock screen.
        func end() {
            guard let call else { return }
            #if targetEnvironment(simulator)
                Task { await finish() }
            #else
                controller.request(CXTransaction(action: CXEndCallAction(call: call.uuid))) {
                    [weak self] error in
                    guard error != nil else { return }
                    // iOS no longer knows the call: end it here anyway.
                    Task { @MainActor in await self?.finish() }
                }
            #endif
        }

        func setMuted(_ muted: Bool) {
            guard let call else { return }
            #if targetEnvironment(simulator)
                call.setMuted(muted)
            #else
                controller.request(
                    CXTransaction(action: CXSetMutedCallAction(call: call.uuid, muted: muted))
                ) { _ in }
            #endif
        }

        private func couldNotStart(_ error: any Error) {
            problem = "iOS didn't let the call start."
            Task { await finish() }
        }

        private func finish() async {
            guard let call else { return }
            await call.end()
            self.call = nil
            showsCall = false
        }
    }

    extension Talk: CXProviderDelegate {
        // The provider calls these on the main queue, as `setDelegate(_:queue: nil)` asks.

        nonisolated func providerDidReset(_ provider: CXProvider) {
            _ = MainActor.assumeIsolated { Task { await self.finish() } }
        }

        nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
            let id = action.callUUID
            let starting = MainActor.assumeIsolated { () -> Bool in
                guard let call, call.uuid == id else { return false }
                call.configureAudioSession()
                call.start()
                return true
            }
            guard starting else { return action.fail() }
            provider.reportOutgoingCall(with: id, startedConnectingAt: nil)
            action.fulfill()
            provider.reportOutgoingCall(with: id, connectedAt: nil)
        }

        nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
            _ = MainActor.assumeIsolated { Task { await self.finish() } }
            action.fulfill()
        }

        nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
            let muted = action.isMuted
            MainActor.assumeIsolated { call?.setMuted(muted) }
            action.fulfill()
        }

        nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession)
        {
            MainActor.assumeIsolated { call?.audioActivated() }
        }

        nonisolated func provider(
            _ provider: CXProvider, didDeactivate audioSession: AVAudioSession
        ) {
            MainActor.assumeIsolated { call?.audioDeactivated() }
        }
    }
#endif
