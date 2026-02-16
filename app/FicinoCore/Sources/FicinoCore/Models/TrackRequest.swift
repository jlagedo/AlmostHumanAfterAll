import Foundation

public struct TrackRequest: Sendable {
    public let name: String
    public let artist: String
    public let album: String
    public let genre: String
    public let durationMs: Int
    public let persistentID: String

    public init(name: String, artist: String, album: String, genre: String, durationMs: Int, persistentID: String) {
        self.name = name
        self.artist = artist
        self.album = album
        self.genre = genre
        self.durationMs = durationMs
        self.persistentID = persistentID
    }
}
