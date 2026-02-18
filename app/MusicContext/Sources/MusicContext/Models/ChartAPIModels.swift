import Foundation

/// Raw Apple Music API chart response models for MusicDataRequest-based storefront queries.

struct ChartResponse: Decodable {
    let results: ChartResults
}

struct ChartResults: Decodable {
    let songs: [ChartEntry]?
}

struct ChartEntry: Decodable {
    let data: [ChartSongData]
}

public struct ChartSongData: Decodable {
    public let id: String
    public let attributes: ChartSongAttributes
}

public struct ChartSongAttributes: Decodable {
    public let artistName: String
    public let name: String
    public let albumName: String?
}

struct GenreListResponse: Decodable {
    let data: [GenreData]
}

struct GenreData: Decodable {
    let id: String
    let attributes: GenreAttributes
}

struct GenreAttributes: Decodable {
    let name: String
}
