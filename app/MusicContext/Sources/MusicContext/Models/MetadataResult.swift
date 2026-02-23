import Foundation

public struct MetadataResult: Sendable {
    public let song: SongMetadata?
    public let geniusData: MusicContextData?
    public let appleMusicURL: URL?

    public init(song: SongMetadata?, geniusData: MusicContextData?, appleMusicURL: URL?) {
        self.song = song
        self.geniusData = geniusData
        self.appleMusicURL = appleMusicURL
    }
}
