import AriKit
import SwiftUI

extension TrackStage {
    /// Its name. One Ari doesn't know counts as Learning.
    var name: String {
        switch rung {
        case 2: "Trusted"
        case 1: "Spot checks"
        default: "Learning"
        }
    }
}

/// How far Kumo has come in an area, in nine dots: three for each stage, lit up to the one it has
/// reached, the rest faint.
struct DotBar: View {
    let stage: TrackStage
    var dot: CGFloat = 6

    var body: some View {
        HStack(spacing: dot * 1.4) {
            ForEach(0..<3, id: \.self) { group in
                HStack(spacing: dot * 0.75) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(group <= stage.rung ? Color.ariText.opacity(0.85) : .ariLine)
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(stage.name)
    }
}

/// A track as a row in Getting to know you: its name, and its dots. A tap opens what it stands on.
struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack {
            Text(track.name)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
            Spacer(minLength: 12)
            DotBar(stage: track.stage)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.ariTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows what it stands on")
    }
}

/// One track in full: where Kumo stands and since when, its line on why, and the evidence it stands
/// on, newest first.
struct TrackView: View {
    let track: Track

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(track.stage.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ariBone)
                        Text("since \(track.since.date.formatted(DeskTime.weekdayDayMonth))")
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                        Spacer(minLength: 8)
                        DotBar(stage: track.stage, dot: 7)
                    }
                    if let note = track.note {
                        Text(note)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.ariText)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(counts)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                }
                if !track.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        DeskSectionLabel("What it stands on")
                        ForEach(Array(track.evidence.enumerated()), id: \.offset) { _, evidence in
                            EvidenceRow(evidence: evidence)
                        }
                    }
                }
                Text(
                    "Learning: I show you my calls and ask when I'm unsure. Spot checks: I check with you now and then. Trusted: I bring only what needs you. A correction always steps it back; to change it yourself, tell me."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var counts: String {
        let confirmed = track.confirmed == 1 ? "1 time right" : "\(track.confirmed) times right"
        let corrected = track.corrected == 1 ? "1 correction" : "\(track.corrected) corrections"
        return "\(confirmed) · \(corrected)"
    }
}

/// One thing a track stands on: what happened, in a line, when, and the stage it led to.
private struct EvidenceRow: View {
    let evidence: TrackEvidence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(evidence.kind == .corrected ? Color.ariBone : .ariDusk)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(evidence.text)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch evidence.kind {
        case .confirmed: "checkmark"
        case .corrected: "arrow.uturn.backward"
        case .moved: "arrow.up.right"
        default: "circle"
        }
    }

    private var detail: String {
        let when = evidence.at.date.formatted(DeskTime.weekdayDayMonth)
        guard let stage = evidence.stage else { return when }
        return "\(when) · \(stage.name)"
    }
}
