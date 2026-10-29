import AriKit
import Foundation
import Testing

/// A golden transcript from ito-core: a header, the server's log when the scenario starts (`given`),
/// then every step in time order. protocol/transcripts/README.md describes the format.
struct Transcript: Sendable, CustomTestStringConvertible {
    /// The file's name without its extension, such as "07-stop".
    let name: String
    let header: Header
    /// The events in the server's log before the first step.
    let given: [LoggedEvent]
    let steps: [Step]

    var testDescription: String { name }

    struct Header: Sendable, Decodable {
        let transcript: String
        let scenario: Int
        let title: String
        let guarantees: [String]
        let app: App

        /// Where the app starts.
        struct App: Sendable, Decodable {
            /// The last event the app applied, if any.
            let cursor: EventID?
            /// The oldest message the app has cached, where that matters.
            let oldestCached: MessageID?

            enum CodingKeys: String, CodingKey {
                case cursor
                case oldestCached = "oldest_cached"
            }
        }
    }

    /// An event as the transcript holds it: its line, its JSON, and what Ari decodes from it.
    struct LoggedEvent: Sendable {
        let line: Int
        let json: JSONValue
        let event: Event
        /// When the app receives it, in milliseconds from the start; `nil` for a given event.
        var at: Int? = nil
    }

    enum Step: Sendable {
        /// The app sends a request.
        case app(Request)
        /// The app receives the answer to its last request, unless it was lost on the way.
        case server(Response)
        /// The app receives an event from `GET /v0/events`.
        case event(LoggedEvent)
        /// Something happens outside the API, such as the network dropping.
        case world(World)
        /// The server pushes a notification to a device: what the phone shows once it decrypts it.
        case push(Push)
        /// A frame on a call's stream, either way, or the server closing it.
        case socket(Socket)

        /// When it happens, in milliseconds from the start.
        var at: Int {
            switch self {
            case .app(let request): request.at
            case .server(let response): response.at
            case .event(let event): event.at ?? 0
            case .world(let world): world.at
            case .push(let push): push.at
            case .socket(let socket): socket.at
            }
        }

        var line: Int {
            switch self {
            case .app(let request): request.line
            case .server(let response): response.line
            case .event(let event): event.line
            case .world(let world): world.line
            case .push(let push): push.line
            case .socket(let socket): socket.line
            }
        }

        /// The step in a few words, such as "POST /v0/turns/t_1/stop" or "message.ended e_9", so a
        /// test can check it stopped where it meant to.
        var summary: String {
            switch self {
            case .app(let request): "\(request.method) \(request.path)"
            case .server(let response): "\(response.status)\(response.lost ? " lost" : "")"
            case .event(let event): "\(event.event.type) \(event.event.id?.rawValue ?? "")"
            case .world(let world): world.marker
            case .push(let push): "push \(push.json["notification"]?["kind"]?.string ?? "")"
            case .socket(let socket): "socket \(socket.fromApp ? "app" : "server")"
            }
        }
    }

    /// A frame on a call's stream: a text frame, the app's audio (a file in files), how much of
    /// Ari's voice arrived, or the server closing the socket.
    struct Socket: Sendable {
        let line: Int
        let at: Int
        let fromApp: Bool
        let frame: JSONValue?
        let audio: String?
        let audioMs: Int?
        let closed: Int?
        let reason: String?
    }

    struct Push: Sendable {
        let line: Int
        let at: Int
        let json: JSONValue
    }

    struct Request: Sendable {
        let line: Int
        let at: Int
        let method: String
        let path: String
        let headers: [String: String]
        let body: JSONValue?
        /// An upload's bytes: a file in protocol/transcripts/files.
        var bodyFile: String? = nil
        /// An upload's bytes, where only their number matters.
        var bodySize: Int? = nil

        var route: Route { Route(method: method, path: path) }

        /// The bytes an upload sends, or `nil` for any other request.
        func uploadBytes() throws -> Data? {
            if let bodyFile {
                return try Data(
                    contentsOf: Fixtures.protocolDirectory().appending(
                        path: "transcripts/files/\(bodyFile)"))
            }
            return bodySize.map { Data(count: $0) }
        }
    }

    struct Response: Sendable {
        let line: Int
        let at: Int
        let status: Int
        let headers: [String: String]
        let body: JSONValue?
        /// The answer never reached the app.
        let lost: Bool
    }

    struct World: Sendable {
        let line: Int
        let at: Int
        let marker: String
        /// The rest of the line, such as the code `ito pair` showed.
        var json: JSONValue? = nil
    }

    init(contentsOf url: URL) throws {
        name = url.deletingPathExtension().lastPathComponent
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        guard let first = lines.first else {
            throw TranscriptError("\(url.lastPathComponent) is empty")
        }
        header = try Self.reading(url, line: 1) {
            try JSONValue(json: String(first)).decode(Header.self)
        }

        var given: [LoggedEvent] = []
        var steps: [Step] = []
        for (index, text) in lines.enumerated().dropFirst() {
            let line = index + 1
            try Self.reading(url, line: line) {
                let json = try JSONValue(json: String(text))
                if let event = json["given"] {
                    let logged = LoggedEvent(
                        line: line, json: event, event: try event.decode(Event.self))
                    given.append(logged)
                } else if let event = json["event"] {
                    let logged = LoggedEvent(
                        line: line, json: event, event: try event.decode(Event.self),
                        at: json["at"]?.int ?? 0)
                    steps.append(.event(logged))
                } else if let request = json["app"] {
                    let sent = Request(
                        line: line, at: json["at"]?.int ?? 0,
                        method: request["method"]?.string ?? "",
                        path: request["path"]?.string ?? "",
                        headers: Self.headers(request["headers"]),
                        body: request["body"], bodyFile: request["body_file"]?.string,
                        bodySize: request["body_size"]?.int)
                    steps.append(.app(sent))
                } else if let response = json["server"] {
                    let answer = Response(
                        line: line, at: json["at"]?.int ?? 0, status: response["status"]?.int ?? 0,
                        headers: Self.headers(response["headers"]), body: response["body"],
                        lost: json["lost"] == .bool(true))
                    steps.append(.server(answer))
                } else if let socket = json["socket"] {
                    steps.append(
                        .socket(
                            Socket(
                                line: line, at: json["at"]?.int ?? 0,
                                fromApp: socket["from"]?.string == "app", frame: socket["frame"],
                                audio: socket["audio"]?.string, audioMs: socket["audio_ms"]?.int,
                                closed: socket["closed"]?.int, reason: socket["reason"]?.string)))
                } else if let push = json["push"] {
                    steps.append(.push(Push(line: line, at: json["at"]?.int ?? 0, json: push)))
                } else if let marker = json["world"]?.string {
                    steps.append(
                        .world(
                            World(
                                line: line, at: json["at"]?.int ?? 0, marker: marker, json: json)))
                } else {
                    throw TranscriptError("no given, event, app, server, world, push or socket")
                }
            }
        }
        self.given = given
        self.steps = steps
    }

    private init(name: String, header: Header, given: [LoggedEvent], steps: [Step]) {
        self.name = name
        self.header = header
        self.given = given
        self.steps = steps
    }

    /// The same transcript with each step replaced by what `transform` returns for it.
    func replacingSteps(_ transform: (Step) throws -> [Step]) rethrows -> Transcript {
        Transcript(name: name, header: header, given: given, steps: try steps.flatMap(transform))
    }

    /// Every event the transcript holds, given or received, in order.
    var events: [LoggedEvent] {
        given
            + steps.compactMap { step in
                if case .event(let event) = step { event } else { nil }
            }
    }

    private static func headers(_ json: JSONValue?) -> [String: String] {
        json?.object?.compactMapValues(\.string) ?? [:]
    }

    @discardableResult
    private static func reading<T>(_ url: URL, line: Int, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw TranscriptError("\(url.lastPathComponent) line \(line): \(error)")
        }
    }
}

/// What a request asks for, read from its method and path.
enum Route: Equatable {
    case discover
    case server
    case events
    case send
    case earlierMessages(before: MessageID, limit: Int?)
    case stop(TurnID)
    case retry(TurnID)
    case cancelAsk(AskID)
    /// Registering a device for notifications, or forgetting it.
    case device
    case presence
    /// Uploading a photo or file's bytes.
    case upload(AttachmentID, name: String)
    /// Fetching an attachment's bytes.
    case attachment(AttachmentID)
    case pair
    case capabilities
    case switchCapability(CapabilityID)
    case setUpCapability(CapabilityID)
    case checkCapability(CapabilityID)
    case connectCapability(CapabilityID)
    case memoryInMind
    case memoryShelves
    case memoryPages
    case memoryRecent
    case memoryPage
    case memoryChange(String)
    case models
    case chooseModel
    case startCall(CallID)
    case endCall(CallID)
    case deleteCallAudio(CallID)
    case voices
    case chooseVoice
    case forgetVoiceprint
    case speech
    case callStream(CallID)
    case motions
    case motion(MotionID)
    case motionState(MotionID)
    case other

    init(method: String, path: String) {
        let components = URLComponents(string: path)
        let parts = (components?.path ?? path).split(separator: "/").map(String.init)
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { $1 })
        switch (method, parts.count) {
        case ("GET", 2) where parts == [".well-known", "ito"]: self = .discover
        case ("GET", 2) where parts == ["v0", "server"]: self = .server
        case ("GET", 2) where parts == ["v0", "events"]: self = .events
        case ("POST", 2) where parts == ["v0", "messages"]: self = .send
        case ("GET", 2) where parts == ["v0", "messages"]:
            self = .earlierMessages(
                before: MessageID(query["before"] ?? ""), limit: query["limit"].flatMap { Int($0) })
        case ("POST", 4) where parts[0] == "v0" && parts[1] == "turns" && parts[3] == "stop":
            self = .stop(TurnID(parts[2]))
        case ("POST", 4) where parts[0] == "v0" && parts[1] == "turns" && parts[3] == "retry":
            self = .retry(TurnID(parts[2]))
        case ("POST", 4) where parts[0] == "v0" && parts[1] == "asks" && parts[3] == "cancel":
            self = .cancelAsk(AskID(parts[2]))
        case ("PUT", 3) where parts[0] == "v0" && parts[1] == "devices",
            ("DELETE", 3) where parts[0] == "v0" && parts[1] == "devices":
            self = .device
        case ("PUT", 3) where parts[0] == "v0" && parts[1] == "attachments":
            self = .upload(AttachmentID(parts[2]), name: query["name"] ?? "")
        case ("GET", 3) where parts[0] == "v0" && parts[1] == "attachments":
            self = .attachment(AttachmentID(parts[2]))
        case ("POST", 2) where parts == ["v0", "pair"]: self = .pair
        case ("PUT", 4) where parts[0] == "v0" && parts[1] == "devices" && parts[3] == "presence":
            self = .presence
        case ("GET", 2) where parts == ["v0", "capabilities"]: self = .capabilities
        case ("PUT", 3) where parts[0] == "v0" && parts[1] == "capabilities":
            self = .switchCapability(CapabilityID(parts[2]))
        case ("PUT", 4) where parts[0] == "v0" && parts[1] == "capabilities" && parts[3] == "setup":
            self = .setUpCapability(CapabilityID(parts[2]))
        case ("POST", 4)
        where parts[0] == "v0" && parts[1] == "capabilities" && parts[3] == "check":
            self = .checkCapability(CapabilityID(parts[2]))
        case ("POST", 4)
        where parts[0] == "v0" && parts[1] == "capabilities" && parts[3] == "connect":
            self = .connectCapability(CapabilityID(parts[2]))
        case ("GET", 3) where parts[0] == "v0" && parts[1] == "memory":
            switch parts[2] {
            case "in-mind": self = .memoryInMind
            case "shelves": self = .memoryShelves
            case "pages": self = .memoryPages
            case "recent": self = .memoryRecent
            case "page": self = .memoryPage
            default: self = .other
            }
        case ("GET", 4) where parts[0] == "v0" && parts[1] == "memory" && parts[2] == "changes":
            self = .memoryChange(parts[3])
        case ("GET", 2) where parts == ["v0", "models"]: self = .models
        case ("PUT", 2) where parts == ["v0", "agent"]: self = .chooseModel
        case ("PUT", 3) where parts[0] == "v0" && parts[1] == "calls":
            self = .startCall(CallID(parts[2]))
        case ("POST", 4) where parts[0] == "v0" && parts[1] == "calls" && parts[3] == "end":
            self = .endCall(CallID(parts[2]))
        case ("DELETE", 4) where parts[0] == "v0" && parts[1] == "calls" && parts[3] == "audio":
            self = .deleteCallAudio(CallID(parts[2]))
        case ("GET", 4) where parts[0] == "v0" && parts[1] == "calls" && parts[3] == "stream":
            self = .callStream(CallID(parts[2]))
        case ("GET", 2) where parts == ["v0", "voices"]: self = .voices
        case ("PUT", 2) where parts == ["v0", "voice"]: self = .chooseVoice
        case ("DELETE", 3) where parts == ["v0", "voice", "voiceprint"]: self = .forgetVoiceprint
        case ("POST", 2) where parts == ["v0", "speech"]: self = .speech
        case ("GET", 2) where parts == ["v0", "motion"]: self = .motions
        case ("GET", 3) where parts[0] == "v0" && parts[1] == "motion":
            self = .motion(MotionID(parts[2]))
        case ("PATCH", 4) where parts[0] == "v0" && parts[1] == "motion" && parts[3] == "state":
            self = .motionState(MotionID(parts[2]))
        default: self = .other
        }
    }

    /// Settings, the Library and a call ask for these, not the conversation's session.
    var isOutsideSession: Bool {
        switch self {
        case .capabilities, .switchCapability, .setUpCapability, .checkCapability,
            .connectCapability,
            .memoryInMind,
            .memoryShelves, .memoryPages, .memoryRecent, .memoryPage, .memoryChange, .models,
            .chooseModel, .voices, .chooseVoice, .forgetVoiceprint, .speech,
            .callStream, .motions, .motion, .motionState:
            true
        default: false
        }
    }
}

struct TranscriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
