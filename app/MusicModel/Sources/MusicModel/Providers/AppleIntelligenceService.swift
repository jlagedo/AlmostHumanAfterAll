import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
public actor AppleIntelligenceService: CommentaryService {
    private var currentTask: Task<String, Error>?
    private let adapter: SystemLanguageModel.Adapter?

    private let systemInstructions = """
        You are a world-class music journalist who writes short, descriptive song presentations.
        1. ONLY use information from the provided sections.
        2. DO NOT fabricate or alter names, titles, genres, dates, or claims.
        3. DO NOT add any information not present in the provided sections.
        """

    private let taskPrompt = "Task Overview: As a world-class music journalist, present this song to the user in 3 sentences in a descriptive writing tone."

    public init() {
        if let url = Bundle.main.url(forResource: "ficino_music", withExtension: "fmadapter") {
            do {
                self.adapter = try SystemLanguageModel.Adapter(fileURL: url)
                NSLog("[AppleIntelligence] Loaded adapter: ficino_music.fmadapter")
            } catch {
                NSLog("[AppleIntelligence] Failed to load adapter: %@", error.localizedDescription)
                self.adapter = nil
            }
        } else {
            NSLog("[AppleIntelligence] No adapter found in bundle, using base model")
            self.adapter = nil
        }
    }

    public func getCommentary(for track: TrackInput) async throws -> String {
        try checkAvailability()

        let prompt = (track.context ?? "") + "\n\n" + taskPrompt

        NSLog("[AppleIntelligence] Instructions:\n%@", systemInstructions)
        NSLog("[AppleIntelligence] Prompt:\n%@", prompt)
        return try await generate(prompt: prompt)
    }

    public func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
        NSLog("[AppleIntelligence] Cancelled current request")
    }

    // MARK: - Private

    private func generate(prompt: String) async throws -> String {
        let adapter = self.adapter
        let task = Task<String, Error> {
            let session: LanguageModelSession
            if let adapter {
                let model = SystemLanguageModel(adapter: adapter)
                session = LanguageModelSession(model: model, instructions: systemInstructions)
            } else {
                session = LanguageModelSession(instructions: systemInstructions)
            }
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.5))
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
