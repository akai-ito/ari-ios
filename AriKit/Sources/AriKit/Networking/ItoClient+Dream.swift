import Foundation

// Kumo's dream and Understanding you: the moon and sun on the Desk, its page, Dream now, and the
// questions Kumo would like you to explain.

extension ItoClient {
    // MARK: - The dream

    /// `GET /v0/dream`: the dream time, when the next one is, one under way, and the latest record.
    public func dream() async throws(RequestError) -> DreamState {
        try await call(HTTPRequest(.get, "/v0/dream"))
    }

    /// `POST /v0/dream`: Dream now. It answers at once with the dream under way; `dream.finished`
    /// follows when it's done. While one runs, it answers with that one and starts nothing.
    public func dreamNow() async throws(RequestError) -> DreamState {
        try await call(HTTPRequest(.post, "/v0/dream"))
    }

    /// `PUT /v0/dream/time`: when Kumo dreams each night, such as `04:00`, on your local clock.
    public func setDreamTime(_ time: String) async throws(RequestError) -> DreamState {
        try await call(
            HTTPRequest(.put, "/v0/dream/time", body: try Self.json(DreamTime(time: time))))
    }

    /// `POST /v0/dreams/{dream}/seen`: you've seen its record, so the moon becomes the sun. Seeing
    /// it again keeps the first time.
    public func see(_ dream: DreamID) async throws(RequestError) -> Dream {
        let answer: DreamResult = try await call(
            HTTPRequest(.post, "/v0/dreams/\(Self.segment(dream.rawValue))/seen"))
        return answer.dream
    }

    // MARK: - Understanding you

    /// `GET /v0/understanding`: every track, the open questions, and what you answered lately.
    public func understanding() async throws(RequestError) -> Understanding {
        try await call(HTTPRequest(.get, "/v0/understanding"))
    }

    /// `POST /v0/understanding/questions/{question}/answer`: taps, your words or a recording, or
    /// none fit or not sure. The question comes back `answered`; Kumo files it in the background.
    public func answer(_ question: QuestionID, _ reply: QuestionReply) async throws(RequestError)
        -> Question
    {
        let answer: QuestionResult = try await call(
            HTTPRequest(
                .post, "/v0/understanding/questions/\(Self.segment(question.rawValue))/answer",
                body: try Self.json(reply)))
        return answer.question
    }

    /// `POST /v0/understanding/questions/{question}/not-now`: leaves it open for another time, with
    /// no reminder, after the rest.
    public func notNow(_ question: QuestionID) async throws(RequestError) -> Question {
        let answer: QuestionResult = try await call(
            HTTPRequest(
                .post, "/v0/understanding/questions/\(Self.segment(question.rawValue))/not-now"))
        return answer.question
    }
}
