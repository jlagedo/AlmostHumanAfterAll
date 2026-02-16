import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
public actor AppleIntelligenceService: CommentaryService {
    private var currentTask: Task<String, Error>?

    public init() {}

    public func getCommentary(for track: TrackInput, personality: Personality) async throws -> String {
        try checkAvailability()

        let prompt: String
        if let context = track.context, !context.isEmpty {
            prompt = """
            "\(track.name)" by \(track.artist), from "\(track.album)" (\(track.genre)).

            \(context)

            Ficino:
            """
        } else {
            prompt = """
            "\(track.name)" by \(track.artist), from "\(track.album)" (\(track.genre)).

            React.
            """
        }

        NSLog("[AppleIntelligence] Instructions:\n%@", personality.instructions)
        NSLog("[AppleIntelligence] Prompt:\n%@", prompt)
        return try await generate(prompt: prompt, personality: personality)
    }

    public func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
        NSLog("[AppleIntelligence] Cancelled current request")
    }

    // MARK: - Private

    private func generate(prompt: String, personality: Personality) async throws -> String {
        let task = Task<String, Error> {
            let session = LanguageModelSession(instructions: personality.instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }
        currentTask = task
        let result = try await task.value
        currentTask = nil
        NSLog("[AppleIntelligence] Response: %@", result)
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

public enum AppleIntelligenceError: LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let msg): return msg
        }
    }
}
