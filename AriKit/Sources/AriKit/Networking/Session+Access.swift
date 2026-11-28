// Full access from Settings: the switch reads and changes it through the session, so the main
// chat's marker follows at once, before `access.changed` comes round the stream.

extension Session {
    /// Asks the server how Kumo runs now. A server that doesn't know full access refuses with 404.
    public func refreshAccess() async throws(RequestError) {
        access = try await client.access()
    }

    /// Gives Kumo full access, from its next turn. Call it only once Face ID or the passcode has
    /// said it's you.
    public func giveFullAccess() async throws(RequestError) {
        access = try await client.giveFullAccess()
    }

    /// Puts Kumo back in its sandbox, from its next turn.
    public func endFullAccess() async throws(RequestError) {
        access = try await client.endFullAccess()
    }
}
