import Foundation

// MARK: - Recording Search

struct MBRecordingSearchResponse: Codable, Sendable {
    let created: String?
    let count: Int
    let offset: Int
    let recordings: [MBRecordingSearchResult]
}

struct MBRecordingSearchResult: Codable, Sendable {
    let id: String
    let score: Int?
    let title: String
    let disambiguation: String?
    let length: Int?
    let video: Bool?
    let firstReleaseDate: String?
    let artistCredit: [MBArtistCredit]?
    let releases: [MBReleaseSearchResult]?

    enum CodingKeys: String, CodingKey {
        case id, score, title, disambiguation, length, video
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
        case releases
    }
}

struct MBReleaseSearchResult: Codable, Sendable {
    let id: String
    let title: String
    let status: String?
    let statusId: String?
    let date: String?
    let country: String?
    let trackCount: Int?
    let releaseGroup: MBReleaseGroup?
    let releaseEvents: [MBReleaseEvent]?
    let media: [MBMedia]?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, media
        case statusId = "status-id"
        case trackCount = "track-count"
        case releaseGroup = "release-group"
        case releaseEvents = "release-events"
    }
}

struct MBReleaseGroup: Codable, Sendable {
    let id: String
    let title: String?
    let primaryType: String?
    let secondaryTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }
}

struct MBReleaseEvent: Codable, Sendable {
    let date: String?
    let area: MBArea?
}

struct MBArea: Codable, Sendable {
    let id: String?
    let name: String?
    let sortName: String?
    let iso31661Codes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortName = "sort-name"
        case iso31661Codes = "iso-3166-1-codes"
    }
}

struct MBMedia: Codable, Sendable {
    let position: Int?
    let format: String?
    let trackCount: Int?
    let trackOffset: Int?
    let track: [MBTrack]?

    enum CodingKeys: String, CodingKey {
        case position, format, track
        case trackCount = "track-count"
        case trackOffset = "track-offset"
    }
}

struct MBTrack: Codable, Sendable {
    let id: String
    let number: String?
    let title: String?
    let length: Int?
}

// MARK: - Artist Credit

struct MBArtistCredit: Codable, Sendable {
    let name: String?
    let joinphrase: String?
    let artist: MBArtistRef

    enum CodingKeys: String, CodingKey {
        case name, joinphrase, artist
    }
}

struct MBArtistRef: Codable, Sendable {
    let id: String
    let name: String
    let sortName: String?
    let disambiguation: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, type
        case sortName = "sort-name"
    }
}

// MARK: - Recording Lookup (with inc=tags+genres+ratings+isrcs+artist-credits)

struct MBRecordingLookup: Codable, Sendable {
    let id: String
    let title: String
    let disambiguation: String?
    let length: Int?
    let video: Bool?
    let firstReleaseDate: String?
    let artistCredit: [MBArtistCredit]?
    let tags: [MBTag]?
    let genres: [MBGenre]?
    let rating: MBRating?
    let isrcs: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, disambiguation, length, video, tags, genres, rating, isrcs
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }
}

struct MBTag: Codable, Sendable {
    let name: String
    let count: Int?
}

struct MBGenre: Codable, Sendable {
    let id: String?
    let name: String
    let disambiguation: String?
    let count: Int?
}

struct MBRating: Codable, Sendable {
    let value: Double?
    let votesCount: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case votesCount = "votes-count"
    }
}

// MARK: - Artist Lookup

struct MBArtistFull: Codable, Sendable {
    let id: String
    let name: String
    let sortName: String?
    let disambiguation: String?
    let type: String?
    let country: String?
    let gender: String?
    let lifeSpan: MBLifeSpan?
    let area: MBArea?
    let beginArea: MBArea?
    let endArea: MBArea?

    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, type, country, gender, area
        case sortName = "sort-name"
        case lifeSpan = "life-span"
        case beginArea = "begin-area"
        case endArea = "end-area"
    }
}

struct MBLifeSpan: Codable, Sendable {
    let begin: String?
    let end: String?
    let ended: Bool?
}

// MARK: - Release Browse (by release-group)

struct MBReleaseBrowseResponse: Codable, Sendable {
    let releaseCount: Int?
    let releaseOffset: Int?
    let releases: [MBReleaseBrowseResult]

    enum CodingKeys: String, CodingKey {
        case releases
        case releaseCount = "release-count"
        case releaseOffset = "release-offset"
    }
}

struct MBReleaseBrowseResult: Codable, Sendable {
    let id: String
    let title: String
    let status: String?
    let date: String?
    let country: String?
    let barcode: String?
    let trackCount: Int?
    let media: [MBMedia]?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, barcode, media
        case trackCount = "track-count"
    }

    /// Total tracks across all media
    var totalTrackCount: Int? {
        if let media, !media.isEmpty {
            return media.reduce(0) { $0 + ($1.trackCount ?? 0) }
        }
        return trackCount
    }
}

// MARK: - Release Lookup (with inc=labels+release-groups)

struct MBReleaseLookup: Codable, Sendable {
    let id: String
    let title: String
    let status: String?
    let date: String?
    let country: String?
    let barcode: String?
    let disambiguation: String?
    let quality: String?
    let artistCredit: [MBArtistCredit]?
    let labelInfo: [MBLabelInfo]?
    let media: [MBMedia]?
    let releaseGroup: MBReleaseGroupFull?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, barcode, disambiguation, quality, media
        case artistCredit = "artist-credit"
        case labelInfo = "label-info"
        case releaseGroup = "release-group"
    }
}

struct MBLabelInfo: Codable, Sendable {
    let catalogNumber: String?
    let label: MBLabel?

    enum CodingKeys: String, CodingKey {
        case label
        case catalogNumber = "catalog-number"
    }
}

struct MBLabel: Codable, Sendable {
    let id: String
    let name: String
    let disambiguation: String?
    let type: String?
    let sortName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, type
        case sortName = "sort-name"
    }
}

struct MBReleaseGroupFull: Codable, Sendable {
    let id: String
    let title: String?
    let primaryType: String?
    let secondaryTypes: [String]?
    let firstReleaseDate: String?
    let disambiguation: String?

    enum CodingKeys: String, CodingKey {
        case id, title, disambiguation
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
        case firstReleaseDate = "first-release-date"
    }
}
