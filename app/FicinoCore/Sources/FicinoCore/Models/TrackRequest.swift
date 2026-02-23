import Foundation

public protocol TrackRequestConvertible {
    var name: String { get }
    var artist: String { get }
    var album: String { get }
    var genre: String { get }
    var durationMs: Int { get }
    var persistentID: String { get }
}

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

    public init(from source: some TrackRequestConvertible) {
        self.init(
            name: source.name,
            artist: source.artist,
            album: source.album,
            genre: source.genre,
            durationMs: source.durationMs,
            persistentID: source.persistentID
        )
    }
}
