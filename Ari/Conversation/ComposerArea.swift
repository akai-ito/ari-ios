import AriKit
import SwiftUI

/// The composer with what you've attached. Its own view, holding the draft, so typing redraws only
/// the composer and not the whole conversation above it; and equatable, so the conversation's
/// changes (a step, each word of a reply) don't redraw the composer either. Its text field measures
/// itself with TextKit on every redraw, which grew costly enough to freeze long conversations.
struct ComposerArea: View, Equatable {
    let session: Session
    @Binding var attached: [PendingAttachment]
    @Binding var attachProblem: String?
    let working: Bool
    /// Your Stop is on its way.
    let stopping: Bool
    /// What Ari waits for you to answer, if anything.
    let asking: Ask?
    let send: (String) -> Bool
    let stop: () -> Void
    let attach: (PendingAttachment) -> Void
    let detach: (AttachmentID) -> Void
    /// Starts a call, where Ari can take one.
    var talk: (() -> Void)?
    var talkReady = true
    /// What the empty field says, such as "Reply in thread"; the chat's own words otherwise.
    var prompt: String?
    /// Where what you're writing is kept: each thread keeps its own.
    var draftKey = "draft"
    /// Inside a thread, a line of the message you're replying to, and how to stop replying to it.
    var quoting: String?
    var stopQuoting: (() -> Void)?

    /// What you're writing. Saved a moment after you stop typing, and when Ari leaves the screen,
    /// so it survives Ari closing; saved on every keystroke, the field kept waiting on it.
    @State private var draft = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Composer(
            draft: $draft, role: role,
            prompt: asking.map(Self.takesTypedAnswer) == true
                ? "Answer \(LeadName.current)" : (prompt ?? "Message \(LeadName.current)"),
            send: submit, stop: stop, talk: talk, talkReady: talkReady
        ) {
            AttachButton(
                room: AttachmentMaker.mostPerMessage - attached.count, add: attach,
                problem: { attachProblem = $0 })
        } above: {
            if let quoting {
                QuoteChip(text: quoting, remove: stopQuoting)
            }
            if !attached.isEmpty {
                AttachedStrip(attached: attached, uploads: session.uploads, remove: detach)
            }
            if let attachProblem {
                Text(attachProblem)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .task(id: attachProblem) {
                        try? await Task.sleep(for: .seconds(4))
                        if !Task.isCancelled { self.attachProblem = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: attached)
        .animation(.easeInOut(duration: 0.2), value: quoting)
        .onAppear {
            if draft.isEmpty { draft = UserDefaults.standard.string(forKey: draftKey) ?? "" }
        }
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { saveDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraft() }
        }
        #if DEBUG
            .task {
                if let draft = DebugScript.draft { self.draft = draft }
            }
        #endif
    }

    private var role: ComposerRole {
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attached.isEmpty {
            return ConversationView.anyRefused(attached, in: session) ? .idle : .send
        }
        if working, !stopping { return .stop }
        // Stop while Ari waits for you cancels what it asked.
        return asking != nil ? .stop : .idle
    }

    private func submit() {
        guard send(draft) else { return }
        draft = ""
        saveDraft()
    }

    private func saveDraft() {
        UserDefaults.standard.set(draft, forKey: draftKey)
    }

    /// Only what the composer shows: the closures are the conversation's own, the same each time.
    static func == (a: ComposerArea, b: ComposerArea) -> Bool {
        a.attached == b.attached && a.attachProblem == b.attachProblem && a.working == b.working
            && a.stopping == b.stopping && a.asking == b.asking && a.talkReady == b.talkReady
            && a.prompt == b.prompt && a.quoting == b.quoting && a.draftKey == b.draftKey
    }

    /// Whether an ask takes a typed answer. Any message still answers it, but the composer only
    /// invites one when the ask does.
    private static func takesTypedAnswer(_ ask: Ask) -> Bool {
        ask.allowsText || ask.options.isEmpty
    }
}
