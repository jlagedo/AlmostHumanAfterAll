import Foundation

protocol CommentaryService {
    func getCommentary(for track: TrackInfo, personality: Personality) async throws -> String
    func getReview(personality: Personality) async throws -> String
    func cancelCurrent() async
}
