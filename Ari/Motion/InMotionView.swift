import AriKit
import SwiftUI

/// The In motion tab: the same six sections in the same order every time, like rooms in a home,
/// each loud inside. Kumo puts what matters most now first and largest, with its picture; what
/// stopped mattering folds into "+ N quieter". An empty section stays in its place as one quiet
/// line, so nothing moves. Ended things leave for History.
struct InMotionView: View {
    let openSettings: () -> Void

    @Environment(Motions.self) private var motions: Motions?
    @State private var opened: OpenedMotion?
    @State private var appeared = false
    @State private var path: [MotionRoute] = []
    @Namespace private var space

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                ScrollView {
                    if let motions, !motions.all.isEmpty {
                        let sections = InMotionReading.sections(motions.going)
                        VStack(alignment: .leading, spacing: 34) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) {
                                index, section in
                                SectionView(
                                    section: section, details: motions.details, space: space
                                )
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(
                                    .smooth(duration: 0.45).delay(0.05 * Double(index)),
                                    value: appeared)
                            }
                            if !InMotionReading.history(motions.done).isEmpty {
                                HistoryLink(done: motions.done).padding(.top, 4)
                            }
                            Color.clear.frame(height: 1).id("foot")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                        .frame(maxWidth: Rhythm.column, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                }
                .overlay { quiet }
                .background(.ariBackground)
                .navigationTitle("In motion")
                .navigationDestination(for: MotionRoute.self) { route in
                    switch route {
                    case .history: HistoryView()
                    case .section(let section): SectionListView(section: section)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape", action: openSettings)
                    }
                }
                .refreshable { await motions?.refresh() }
                .onAppear { appeared = true }
                #if DEBUG
                    .task {
                        if let id = DebugScript.motion {
                            opened = OpenedMotion(id: MotionID(id), source: "row \(id)")
                        }
                        switch DebugScript.motionRoute {
                        case "history": path = [.history]
                        case "bottom":
                            try? await Task.sleep(for: .seconds(2))
                            scroller.scrollTo("foot", anchor: .bottom)
                        default: break
                        }
                    }
                #endif
            }
        }
        .environment(
            \.motionOpener,
            MotionOpener(namespace: space) { id, source in
                opened = OpenedMotion(id: id, source: source)
            }
        )
        .motionCover($opened, in: space)
    }

    /// What shows while there's nothing to list.
    @ViewBuilder
    private var quiet: some View {
        if let motions, motions.all.isEmpty {
            switch motions.load {
            case .loading:
                ProgressView()
            case .failed(let error):
                VStack(spacing: 14) {
                    Text("Couldn't load what's in motion: \(error.plainWords)")
                        .font(.ariBody)
                        .foregroundStyle(.ariSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await motions.refresh() } }
                        .buttonStyle(.bordered)
                        .tint(.ariText)
                }
                .padding(40)
            case .loaded:
                Text(
                    "Nothing in motion yet. When \(LeadName.current) keeps something going with you, "
                        + "like a trip, a role or a training block, it lives here, and "
                        + "\(LeadName.current) keeps it current as you talk."
                )
                .font(.ariBody)
                .foregroundStyle(.ariTertiary)
                .multilineTextAlignment(.center)
                .padding(40)
            }
        }
    }
}

/// Where In motion goes within its tab.
enum MotionRoute: Hashable {
    case history
    /// Everything in a section, the quiet ones too.
    case section(MotionSection)
}

/// One section: its head with its art, then the loudest thing big with the rest as rows under it,
/// and what's quieter one tap away. Empty, it's one quiet line.
private struct SectionView: View {
    let section: InMotionReading.Section
    let details: [MotionID: MotionDetail]
    let space: Namespace.ID

    var body: some View {
        if section.isEmpty {
            HStack(spacing: 12) {
                HalftoneArt(art: section.kind, side: 36, across: 20, faded: true)
                    .frame(width: 56)
                Text(section.kind.name).font(.ariHeading).foregroundStyle(.ariTertiary)
                Spacer(minLength: 8)
                Text("nothing right now").font(.footnote).foregroundStyle(.ariTertiary)
            }
            .opacity(0.8)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HalftoneArt(art: section.kind, side: 56, across: 27)
                    Text(section.kind.name).font(.ariHeading).foregroundStyle(.ariText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
                if section.lead != nil || !section.rows.isEmpty {
                    VStack(spacing: 0) {
                        if let lead = section.lead {
                            MotionLead(motion: lead, detail: details[lead.id], space: space)
                        }
                        ForEach(section.rows) { motion in
                            Hairline().padding(.leading, 16)
                            MotionRow(motion: motion, detail: details[motion.id], space: space)
                        }
                    }
                    .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
                }
                if !section.quieter.isEmpty {
                    NavigationLink(value: MotionRoute.section(section.kind)) {
                        QuieterLink(text: quieterText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "3 going", "week 1 of 8", "1 coming".
    private var trailing: String? {
        let shown = (section.lead.map { [$0] } ?? []) + section.rows
        switch section.kind {
        case .body:
            if let lead = section.lead, case .body(let block)? = details[lead.id]?.content {
                return BodyReading.weekLine(of: block)?.lowercased()
            }
            return shown.isEmpty ? nil : "\(shown.count) going"
        case .trips:
            return shown.isEmpty ? nil : "\(shown.count) coming"
        default:
            return shown.isEmpty ? nil : "\(shown.count) going"
        }
    }

    /// "+ 4 quieter", or for one, what it is: "+ 1 quieter: Japan in spring".
    private var quieterText: String {
        let quiet = section.quieter
        if quiet.count == 1, let only = quiet.first { return "+ 1 quieter: \(only.title)" }
        return section.kind == .career
            ? "+ \(quiet.count) quieter leads" : "+ \(quiet.count) quieter"
    }
}

/// Everything in a section, loudest first, the quiet ones too: what "+ N quieter" opens.
private struct SectionListView: View {
    let section: MotionSection

    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.motionOpener) private var opener

    var body: some View {
        ScrollView {
            let all =
                InMotionReading.sections(motions?.going ?? [])
                .first { $0.kind == section }?.all ?? []
            VStack(spacing: 0) {
                ForEach(all) { motion in
                    if motion.id != all.first?.id { Hairline().padding(.leading, 16) }
                    MotionRow(
                        motion: motion, detail: motions?.details[motion.id],
                        space: opener.namespace, source: "list")
                }
            }
            .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle(section.name)
    }
}

/// The way to History: how each ended thing ended, as marks.
private struct HistoryLink: View {
    let done: [Motion]

    var body: some View {
        let ended = InMotionReading.history(done).flatMap(\.items)
        NavigationLink(value: MotionRoute.history) {
            HStack(spacing: 12) {
                Text("History").font(.ariHeading).foregroundStyle(.ariSecondary)
                HStack(spacing: 4) {
                    ForEach(ended.prefix(10)) { motion in
                        OutcomeMark(outcome: motion.outcome, side: 9)
                    }
                }
                Spacer(minLength: 8)
                Text("\(ended.count) ended").font(.footnote).foregroundStyle(.ariTertiary)
                    .fixedSize()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.ariSurface.opacity(0.55), in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("History, \(ended.count) ended")
    }
}
