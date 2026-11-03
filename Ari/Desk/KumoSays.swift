import AriKit
import SwiftUI

/// Whether Kumo is keeping up: reading, with when the last mail came in, or something's wrong; or
/// nothing to say, with no mail connected.
enum KumoLiveness: Equatable {
    case reading(lastMail: Date)
    case wrong
    case idle

    /// From the Desk and the server's problems.
    init(lastMail: Timestamp?, hasProblems: Bool) {
        if hasProblems {
            self = .wrong
        } else if let lastMail {
            self = .reading(lastMail: lastMail.date)
        } else {
            self = .idle
        }
    }
}

/// The top of the Desk: Kumo's face, a tiny line on how it is, and Kumo's line, when it has set
/// one. Tapping the face, or the line while all's well, opens Kumo's work.
struct KumoSays: View {
    let line: DeskLine?
    let liveness: KumoLiveness
    let openWork: () -> Void
    let openSettings: () -> Void
    /// Opens what's wrong, from "Something's wrong ›".
    let openProblems: () -> Void

    @State private var presence = PoseHistory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Button(action: openWork) {
                    PresenceView(history: presence, size: 44)
                        .frame(width: 64, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LeadName.current)'s work")
                .accessibilityHint("Shows what \(LeadName.current) did today")
                .padding(.bottom, 2)
                KumoStatusLine(
                    liveness: liveness, open: liveness == .wrong ? openProblems : openWork)
                if let line {
                    Text(line.text)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.ariText)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340)
                        .padding(.horizontal, 8)
                        .id(line.at)
                        .transition(
                            reduceMotion
                                ? .opacity : .opacity.combined(with: .offset(y: 6))
                        )
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            SettingsButton(action: openSettings)
        }
        .padding(.top, 12)
        .animation(.smooth(duration: 0.4), value: line)
        .onChange(of: pose, initial: true) { _, pose in presence.set(pose) }
    }

    /// A little off when something's wrong; a quiet stone otherwise.
    private var pose: Pose {
        liveness == .wrong ? .unwell : .resting
    }
}

/// How Kumo is, in one tiny line under its face: "Reading · last mail 2 min ago", or, when
/// something's wrong, "Something's wrong ›", which opens what.
struct KumoStatusLine: View {
    let liveness: KumoLiveness
    let open: () -> Void

    var body: some View {
        if liveness != .idle { line }
    }

    private var line: some View {
        Button(action: open) {
            switch liveness {
            case .idle:
                EmptyView()
            case .reading(let lastMail):
                // The timeline's date is the minute's start; the line says what the clock says.
                TimelineView(.everyMinute) { _ in
                    Text("Reading · last mail \(Self.ago(lastMail, now: .now))")
                        .foregroundStyle(.ariTertiary)
                }
            case .wrong:
                Text("Something's wrong \(Text("›").foregroundStyle(.ariTertiary))")
                    .fontWeight(.semibold)
                    .foregroundStyle(.ariBone)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .accessibilityHint(
            liveness == .wrong ? "Shows what's wrong" : "Shows \(LeadName.current)'s work")
    }

    /// "just now", "2 min ago", the time past an hour, or the day before today: "at 14:05" alone
    /// read as today after a quiet weekend.
    static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "at \(date.formatted(DeskTime.time))" }
        return "on \(date.formatted(DeskTime.weekdayDay))"
    }
}

/// Done on the Desk: one plain row that opens Kumo's work. How much Kumo handled is said once, in
/// its quiet line.
struct DeskDoneLine: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            DeskSectionLabel("Done", trailing: "›")
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Done")
        .accessibilityHint("Shows what \(LeadName.current) did")
        .accessibilityAddTraits(.isButton)
    }
}
