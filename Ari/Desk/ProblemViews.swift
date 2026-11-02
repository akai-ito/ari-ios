import AriKit
import SwiftUI

/// What's wrong on the server, opened from "Something's wrong ›" under Kumo's face: each problem,
/// what it means for you and how to fix it. It follows the server, so a problem fixed meanwhile
/// leaves the list, and the Desk closes it once nothing's wrong.
struct ProblemsSheet: View {
    let problems: [ServerProblem]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(problems.enumerated()), id: \.element.id) { index, problem in
                        if index > 0 { Divider().overlay(Color.ariLine) }
                        ProblemDetail(problem: problem)
                    }
                    Text("Each goes away by itself once it's fixed.")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .animation(.smooth(duration: 0.3), value: problems)
            }
            .background(.ariBackground)
            .navigationTitle("Needs you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.ariText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One problem: what's wrong, what it means for you, and how to fix it. The same on the Desk's
/// list and at the top of Settings.
struct ProblemDetail: View {
    let problem: ServerProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(problem.title, systemImage: ProblemLook.symbol(problem.area))
                .font(.body.weight(.semibold))
                .foregroundStyle(.ariText)
            Text(problem.detail)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
            Text(problem.fix)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    }
}

/// How each area of problem looks: a symbol for what it's about.
enum ProblemLook {
    static func symbol(_ area: ProblemArea) -> String {
        switch area {
        case .notifications: "bell.slash"
        case .mail: "envelope.badge"
        case .calendar: "calendar.badge.exclamationmark"
        case .contacts: "person.crop.circle.badge.exclamationmark"
        case .capabilities: "puzzlepiece.extension"
        case .memory: "externaldrive.badge.exclamationmark"
        default: "exclamationmark.circle"
        }
    }
}

#if DEBUG
    #Preview("Needs you") {
        Color.ariBackground
            .sheet(isPresented: .constant(true)) {
                ProblemsSheet(problems: [ProblemSamples.push, ProblemSamples.outlook])
            }
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
