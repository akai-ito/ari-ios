import AriKit
import SwiftUI

/// The In motion tab: what's going on, each with its line and how far along it is, then what's
/// done. These are the things you're actually doing, which Ari keeps current as you talk.
struct InMotionView: View {
    let openSettings: () -> Void

    @Environment(Motions.self) private var motions: Motions?
    @State private var opened: OpenedMotion?
    @State private var appeared = false
    @Namespace private var space

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let motions {
                        ForEach(Array(motions.going.enumerated()), id: \.element.id) {
                            index, motion in
                            row(motion, detail: motions.details[motion.id])
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(
                                    .smooth(duration: 0.45).delay(0.06 * Double(index)),
                                    value: appeared)
                        }
                        if !motions.done.isEmpty {
                            Text("Done")
                                .font(.ariHeading)
                                .foregroundStyle(.ariText)
                                .padding(.top, 22)
                                .padding(.bottom, 2)
                            ForEach(motions.done) { motion in done(motion) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: Rhythm.column)
                .frame(maxWidth: .infinity)
            }
            .overlay { quiet }
            .background(.ariBackground)
            .navigationTitle("In motion")
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
                }
            #endif
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
                    "Nothing in motion yet. When Ari plans something with you, like a trip, it "
                        + "lives here, and Ari keeps it current as you talk."
                )
                .font(.ariBody)
                .foregroundStyle(.ariTertiary)
                .multilineTextAlignment(.center)
                .padding(40)
            }
        }
    }

    private func row(_ motion: Motion, detail: MotionDetail?) -> some View {
        let line = MotionLineText(motion, detail)
        let source = "row \(motion.id)"
        return Button {
            opened = OpenedMotion(id: motion.id, source: source)
        } label: {
            HStack(spacing: 14) {
                SymbolDisc(symbol: MotionSymbol.name(for: motion.kind), size: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text(motion.title).font(.headline).foregroundStyle(.ariText)
                    HStack(spacing: 5) {
                        Text(line.detail)
                        if let left = line.left {
                            Text("·").foregroundStyle(.ariTertiary)
                            LeftCount(left: left)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
                    if let progress = line.progress {
                        ProgressLine(progress: progress)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
            .padding(14)
            .background(.ariSurface, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .motionSource(source, in: space)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }

    private func done(_ motion: Motion) -> some View {
        let source = "row \(motion.id)"
        return Button {
            opened = OpenedMotion(id: motion.id, source: source)
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                Text(motion.title).foregroundStyle(.ariSecondary)
                Spacer()
                if let doneAt = motion.doneAt {
                    Text(doneAt.date, format: .dateTime.day().month(.abbreviated))
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motionSource(source, in: space)
    }
}

/// How far along, as a thin line that fills with bone.
private struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.ariLine)
                Capsule().fill(.ariBone).frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.6), value: progress)
        .accessibilityHidden(true)
    }
}
