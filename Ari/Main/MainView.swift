import AriKit
import SwiftUI

/// Ari's three places, as the map plans them: Chat, where you talk; Goals, what's in motion; and
/// Library, what Ari has made for you. Settings open from the corner of each.
struct MainView: View {
    let session: Session
    let model: AppModel

    @State private var place = Place.chat
    @State private var showsSettings = false
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
                ComingPlace(
                    title: "Library",
                    text: "What Ari makes for you, plans, summaries and lists, will be kept here."
                ) { showsSettings = true }
            }
        }
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
            if link == .live { model.reconnected() }
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

/// The gear in the corner: a small glass circle, quiet until you need it.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 17))
                .foregroundStyle(.ariSecondary)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
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
