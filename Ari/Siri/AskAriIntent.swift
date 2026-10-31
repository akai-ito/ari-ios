import AppIntents
import AriKit
import UIKit

/// "Hey Siri, ask Ari": Siri asks what to send, and it goes to Ari like a message from the chat.
/// A reply within ten seconds comes back through Siri; a slower one arrives as a notification,
/// as any reply does while you're away. Shortcuts can send it too.
struct AskAriIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Ito"
    static let description = IntentDescription(
        "Send Kumo a message. A quick reply is read back; a longer one comes as a notification.")

    @Parameter(title: "Message", requestValueDialog: "What should I tell Kumo?")
    var message: String

    @Dependency private var model: AppModel

    /// How long Siri waits for the reply before leaving it to a notification.
    private static let patience = Duration.seconds(10)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = model.session else { throw AskAriError.notConnected }
        // In the background the stream is closed: open it for the reply, and say this device
        // is looking, so the server doesn't also push what Siri reads out.
        let wasPaused = session.link == .paused
        let wasLooking = model.isLooking
        if wasPaused { session.start() }
        if !wasLooking { model.setLooking(true) }
        defer {
            if !wasLooking { model.setLooking(false) }
            if wasPaused, UIApplication.shared.applicationState == .background,
                !CallEngine.isOn
            {
                session.pause()
            }
        }
        let id = MessageID(UUID().uuidString.lowercased())
        guard await session.sendFromNotification(message, id: id) else {
            throw AskAriError.notSent
        }
        if let answer = await Self.answer(to: id, in: session) {
            return .result(dialog: IntentDialog(stringLiteral: answer))
        }
        return .result(dialog: "\(LeadName.current)'s on it. The reply will come as a notification.")
    }

    /// What Ari said back, as Siri should say it, once the turn has ended: the reply up to its
    /// details, or the question it asked. `nil` if it takes longer than Siri waits.
    @MainActor
    private static func answer(to id: MessageID, in session: Session) async -> String? {
        let deadline = ContinuousClock.now + patience
        while ContinuousClock.now < deadline {
            let conversation = session.conversation
            if conversation.turn == nil, let sent = conversation[id]?.position {
                if let ask = conversation.waitingAsk, ask.position > sent {
                    return ask.question + " Answer it in Ito."
                }
                if let reply = conversation.entries.last(where: {
                    $0.role == .agent && $0.kind == .reply && $0.endedAt != nil
                        && ($0.position ?? 0) > sent
                }) {
                    return spoken(reply.text)
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// A reply as it's said aloud, as on a call: only what comes before a line holding `---`,
    /// as plain words, without the blocks Ari draws.
    static func spoken(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let said = lines.prefix { $0.trimmingCharacters(in: .whitespaces) != "---" }
        return ReplyDocument(markdown: said.joined(separator: "\n")).withoutShapes.plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AskAriError: Error, CustomLocalizedStringResourceConvertible {
    case notConnected
    case notSent

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected: "Ito isn't connected to your server yet. Open Ito to connect."
        case .notSent: "Ito couldn't reach your server just now. It'll send it when it can."
        }
    }
}
