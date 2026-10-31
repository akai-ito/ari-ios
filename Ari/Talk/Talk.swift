import AVFoundation
import AriKit
import CallKit
import Foundation
import UIKit
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
    /// Why the last call ended or couldn't start, for the chat to say: Talk is off rather than
    /// worse, and this is why.
    var notice: String?

    @ObservationIgnored private let session: Session
    /// Whether the server can talk: a call needs its voice.
    @ObservationIgnored private let voices: Voices
    @ObservationIgnored private let provider: CXProvider
    @ObservationIgnored private let controller = CXCallController()

    private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "talk")

    init(session: Session, voices: Voices) {
        self.session = session
        self.voices = voices
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// You tapped Talk.
    func start() {
        if call != nil {
            showsCall = true
            return
        }
        // Without the server's voice there's no call, rather than a worse one.
        guard voices.canTalk else {
            notice = voices.reason ?? "\(LeadName.current)'s voice isn't ready on your server yet."
            return
        }
        problem = nil
        notice = nil
        begin()
    }

    private func begin() {
        let call = CallEngine(session: session)
        call.ended = { [weak self] reason in self?.end(because: reason) }
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
            let handle = CXHandle(type: .generic, value: LeadName.current)
            let action = CXStartCallAction(call: call.uuid, handle: handle)
            action.contactIdentifier = LeadName.current
            controller.request(CXTransaction(action: action)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.couldNotStart(error) }
            }
        #endif
    }

    /// The call can't go on, such as when the server's voice stops: it ends, and the chat says
    /// why.
    func end(because reason: String?) {
        notice = reason
        end()
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
        // The connection stayed open for the call; in the background it closes as usual.
        if UIApplication.shared.applicationState == .background { session.pause() }
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

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { call?.audioActivated() }
    }

    nonisolated func provider(
        _ provider: CXProvider, didDeactivate audioSession: AVAudioSession
    ) {
        MainActor.assumeIsolated { call?.audioDeactivated() }
    }
}
