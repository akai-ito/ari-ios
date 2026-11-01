import AriKit
import Clocks
import Foundation
import Testing

/// Settings › Memory's backup through the real client: what each state carries, what Ari sends,
/// and following a backup under way until it's on.
@Suite("Memory backup")
@MainActor
struct BackupTests {
    static let connecting = """
        { "state": "connecting", "code": "WDJB-MJHT", "url": "https://github.com/login/device",
          "expires_at": "2026-11-01T09:15:00.000Z" }
        """
    static let installing = """
        { "state": "installing", "repository": "octo-person/ito-thread",
          "repository_url": "https://github.com/octo-person/ito-thread", "created": true,
          "install_url": "https://github.com/apps/ito-memory/installations/new/permissions?suggested_target_id=4242&repository_ids[]=9000",
          "repository_chosen": true }
        """
    static let on = """
        { "state": "on", "repository": "octo-person/ito-thread",
          "repository_url": "https://github.com/octo-person/ito-thread",
          "pushed_at": "2026-11-01T09:12:00.000Z" }
        """

    private func decode(_ json: String) throws -> MemoryBackup {
        try JSONDecoder().decode(MemoryBackup.self, from: Data(json.utf8))
    }

    @Test("reads each state with what it carries")
    func decodes() throws {
        let connecting = try decode(Self.connecting)
        #expect(connecting.state == .connecting && connecting.state.isUnderway)
        #expect(connecting.code == "WDJB-MJHT")
        #expect(connecting.url?.absoluteString == "https://github.com/login/device")
        #expect(connecting.expiresAt?.rawValue == "2026-11-01T09:15:00.000Z")

        let installing = try decode(Self.installing)
        #expect(installing.state == .installing)
        #expect(installing.created && installing.repositoryChosen)
        #expect(installing.installURL?.query()?.contains("repository_ids") == true)
        #expect(installing.newRepositoryURL == nil)

        let on = try decode(Self.on)
        #expect(on.isThroughApp && !on.state.isUnderway)
        #expect(on.pushedAt?.rawValue == "2026-11-01T09:12:00.000Z")
        #expect(!on.created && !on.repositoryChosen)

        let remote = try decode(#"{ "state": "on", "remote": "git@example.com:robin/notes.git" }"#)
        #expect(!remote.isThroughApp && remote.remote == "git@example.com:robin/notes.git")

        let stopped = try decode(
            #"{ "state": "stopped", "repository": "octo-person/ito-thread", "problem": "GitHub no longer accepts Ito Memory's sign-in." }"#
        )
        #expect(stopped.state == .stopped && stopped.problem?.hasPrefix("GitHub") == true)

        // A state this Ari doesn't know still decodes.
        #expect(try !decode(#"{ "state": "paused" }"#).state.isKnown)
    }

    @Test("starts, follows along until it's on, and disconnects")
    func follows() async throws {
        let server = StubServer()
        await server.answer(.post, "/v0/memory/backup", with: Self.connecting)
        await server.answer(.get, "/v0/memory/backup", with: Self.on)
        await server.answer(.delete, "/v0/memory/backup", with: #"{ "state": "off" }"#)
        let backup = Backup(client: server.client, clock: ImmediateClock())

        try await backup.start()
        #expect(backup.status?.code == "WDJB-MJHT")
        await backup.follow()
        #expect(backup.status?.state == .on)
        #expect(backup.status?.repository == "octo-person/ito-thread")

        try await backup.disconnect()
        #expect(backup.status?.state == .off)
        let sent = await server.requests.map { "\($0.method.rawValue) \($0.path)" }
        #expect(
            sent == [
                "POST /v0/memory/backup", "GET /v0/memory/backup", "DELETE /v0/memory/backup",
            ])
    }

    @Test("a refresh that fails keeps what was shown")
    func keepsOnFailure() async throws {
        let server = StubServer()
        await server.answer(.get, "/v0/memory/backup", with: Self.on)
        let backup = Backup(client: server.client)
        await backup.refresh()
        await server.goOffline()
        await backup.refresh()
        #expect(backup.status?.state == .on)
    }

    @Test("a memory problem has its own area")
    func problemArea() throws {
        let problem = try JSONDecoder().decode(
            ServerProblem.self,
            from: Data(
                #"{ "id": "memory:backup", "area": "memory", "title": "Memory isn't backed up", "detail": "d", "fix": "f" }"#
                    .utf8))
        #expect(problem.area == .memory && problem.area.isKnown)
    }
}
