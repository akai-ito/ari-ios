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

    /// What you're writing. Saved a moment after you stop typing, and when Ari leaves the screen,
    /// so it survives Ari closing; saved on every keystroke, the field kept waiting on it.
    @State private var draft = UserDefaults.standard.string(forKey: "draft") ?? ""
    /// A secret answer, such as a code: apart from your draft, so your draft never goes as the
    /// secret and the secret is never saved. It's gone once sent, or once Ari stops asking.
    @State private var secretAnswer = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let secret = asking?.secret ?? false
        Composer(
            draft: secret ? $secretAnswer : $draft, role: role,
            prompt: asking.map(Self.takesTypedAnswer) == true ? "Answer Ari" : "Message Ari",
            secret: secret, send: submit, stop: stop
        ) {
            // A secret answer is only ever typed.
            if !secret {
                AttachButton(
                    room: AttachmentMaker.mostPerMessage - attached.count, add: attach,
                    problem: { attachProblem = $0 })
            }
        } above: {
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
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { saveDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraft() }
        }
        .onChange(of: asking?.secret ?? false) { _, secret in
            if !secret { secretAnswer = "" }
        }
        #if DEBUG
            .task {
                if let draft = DebugScript.draft { self.draft = draft }
            }
        #endif
    }

    private var role: ComposerRole {
        let text = asking?.secret == true ? secretAnswer : draft
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attached.isEmpty {
            return ConversationView.anyRefused(attached, in: session) ? .idle : .send
        }
        if working, !stopping { return .stop }
        // Stop while Ari waits for you cancels what it asked.
        return asking != nil ? .stop : .idle
    }

    private func submit() {
        if asking?.secret == true {
            guard send(secretAnswer) else { return }
            secretAnswer = ""
            return
        }
        guard send(draft) else { return }
        draft = ""
        saveDraft()
    }

    private func saveDraft() {
        UserDefaults.standard.set(draft, forKey: "draft")
    }

    /// Only what the composer shows: the closures are the conversation's own, the same each time.
    static func == (a: ComposerArea, b: ComposerArea) -> Bool {
        a.attached == b.attached && a.attachProblem == b.attachProblem && a.working == b.working
            && a.stopping == b.stopping && a.asking == b.asking
    }

    /// Whether an ask takes a typed answer. Any message still answers it, but the composer only
    /// invites one when the ask does.
    private static func takesTypedAnswer(_ ask: Ask) -> Bool {
        ask.allowsText || ask.options.isEmpty || ask.secret
    }
}
