import Foundation

/// Public DTO that crosses actor boundaries. Codable, Sendable, Identifiable.
/// This is NOT a @Model — the @Model class is internal to HistoryStore.
public struct CommentaryRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let trackName: String
    public let artist: String
    public let album: String
    public let genre: String
    public let commentary: String
    public let timestamp: Date
    public let appleMusicURL: URL?
    public let persistentID: String
    public var isFavorited: Bool
    public var thumbnailData: Data?

    public init(
        id: UUID,
        trackName: String,
        artist: String,
        album: String,
        genre: String,
        commentary: String,
        timestamp: Date,
        appleMusicURL: URL?,
        persistentID: String,
        isFavorited: Bool = false,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.trackName = trackName
        self.artist = artist
        self.album = album
        self.genre = genre
        self.commentary = commentary
        self.timestamp = timestamp
        self.appleMusicURL = appleMusicURL
        self.persistentID = persistentID
        self.isFavorited = isFavorited
        self.thumbnailData = thumbnailData
    }

    public var shareText: String {
        var text = "\(trackName) by \(artist)"
        if !album.isEmpty {
            text += " (\(album))"
        }
        text += "\n\n\(commentary)"
        if let url = appleMusicURL {
            text += "\n\n\(url.absoluteString)"
        }
        return text
    }
}
