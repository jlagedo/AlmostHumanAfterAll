import Foundation
import MusicKit
import TipKit
import MusicModel
import MusicContext
import MusicTracker
import FicinoCore
import os

private let logger = Logger(subsystem: "com.ficino", category: "MusicCoordinator")

@MainActor
final class MusicCoordinator {
    // MARK: - State Updates

    enum StateUpdate {
        case trackChanged(TrackInfo)
        case loading(Bool)
        case commentaryReceived(commentary: String, artwork: NSImage?, resultID: UUID)
        case error(String)
        case historyUpdated([CommentaryRecord])
        case setupError(String)
        case clearError
        case lastFmAuthStarted
        case lastFmAuthCompleted(username: String, sessionKey: String)
        case lastFmAuthFailed(String)
    }

    var onStateUpdate: ((StateUpdate) -> Void)?

    // MARK: - Services

    private let musicListener: MusicListener
    let notificationService: NotificationService

    private var ficinoCore: FicinoCore?
    private var historyStore: HistoryStore?
    private var lastFmService: LastFmService?
    private var scrobbleTracker = ScrobbleTracker()

    private var commentTask: Task<Void, Never>?
    private var authPollTask: Task<Void, Never>?
    private var scrobbleTimerTask: Task<Void, Never>?
    private var pendingAuthToken: String?
    private var currentScrobbleTrackID: String?
    private var currentResultID: UUID?
    private var hasStarted = false

    // MARK: - Init

    init(
        ficinoCore: FicinoCore? = nil,
        historyStore: HistoryStore? = nil,
        musicListener: MusicListener = MusicListener(),
        notificationService: NotificationService? = nil,
        lastFmSessionKey: String? = nil
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
                // Last.fm
                let lastFm: LastFmService?
                if let (apiKey, secret) = Self.lastFmCredentials() {
                    lastFm = LastFmService(apiKey: apiKey, sharedSecret: secret, sessionKey: lastFmSessionKey)
                    logger.info("Last.fm configured\(lastFmSessionKey != nil ? " (session found)" : "")")
                } else {
                    lastFm = nil
                }
                self.lastFmService = lastFm

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
                    onStateUpdate?(.setupError("Failed to initialize history store: \(error.localizedDescription)"))
                }
            }
            #endif
        }
    }

    // MARK: - Lifecycle

    func start(preferences: PreferencesStore) {
        guard !hasStarted else { return }
        hasStarted = true
        logger.notice("Starting services...")

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            Task {
                let authorized = await FicinoCore.requestMusicKitAuthorization()
                logger.info("MusicKit authorization: \(authorized)")
                let history = await historyStore?.getAll() ?? []
                onStateUpdate?(.historyUpdated(history))
                logger.info("Loaded \(history.count) history entries from store")

                if let store = self.historyStore {
                    for await records in store.updates {
                        self.onStateUpdate?(.historyUpdated(records))
                    }
                }
            }
        } else {
            onStateUpdate?(.setupError("Ficino requires macOS 26 or later for Apple Intelligence"))
        }
        #else
        onStateUpdate?(.setupError("Apple Intelligence is not available on this system"))
        #endif

        // Only start listening if we have a working core
        guard ficinoCore != nil else {
            logger.warning("FicinoCore not initialized, music listener disabled")
            return
        }

        // Sync loved tracks with Last.fm in background (only if authenticated)
        if let lastFm = lastFmService,
           let username = preferences.lastFmUsername,
           preferences.lastFmSessionKey != nil {
            Task.detached { [weak self] in
                let lovedKeys = await lastFm.getLovedTracks(username: username)
                guard !lovedKeys.isEmpty else { return }
                await self?.historyStore?.syncLovedTracks(lovedKeys)
            }
        }

        musicListener.onTrackChange = { [weak self] track, playerState in
            guard let self else { return }
            logger.info("Track change: \(track.name) - \(track.artist) (state: \(playerState))")
            Task { @MainActor in
                self.handleTrackChange(track: track, playerState: playerState, preferences: preferences)
            }
        }
        musicListener.start()
    }

    func stop() {
        musicListener.stop()
        commentTask?.cancel()
        authPollTask?.cancel()
        scrobbleTimerTask?.cancel()
        // Scrobble current track before shutdown if not already scrobbled (best-effort)
        if !scrobbleTracker.isScrobbled,
           let candidate = scrobbleTracker.candidate(),
           scrobbleTracker.timeUntilScrobblePoint() == 0,
           let lastFm = lastFmService {
            let resultID = currentResultID
            let store = historyStore
            Task {
                await lastFm.scrobble(
                    artist: candidate.artist, track: candidate.track,
                    album: candidate.album, timestamp: candidate.timestamp,
                    duration: candidate.duration
                )
                if let resultID {
                    await store?.markScrobbled(id: resultID)
                }
            }
        }
        Task { await ficinoCore?.cancel() }
    }

    // MARK: - Track Handling

    private func handleTrackChange(track: TrackInfo, playerState: String, preferences: PreferencesStore) {
        // Scrobble tracking needs to see ALL state changes (play, pause, stop),
        // independent of the commentary gatekeeper which rejects non-"Playing" states.
        if preferences.lastFmEnabled, lastFmService != nil {
            handleScrobbleState(track: track, playerState: playerState)
        }

        // Capture previous task — only cancel it after the gatekeeper accepts a new track.
        // This prevents duplicate/pause notifications from killing in-flight artwork fetches.
        let previousTask = commentTask
        commentTask = Task {
            guard let core = ficinoCore else { return }
            let decision = await core.shouldProcess(
                trackID: track.id, playerState: playerState,
                skipThreshold: preferences.skipThreshold
            )
            guard case .accept = decision else { return }

            // Genuinely new track accepted — now cancel the previous commentary
            previousTask?.cancel()

            logger.info("New track accepted: \"\(track.name)\" by \(track.artist) (id=\(track.id))")

            onStateUpdate?(.trackChanged(track))

            await runCommentaryBody(track: track, preferences: preferences) { core, request in
                try await core.process(request)
            }
        }
    }

    // MARK: - Scrobble State

    private func handleScrobbleState(track: TrackInfo, playerState: String) {
        guard let lastFm = lastFmService else { return }

        logger.debug("Scrobble state: \(playerState) — \"\(track.name)\" by \(track.artist) (id=\(track.id), duration=\(Int(track.totalTime))s)")

        switch playerState {
        case "Playing":
            if let currentID = currentScrobbleTrackID, currentID == track.id {
                scrobbleTracker.resume()
                logger.debug("Scrobble: resumed tracking (same track)")
                scheduleScrobbleTimer(lastFm: lastFm)
            } else {
                // New track — start tracking
                let playing = ScrobbleTracker.PlayingTrack(
                    artist: track.artist, track: track.name,
                    album: track.album, duration: track.totalTime,
                    startedAt: track.timestamp
                )
                scrobbleTracker.trackStarted(playing)
                currentScrobbleTrackID = track.id
                logger.debug("Scrobble: now tracking \"\(track.name)\"")

                scheduleScrobbleTimer(lastFm: lastFm)

                Task { await lastFm.updateNowPlaying(
                    artist: track.artist, track: track.name,
                    album: track.album, duration: track.totalTime
                )}
            }

        case "Paused":
            scrobbleTracker.pause()
            scrobbleTimerTask?.cancel()
            logger.debug("Scrobble: paused tracking (timer cancelled)")

        case "Stopped":
            scrobbleTimerTask?.cancel()
            // Submit if eligible and not already scrobbled
            if !scrobbleTracker.isScrobbled, let candidate = scrobbleTracker.candidate(),
               scrobbleTracker.timeUntilScrobblePoint() == 0 {
                logger.debug("Scrobble: stopped — submitting \"\(candidate.track)\" by \(candidate.artist)")
                let resultID = currentResultID
                let store = historyStore
                Task {
                    await lastFm.scrobble(
                        artist: candidate.artist, track: candidate.track,
                        album: candidate.album, timestamp: candidate.timestamp,
                        duration: candidate.duration
                    )
                    if let resultID {
                        await store?.markScrobbled(id: resultID)
                    }
                }
            } else {
                logger.debug("Scrobble: stopped — track not eligible or already scrobbled")
            }
            scrobbleTracker.reset()
            currentScrobbleTrackID = nil

        default:
            logger.debug("Scrobble: ignoring unknown player state")
        }
    }

    private func scheduleScrobbleTimer(lastFm: LastFmService) {
        scrobbleTimerTask?.cancel()

        guard !scrobbleTracker.isScrobbled,
              let remaining = scrobbleTracker.timeUntilScrobblePoint() else {
            return
        }

        if remaining == 0 {
            // Already past the threshold (e.g., resumed after a long pause) — scrobble now
            fireScrobble(lastFm: lastFm)
            return
        }

        logger.debug("Scrobble: timer scheduled in \(Int(remaining))s")
        scrobbleTimerTask = Task {
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self.fireScrobble(lastFm: lastFm)
        }
    }

    private func fireScrobble(lastFm: LastFmService) {
        guard !scrobbleTracker.isScrobbled,
              let candidate = scrobbleTracker.candidate() else { return }

        scrobbleTracker.markScrobbled()
        let resultID = currentResultID
        logger.debug("Scrobble: firing — \"\(candidate.track)\" by \(candidate.artist)")
        Task {
            await lastFm.scrobble(
                artist: candidate.artist, track: candidate.track,
                album: candidate.album, timestamp: candidate.timestamp,
                duration: candidate.duration
            )
            if let resultID {
                await historyStore?.markScrobbled(id: resultID)
            }
        }
    }

    // MARK: - User Actions

    func toggleFavorite(id: UUID) {
        Task {
            guard let store = historyStore else { return }
            guard let newState = await store.toggleFavorite(id: id) else { return }
            // Sync with Last.fm only if authenticated
            if let lastFm = lastFmService, await lastFm.isAuthenticated,
               let record = await store.getRecord(id: id) {
                if newState {
                    await lastFm.love(artist: record.artist, track: record.trackName)
                } else {
                    await lastFm.unlove(artist: record.artist, track: record.trackName)
                }
            }
        }
    }

    func deleteHistoryRecord(id: UUID) {
        Task {
            guard let store = historyStore else { return }
            await store.delete(id: id)
        }
    }

    // MARK: - Commentary Pipeline

    private func runCommentaryBody(
        track: TrackInfo,
        preferences: PreferencesStore,
        using generate: (FicinoCore, TrackRequest) async throws -> CommentaryResult
    ) async {
        onStateUpdate?(.loading(true))

        guard let core = ficinoCore else {
            onStateUpdate?(.loading(false))
            onStateUpdate?(.error("Apple Intelligence is not available"))
            return
        }

        async let artworkTask: NSImage? = fetchArtwork(name: track.name, artist: track.artist)

        do {
            let result = try await generate(core, TrackRequest(from: track))

            guard !Task.isCancelled else { return }

            let artwork = await artworkTask
            guard !Task.isCancelled else { return }

            self.currentResultID = result.id
            onStateUpdate?(.commentaryReceived(commentary: result.commentary, artwork: artwork, resultID: result.id))

            logger.info("Got comment (\(result.commentary.count) chars), showing notification")

            if let artwork {
                let resultID = result.id
                let store = self.historyStore
                Task.detached {
                    if let thumbnailData = CommentaryRecord.makeThumbnail(from: artwork) {
                        await store?.updateThumbnail(id: resultID, data: thumbnailData)
                    }
                }
            }

            await HistoryInteractionTip.commentaryReceived.donate()

            sendNotificationIfEnabled(track: track, comment: result.commentary, artwork: artwork, preferences: preferences)

        } catch let error as FicinoError {
            guard !Task.isCancelled else { return }
            switch error {
            case .cancelled:
                return
            case .emptyResponse, .aiUnavailable:
                onStateUpdate?(.loading(false))
                logger.error("FicinoCore error: \(error.localizedDescription)")
                onStateUpdate?(.error(error.localizedDescription))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            onStateUpdate?(.loading(false))
            logger.error("FicinoCore error: \(error.localizedDescription)")
            onStateUpdate?(.error(error.localizedDescription))
        }
    }

    private func sendNotificationIfEnabled(track: TrackInfo, comment: String, artwork: NSImage?, preferences: PreferencesStore) {
        guard preferences.notificationsEnabled else { return }
        notificationService.duration = preferences.notificationDuration
        notificationService.position = preferences.notificationPosition
        notificationService.send(track: track, comment: comment, artwork: artwork)
    }

    // MARK: - Last.fm Auth

    func startLastFmAuth() {
        guard let lastFm = lastFmService else {
            onStateUpdate?(.lastFmAuthFailed("Last.fm is not configured"))
            return
        }

        onStateUpdate?(.lastFmAuthStarted)

        Task {
            do {
                let token = try await lastFm.getRequestToken()
                self.pendingAuthToken = token
                let url = lastFm.authURL(token: token)
                NSWorkspace.shared.open(url)
                startAuthPolling(token: token)
            } catch {
                logger.error("Last.fm auth token request failed: \(error.localizedDescription)")
                onStateUpdate?(.lastFmAuthFailed(error.localizedDescription))
            }
        }
    }

    func disconnectLastFm() {
        authPollTask?.cancel()
        pendingAuthToken = nil
        Task {
            await lastFmService?.setSessionKey(nil)
        }
    }

    func updateLastFmSession(_ key: String?) {
        Task {
            await lastFmService?.setSessionKey(key)
        }
    }

    private func startAuthPolling(token: String) {
        authPollTask?.cancel()
        authPollTask = Task {
            // Poll every 3s for up to 2 minutes
            for _ in 0..<40 {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }

                guard let lastFm = lastFmService else { return }
                do {
                    let (sessionKey, username) = try await lastFm.getSession(token: token)
                    self.pendingAuthToken = nil
                    logger.info("Last.fm auth polling succeeded: \(username)")
                    onStateUpdate?(.lastFmAuthCompleted(username: username, sessionKey: sessionKey))
                    return
                } catch let error as LastFmError {
                    if case .apiError(let code, _) = error, code == 14 {
                        // Token not yet authorized — keep polling
                        continue
                    }
                    // Actual API error — stop polling
                    self.pendingAuthToken = nil
                    logger.warning("Last.fm auth polling failed: \(error.localizedDescription)")
                    onStateUpdate?(.lastFmAuthFailed(error.localizedDescription))
                    return
                } catch {
                    // Network error — keep trying
                    continue
                }
            }
            self.pendingAuthToken = nil
            logger.info("Last.fm auth polling timed out")
            onStateUpdate?(.lastFmAuthFailed("Authorization timed out — try again"))
        }
    }

    // MARK: - Helpers

    static func lastFmCredentials() -> (apiKey: String, secret: String)? {
        guard let key = Bundle.main.infoDictionary?["LastFmAPIKey"] as? String,
              !key.isEmpty, !key.hasPrefix("$("),
              let secret = Bundle.main.infoDictionary?["LastFmSharedSecret"] as? String,
              !secret.isEmpty, !secret.hasPrefix("$(") else {
            return nil
        }
        return (key, secret)
    }

    static func geniusAccessToken() -> String? {
        guard let token = Bundle.main.infoDictionary?["GeniusAccessToken"] as? String,
              !token.isEmpty,
              !token.hasPrefix("$(") else {
            return nil
        }
        return token
    }

    nonisolated func fetchArtwork(name: String, artist: String) async -> NSImage? {
        var request = MusicCatalogSearchRequest(term: "\(artist) \(name)", types: [Song.self])
        request.limit = 1
        let song: Song?
        do {
            song = try await request.response().songs.first
        } catch {
            logger.debug("MusicKit artwork search failed: \(error.localizedDescription)")
            return nil
        }
        guard let song, let url = song.artwork?.url(width: 600, height: 600) else { return nil }
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
