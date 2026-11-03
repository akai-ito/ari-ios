import AriKit
import SwiftUI

/// What tapping Kumo opens: what needs you, the plans Kumo has made, what it's done today, and how
/// well it's getting to know you. A few words each; a tap goes deeper.
struct WhatImUpTo: View {
    let session: Session
    let mood: FaceMood
    /// Opens with "That was wrong" asked of the first thing Kumo did, for a still.
    var asksWrongAtFirst = false
    /// Opens scrolled down to Getting to know you, for a still.
    var opensAtTracks = false

    @State private var work: KumoWork?
    @State private var workProblem: String?
    @State private var editing: WakeUp?
    @State private var path: [Route] = []
    @Environment(\.dismiss) private var dismiss

    enum Route: Hashable {
        case card(CardID)
        case track(TrackID)
        case allWork
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        if !waiting.isEmpty { needsYou }
                        plans
                        done
                        if let tracks = work?.tracks, !tracks.isEmpty {
                            gettingToKnowYou(tracks).id("tracks")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .frame(maxWidth: Rhythm.column, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: work?.tracks.isEmpty) { _, _ in
                    if opensAtTracks { proxy.scrollTo("tracks", anchor: .bottom) }
                }
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .card(let id):
                    if let card = waiting.first(where: { $0.id == id }) { cardView(card) }
                case .track(let id):
                    if let track = work?.tracks.first(where: { $0.id == id }) {
                        TrackView(track: track)
                    }
                case .allWork:
                    KumosWorkScreen(session: session, asksWrongAtFirst: asksWrongAtFirst)
                }
            }
        }
        .task { await load() }
        // The Desk carries the plans; asking again catches one moved while the stream was down.
        .task { try? await session.refreshPlans() }
        .sheet(item: $editing) { PlanEditor(plan: $0, session: session) }
        #if DEBUG
            .task {
                guard asksWrongAtFirst else { return }
                try? await Task.sleep(for: .milliseconds(600))
                path = [.allWork]
            }
        #endif
    }

    private var waiting: [DeskCard] { session.desk?.waiting ?? [] }

    private var header: some View {
        HStack(spacing: 6) {
            KumoFace(mood: mood, size: 50)
                .frame(width: 60)
            Text("What I'm up to")
                .font(.ariHeading)
                .foregroundStyle(.ariText)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel(title)
            content()
        }
    }

    // MARK: Needs you

    private var needsYou: some View {
        section("Needs you") {
            VStack(spacing: 0) {
                ForEach(Array(waiting.enumerated()), id: \.element.id) { index, card in
                    if index > 0 {
                        Divider().overlay(Color.ariBone.opacity(0.15)).padding(.leading, 30)
                    }
                    NeedsYouRow(card: card, context: context(for: card)) {
                        path.append(.card(card.id))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.ariBone.opacity(0.08)))
        }
    }

    /// A card that needs you, in full, as the Desk has it now.
    private func cardView(_ card: DeskCard) -> some View {
        ScrollView {
            DeskCardView(card: card, context: context(for: card)) { answer in
                try await session.answer(card.id, answer)
                path.removeAll { $0 == .card(card.id) }
            }
            .padding(16)
        }
        .background(.ariBackground)
        .navigationTitle(CardLook.name(card.kind))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The card's corner: the thing in motion it's about, such as "Job search".
    private func context(for card: DeskCard) -> String? {
        guard let motion = card.motion else { return nil }
        return session.motions?.all.first { $0.id == motion }?.title
    }

    // MARK: My plans

    private var plans: some View {
        section("My plans") {
            let plans = session.desk?.plans ?? []
            if plans.isEmpty {
                Text(
                    "Nothing planned. When I set myself a reminder to look at something, it shows here."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(plans) { plan in
                        PlanRow(plan: plan) { editing = plan }
                            .contextMenu {
                                Button("Change…", systemImage: "pencil") { editing = plan }
                                Button("Cancel this plan", systemImage: "xmark", role: .destructive)
                                {
                                    Task { try? await session.cancel(plan.id) }
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: Done

    private var done: some View {
        section("Done") {
            if let work {
                VStack(alignment: .leading, spacing: 14) {
                    if work.handled.isEmpty {
                        Text("Nothing yet today.")
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    }
                    ForEach(work.handled.prefix(Self.shown)) { entry in
                        DoneEntryRow(entry: entry, undo: undo(_:), correct: correct(_:_:))
                    }
                    NavigationLink(value: Route.allWork) {
                        HStack(spacing: 4) {
                            Text(allWorkLabel(work))
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 26)
                }
            } else if let workProblem {
                VStack(alignment: .leading, spacing: 8) {
                    DeskProblemLine(text: workProblem)
                    DeskPill(title: "Try again") { Task { await load() } }
                }
            } else {
                ProgressView().tint(.ariSecondary)
            }
        }
    }

    /// How many of today's things show here; the rest are in all of Kumo's work.
    private static let shown = 4

    /// "and 6 more", with the mail read and left alone, or "Everything I've done".
    private func allWorkLabel(_ work: KumoWork) -> String {
        let more = max(0, work.handled.count - Self.shown) + work.cleared.count
        return more > 0 ? "and \(more) more" : "Everything I've done"
    }

    private func load() async {
        do {
            work = try await session.work()
            workProblem = nil
        } catch {
            workProblem = "Couldn't load today's work: \(DeskSending.words(for: error))"
        }
    }

    private func undo(_ entry: DoneEntry) async throws {
        try await session.undo(entry.id)
        await load()
    }

    private func correct(_ entry: DoneEntry, _ words: String?) async throws {
        try await session.correct(entry.id, text: words)
        await load()
    }

    // MARK: Getting to know you

    private func gettingToKnowYou(_ tracks: [Track]) -> some View {
        section("Getting to know you") {
            VStack(spacing: 14) {
                ForEach(tracks) { track in
                    NavigationLink(value: Route.track(track.id)) { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A card that needs you, as one row: a bone dot, its title, where it belongs, and a chevron.
private struct NeedsYouRow: View {
    let card: DeskCard
    let context: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Circle().fill(.ariBone).frame(width: 6, height: 6)
                Text(card.title)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let context {
                    Text(context)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariBone.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!card.kind.isKnown)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }
}
