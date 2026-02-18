import Foundation
import MusicKit
import MusicModel
import MusicContext

public actor FicinoCore {
    private let commentaryService: any CommentaryService
    private let musicContext: MusicContextService
    private var currentTask: Task<String, Error>?

    public init(commentaryService: any CommentaryService, geniusAccessToken: String? = nil) {
        self.commentaryService = commentaryService
        self.musicContext = MusicContextService(geniusAccessToken: geniusAccessToken)
    }

    /// Process a track change: fetch context, generate commentary.
    public func process(_ request: TrackRequest) async throws -> String {
        currentTask?.cancel()

        let service = commentaryService
        let context = musicContext

        let task = Task<String, Error> {
            let sections = await context.fetch(
                name: request.name, artist: request.artist,
                album: request.album, genre: request.genre
            )

            try Task.checkCancellation()

            let trackInput = TrackInput(
                name: request.name, artist: request.artist,
                album: request.album, genre: request.genre,
                durationString: "0:00", context: sections
            )

            return try await service.getCommentary(for: trackInput)
        }

        currentTask = task

        do {
            let result = try await task.value
            currentTask = nil
            return result
        } catch {
            currentTask = nil
            throw error
        }
    }

    /// Cancel any in-flight processing.
    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
        await commentaryService.cancelCurrent()
    }

    /// Request MusicKit authorization.
    public static func requestMusicKitAuthorization() async -> MusicAuthorization.Status {
        await MusicContextService.requestAuthorization()
    }
}
