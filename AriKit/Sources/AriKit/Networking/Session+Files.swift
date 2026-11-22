import Foundation

/// Recordings, their transcripts, the files Kumo shows, and what the server takes.
extension Session {
    /// What the server takes and whether it can transcribe now, asked once and kept; `refresh`
    /// asks again, as when you're about to pick a recording.
    public func uploadLimits(refresh: Bool = false) async throws(RequestError) -> UploadList {
        if let uploadList, !refresh { return uploadList }
        let list = try await client.uploads()
        uploadList = list
        return list
    }

    /// The limits as last heard, without asking.
    public var knownUploadLimits: UploadList? { uploadList }

    /// Asks for the recordings on screen again, after a snapshot: their changes are compacted.
    func refreshRecordings() {
        guard !recordings.isEmpty else { return }
        let client = client
        Task {
            guard let list = try? await client.recordings() else { return }
            for recording in list { recordings[recording.attachment] = recording }
        }
    }

    /// Where a recording on screen stands, when Ari hasn't heard since it opened.
    public func refreshRecording(_ recording: AttachmentID) async {
        guard let now = try? await client.recording(recording) else { return }
        recordings[now.attachment] = now
    }

    /// A recording's transcript, with your corrections.
    public func transcript(of recording: AttachmentID) async throws(RequestError) -> Transcript {
        try await client.transcript(of: recording)
    }

    /// Fixes words the server misheard, everywhere they were heard. The answer is the transcript,
    /// corrected.
    public func correct(_ recording: AttachmentID, heard: String, meant: String)
        async throws(RequestError) -> Transcript
    {
        try await client.correct(
            recording,
            CorrectTranscript(replace: [Transcript.Correction(heard: heard, meant: meant)]))
    }

    /// Transcribes a failed recording again.
    public func retryRecording(_ recording: AttachmentID) async throws(RequestError) {
        let now = try await client.retryRecording(recording)
        recordings[now.attachment] = now
    }

    /// Deletes a recording's audio and transcript from the server. The message stays.
    public func deleteRecording(_ recording: AttachmentID) async throws(RequestError) {
        let now = try await client.deleteRecording(recording)
        recordings[now.attachment] = now
    }

    /// A file Kumo showed, with every version: kept once fetched, unless `refresh`, as when a card
    /// opens and a newer version may exist.
    public func shownFile(_ file: FileID, refresh: Bool = false) async throws(RequestError)
        -> ShownFile
    {
        if let kept = shownFiles[file], !refresh { return kept }
        let fetched = try await client.file(file)
        shownFiles[file] = fetched
        return fetched
    }

    /// A recording's audio as a file on the phone: the one this phone sent, kept a week, or
    /// downloaded once into the caches.
    public func recordingFile(_ recording: Attachment) async throws -> URL {
        if let kept = bigUploads?.store.keptFile(recording.id) { return kept }
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appending(path: "Recordings", directoryHint: .isDirectory)
        let ext = (recording.name as NSString).pathExtension
        let file = folder.appending(path: recording.id.rawValue + (ext.isEmpty ? "" : "." + ext))
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let (downloaded, response) = try await URLSession(configuration: configuration)
            .download(for: client.attachmentRequest(recording.id))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RequestError.refused(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0, error: nil, retryAfter: nil
            )
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: downloaded, to: file)
        return file
    }

    /// The file kept from a cache, without asking.
    public func knownShownFile(_ file: FileID) -> ShownFile? {
        shownFiles[file]
    }
}
