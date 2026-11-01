import AriKit
import SwiftUI

/// Something wrong on the server, in one quiet line on the Desk: its title beside a small mark. A
/// tap opens how to fix it. It stays until it's fixed, when the server clears it.
struct ProblemLine: View {
    let problem: ServerProblem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: ProblemLook.symbol(problem.area))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ariBone)
                    .accessibilityHidden(true)
                Text(problem.title)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(problem.title)
        .accessibilityHint("Shows how to fix it")
    }
}

/// A problem in full: what's wrong, what it means for you, and how to fix it.
struct ProblemView: View {
    let problem: ServerProblem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(problem.title, systemImage: ProblemLook.symbol(problem.area))
                    .font(.headline)
                    .foregroundStyle(.ariText)
                Text(problem.detail)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    DeskSectionLabel("How to fix it")
                    Text(problem.fix)
                        .font(.ariBody)
                        .foregroundStyle(.ariText)
                        .lineSpacing(Rhythm.ariLineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("This goes away by itself once it's fixed.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(.ariBackground)
    }
}

/// How each area of problem looks: a symbol for what it's about.
enum ProblemLook {
    static func symbol(_ area: ProblemArea) -> String {
        switch area {
        case .notifications: "bell.slash"
        case .mail: "envelope.badge"
        case .calendar: "calendar.badge.exclamationmark"
        case .capabilities: "puzzlepiece.extension"
        default: "exclamationmark.circle"
        }
    }
}

#if DEBUG
    #Preview("A problem") {
        VStack(alignment: .leading, spacing: 14) {
            ProblemLine(problem: ProblemSamples.push) {}
            ProblemLine(problem: ProblemSamples.outlook) {}
        }
        .padding(18)
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }

    #Preview("How to fix it") {
        ProblemView(problem: ProblemSamples.push)
            .preferredColorScheme(.dark)
    }

    enum ProblemSamples {
        static let push = ServerProblem(
            id: "push", area: .notifications, title: "Notifications can't be sent",
            detail:
                "This server has no Apple push key, so nothing reaches your phone while Ito is closed.",
            fix:
                "On the server, run ito push setup with your APNs key. The server's README, under Notifications, has the steps."
        )
        static let outlook = ServerProblem(
            id: "mail:outlook", area: .mail, title: "Outlook mail isn't working",
            detail:
                "Kumo can't read or file your Outlook mail: Microsoft didn't renew the sign-in.",
            fix: "Sign in to Outlook again in Settings › Capabilities › Outlook.")
    }
#endif
