import Foundation

public protocol MusicContextProvider: Sendable {
    func fetch(name: String, artist: String, album: String, genre: String) async -> MetadataResult
}
