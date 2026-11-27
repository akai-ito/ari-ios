import Foundation
import Observation

/// Understanding you, for Getting to know you: Kumo's tracks, the questions it would like you to
/// explain, and what you answered lately. The session hands it every event; `question.changed`
/// carries each question as it moves on, and a snapshot asks again. A refresh that fails keeps what
/// was shown.
@MainActor
@Observable
public final class UnderstandingYou {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    /// As the server last said, with every question since.
    public private(set) var current: Understanding?
    public private(set) var load = Load.loading

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// The open questions to show: at most `limit`, those you haven't set aside first.
    public func shown(limit: Int = 3) -> [Question] {
        Array((current?.questions ?? []).filter(\.isOpen).prefix(limit))
    }

    /// Questions answered or settled lately, newest first.
    public var settled: [Question] { current?.recent ?? [] }

    /// Asks again, such as when Getting to know you opens.
    public func refresh() async {
        do {
            current = try await client.understanding()
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(error) }
        }
    }

    /// Answers a question: taps, your words or a recording, or none fit or not sure. It moves on at
    /// once; Kumo files what it learned in the background.
    @discardableResult
    public func answer(_ question: QuestionID, _ reply: QuestionReply) async throws(RequestError)
        -> Question
    {
        let answered = try await client.answer(question, reply)
        take(answered)
        return answered
    }

    /// Answers a question aloud: the recording goes up first, then the answer names it. The server
    /// hears it on its own GPU, and the answer's words follow in `question.changed`.
    @discardableResult
    public func answer(
        _ question: QuestionID, recording bytes: Data, mediaType: String = "audio/mp4",
        id: AttachmentID = AttachmentID(UUID().uuidString.lowercased())
    ) async throws(RequestError) -> Question {
        let uploaded = try await client.upload(
            id, name: "Your answer.m4a", mediaType: mediaType, bytes: bytes)
        return try await answer(question, QuestionReply(audio: uploaded.attachment.id))
    }

    /// "Not now": it stays open, after the rest, with no reminder.
    @discardableResult
    public func notNow(_ question: QuestionID) async throws(RequestError) -> Question {
        let later = try await client.notNow(question)
        take(later)
        return later
    }

    /// Follows the stream: a question added or moved on, on any device. A snapshot means asking
    /// again.
    public func apply(_ event: Event) {
        switch event.payload {
        case .snapshot:
            Task { await refresh() }
        case .questionChanged(let changed):
            take(changed.question)
        default:
            break
        }
    }

    /// A question as the server now has it, unless what's shown is newer.
    private func take(_ question: Question) {
        guard let current else { return }
        let known = (current.questions + current.recent).first { $0.id == question.id }
        if let known {
            if known.changedAt.date > question.changedAt.date { return }
            // Filed and answered at the same moment: an answer arriving after the filing keeps it.
            if known.changedAt == question.changedAt, known.filed != nil, question.filed == nil {
                return
            }
        }
        self.current = current.with(question)
    }
}
