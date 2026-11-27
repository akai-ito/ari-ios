#if DEBUG
    import AriKit
    import SwiftUI

    /// Stills for Milestone 9's first design round: What I'm up to split across the Desk, the
    /// dream and its views, Plans and Done, Understanding you, and the smaller pieces.
    /// `ARI_SKETCH=<name>` opens one from samples, without a server. Everyone and everything in
    /// them is made up.
    enum FollowThroughSketch: String, CaseIterable {
        // The Desk, three placements of the moon or sun and the needs-you bubble.
        case deskAMoon = "m9-desk-a-moon"
        case deskASun = "m9-desk-a-sun"
        case deskBMoon = "m9-desk-b-moon"
        case deskBSun = "m9-desk-b-sun"
        case deskCMoon = "m9-desk-c-moon"
        case deskCSun = "m9-desk-c-sun"
        case deskAEvening = "m9-desk-a-evening"
        // The moon or sun's page.
        case nightPage = "m9-night-page"
        case nightPageLower = "m9-night-page-lower"
        case dreamLine = "m9-dream-line"
        case todayManual = "m9-today-manual"
        // Plans and Done.
        case plans = "m9-plans"
        case planDetail = "m9-plan-detail"
        case doneDetail = "m9-done-detail"
        // Getting to know you and Understanding you.
        case knowYou = "m9-know-you"
        case question = "m9-question"
        // Weaving the day.
        case weave1 = "m9-weave-1"
        case weave2 = "m9-weave-2"
        case weave3 = "m9-weave-3"
        case weaveReplay = "m9-weave-replay"
        // Sleeping Kumo, drifting thoughts.
        case sleep1 = "m9-sleep-1"
        case sleep2 = "m9-sleep-2"
        case sleep3 = "m9-sleep-3"
        case sleep4 = "m9-sleep-4"
        case sleepWatch = "m9-sleep-watch"
        case sleepMoon = "m9-sleep-moon"
        // Smaller pieces.
        case settings = "m9-settings"
        case faceID = "m9-faceid"
        case chatFullAccess = "m9-chat-full-access"
        case share = "m9-share"
        case shareReplied = "m9-share-replied"
        case shareBanner = "m9-share-banner"
        case offlineChat = "m9-offline-chat"
        case offlineDesk = "m9-offline-desk"
    }

    struct FollowThroughRoot: View {
        let sketch: FollowThroughSketch

        var body: some View {
            Group {
                switch sketch {
                case .deskAMoon: DeskTabs { M9Desk(scene: .morning, placement: .shoulders) }
                case .deskASun: DeskTabs { M9Desk(scene: .afternoon, placement: .shoulders) }
                case .deskBMoon: DeskTabs { M9Desk(scene: .morning, placement: .sky) }
                case .deskBSun: DeskTabs { M9Desk(scene: .afternoon, placement: .sky) }
                case .deskCMoon: DeskTabs { M9Desk(scene: .morning, placement: .cushion) }
                case .deskCSun: DeskTabs { M9Desk(scene: .afternoon, placement: .cushion) }
                case .deskAEvening:
                    DeskTabs { M9Desk(scene: .evening, placement: .shoulders) }
                case .nightPage:
                    DeskTabs {
                        M9Desk(scene: .morning, placement: .shoulders, opens: .night(.top))
                    }
                case .nightPageLower:
                    DeskTabs {
                        M9Desk(scene: .morning, placement: .shoulders, opens: .night(.lower))
                    }
                case .dreamLine:
                    DeskTabs {
                        M9Desk(scene: .morning, placement: .shoulders, opens: .night(.dreamLine))
                    }
                case .todayManual:
                    DeskTabs {
                        M9Desk(scene: .afternoon, placement: .shoulders, opens: .night(.manual))
                    }
                case .plans:
                    DeskTabs {
                        M9Desk(
                            scene: .afternoon, placement: .shoulders, opens: .plans(detail: false))
                    }
                case .planDetail:
                    DeskTabs {
                        M9Desk(
                            scene: .afternoon, placement: .shoulders, opens: .plans(detail: true))
                    }
                case .doneDetail:
                    DeskTabs {
                        M9Desk(scene: .afternoon, placement: .shoulders, opens: .night(.doneDetail))
                    }
                case .knowYou:
                    DeskTabs {
                        M9Desk(
                            scene: .afternoon, placement: .shoulders,
                            opens: .knowYou(question: false))
                    }
                case .question:
                    DeskTabs {
                        M9Desk(
                            scene: .afternoon, placement: .shoulders,
                            opens: .knowYou(question: true))
                    }
                case .weave1: WeaveScreen(stage: .gathering)
                case .weave2: WeaveScreen(stage: .knotting)
                case .weave3: WeaveScreen(stage: .tomorrow)
                case .weaveReplay:
                    DeskTabs {
                        M9Desk(scene: .morning, placement: .shoulders, opens: .night(.replay))
                    }
                case .sleep1: DeskTabs { M9Desk(scene: .asleep, placement: .shoulders) }
                case .sleep2:
                    DeskTabs { M9Desk(scene: .dreaming(.drifting), placement: .shoulders) }
                case .sleep3: DeskTabs { M9Desk(scene: .dreaming(.word), placement: .shoulders) }
                case .sleep4:
                    DeskTabs { M9Desk(scene: .dreaming(.nextWord), placement: .shoulders) }
                case .sleepWatch: SleepWatchScreen()
                case .sleepMoon: DeskTabs { M9Desk(scene: .dreamt, placement: .shoulders) }
                case .settings: SettingsSketch(stage: .off)
                case .faceID: SettingsSketch(stage: .faceID)
                case .chatFullAccess: ChatTabs { MainChatSketch(mode: .fullAccess) }
                case .share: ShareSketch(stage: .writing)
                case .shareReplied: ShareSketch(stage: .replied)
                case .shareBanner: ShareSketch(stage: .banner)
                case .offlineChat: ChatTabs { MainChatSketch(mode: .offline) }
                case .offlineDesk: DeskTabs { M9Desk(scene: .offline, placement: .shoulders) }
                }
            }
            .tint(.ariText)
        }
    }

    // MARK: - Tabs

    /// The app's tabs with the Desk up.
    struct DeskTabs<Desk: View>: View {
        @ViewBuilder var desk: Desk

        var body: some View {
            TabView(selection: .constant(0)) {
                Tab("Desk", systemImage: "rectangle.grid.1x2", value: 0) { desk }
                Tab("Chat", systemImage: "bubble.left", value: 1) { Color.ariBackground }
                Tab("In motion", systemImage: "circle.dotted.circle", value: 2) {
                    Color.ariBackground
                }
                Tab("You", systemImage: "person.crop.circle", value: 3) { Color.ariBackground }
            }
        }
    }

    /// The app's tabs with the chat up.
    struct ChatTabs<Chat: View>: View {
        @ViewBuilder var chat: Chat

        var body: some View {
            TabView(selection: .constant(1)) {
                Tab("Desk", systemImage: "rectangle.grid.1x2", value: 0) { Color.ariBackground }
                Tab("Chat", systemImage: "bubble.left", value: 1) { chat }
                Tab("In motion", systemImage: "circle.dotted.circle", value: 2) {
                    Color.ariBackground
                }
                Tab("You", systemImage: "person.crop.circle", value: 3) { Color.ariBackground }
            }
        }
    }

    // MARK: - Small shared pieces

    /// A label that tells a variant apart, so nobody mistakes one for another.
    struct M9VariantLabel: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.ariBackground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ariBone, in: Capsule())
        }
    }

    /// The same, made-up randomness every time, so a still renders the same twice.
    nonisolated enum Seeded {
        static func unit(_ i: Int, _ salt: Int = 0) -> Double {
            let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
            return x - floor(x)
        }
    }

    /// A sheet's own header: a glyph, a serif title and a quiet line under it.
    struct PageHeader<Glyph: View>: View {
        let title: String
        var subtitle: String?
        @ViewBuilder var glyph: Glyph

        var body: some View {
            HStack(spacing: 12) {
                glyph.frame(width: 56, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ariHeading)
                        .foregroundStyle(.ariText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    }
                }
            }
        }
    }
#endif
