import Foundation

/// The repository's pinned copy of ito-core's protocol, read in place. It is found by walking up
/// from this file, which works under `swift test`, under `xcodebuild test`, and in the iOS Simulator
/// (it can't on a device, where the source tree doesn't exist).
enum Fixtures {
    static func protocolDirectory(near file: String = #filePath) throws -> URL {
        var directory = URL(filePath: file).deletingLastPathComponent()
        while directory.path(percentEncoded: false) != "/" {
            let candidate = directory.appending(path: "protocol", directoryHint: .isDirectory)
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "transcripts").path(percentEncoded: false))
            {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw TranscriptError("No protocol/transcripts directory above \(file)")
    }

    static func transcriptFiles() throws -> [URL] {
        let directory = try protocolDirectory().appending(
            path: "transcripts", directoryHint: .isDirectory)
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every golden transcript, in scenario order.
    static func transcripts() throws -> [Transcript] {
        try transcriptFiles().map(Transcript.init(contentsOf:))
    }

    /// One transcript by name, such as "07-stop".
    static func transcript(_ name: String) throws -> Transcript {
        try Transcript(contentsOf: protocolDirectory().appending(path: "transcripts/\(name).jsonl"))
    }

    /// protocol/events.schema.json.
    static func eventsSchema() throws -> JSONValue {
        try JSONValue(
            data: Data(contentsOf: protocolDirectory().appending(path: "events.schema.json")))
    }
}
