import AriKit
import CoreSpotlight
import SwiftUI

/// Ito's four places: the Desk, home for everything admin; Chat, the one conversation with Kumo; In
/// motion, what you're actually doing, which Kumo keeps current; and You, what Kumo knows. Settings
/// open from the corner of each.
struct MainView: View {
    let session: Session
    let model: AppModel

    @State private var place = Place.desk
    @State private var showsSettings = false
    @State private var libraryPath = LibraryView.startingPath
    /// What Ari knows, for the Library, In mind and memory steps on the trail.
    @State private var memory: Memory?
    /// What's in motion, for its tab, the pinned line and compact lines in the chat.
    @State private var motions: Motions?
    /// Calls with Ari, registered with iOS.
    @State private var talk: Talk?
    /// Ari's voice on the server, and whether it can talk.
    @State private var voices: Voices?
    /// The calls Siri asked for that have started here.
    @State private var startedCalls = 0
    @Environment(\.scenePhase) private var scenePhase

    enum Place: Hashable { case desk, chat, motion, library }

    var body: some View {
        TabView(selection: $place) {
            Tab("Desk", systemImage: "rectangle.grid.1x2", value: .desk) {
                DeskScreen(
                    session: session, openChat: { place = .chat },
                    openSettings: { showsSettings = true },
                    talk: {
                        makeTalk()
                        place = .chat
                        talk?.start()
                    },
                    talkReady: voices?.canTalk ?? false)
            }
            Tab("Chat", systemImage: "bubble.left", value: .chat) {
                ConversationView(
                    session: session, connectAgain: model.connectAgain,
                    opening: Binding(get: { model.opening }, set: { model.opening = $0 }),
                    openingPosition: Binding(
                        get: { model.openingPosition }, set: { model.openingPosition = $0 }),
                    offersNotifications: model.offersNotifications,
                    answerOffer: { yes in
                        if yes {
                            Task { await model.turnOnNotifications() }
                        } else {
                            model.declineNotifications()
                        }
                    }
                )
                // The composer sits at the bottom of the conversation, just above the tab bar.
                .overlay(alignment: .topTrailing) {
                    SettingsButton { showsSettings = true }
                        .padding(.trailing, 16)
                        .padding(.top, 2)
                }
            }
            Tab("In motion", systemImage: "circle.dotted.circle", value: .motion) {
                InMotionView { showsSettings = true }
            }
            Tab("You", systemImage: "person.crop.circle", value: .library) {
                LibraryView(memory: memory, path: $libraryPath) { showsSettings = true }
            }
        }
        .environment(memory)
        .environment(motions)
        .environment(\.attachmentBytes) { await session.bytes(of: $0) }
        // "What changed" goes back to where in the chat it happened.
        .environment(\.openInChat) { model.openingPosition = $0 }
        .task {
            if motions == nil, let client = model.client() {
                let made = Motions(client: client)
                session.motions = made
                motions = made
            }
            await motions?.refresh()
        }
        .onChange(of: model.openingPosition) { _, position in
            if position != nil { place = .chat }
        }
        .task {
            if memory == nil { memory = model.client().map(Memory.init(client:)) }
            // Every page in the device's search, from the start, not only once the Library opens.
            if let memory {
                await memory.refresh()
                await Spotlight.index(memory)
            }
        }
        // A search result opens its page in the Library.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let page = Spotlight.page(from: activity) else { return }
            place = .library
            libraryPath = NavigationPath([page])
        }
        .environment(talk)
        .environment(voices)
        .task {
            makeTalk()
            await voices?.refresh()
            #if DEBUG
                if DebugScript.talks { talk?.start() }
            #endif
        }
        // "Hey Siri, talk to Ari", including when it opened Ari.
        .onChange(of: TalkRequests.shared.count, initial: true) { _, count in
            guard count > startedCalls else { return }
            startedCalls = count
            makeTalk()
            place = .chat
            Task {
                // Opened by Siri: know whether the server can talk before starting.
                if voices?.state == nil { await voices?.refresh() }
                talk?.start()
            }
        }
        // The server's voice changed: Talk follows, and a call ends if it can't go on.
        .onChange(of: session.voiceStatus) { _, status in
            guard let status, let voices else { return }
            voices.apply(status)
            if talk?.call != nil, !voices.canTalk {
                talk?.end(
                    because: voices.reason ?? "\(LeadName.current)'s voice stopped on your server.")
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                // During onboarding, onboarding shows the call over itself.
                get: { (talk?.showsCall ?? false) && !onboarding }, set: { talk?.showsCall = $0 })
        ) {
            if let talk, let call = talk.call {
                CallView(talk: talk, call: call, session: session)
            }
        }
        // Getting started, until Kumo has caught up and you've opened the Desk.
        .fullScreenCover(
            isPresented: Binding(
                get: { onboarding }, set: { _ in })
        ) {
            OnboardingHost(session: session, app: model)
                .environment(talk)
                .environment(voices)
        }
        // A tab bar on the iPhone; a sidebar once there's an iPad layout.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showsSettings) {
            // A sheet takes the environment from where it's attached, outside the one above.
            SettingsView(model: model, session: session).environment(voices)
        }
        // The server pushes only while you're not looking at the conversation.
        .onChange(of: scenePhase == .active && place == .chat, initial: true) { _, looking in
            model.setLooking(looking)
        }
        .onChange(of: session.link) { _, link in
            guard link == .live else { return }
            model.reconnected()
            // The voice may have changed while the stream was down.
            Task { await voices?.refresh() }
        }
        .onChange(of: model.opening) { _, message in
            if message != nil { place = .chat }
        }
        #if DEBUG
            .task {
                place =
                    ["chat": .chat, "motion": .motion, "library": .library, "you": .library][
                        DebugScript.place ?? ""] ?? place
                showsSettings = DebugScript.opensSettings
            }
        #endif
    }
}

extension MainView {
    /// Whether getting started is still going: Kumo catching up, or the reveal not yet seen.
    fileprivate var onboarding: Bool { session.onboarding.map { $0.state != .done } ?? false }

    /// Ari's voice and calls, made once there's a server to talk to.
    fileprivate func makeTalk() {
        if voices == nil, let client = model.client() { voices = Voices(client: client) }
        if talk == nil, let voices { talk = Talk(session: session, voices: voices) }
    }
}

/// The gear in the corner: a small glass circle, quiet until you need it.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 17))
                .foregroundStyle(.ariSecondary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // On the button, and interactive: glass on the label took the touch, so the gear did
        // nothing when tapped.
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Settings")
    }
}
