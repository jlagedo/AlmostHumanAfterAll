import Foundation
import MusicModel
import MusicContext
import os

private let logger = Logger(subsystem: "com.ficino", category: "FicinoCore")

public actor FicinoCore {
    private let commentaryService: any CommentaryService
    private let musicContext: any MusicContextProvider
    public let historyStore: HistoryStore
    private var currentTask: Task<CommentaryResult, Error>?
    private var gatekeeper = TrackGatekeeper()

    public init(
        commentaryService: any CommentaryService,
        musicContext: any MusicContextProvider,
        historyStore: HistoryStore
    ) {
        self.commentaryService = commentaryService
        self.musicContext = musicContext
        self.historyStore = historyStore
    }

    /// Process a track change: fetch context, generate commentary, save to history.
    public func process(_ request: TrackRequest) async throws -> CommentaryResult {
        currentTask?.cancel()
        return try await runCommentary(request, updateCurrentTask: true)
    }

    /// Regenerate commentary for a track without cancelling in-flight work.
    public func regenerate(_ request: TrackRequest) async throws -> CommentaryResult {
        try await runCommentary(request, updateCurrentTask: false)
    }

    /// Evaluate whether a track change should trigger commentary.
    public func shouldProcess(
        trackID: String, playerState: String,
        isPaused: Bool, skipThreshold: TimeInterval
    ) -> TrackGatekeeper.Decision {
        let config = TrackGatekeeper.Configuration(
            isPaused: isPaused,
            skipThreshold: skipThreshold
        )
        return gatekeeper.evaluate(
            trackID: trackID,
            playerState: playerState,
            configuration: config
        )
    }

    /// Cancel any in-flight processing.
    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
        await commentaryService.cancelCurrent()
    }

    /// Request MusicKit authorization.
    public static func requestMusicKitAuthorization() async -> Bool {
        await MusicContextService.isAuthorized()
    }

    // MARK: - Private

    private func runCommentary(
        _ request: TrackRequest,
        updateCurrentTask: Bool
    ) async throws -> CommentaryResult {
        let service = commentaryService
        let context = musicContext
        let store = historyStore

        let task = Task<CommentaryResult, Error> {
            async let warmup: Void = service.prewarm()

            let metadata: MetadataResult
            do {
                metadata = try await withTimeout(.seconds(15)) { [context] in
                    await context.fetch(
                        name: request.name, artist: request.artist,
                        album: request.album, genre: request.genre
                    )
                }
            } catch is TimeoutError {
                logger.warning("Metadata fetch timed out, proceeding with basic info")
                metadata = MetadataResult(song: nil, geniusData: nil, appleMusicURL: nil)
            }
            _ = await warmup

            try Task.checkCancellation()

            let sections = PromptBuilder.build(
                name: request.name, artist: request.artist,
                album: request.album, genre: request.genre,
                song: metadata.song, geniusData: metadata.geniusData
            )

            let trackInput = TrackInput(
                name: request.name, artist: request.artist,
                album: request.album, genre: request.genre,
                durationString: "0:00", context: sections
            )

            let commentary: String
            do {
                commentary = try await withTimeout(.seconds(30)) { [service] in
                    try await service.getCommentary(for: trackInput)
                }
            } catch is TimeoutError {
                throw FicinoError.aiUnavailable("Commentary generation timed out. Try again.")
            } catch is CancellationError {
                throw FicinoError.cancelled
            } catch let error as AppleIntelligenceError {
                throw FicinoError.aiUnavailable(error.localizedDescription)
            }

            guard !commentary.isEmpty else {
                throw FicinoError.emptyResponse
            }

            let id = UUID()
            let record = CommentaryRecord(
                id: id,
                trackName: request.name,
                artist: request.artist,
                album: request.album,
                genre: request.genre,
                commentary: commentary,
                timestamp: Date(),
                appleMusicURL: metadata.appleMusicURL,
                persistentID: request.persistentID,
                isFavorited: false,
                thumbnailData: nil
            )
            await store.save(record)

            return CommentaryResult(
                id: id,
                commentary: commentary,
                appleMusicURL: metadata.appleMusicURL,
                trackName: request.name,
                artist: request.artist,
                album: request.album,
                genre: request.genre
            )
        }

        if updateCurrentTask {
            currentTask = task
        }

        do {
            let result = try await task.value
            if updateCurrentTask {
                currentTask = nil
            }
            return result
        } catch {
            if updateCurrentTask {
                currentTask = nil
            }
            throw error
        }
    }
}
