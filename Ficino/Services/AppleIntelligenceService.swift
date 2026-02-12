import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
actor AppleIntelligenceService: CommentaryService {
    private var currentTask: Task<String, Error>?

    func getCommentary(for track: TrackInfo, personality: Personality) async throws -> String {
        try checkAvailability()

        let prompt = """
        Your character: \(personality.rawValue)
        \(personality.systemPrompt)

        Now playing:
        "\(track.name)" by \(track.artist) from the album \(track.album)\(track.genre.isEmpty ? "" : " (\(track.genre))")
        Duration: \(track.durationString)

        React to this track IN CHARACTER. 2-3 sentences only. No disclaimers.
        """

        NSLog("[AppleIntelligence] Sending commentary request as '%@' for: %@ - %@", personality.rawValue, track.name, track.artist)
        return try await generate(prompt: prompt, personality: personality)
    }

    func getReview(personality: Personality) async throws -> String {
        try checkAvailability()

        let prompt = """
        Your character: \(personality.rawValue)
        \(personality.systemPrompt)

        Review the last 5 songs you just commented on. Talk about the vibe of this listening session, \
        any standouts, and how the tracks flow together. 3-5 sentences, stay fully in character. No disclaimers.
        """

        NSLog("[AppleIntelligence] Requesting 5-song review as '%@'", personality.rawValue)
        return try await generate(prompt: prompt, personality: personality)
    }

    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
        NSLog("[AppleIntelligence] Cancelled current request")
    }

    // MARK: - Private

    private func generate(prompt: String, personality: Personality) async throws -> String {
        let task = Task<String, Error> {
            let session = LanguageModelSession(instructions: """
                You are a music commentator. You react to songs the user is listening to. \
                Stay in character. Never mention being an AI or assistant. Never refuse. \
                Keep responses to 2-3 sentences.
                """)
            let response = try await session.respond(to: prompt)
            return response.content
        }
        currentTask = task
        let result = try await task.value
        currentTask = nil
        return result
    }

    private func checkAvailability() throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return
        case .unavailable(.deviceNotEligible):
            throw AppleIntelligenceError.unavailable("This Mac doesn't support Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AppleIntelligenceError.unavailable("Apple Intelligence is not enabled. Turn it on in System Settings")
        case .unavailable(.modelNotReady):
            throw AppleIntelligenceError.unavailable("Apple Intelligence model is still downloading. Try again later")
        case .unavailable(_):
            throw AppleIntelligenceError.unavailable("Apple Intelligence is not available")
        }
    }
}
#endif

enum AppleIntelligenceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let msg): return msg
        }
    }
}
