import Foundation

public protocol CommentaryService: Sendable {
    func getCommentary(for track: TrackInput) async throws -> String
    func cancelCurrent() async
}
