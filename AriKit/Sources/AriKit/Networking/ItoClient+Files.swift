import Foundation

/// Big uploads, recordings and the files Kumo shows.
extension ItoClient {
    // MARK: - Big uploads

    /// `GET /v0/uploads`: the limits and what happens to a recording, to show before anything goes,
    /// and the big uploads that haven't finished.
    public func uploads() async throws(RequestError) -> UploadList {
        try await call(HTTPRequest(.get, "/v0/uploads"))
    }

    /// `POST /v0/uploads`: says what's coming. Starting the same upload again answers where it
    /// stands, so it's also how an upload resumes.
    public func createUpload(_ upload: CreateUpload) async throws(RequestError) -> UploadStatus {
        let result: UploadResult = try await call(
            HTTPRequest(.post, "/v0/uploads", body: try Self.json(upload)))
        return result.upload
    }

    /// `GET /v0/uploads/{upload}`: how much the server has.
    public func uploadStatus(_ upload: AttachmentID) async throws(RequestError) -> UploadStatus {
        let result: UploadResult = try await call(
            HTTPRequest(.get, "/v0/uploads/\(Self.segment(upload.rawValue))"))
        return result.upload
    }

    /// `PUT /v0/uploads/{upload}?offset=N`: the next bytes. The answer says how much the server
    /// now has.
    public func sendChunk(_ upload: AttachmentID, offset: Int, bytes: Data)
        async throws(RequestError) -> UploadStatus
    {
        let result: UploadResult = try await call(
            chunkRequest(upload, offset: offset, body: bytes),
            contentType: "application/octet-stream")
        return result.upload
    }

    /// The request for one chunk, without its body, for a background upload from a file.
    public func chunkRequest(_ upload: AttachmentID, offset: Int, body: Data? = nil) -> HTTPRequest
    {
        authorize(
            HTTPRequest(
                .put, "/v0/uploads/\(Self.segment(upload.rawValue))?offset=\(offset)",
                headers: ["Content-Type": "application/octet-stream"], body: body))
    }

    /// `POST /v0/uploads/{upload}/finish`: the upload becomes an attachment, to name in a message.
    public func finishUpload(_ upload: AttachmentID) async throws(RequestError) -> Attachment {
        let result: AttachmentResult = try await call(
            HTTPRequest(
                .post, "/v0/uploads/\(Self.segment(upload.rawValue))/finish", body: Data("{}".utf8))
        )
        return result.attachment
    }

    /// `DELETE /v0/uploads/{upload}`: gives up an unfinished upload.
    public func cancelUpload(_ upload: AttachmentID) async throws(RequestError) {
        try await callWithoutAnswer(
            HTTPRequest(.delete, "/v0/uploads/\(Self.segment(upload.rawValue))"))
    }

    /// Reads a chunk's answer, as a background upload hears it.
    public static func chunkAnswer(status: Int, headers: [String: String], body: Data)
        -> Result<UploadStatus, RequestError>
    {
        let response = HTTPResponse(status: status, headers: headers, body: body)
        do throws(RequestError) {
            try checkVersion(response.headers)
        } catch {
            return .failure(error)
        }
        // A refused chunk still says where the upload stands, such as after an offset mismatch.
        if let result = try? JSONDecoder().decode(UploadResult.self, from: body) {
            return (200..<300).contains(status)
                ? .success(result.upload)
                : .failure(
                    refusal(response))
        }
        return .failure(
            (200..<300).contains(status)
                ? .unreadable("no upload in the answer") : refusal(response)
        )
    }

    // MARK: - Recordings

    /// `GET /v0/recordings`: the recordings you sent, newest first, after a snapshot.
    public func recordings() async throws(RequestError) -> [Recording] {
        let list: RecordingList = try await call(HTTPRequest(.get, "/v0/recordings"))
        return list.recordings
    }

    /// `GET /v0/recordings/{attachment}`: where one recording stands.
    public func recording(_ recording: AttachmentID) async throws(RequestError) -> Recording {
        let result: RecordingResult = try await call(
            HTTPRequest(.get, "/v0/recordings/\(Self.segment(recording.rawValue))"))
        return result.recording
    }

    /// `GET /v0/recordings/{attachment}/transcript`.
    public func transcript(of recording: AttachmentID) async throws(RequestError) -> Transcript {
        let result: TranscriptResult = try await call(
            HTTPRequest(.get, "/v0/recordings/\(Self.segment(recording.rawValue))/transcript"))
        return result.transcript
    }

    /// `POST /v0/recordings/{attachment}/corrections`: misheard words, fixed everywhere they were
    /// heard. The answer is the transcript, corrected.
    public func correct(_ recording: AttachmentID, _ correction: CorrectTranscript)
        async throws(RequestError) -> Transcript
    {
        let result: TranscriptResult = try await call(
            HTTPRequest(
                .post, "/v0/recordings/\(Self.segment(recording.rawValue))/corrections",
                body: try Self.json(correction)))
        return result.transcript
    }

    /// `POST /v0/recordings/{attachment}/retry`: transcribe a failed recording again.
    public func retryRecording(_ recording: AttachmentID) async throws(RequestError) -> Recording {
        let result: RecordingResult = try await call(
            HTTPRequest(.post, "/v0/recordings/\(Self.segment(recording.rawValue))/retry"))
        return result.recording
    }

    /// `DELETE /v0/recordings/{attachment}`: its audio and transcript go.
    public func deleteRecording(_ recording: AttachmentID) async throws(RequestError) -> Recording {
        let result: RecordingResult = try await call(
            HTTPRequest(.delete, "/v0/recordings/\(Self.segment(recording.rawValue))"))
        return result.recording
    }

    /// `GET /v0/attachments/{attachment}` as a request of its own, to download a long recording
    /// straight to a file.
    public func attachmentRequest(_ attachment: AttachmentID) -> URLRequest {
        authorize(HTTPRequest(.get, "/v0/attachments/\(Self.segment(attachment.rawValue))"))
            .urlRequest(to: address.url)
    }

    // MARK: - Files Kumo shows

    /// `GET /v0/files`: every file Kumo showed you, newest change first, each with its versions,
    /// for the Made shelf.
    public func files() async throws(RequestError) -> [ShownFile] {
        let result: FileList = try await call(HTTPRequest(.get, "/v0/files"))
        return result.files
    }

    /// `GET /v0/files/{file}`: what an `ari:file` card needs, every version.
    public func file(_ file: FileID) async throws(RequestError) -> ShownFile {
        let result: FileResult = try await call(
            HTTPRequest(.get, "/v0/files/\(Self.segment(file.rawValue))"))
        return result.file
    }
}
