import Foundation

public protocol ScrobbleService: Sendable {
    /// Submit a scrobble for a completed track. Fire-and-forget — never throws.
    func scrobble(artist: String, track: String, album: String,
                  timestamp: Date, duration: TimeInterval) async

    /// Update the "Now Playing" status. Fire-and-forget — never throws.
    func updateNowPlaying(artist: String, track: String,
                          album: String, duration: TimeInterval) async

    // MARK: - Auth

    /// Request a temporary token for the auth flow.
    func getRequestToken() async throws -> String

    /// Build the browser URL for user authorization.
    nonisolated func authURL(token: String) -> URL

    /// Exchange an authorized token for a permanent session key.
    func getSession(token: String) async throws -> (sessionKey: String, username: String)

    /// Update the stored session key (after auth or on launch).
    func setSessionKey(_ key: String?) async

    /// Whether the service has a valid session key.
    var isAuthenticated: Bool { get async }
}
