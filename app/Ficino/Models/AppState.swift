import SwiftUI
import Combine
import MusicKit
import TipKit
import MusicModel
import MusicContext
import FicinoCore
import os

private let logger = Logger(subsystem: "com.ficino", category: "AppState")

enum NotificationPosition: String {
    case topRight, topLeft, bottomRight, bottomLeft
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var currentTrack: TrackInfo?
    @Published var currentComment: String?
    @Published var currentArtwork: NSImage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var history: [CommentaryRecord] = []
    @Published var setupError: String?

    @Published var preferences = PreferencesStore()

    // MARK: - Services
    private let musicListener: MusicListener
    let notificationService: NotificationService

    private var ficinoCore: FicinoCore?
    private var historyStore: HistoryStore?

    private var commentTask: Task<Void, Never>?
    private var hasStarted = false

    // MARK: - Lifecycle

    init(
        ficinoCore: FicinoCore? = nil,
        historyStore: HistoryStore? = nil,
        musicListener: MusicListener = MusicListener(),
        notificationService: NotificationService? = nil
    ) {
        self.musicListener = musicListener
        self.notificationService = notificationService ?? NotificationService()

        if let ficinoCore, let historyStore {
            self.ficinoCore = ficinoCore
            self.historyStore = historyStore
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                let geniusToken = Self.geniusAccessToken()
                if geniusToken != nil {
                    logger.info("Genius API token found, Genius context enabled")
                }
                do {
                    let store = try HistoryStore()
                    self.historyStore = store
                    self.ficinoCore = FicinoCore(
                        commentaryService: AppleIntelligenceService(),
                        musicContext: MusicContextService(geniusAccessToken: geniusToken),
                        historyStore: store
                    )
                } catch {
                    logger.error("Failed to initialize HistoryStore: \(error.localizedDescription)")
                    self.setupError = "Failed to initialize history store: \(error.localizedDescription)"
                }
            }
            #endif
        }

        start()
    }

    func startIfNeeded() {
        start()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        logger.notice("Starting services...")

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            Task {
                let authorized = await FicinoCore.requestMusicKitAuthorization()
                logger.info("MusicKit authorization: \(authorized)")
                self.history = await historyStore?.getAll() ?? []
                logger.info("Loaded \(self.history.count) history entries from store")

                if let store = self.historyStore {
                    for await records in store.updates {
                        self.history = records
                    }
                }
            }
        } else {
            setupError = "Ficino requires macOS 26 or later for Apple Intelligence"
        }
        #else
        setupError = "Apple Intelligence is not available on this system"
        #endif

        musicListener.onTrackChange = { [weak self] track, playerState in
            guard let self else { return }
            logger.info("Track change: \(track.name) - \(track.artist) (state: \(playerState))")
            Task { @MainActor in
                self.handleTrackChange(track: track, playerState: playerState)
            }
        }
        musicListener.start()
    }

    func stop() {
        musicListener.stop()
        commentTask?.cancel()
        Task { await ficinoCore?.cancel() }
    }

    // MARK: - Track Handling

    private func handleTrackChange(track: TrackInfo, playerState: String) {
        commentTask?.cancel()
        commentTask = Task {
            guard let core = ficinoCore else { return }
            let decision = await core.shouldProcess(
                trackID: track.id, playerState: playerState,
                isPaused: preferences.isPaused,
                skipThreshold: preferences.skipThreshold
            )
            guard case .accept = decision else { return }

            logger.info("New track accepted: \"\(track.name)\" by \(track.artist) (id=\(track.id))")

            currentTrack = track
            currentComment = nil
            currentArtwork = nil
            errorMessage = nil
            setupError = nil

            await runCommentaryBody(track: track) { core, request in
                try await core.process(request)
            }
        }
    }

    // MARK: - User Actions

    func regenerate() {
        guard let track = currentTrack else { return }
        currentComment = nil
        errorMessage = nil

        commentTask?.cancel()
        commentTask = Task {
            await runCommentaryBody(track: track) { core, request in
                try await core.regenerate(request)
            }
        }
    }

    private func runCommentaryBody(
        track: TrackInfo,
        using generate: (FicinoCore, TrackRequest) async throws -> CommentaryResult
    ) async {
        isLoading = true

        guard let core = ficinoCore else {
            isLoading = false
            errorMessage = "Apple Intelligence is not available"
            return
        }

        async let artworkTask: NSImage? = fetchArtwork(name: track.name, artist: track.artist)

        do {
            let result = try await generate(core, track.asTrackRequest)

            guard !Task.isCancelled else { return }

            let artwork = await artworkTask
            guard !Task.isCancelled else { return }

            currentArtwork = artwork
            currentComment = result.commentary
            isLoading = false

            logger.info("Got comment (\(result.commentary.count) chars), showing notification")

            if let thumbnailData = CommentaryRecord.makeThumbnail(from: artwork) {
                await self.historyStore?.updateThumbnail(id: result.id, data: thumbnailData)
            }

            await HistoryInteractionTip.commentaryReceived.donate()

            sendNotificationIfEnabled(track: track, comment: result.commentary, artwork: artwork)

        } catch let error as FicinoError {
            guard !Task.isCancelled else { return }
            switch error {
            case .cancelled:
                return
            case .emptyResponse, .aiUnavailable:
                isLoading = false
                logger.error("FicinoCore error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            logger.error("FicinoCore error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func sendNotificationIfEnabled(track: TrackInfo, comment: String, artwork: NSImage?) {
        guard preferences.notificationsEnabled else { return }
        notificationService.duration = preferences.notificationDuration
        notificationService.position = preferences.notificationPosition
        notificationService.send(track: track, comment: comment, artwork: artwork)
    }

    func toggleFavorite(id: UUID) {
        Task {
            guard let store = historyStore else { return }
            _ = await store.toggleFavorite(id: id)
        }
    }

    func deleteHistoryRecord(id: UUID) {
        Task {
            guard let store = historyStore else { return }
            await store.delete(id: id)
        }
    }

    // MARK: - Helpers

    private static func geniusAccessToken() -> String? {
        guard let token = Bundle.main.infoDictionary?["GeniusAccessToken"] as? String,
              !token.isEmpty,
              !token.hasPrefix("$(") else {
            return nil
        }
        return token
    }

    private nonisolated func fetchArtwork(name: String, artist: String) async -> NSImage? {
        var request = MusicCatalogSearchRequest(term: "\(artist) \(name)", types: [Song.self])
        request.limit = 1
        guard let song = try? await request.response().songs.first,
              let url = song.artwork?.url(width: 600, height: 600) else { return nil }
        return await loadImage(from: url)
    }

    private nonisolated func loadImage(from url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            logger.error("Failed to load artwork: \(error.localizedDescription)")
            return nil
        }
    }
}
