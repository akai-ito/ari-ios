import AriKit
import SwiftUI

/// Ari's three places, as the map plans them: Chat, where you talk; Goals, what's in motion; and
/// Library, what Ari has made for you. Settings open from the corner of each.
struct MainView: View {
    let session: Session
    let model: AppModel

    @State private var place = Place.chat
    @State private var showsSettings = false
    /// What Ari knows, for the Library, In mind and memory steps on the trail.
    @State private var memory: Memory?
    #if os(iOS)
        /// Calls with Ari, registered with iOS.
        @State private var talk: Talk?
        /// Ari's voice on the server, and whether it can talk.
        @State private var voices: Voices?
        /// The calls Siri asked for that have started here.
        @State private var startedCalls = 0
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    enum Place: Hashable { case chat, goals, library }

    var body: some View {
        TabView(selection: $place) {
            Tab("Chat", systemImage: "bubble.left", value: .chat) {
                ConversationView(
                    session: session, connectAgain: model.connectAgain,
                    opening: Binding(get: { model.opening }, set: { model.opening = $0 }),
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
            Tab("Goals", systemImage: "scope", value: .goals) {
                ComingPlace(
                    title: "Goals",
                    text: "Nothing in motion yet. When Ari is working towards something for you, "
                        + "it shows here."
                ) { showsSettings = true }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                LibraryView(memory: memory) { showsSettings = true }
            }
        }
        .environment(memory)
        .task { if memory == nil { memory = model.client().map(Memory.init(client:)) } }
        #if os(iOS)
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
                    talk?.end(because: voices.reason ?? "Ari's voice stopped on your server.")
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { talk?.showsCall ?? false }, set: { talk?.showsCall = $0 })
            ) {
                if let talk, let call = talk.call {
                    CallView(talk: talk, call: call, session: session)
                }
            }
        #endif
        // A tab bar on iPhone, a sidebar on the Mac.
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        #if os(iOS)
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: model, session: session)
            }
        #else
            // On the Mac, Settings is a window of its own.
            .onChange(of: showsSettings) { _, shows in
                guard shows else { return }
                showsSettings = false
                openSettings()
            }
        #endif
        // The server pushes only while you're not looking at the conversation.
        .onChange(of: scenePhase == .active && place == .chat, initial: true) { _, looking in
            model.setLooking(looking)
        }
        .onChange(of: session.link) { _, link in
            guard link == .live else { return }
            model.reconnected()
            #if os(iOS)
                // The voice may have changed while the stream was down.
                Task { await voices?.refresh() }
            #endif
        }
        .onChange(of: model.opening) { _, message in
            if message != nil { place = .chat }
        }
        #if DEBUG
            .task {
                place = ["goals": .goals, "library": .library][DebugScript.place ?? ""] ?? place
                showsSettings = DebugScript.opensSettings
            }
        #endif
    }
}

#if os(iOS)
    extension MainView {
        /// Ari's voice and calls, made once there's a server to talk to.
        fileprivate func makeTalk() {
            if voices == nil, let client = model.client() { voices = Voices(client: client) }
            if talk == nil, let voices { talk = Talk(session: session, voices: voices) }
        }
    }
#endif

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

/// A place that has nothing in it yet, saying plainly what it will hold.
private struct ComingPlace: View {
    let title: String
    let text: String
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            Text(text)
                .font(.ariBody)
                .foregroundStyle(.ariTertiary)
                .multilineTextAlignment(.center)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ariBackground)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape", action: openSettings)
                    }
                }
        }
    }
}
