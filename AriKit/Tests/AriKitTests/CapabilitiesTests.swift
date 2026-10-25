import AriKit
import Foundation
import Testing

/// Settings › Capabilities through the real client: what Ari asks for, what it sends, and how it
/// keeps the list up to date.
@Suite("Capabilities")
@MainActor
struct CapabilitiesTests {
    static let list = """
        { "capabilities": [
          { "id": "reports", "kind": "hand", "title": "Reports",
            "summary": "Tells Ito's makers when something breaks", "symbol": "exclamationmark.bubble",
            "version": "0.1.0", "state": "on",
            "fields": [ { "name": "token", "label": "GitHub token", "kind": "secret", "set": true } ],
            "uses": { "hosts": ["api.github.com"] } },
          { "id": "time", "kind": "domain", "title": "Time", "summary": "Your calendar",
            "version": "0.1.0", "state": "needs_you", "detail": "iCloud rejected the password",
            "fields": [
              { "name": "apple_id", "label": "Apple ID", "kind": "text", "value": "you@icloud.com" },
              { "name": "password", "label": "App-specific password", "kind": "secret", "set": false },
              { "name": "calendars", "label": "Calendars", "kind": "choice", "optional": true,
                "options": [ { "value": "all", "label": "All" }, { "value": "home", "label": "Home" } ],
                "value": "all" },
              { "name": "travel", "label": "Travel time", "kind": "toggle", "value": true } ],
            "uses": { "hosts": ["caldav.icloud.com"], "folders": ["time"] } },
          { "id": "garden", "kind": "greenhouse", "title": "Garden", "summary": "", "state": "dormant" }
        ] }
        """

    @Test("reads the list: kinds, states, fields and what each reaches")
    func decodesTheList() throws {
        let list = try JSONDecoder().decode(CapabilityList.self, from: Data(Self.list.utf8))
        let reports = list.capabilities[0]
        #expect(reports.kind == .hand)
        #expect(reports.state == .on)
        #expect(reports.fields[0].kind == .secret && reports.fields[0].set)
        #expect(reports.fields[0].value == nil)
        #expect(reports.hosts == ["api.github.com"])
        #expect(reports.isSetUp)

        let time = list.capabilities[1]
        #expect(time.state == .needsYou)
        #expect(time.detail == "iCloud rejected the password")
        #expect(time.fields.map(\.kind) == [.text, .secret, .choice, .toggle])
        #expect(time.fields[2].required == false)
        #expect(time.fields[2].options.map(\.label) == ["All", "Home"])
        #expect(time.fields[3].value == .toggle(true))
        #expect(time.folders == ["time"])
        // The password isn't set, so setup isn't finished.
        #expect(!time.isSetUp)

        // A kind and a state this Ari doesn't know still decode.
        let garden = list.capabilities[2]
        #expect(!garden.kind.isKnown && !garden.state.isKnown)
    }

    @Test("groups domains apart from hands, and anything unknown with the hands")
    func groups() async throws {
        let server = StubServer()
        await server.answer(.get, "/v0/capabilities", with: Self.list)
        let capabilities = Capabilities(client: server.client)
        await capabilities.refresh()
        #expect(capabilities.load == .loaded)
        #expect(capabilities.domains.map(\.id) == ["time"])
        #expect(capabilities.hands.map(\.id) == ["reports", "garden"])
    }

    @Test("switching puts the server's answer in the list")
    func switches() async throws {
        let server = StubServer()
        await server.answer(.get, "/v0/capabilities", with: Self.list)
        await server.answer(
            .put, "/v0/capabilities/reports",
            with: """
                { "id": "reports", "kind": "hand", "title": "Reports", "summary": "", "state": "off" }
                """)
        let capabilities = Capabilities(client: server.client)
        await capabilities.refresh()
        try await capabilities.setOn("reports", false)
        #expect(capabilities.capability("reports")?.state == .off)
        #expect(capabilities.switching.isEmpty)
        let sent = try #require(await server.requests.last)
        #expect(sent.method == .put)
        #expect(
            try JSONSerialization.jsonObject(with: #require(sent.body)) as? [String: Bool] == [
                "on": false
            ])
    }

    @Test("setup sends values under `values`, and the answer replaces the capability")
    func savesSetup() async throws {
        let server = StubServer()
        await server.answer(.get, "/v0/capabilities", with: Self.list)
        await server.answer(
            .put, "/v0/capabilities/time/setup",
            with: """
                { "id": "time", "kind": "domain", "title": "Time", "summary": "", "state": "on",
                  "fields": [ { "name": "password", "label": "Password", "kind": "secret", "set": true } ] }
                """)
        let capabilities = Capabilities(client: server.client)
        await capabilities.refresh()
        let saved = try await capabilities.save("time", values: ["password": .text("abcd-efgh")])
        #expect(saved.state == .on)
        #expect(capabilities.capability("time")?.fields.first?.set == true)
        let body = try #require(await server.requests.last?.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: [String: String]])
        #expect(json == ["values": ["password": "abcd-efgh"]])
    }

    @Test("Test connection reads nothing as working, and a problem as not")
    func checks() async throws {
        let server = StubServer()
        await server.answer(.post, "/v0/capabilities/time/check", with: "{}")
        let capabilities = Capabilities(client: server.client)
        #expect(try await capabilities.check("time", values: [:]).ok)

        await server.answer(
            .post, "/v0/capabilities/time/check",
            with: #"{ "problem": "iCloud rejected the password" }"#)
        let result = try await capabilities.check("time", values: ["password": .text("wrong")])
        #expect(!result.ok)
        #expect(result.problem == "iCloud rejected the password")
    }

    @Test("a failed refresh keeps the list it had")
    func keepsTheListOnFailure() async throws {
        let server = StubServer()
        await server.answer(.get, "/v0/capabilities", with: Self.list)
        let capabilities = Capabilities(client: server.client)
        await capabilities.refresh()
        await server.goOffline()
        await capabilities.refresh()
        #expect(capabilities.all.count == 3)
        #expect(capabilities.load == .loaded)
    }

    @Test("the server's info lists the capabilities that are on")
    func serverInfo() throws {
        let info = try JSONDecoder().decode(
            ServerInfo.self,
            from: Data(
                """
                { "name": "box", "version": "0.5.0", "protocol": "0.5",
                  "agent": { "name": "Ari" }, "setup": { "notifications": true },
                  "capabilities": [ { "id": "reports", "version": "0.1.0" } ] }
                """.utf8))
        #expect(info.capabilities?.map(\.id) == ["reports"])
        #expect(info.setup?.notifications == true)
    }
}

/// A server that answers each route with a canned body, and remembers what Ari sent.
actor StubServer: Transport {
    private var answers: [String: String] = [:]
    private var offline = false
    private(set) var requests: [HTTPRequest] = []

    nonisolated var client: ItoClient {
        ItoClient(
            address: try! ServerAddress("http://127.0.0.1:8787"), token: Token("t"), transport: self
        )
    }

    func answer(_ method: HTTPRequest.Method, _ path: String, with body: String) {
        answers["\(method.rawValue) \(path)"] = body
    }

    func goOffline() { offline = true }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        guard !offline else { throw URLError(.notConnectedToInternet) }
        requests.append(request)
        guard let body = answers["\(request.method.rawValue) \(request.path)"] else {
            return HTTPResponse(status: 404, headers: ["ito-protocol": "0.4"], body: Data())
        }
        return HTTPResponse(status: 200, headers: ["ito-protocol": "0.4"], body: Data(body.utf8))
    }

    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        throw URLError(.unsupportedURL)
    }
}
