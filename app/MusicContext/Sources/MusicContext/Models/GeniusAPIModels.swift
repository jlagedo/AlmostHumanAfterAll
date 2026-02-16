import Foundation

// MARK: - Search

struct GeniusSearchResponse: Codable, Sendable {
    let response: GeniusSearchResponseBody
}

struct GeniusSearchResponseBody: Codable, Sendable {
    let hits: [GeniusSearchHit]
}

struct GeniusSearchHit: Codable, Sendable {
    let type: String?
    let result: GeniusSearchSong
}

struct GeniusSearchSong: Codable, Sendable {
    let id: Int
    let title: String
    let titleWithFeatured: String?
    let url: String?
    let primaryArtist: GeniusArtistRef
    let stats: GeniusStats?

    enum CodingKeys: String, CodingKey {
        case id, title, url, stats
        case titleWithFeatured = "title_with_featured"
        case primaryArtist = "primary_artist"
    }
}

struct GeniusArtistRef: Codable, Sendable {
    let id: Int
    let name: String
    let url: String?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case imageUrl = "image_url"
    }
}

struct GeniusStats: Codable, Sendable {
    let pageviews: Int?
}

// MARK: - Song Detail

struct GeniusSongResponse: Codable, Sendable {
    let response: GeniusSongResponseBody
}

struct GeniusSongResponseBody: Codable, Sendable {
    let song: GeniusSongFull
}

struct GeniusSongFull: Codable, Sendable {
    let id: Int
    let title: String
    let titleWithFeatured: String?
    let url: String?
    let releaseDate: String?
    let releaseDateForDisplay: String?
    let recordingLocation: String?
    let primaryArtist: GeniusArtistRef
    let writerArtists: [GeniusArtistRef]?
    let producerArtists: [GeniusArtistRef]?
    let featuredArtists: [GeniusArtistRef]?
    let album: GeniusAlbumRef?
    let media: [GeniusMedia]?
    let songRelationships: [GeniusSongRelationship]?
    let customPerformances: [GeniusCustomPerformance]?
    let songDescription: GeniusDescription?
    let stats: GeniusStats?
    let appleMusic: GeniusAppleMusicRef?

    enum CodingKeys: String, CodingKey {
        case id, title, url, album, media, stats
        case titleWithFeatured = "title_with_featured"
        case releaseDate = "release_date"
        case releaseDateForDisplay = "release_date_for_display"
        case recordingLocation = "recording_location"
        case primaryArtist = "primary_artist"
        case writerArtists = "writer_artists"
        case producerArtists = "producer_artists"
        case featuredArtists = "featured_artists"
        case songRelationships = "song_relationships"
        case customPerformances = "custom_performances"
        case songDescription = "description"
        case appleMusic = "apple_music"
    }
}

struct GeniusAlbumRef: Codable, Sendable {
    let id: Int
    let name: String
    let url: String?
    let fullTitle: String?
    let coverArtUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case fullTitle = "full_title"
        case coverArtUrl = "cover_art_url"
    }
}

struct GeniusMedia: Codable, Sendable {
    let provider: String?
    let type: String?
    let url: String?
}

struct GeniusSongRelationship: Codable, Sendable {
    let relationshipType: String?
    let type: String?
    let songs: [GeniusSearchSong]?

    enum CodingKeys: String, CodingKey {
        case type, songs
        case relationshipType = "relationship_type"
    }
}

struct GeniusCustomPerformance: Codable, Sendable {
    let label: String?
    let artists: [GeniusArtistRef]?
}

struct GeniusDescription: Codable, Sendable {
    let plain: String?
}

struct GeniusAppleMusicRef: Codable, Sendable {
    let id: String?
    let url: String?
}

// MARK: - Artist Detail

struct GeniusArtistResponse: Codable, Sendable {
    let response: GeniusArtistResponseBody
}

struct GeniusArtistResponseBody: Codable, Sendable {
    let artist: GeniusArtistFull
}

struct GeniusArtistFull: Codable, Sendable {
    let id: Int
    let name: String
    let url: String?
    let imageUrl: String?
    let artistDescription: GeniusDescription?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case imageUrl = "image_url"
        case artistDescription = "description"
    }
}
