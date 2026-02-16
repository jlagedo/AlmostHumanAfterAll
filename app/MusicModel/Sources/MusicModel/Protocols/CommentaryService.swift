import Foundation

public protocol CommentaryService: Sendable {
    func getCommentary(for track: TrackInput, personality: Personality) async throws -> String
    func cancelCurrent() async
}
