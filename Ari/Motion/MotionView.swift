import AriKit
import SwiftUI

/// A thing in motion, open: its widget, full screen, with what changed at the bottom. Swipe down,
/// or the chevron, to put it back.
struct MotionView: View {
    let id: MotionID

    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ariBackground.ignoresSafeArea()
            if let detail = motions?.details[id] {
                switch detail.content {
                case .trip(let trip): TripView(detail: detail, trip: trip)
                case .training(let training): TrainingView(detail: detail, training: training)
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
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.ariText)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // Tinted dark, so the chevron still shows over a bright cover photo.
            .glassEffect(.regular.tint(.black.opacity(0.3)).interactive(), in: Circle())
            .accessibilityLabel("Close")
            .padding(.leading, 16)
            .padding(.top, 4)
        }
        // A link back to the chat closes the thing first.
        .transformEnvironment(\.openInChat) { open in
            guard let inner = open else { return }
            open = { position in
                dismiss()
                inner(position)
            }
        }
        .task { await load() }
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

/// A kind this Ari doesn't know, or can't read: its title, Ari's line on where it stands, and what
/// changed. Nothing pretends to be the widget it should be.
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
                        ? "This version of Ari can't show all of it. Update Ari to see it in full."
                        : "This version of Ari can't show this kind of thing yet. Update Ari to see "
                            + "it in full."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                ChangesList(changes: detail.changes)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// "What changed": Ari's notes, newest first, each linking back to where in the chat it happened.
struct ChangesList: View {
    let changes: [MotionChange]

    @Environment(\.openInChat) private var openInChat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What changed").font(.ariHeading).foregroundStyle(.ariText)
            ForEach(changes) { change in
                Button {
                    openInChat?(change.position)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(change.note)
                            .font(.subheadline)
                            .foregroundStyle(.ariText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(change.at.date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                        if openInChat != nil {
                            Image(systemName: "bubble.left")
                                .font(.caption)
                                .foregroundStyle(.ariTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(openInChat == nil)
                .accessibilityHint(openInChat == nil ? "" : "Shows where in the chat")
            }
            Text("Ari keeps this. To change it, just tell Ari.")
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .padding(.top, 4)
        }
    }
}
