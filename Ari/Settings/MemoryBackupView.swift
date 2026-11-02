import AriKit
import SwiftUI

/// Settings › Memory: where what Ari knows is backed up. Off, a way to back it up to GitHub; on,
/// the repository and the last push, with Disconnect; stopped, what's wrong and Connect again.
struct MemoryBackupSection: View {
    let backup: Backup?
    /// What `GET /v0/server` says, until the backup itself has loaded.
    let isBackedUp: Bool?

    @State private var confirmsDisconnect = false
    @State private var problem: String?

    var body: some View {
        if let status = backup?.status {
            Section {
                rows(status)
            } header: {
                Text("Memory")
            } footer: {
                Text(problem ?? footer(status))
            }
            .listRowBackground(Color.ariSurface)
        } else if let isBackedUp {
            Section {
                LabeledContent("Backup", value: isBackedUp ? "On" : "Not backed up")
            } header: {
                Text("Memory")
            }
            .listRowBackground(Color.ariSurface)
        }
    }

    @ViewBuilder
    private func rows(_ status: MemoryBackup) -> some View {
        switch status.state {
        case .on:
            backedUp(status)
            if status.isThroughApp { disconnectButton }
        case .stopped:
            VStack(alignment: .leading, spacing: 4) {
                Label("Backup stopped", systemImage: "exclamationmark.circle")
                    .font(.body.weight(.semibold))
                if let reason = status.problem {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            if status.isThroughApp {
                NavigationLink("Connect GitHub again", value: SettingsRoute.memoryBackup)
                disconnectButton
            }
        case .connecting, .installing:
            NavigationLink(value: SettingsRoute.memoryBackup) {
                LabeledContent("Back up to GitHub", value: "Waiting for you")
            }
        default:
            NavigationLink("Back up to GitHub", value: SettingsRoute.memoryBackup)
        }
    }

    /// "Backed up to octo-person/ito-thread", and when it last got there.
    private func backedUp(_ status: MemoryBackup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Backed up to \(status.repository ?? status.remote ?? "your repository")")
                .font(.body)
                .lineLimit(2)
                .truncationMode(.middle)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.lastPush(status.pushedAt?.date, now: context.date))
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var disconnectButton: some View {
        Button("Disconnect") { confirmsDisconnect = true }
            .disabled(backup?.busy == true)
            .confirmationDialog(
                "Stop backing up to GitHub?", isPresented: $confirmsDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { disconnect() }
            } message: {
                Text(
                    "Ito forgets its access to GitHub. The repository and everything in it stay "
                        + "there, and memory stays on your server.")
            }
    }

    private func footer(_ status: MemoryBackup) -> String {
        let lead = LeadName.current
        switch status.state {
        case .on where status.isThroughApp:
            return "What \(lead) knows goes to your private repository after each change."
        case .on:
            return "Set on your server with ito memory remote, which pushes with its own git "
                + "credentials."
        case .stopped:
            return "Until it's fixed, what \(lead) knows is only on your server."
        case .connecting, .installing:
            return "Finish on GitHub, and it starts by itself."
        default:
            let tried = status.problem.map { " \($0)" } ?? ""
            return "What \(lead) knows lives only on your server. Back it up to a private "
                + "GitHub repository, and Ito pushes to it after each change.\(tried)"
        }
    }

    /// "Last push 2 min ago", or that nothing has gone yet.
    static func lastPush(_ date: Date?, now: Date) -> String {
        guard let date else { return "Nothing pushed yet" }
        if now.timeIntervalSince(date) < 60 { return "Last push just now" }
        let ago = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "Last push \(ago)"
    }

    private func disconnect() {
        problem = nil
        Task {
            do throws(RequestError) {
                try await backup?.disconnect()
            } catch {
                problem = "Couldn't disconnect: \(error.plainWords)"
            }
        }
    }
}

/// Backing up to GitHub, a step at a time: the code to approve, then installing Ito Memory on
/// just the one repository, then done. The server does the work and notices each step by itself;
/// this page follows along.
struct MemoryBackupPage: View {
    let backup: Backup

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @ScaledMetric(relativeTo: .footnote) private var stepSize: CGFloat = 24

    private var status: MemoryBackup? { backup.status }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(
                    "Ito keeps what \(LeadName.current) knows in a private GitHub repository of "
                        + "yours, ito\u{2011}thread, and pushes to it after each change. Ito Memory, Ito's "
                        + "GitHub app, can reach only that repository, and its access stays on "
                        + "your server."
                )
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .fixedSize(horizontal: false, vertical: true)
                content
                if let problem { line(problem, ok: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(.ariBackground)
        .navigationTitle("Back up to GitHub")
        .navigationBarTitleDisplayMode(.inline)
        .task { await open() }
        .task(id: status?.state) { await backup.follow() }
    }

    @ViewBuilder
    private var content: some View {
        switch status?.state {
        case .connecting?:
            approving
        case .installing?:
            installing
        case .on?:
            VStack(alignment: .leading, spacing: 18) {
                line(
                    "Backed up to \(status?.repository ?? status?.remote ?? "your repository")",
                    ok: true)
                Text("From now on, memory goes there after each change.")
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                Button("Done") { dismiss() }
                    .buttonStyle(SetupPill(primary: true))
            }
        case .stopped?, .off?:
            VStack(alignment: .leading, spacing: 18) {
                if let reason = status?.problem { line(reason, ok: false) }
                if backup.busy {
                    DeviceCodeCard(code: nil)
                } else {
                    Button("Try again") { Task { await start() } }
                        .buttonStyle(SetupPill(primary: true))
                }
            }
        default:
            if problem == nil {
                DeviceCodeCard(code: nil)
            } else {
                Button("Try again") { Task { await open() } }
                    .buttonStyle(SetupPill(primary: true))
            }
        }
    }

    /// The code, copied, and GitHub's page to approve it on.
    private var approving: some View {
        VStack(spacing: 22) {
            DeviceCodeCard(code: status?.code)
            if let url = status?.url {
                Button("Open GitHub") { openURL(url) }
                    .buttonStyle(SetupPill(primary: true))
            }
            waiting("Waiting for you to approve it on GitHub…")
        }
        .frame(maxWidth: .infinity)
    }

    /// Installing Ito Memory on the one repository: chosen already when GitHub can be told which,
    /// otherwise picked there; first made, when there may be none and the server can't make it yet.
    private var installing: some View {
        VStack(alignment: .leading, spacing: 18) {
            if status?.created == true, let repository = status?.repository {
                line("Ito made a private repository for it, \(repository).", ok: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                let makesFirst = status?.newRepositoryURL != nil
                if let url = status?.newRepositoryURL {
                    step(
                        1,
                        "No ito\u{2011}thread yet? Make it on GitHub, private, and leave it empty.",
                        title: "Make it on GitHub", url: url, primary: false)
                }
                if let url = status?.installURL {
                    step(
                        makesFirst ? 2 : 1, installWords, title: "Install on GitHub", url: url,
                        primary: true)
                }
            }
            waiting("Waiting for GitHub…")
        }
    }

    private var installWords: String {
        guard status?.repositoryChosen != true else {
            return "Install Ito Memory. GitHub opens with ito\u{2011}thread already chosen."
        }
        return "Install Ito Memory, with access to only ito\u{2011}thread: choose Only "
            + "select repositories, then ito\u{2011}thread."
    }

    private func step(_ number: Int, _ text: String, title: String, url: URL, primary: Bool)
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.ariBackground)
                .frame(width: stepSize, height: stepSize)
                .background(.ariBone, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityLabel("Step \(number): \(text)")
                Button(title) { openURL(url) }
                    .buttonStyle(SetupPill(primary: primary))
            }
        }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
        }
    }

    private func line(_ text: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? Color.ariBone : .ariSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Asks where the backup stands, then starts it if it's off or stopped. If the server can't be
    /// reached and nothing is known yet, says so, rather than waiting on a spinner.
    private func open() async {
        problem = nil
        await backup.refresh()
        guard let state = status?.state else {
            let why = backup.refreshProblem?.plainWords ?? "no answer."
            problem = "Couldn't reach your server: \(why)"
            return
        }
        if state == .off || state == .stopped { await start() }
    }

    private func start() async {
        problem = nil
        do throws(RequestError) {
            try await backup.start()
            if let code = backup.status?.code { UIPasteboard.general.string = code }
        } catch {
            problem = "Couldn't start backing up: \(error.plainWords)"
        }
    }
}
