import AriKit
import SwiftUI

/// The conversation's rows, and how each is drawn.
extension ConversationView {
    typealias Row = ConversationRow

    /// The conversation as it reads (messages, and Ari's trail between them), with the date at the
    /// start of each day.
    func rows(_ conversation: Conversation) -> [Row] {
        let key = RowsCache.Key(
            revision: conversation.revision, held: reveal.held,
            offering: offering && offersNotifications)
        if cache.key == key { return cache.rows }
        let rows = RowsCache.make(conversation, reveal: reveal.reveal, offering: key.offering)
        cache.keep(rows, for: key)
        return rows
    }

    @ViewBuilder
    func rowView(_ row: Row, in conversation: Conversation) -> some View {
        switch row.kind {
        case .day(let date):
            DayLabel(date: date)
        case .topic(let topic):
            TopicLabel(label: topic.label) { showsTopics = true }
        case .yours(let entry):
            YourMessage(
                text: entry.text,
                tag: tag(for: entry, in: conversation)
            ) {
                if !entry.attachments.isEmpty {
                    MessageAttachments(attachments: entry.attachments) {
                        await session.bytes(of: $0)
                    }
                }
            } footer: {
                if let spoken = entry.spoken {
                    SpokenFooter(spoken: spoken) { await session.bytes(of: $0) }
                }
            }
        case .call(let call):
            CallBlock(
                call: call, returnToCall: returnToCall(call),
                deleteAudio: { session.deleteAudio(of: call.id) })
        case .ari(let entry):
            let text = entry.text
            let document = cache.document(entry.id, text)
            Paced(shown: reveal.shown(entry), length: text.utf16.count) { position in
                VStack(alignment: .leading, spacing: 8) {
                    if !text.isEmpty {
                        ReplyView(document: document, position: position)
                            .environment(\.replyActions, replyActions(for: entry, in: conversation))
                    }
                    if position == .infinity { footer(for: entry, in: conversation) }
                }
            }
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(entry.text) }
                Button("Select Text", systemImage: "selection.pin.in.out") {
                    sheet = .selecting(entry.text)
                }
                ShareLink(item: entry.text)
            } preview: {
                // A long reply lifted whole would cover the screen, so the menu shows its opening.
                ReplyPreview(text: entry.text)
            }
        case .trail(let trail):
            TrailView(
                trail: trail, conversation: conversation, reveal: reveal, opened: $opened,
                answer: answer, document: cache.document)
        case .failure(let turn, let error):
            failureLine(turn: turn, error: error, in: conversation)
        case .offer:
            NotificationOffer(answer: answerOffer)
        }
    }

    /// What a reply's shapes can do here: tick its plans, fetch its pictures, and, while it's the
    /// latest thing said and Ari is idle, send one of its choices.
    func replyActions(for entry: Conversation.Entry, in conversation: Conversation)
        -> ReplyActions
    {
        let latest =
            conversation.turn == nil && conversation.entries.last(where: \.isShown)?.id == entry.id
        let session = session
        return ReplyActions(
            choose: latest
                ? { label in
                    guard session.send(label) != nil else { return }
                    scrollToEnd()
                } : nil)
    }

    /// Under your message: whether the server has it, and whether Ari took it in or it waits.
    func tag(for entry: Conversation.Entry, in conversation: Conversation) -> String? {
        if session.refusedMessages[entry.id] != nil { return "Couldn't send" }
        if entry.delivery == .sending {
            return session.link == .live ? "Sending" : "Waiting to send"
        }
        switch entry.mark {
        case .next: return "Next"
        case .read:
            // Once the adjusted reply starts, the reply itself shows Ari listened.
            let index = conversation.entries.firstIndex { $0.id == entry.id } ?? 0
            let answered = conversation.entries[index...].contains {
                $0.role == .agent && $0.isShown
            }
            return answered ? nil : "Read"
        default: return nil
        }
    }

    /// Under a reply, once it's all on screen: how it ended, if not as it should.
    @ViewBuilder
    func footer(for entry: Conversation.Entry, in conversation: Conversation) -> some View {
        switch entry.outcome {
        case .stopped: Tag(text: "Stopped")
        case .interrupted: Tag(text: "Interrupted · Your server restarted")
        case .failed:
            if let turn = entry.turn {
                failureLine(turn: turn, error: entry.error, in: conversation)
            }
        default: EmptyView()
        }
    }

    func failureLine(turn: TurnID, error: ServerError?, in conversation: Conversation)
        -> some View
    {
        FailureLine(
            message: "Couldn't finish. "
                + (error?.message ?? "Something went wrong on the server."),
            canTryAgain: !conversation.retriedTurns.contains(turn),
            tryAgain: { session.tryAgain(turn) },
            details: {
                sheet = .details(
                    error
                        ?? ServerError(code: ErrorCode(rawValue: "unknown"), message: "No details.")
                )
            })
    }
}
