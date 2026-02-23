import Foundation

/// Domain representation of MusicKit song data, decoupled from the MusicKit framework.
/// Created at the MusicContext boundary so downstream consumers don't depend on MusicKit.
public struct SongMetadata: Sendable {
    public let releaseDate: Date?
    public let genres: [String]
    public let albumEditorialNotes: String?
    public let artistEditorialNotes: String?

    public init(
        releaseDate: Date?,
        genres: [String],
        albumEditorialNotes: String?,
        artistEditorialNotes: String?
    ) {
        self.releaseDate = releaseDate
        self.genres = genres
        self.albumEditorialNotes = albumEditorialNotes
        self.artistEditorialNotes = artistEditorialNotes
    }
}
