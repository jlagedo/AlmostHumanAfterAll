import Foundation

// MARK: - Domain Models

public struct TrackContext: Codable, Sendable {
    public var title: String
    public var durationMs: Int?
    public var genres: [String]
    public var tags: [String]
    public var isrc: String?
    public var communityRating: Double?
    public var wikiSummary: String?
    public var musicBrainzId: String?

    public init(
        title: String,
        durationMs: Int? = nil,
        genres: [String] = [],
        tags: [String] = [],
        isrc: String? = nil,
        communityRating: Double? = nil,
        wikiSummary: String? = nil,
        musicBrainzId: String? = nil
    ) {
        self.title = title
        self.durationMs = durationMs
        self.genres = genres
        self.tags = tags
        self.isrc = isrc
        self.communityRating = communityRating
        self.wikiSummary = wikiSummary
        self.musicBrainzId = musicBrainzId
    }
}

public struct ArtistContext: Codable, Sendable {
    public var name: String
    public var type: String?
    public var country: String?
    public var activeSince: String?
    public var activeUntil: String?
    public var disambiguation: String?
    public var bio: String?
    public var description: String?
    public var listeners: Int?
    public var playcount: Int?
    public var similarArtists: [String]
    public var members: [String]
    public var musicBrainzId: String?
    public var wikidataId: String?

    public init(
        name: String,
        type: String? = nil,
        country: String? = nil,
        activeSince: String? = nil,
        activeUntil: String? = nil,
        disambiguation: String? = nil,
        bio: String? = nil,
        description: String? = nil,
        listeners: Int? = nil,
        playcount: Int? = nil,
        similarArtists: [String] = [],
        members: [String] = [],
        musicBrainzId: String? = nil,
        wikidataId: String? = nil
    ) {
        self.name = name
        self.type = type
        self.country = country
        self.activeSince = activeSince
        self.activeUntil = activeUntil
        self.disambiguation = disambiguation
        self.bio = bio
        self.description = description
        self.listeners = listeners
        self.playcount = playcount
        self.similarArtists = similarArtists
        self.members = members
        self.musicBrainzId = musicBrainzId
        self.wikidataId = wikidataId
    }
}

public struct AlbumContext: Codable, Sendable {
    public var title: String
    public var releaseDate: String?
    public var country: String?
    public var label: String?
    public var trackCount: Int?
    public var status: String?
    public var albumType: String?
    public var wikiSummary: String?
    public var musicBrainzId: String?

    public init(
        title: String,
        releaseDate: String? = nil,
        country: String? = nil,
        label: String? = nil,
        trackCount: Int? = nil,
        status: String? = nil,
        albumType: String? = nil,
        wikiSummary: String? = nil,
        musicBrainzId: String? = nil
    ) {
        self.title = title
        self.releaseDate = releaseDate
        self.country = country
        self.label = label
        self.trackCount = trackCount
        self.status = status
        self.albumType = albumType
        self.wikiSummary = wikiSummary
        self.musicBrainzId = musicBrainzId
    }
}

public struct ChartPosition: Codable, Sendable {
    public var chart: String
    public var position: Int
    public var year: Int?

    public init(chart: String, position: Int, year: Int? = nil) {
        self.chart = chart
        self.position = position
        self.year = year
    }
}

public struct TriviaContext: Codable, Sendable {
    public var awards: [String]
    public var chartPositions: [ChartPosition]
    public var songwriters: [String]
    public var producers: [String]
    public var samples: [String]
    public var sampledBy: [String]
    public var influences: [String]
    public var recordLabel: String?

    public init(
        awards: [String] = [],
        chartPositions: [ChartPosition] = [],
        songwriters: [String] = [],
        producers: [String] = [],
        samples: [String] = [],
        sampledBy: [String] = [],
        influences: [String] = [],
        recordLabel: String? = nil
    ) {
        self.awards = awards
        self.chartPositions = chartPositions
        self.songwriters = songwriters
        self.producers = producers
        self.samples = samples
        self.sampledBy = sampledBy
        self.influences = influences
        self.recordLabel = recordLabel
    }
}

public struct MusicContextData: Codable, Sendable {
    public var track: TrackContext
    public var artist: ArtistContext
    public var album: AlbumContext
    public var trivia: TriviaContext

    public init(
        track: TrackContext,
        artist: ArtistContext,
        album: AlbumContext,
        trivia: TriviaContext = TriviaContext()
    ) {
        self.track = track
        self.artist = artist
        self.album = album
        self.trivia = trivia
    }
}
