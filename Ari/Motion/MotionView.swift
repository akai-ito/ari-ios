import AriKit
import SwiftUI

/// A thing in motion, open: its widget, full screen, with what changed behind a button at the top.
/// Swipe down, or the chevron, to put it back.
struct MotionView: View {
    let id: MotionID

    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var showsChanges = false
    /// The newest change you've seen, so a faint dot says when there's something new.
    @State private var seen = 0
    /// What you'd seen when the sheet opened, so the new ones stay marked inside it.
    @State private var seenBefore = 0

    var body: some View {
        // A stack, so a trip's place can open as its own page.
        NavigationStack {
            ZStack(alignment: .top) {
                Color.ariBackground.ignoresSafeArea()
                if let detail = motions?.details[id] {
                    switch detail.content {
                    case .trip(let trip): TripView(detail: detail, trip: trip)
                    case .training(let training): TrainingView(detail: detail, training: training)
                    case .pursuit(let pursuit): PursuitView(detail: detail, pursuit: pursuit)
                    case .occasion(let occasion): OccasionView(detail: detail, occasion: occasion)
                    case .caseFile(let file): CaseView(detail: detail, file: file)
                    case .unknown, .unreadable: PlainMotionView(detail: detail)
                    }
                } else if let problem {
                    Notice(text: problem) {
                        self.problem = nil
                        Task { await load() }
                    }
                } else if motions?[id] == nil, motions?.load == .loaded {
                    Notice(text: "This is no longer in motion.")
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    GlassButton(symbol: "chevron.down", label: "Close") { dismiss() }
                    Spacer()
                    if let changes = motions?.details[id]?.changes, !changes.isEmpty {
                        GlassButton(symbol: "clock.arrow.circlepath", label: "What changed") {
                            showsChanges = true
                        }
                        .overlay(alignment: .topTrailing) {
                            if (changes.map(\.version).max() ?? 0) > seen {
                                Circle().fill(.ariBone).frame(width: 8, height: 8)
                                    .offset(x: -2, y: 2)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .accessibilityValue(
                            (changes.map(\.version).max() ?? 0) > seen ? "Something new" : "")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showsChanges) {
            if let changes = motions?.details[id]?.changes {
                NavigationStack {
                    ScrollView {
                        ChangesList(changes: changes, seen: seenBefore).padding(20)
                    }
                    .background(.ariBackground)
                    .navigationTitle("What changed")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: showsChanges) { _, shows in
            guard shows, let newest = motions?.details[id]?.changes.map(\.version).max() else {
                return
            }
            seenBefore = seen
            withAnimation(.smooth(duration: 0.3)) { seen = newest }
            SeenChanges.see(newest, of: id)
        }
        // A link back to the chat closes the thing first.
        .transformEnvironment(\.openInChat) { open in
            guard let inner = open else { return }
            open = { position in
                showsChanges = false
                dismiss()
                inner(position)
            }
        }
        .task {
            seen = SeenChanges.newest(of: id)
            #if DEBUG
                if DebugScript.opensChanges { showsChanges = true }
            #endif
            await load()
        }
    }

    private func load() async {
        guard let motions else { return }
        do throws(RequestError) {
            try await motions.detail(id)
        } catch {
            if motions.details[id] == nil { problem = "Couldn't open it: \(error.plainWords)" }
        }
    }
}

/// The newest change you've seen of each thing, kept on this phone.
enum SeenChanges {
    private static func key(_ id: MotionID) -> String { "seen change \(id.rawValue)" }

    static func newest(of id: MotionID) -> Int {
        UserDefaults.standard.integer(forKey: key(id))
    }

    static func see(_ version: Int, of id: MotionID) {
        UserDefaults.standard.set(version, forKey: key(id))
    }
}

/// A round glass button over a thing's cover, tinted dark so it shows over a bright photo.
private struct GlassButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.ariText)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.black.opacity(0.3)).interactive(), in: Circle())
        .accessibilityLabel(label)
    }
}

/// Something Ari couldn't show, said plainly, with a way to try again where that might help.
private struct Notice: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Text(text)
                .font(.ariBody)
                .foregroundStyle(.ariSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry).buttonStyle(.bordered).tint(.ariText)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A kind this Ari doesn't know, or can't read: its title and Ari's line on where it stands. Nothing
/// pretends to be the widget it should be.
struct PlainMotionView: View {
    let detail: MotionDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.motion.title).font(.ariTitle).foregroundStyle(.ariText)
                    Text(detail.motion.summary).font(.subheadline).foregroundStyle(.ariSecondary)
                }
                Text(
                    detail.content == .unreadable
                        ? "This version of Ito can't show all of it. Update Ito to see it in full."
                        : "This version of Ito can't show this kind of thing yet. Update Ito to see "
                            + "it in full."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// "What changed": Ari's notes, newest first, on a rail like the chat's trail, each linking back to
/// where in the chat it happened. What's new since you last looked has a bone dot.
struct ChangesList: View {
    let changes: [MotionChange]
    /// The newest change you'd seen before.
    var seen = Int.max

    @Environment(\.openInChat) private var openInChat

    var body: some View {
        let ordered = changes.sorted { $0.version > $1.version }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, change in
                Button {
                    openInChat?(change.position)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(change.version > seen ? Color.ariBone : .ariDusk)
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            if index < ordered.count - 1 {
                                Rectangle().fill(.ariLine).frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.note)
                                .font(.subheadline)
                                .foregroundStyle(.ariText)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                Text(change.at.date, format: .relative(presentation: .named))
                                if openInChat != nil {
                                    Text("·")
                                    Text("In the chat")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                        }
                        .padding(.bottom, 18)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(openInChat == nil)
                .accessibilityHint(openInChat == nil ? "" : "Shows where in the chat")
            }
            Text("\(LeadName.current) keeps this. To change it, just say so.")
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .padding(.top, 4)
        }
    }
}
