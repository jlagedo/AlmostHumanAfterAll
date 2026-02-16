import Foundation
import MusicKit
import MusicModel
import MusicContext

public actor FicinoCore {
    private let commentaryService: any CommentaryService
    private let musicKit: MusicKitProvider
    private let genius: GeniusProvider?
    private var currentTask: Task<TrackResult, Error>?

    public init(commentaryService: any CommentaryService, geniusAccessToken: String? = nil) {
        self.commentaryService = commentaryService
        self.musicKit = MusicKitProvider()
        self.genius = geniusAccessToken.map { GeniusProvider(accessToken: $0) }
    }

    /// Process a track change: look up MusicKit metadata, build enriched prompt, generate commentary.
    public func process(_ request: TrackRequest, personality: Personality) async throws -> TrackResult {
        // Cancel any in-flight processing
        currentTask?.cancel()

        let service = commentaryService
        let musicKit = self.musicKit
        let genius = self.genius

        let task = Task<TrackResult, Error> {
            // Phase 1: MusicKit + Genius lookups in parallel (both failable)
            async let songResult: Song? = {
                do {
                    let result = try await musicKit.searchSong(
                        artist: request.artist,
                        track: request.name,
                        album: request.album
                    )
                    NSLog("[FicinoCore] MusicKit match: \"%@\" by %@", result.title, result.artistName)
                    return result
                } catch {
                    NSLog("[FicinoCore] MusicKit lookup failed (non-fatal): %@", error.localizedDescription)
                    return nil
                }
            }()

            async let geniusResult: MusicContextData? = {
                guard let genius else {
                    NSLog("[FicinoCore] Genius: skipped (no token)")
                    return nil
                }
                do {
                    NSLog("[FicinoCore] Genius: searching \"%@\" by %@", request.name, request.artist)
                    let data = try await genius.fetchContext(
                        artist: request.artist,
                        track: request.name,
                        album: request.album
                    )
                    NSLog("[FicinoCore] Genius match: \"%@\" by %@", data.track.title, data.artist.name)
                    let producers = data.trivia.producers
                    let samples = data.trivia.samples
                    let hasDesc = data.track.wikiSummary != nil
                    NSLog("[FicinoCore] Genius data: %d producers, %d samples, description=%@",
                          producers.count, samples.count, hasDesc ? "yes" : "no")
                    if !producers.isEmpty {
                        NSLog("[FicinoCore] Genius producers: %@", producers.joined(separator: ", "))
                    }
                    if !samples.isEmpty {
                        NSLog("[FicinoCore] Genius samples: %@", samples.joined(separator: "; "))
                    }
                    return data
                } catch {
                    NSLog("[FicinoCore] Genius lookup failed (non-fatal): %@", error.localizedDescription)
                    return nil
                }
            }()

            let song = await songResult
            let geniusData = await geniusResult

            try Task.checkCancellation()

            // Phase 2: Build enriched TrackInput
            let trackInput = PromptBuilder.buildTrackInput(from: request, song: song, geniusData: geniusData)
            let artworkURL = song.flatMap { PromptBuilder.artworkURL(from: $0) }

            // Phase 3: Generate commentary
            let commentary = try await service.getCommentary(for: trackInput, personality: personality)

            return TrackResult(commentary: commentary, artworkURL: artworkURL)
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
        await MusicKitProvider.authorize()
    }
}
