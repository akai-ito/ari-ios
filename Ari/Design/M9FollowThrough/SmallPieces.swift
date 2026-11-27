#if DEBUG
    import AriKit
    import SwiftUI

    // MARK: - Settings: the dream's time, and Full access

    struct SettingsSketch: View {
        enum Stage { case off, faceID }
        let stage: Stage

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ito box").font(.body.weight(.semibold))
                                Text("ito-box.local")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.ariTertiary)
                            }
                            Spacer()
                            Text("Connected").font(.footnote).foregroundStyle(.ariTertiary)
                        }
                        .padding(.vertical, 2)
                        LabeledContent("Version", value: "0.20.0")
                    }
                    .listRowBackground(Color.ariSurface)
                    Section {
                        LabeledContent("Name", value: "Kumo")
                        LabeledContent("Where you are", value: "London · Europe/London")
                    } header: {
                        Text("Kumo")
                    }
                    .listRowBackground(Color.ariSurface)
                    Section {
                        HStack {
                            Text("Dream at")
                            Spacer()
                            Text("04:00")
                                .monospacedDigit()
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color.ariText.opacity(0.1), in: .rect(cornerRadius: 8))
                        }
                        LabeledContent("Last dream", value: "Today 04:00 · 31 min")
                    } header: {
                        Text("Dreaming")
                    } footer: {
                        Text(
                            "Each night Kumo reads your day, tidies its memory, sets tomorrow up and writes your journal. What it did waits under the moon on your Desk, with Dream now."
                        )
                    }
                    .listRowBackground(Color.ariSurface)
                    Section {
                        Toggle(isOn: .constant(stage == .faceID)) {
                            HStack(spacing: 10) {
                                Image(systemName: stage == .faceID ? "lock.open" : "lock")
                                    .foregroundStyle(.ariSecondary)
                                    .frame(width: 20)
                                Text("Full access")
                            }
                        }
                    } header: {
                        Text("Full access")
                    } footer: {
                        Text(
                            "Kumo works inside a sandbox: its own folder and the tools you've connected. With full access it can use the whole box, any file and any program, from its next message; the dream follows it too. Turning it on asks for Face ID."
                        )
                    }
                    .listRowBackground(Color.ariSurface)
                    Section("Notifications") {
                        LabeledContent("Messages from Kumo", value: "On")
                    }
                    .listRowBackground(Color.ariSurface)
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(.ariBackground)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
                }
            }
            .tint(.ariText)
            .overlay {
                if stage == .faceID {
                    VStack(spacing: 14) {
                        Image(systemName: "faceid")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.white)
                        Text("Face ID").font(.footnote).foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 160, height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .environment(\.colorScheme, .dark)
                }
            }
        }
    }

    // MARK: - The main chat

    /// The corner a thread hangs from: down, then along.
    nonisolated struct M9Hook: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                let r = min(rect.width, rect.height) * 0.45
                path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - r))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + 1 + r, y: rect.maxY),
                    control: CGPoint(x: rect.minX + 1, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
        }
    }

    struct M9ThreadLine: View {
        let title: String
        let replies: Int
        var open = true

        var body: some View {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                M9Hook()
                    .stroke(
                        .ariDusk,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 12, height: 17)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 4 }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if open {
                        Image(systemName: "circle.dotted")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.ariBone)
                    }
                    Text(title).foregroundStyle(open ? Color.ariText : .ariSecondary)
                    Text("·").foregroundStyle(.ariTertiary)
                    Text("\(replies) replies").foregroundStyle(.ariTertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.ariTertiary)
                }
                .font(.footnote)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct M9KumoWords: View {
        let text: String

        init(_ text: String) { self.text = text }

        var body: some View {
            Text(text)
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct M9FlowNote: View {
        let text: String

        init(_ text: String) { self.text = text }

        var body: some View {
            Text(text)
                .font(.caption)
                .foregroundStyle(.ariTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    /// The main chat, with Full access's marker in the header, or offline from the cache.
    struct MainChatSketch: View {
        enum Mode { case fullAccess, offline }
        let mode: Mode

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Rhythm.messageGap) {
                    switch mode {
                    case .fullAccess: fullAccessRows
                    case .offline: offlineRows
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(
                    draft: .constant(""), role: .idle, prompt: "Message Kumo", send: {}, stop: {},
                    talk: {}, talkReady: mode != .offline
                ) {
                    AttachButton(room: 4, add: { _ in }, problem: { _ in })
                }
                .background(.ariBackground)
            }
            .background(.ariBackground)
        }

        private var header: some View {
            ZStack(alignment: .top) {
                VStack(spacing: 2) {
                    PresenceView(history: PoseHistory(mode == .offline ? .offline : .resting))
                        .padding(.bottom, 6)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Today").font(.ariName).foregroundStyle(.ariText)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.ariTertiary)
                    }
                    if mode == .offline {
                        HStack(spacing: 5) {
                            Image(systemName: "icloud.slash").font(.caption.weight(.semibold))
                            Text("Offline · updated 14:02")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                    } else {
                        StatusLine(status: .quiet("4 open threads"))
                    }
                }
                .frame(maxWidth: .infinity)
                HStack {
                    if mode == .fullAccess { FullAccessMarker() }
                    Spacer()
                    SettingsButton {}
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background {
                VStack(spacing: 0) {
                    Color.ariBackground
                    LinearGradient(
                        colors: [.ariBackground, .ariBackground.opacity(0)], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 28)
                }
                .padding(.bottom, -28)
                .ignoresSafeArea(edges: .top)
            }
        }

        @ViewBuilder
        private var fullAccessRows: some View {
            M9FlowNote("Today 16:12")
            YourMessage(
                text: "Can you clear the old Docker images off the box? It's nearly full.", tag: nil
            ) {
                EmptyView()
            } footer: {
                EmptyView()
            }
            M9KumoWords(
                "Done: 14 GB back, and the disk's at 61% now. I left alone the images your running services use."
            )
            M9ThreadLine(title: "Shoes", replies: 3)
            YourMessage(text: "Thanks. Remind me to ring Mum on Sunday", tag: nil) {
                EmptyView()
            } footer: {
                EmptyView()
            }
            M9KumoWords("Sunday at 11, after your run. It's in Plans.")
        }

        @ViewBuilder
        private var offlineRows: some View {
            M9FlowNote("Today 13:48")
            M9KumoWords(
                "Clara Voss asked if Thursday still works. Here's a reply saying yes, at 10:"
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope").foregroundStyle(.ariSecondary)
                    Text("Reply to Clara Voss").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                    Spacer()
                    Text("Halcyon").font(.footnote).foregroundStyle(.ariTertiary)
                }
                Text(
                    "Hi Clara, Thursday at 10 still works for me. I'll bring the notes from Monday. Thanks"
                )
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                HStack(spacing: 10) {
                    DeskPill(title: "Drop it") {}
                    DeskPill(title: "Change…") {}
                    DeskPill(title: "Open in Mail") {}
                }
                .disabled(true)
                Text("Back online to act on this").font(.caption).foregroundStyle(.ariTertiary)
            }
            .deskCard()
            M9ThreadLine(title: "Northwind prep", replies: 6)
            YourMessage(text: "Running 5 min late, can you tell Sam?", tag: "Waiting to send") {
                EmptyView()
            } footer: {
                EmptyView()
            }
        }
    }

    /// While Full access is on: a small open lock in the header's corner, opposite the gear.
    struct FullAccessMarker: View {
        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: "lock.open.fill").font(.caption2.weight(.semibold))
                Text("Full access").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.ariBone)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.ariBone.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.ariBone.opacity(0.4), lineWidth: 0.7))
            .padding(.top, 5)
        }
    }

    // MARK: - The share sheet

    struct ShareSketch: View {
        enum Stage { case writing, replied, banner }
        let stage: Stage

        var body: some View {
            ShopPage()
                .overlay(alignment: .top) {
                    if stage == .banner {
                        Banner().padding(.horizontal, 10).padding(.top, 4)
                    }
                }
                .sheet(isPresented: .constant(stage != .banner)) {
                    ShareSheetSketch(replied: stage == .replied)
                        .presentationDetents([.large])
                        .presentationBackground(.ariBackground)
                }
        }
    }

    /// A made-up shop's page in the browser, to share from.
    struct ShopPage: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.86, green: 0.84, blue: 0.8),
                                Color(red: 0.74, green: 0.72, blue: 0.68),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 360)
                    .overlay {
                        Image(systemName: "shoe.2.fill")
                            .font(.system(size: 120))
                            .foregroundStyle(Color(red: 0.25, green: 0.3, blue: 0.36))
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text("FERNWAY").font(.caption.weight(.bold)).tracking(2).foregroundStyle(
                        .black.opacity(0.6))
                    Text("Trail 3 · Running shoe").font(.title2.weight(.semibold)).foregroundStyle(
                        .black)
                    HStack(spacing: 8) {
                        Text("£92").font(.title3.weight(.semibold)).foregroundStyle(.black)
                        Text("£115").strikethrough().foregroundStyle(.black.opacity(0.5))
                    }
                    Text("Sizes 7–12 · Free returns")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.6))
                }
                .padding(.horizontal, 20)
                Spacer()
                HStack {
                    Spacer()
                    Text("fernway.co.uk")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(.horizontal, 60)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.97, green: 0.96, blue: 0.94))
            .ignoresSafeArea(edges: .top)
            .environment(\.colorScheme, .light)
        }
    }

    /// The share sheet in Ari's look: the link, your thought, Send; then, once Kumo has
    /// answered, where it replied.
    struct ShareSheetSketch: View {
        let replied: Bool

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.8, green: 0.78, blue: 0.74))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: "shoe.2.fill")
                                    .foregroundStyle(Color(red: 0.25, green: 0.3, blue: 0.36))
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trail 3 · Running shoe · Fernway")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.ariText)
                                .lineLimit(2)
                            Text("fernway.co.uk").font(.caption).foregroundStyle(.ariTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.ariLine, lineWidth: 1))
                    if replied {
                        Text("Are these the ones Leo meant? I'm a 10.")
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        reply
                    } else {
                        Text("Are these the ones Leo meant? I'm a 10.")
                            .foregroundStyle(.ariText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(.ariLine, lineWidth: 1))
                        Text("Kumo answers in a thread about this, or in the one it belongs to.")
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(.ariBackground)
                .navigationTitle("Share with Kumo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if replied {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {}.fontWeight(.semibold)
                        }
                    } else {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Send") {}.fontWeight(.semibold)
                        }
                    }
                }
            }
            .tint(.ariText)
        }

        private var reply: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    PresenceView(history: PoseHistory(.resting), size: 26)
                        .frame(width: 30)
                    Text("Kumo replied in ")
                        .foregroundStyle(.ariSecondary)
                        + Text("Shoes").foregroundStyle(.ariText).fontWeight(.semibold)
                        + Text(" thread").foregroundStyle(.ariSecondary)
                }
                .font(.subheadline)
                Text(
                    "Yes, the same ones. They're £23 less than when Leo looked, and there's still a 10."
                )
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                DeskPill(title: "Open the thread", acts: true) {}
            }
            .deskCard()
            .padding(.top, 6)
        }
    }

    /// The notification, when the reply comes after the sheet has closed.
    struct Banner: View {
        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image("IconPreviewRest")
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Kumo · Shoes").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("now").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(
                        "Yes, the same ones. They're £23 less than when Leo looked, and there's still a 10."
                    )
                    .font(.subheadline)
                    .lineLimit(2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial)
            )
            .environment(\.colorScheme, .dark)
        }
    }
#endif
