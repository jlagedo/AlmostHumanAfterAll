import Foundation

public struct TrackResult: Sendable {
    public let commentary: String
    public let artworkURL: URL?

    public init(commentary: String, artworkURL: URL?) {
        self.commentary = commentary
        self.artworkURL = artworkURL
    }
}
