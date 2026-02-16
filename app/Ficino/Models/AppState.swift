import SwiftUI
import Combine
import MusicModel
import FicinoCore

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var currentTrack: TrackInfo?
    @Published var currentComment: String?
    @Published var currentArtwork: NSImage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var history: [CommentEntry] = []
    @Published var setupError: String?

    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: "isPaused") }
    }
    @Published var skipThreshold: TimeInterval {
        didSet { UserDefaults.standard.set(skipThreshold, forKey: "skipThreshold") }
    }
    @Published var notificationDuration: TimeInterval {
        didSet { UserDefaults.standard.set(notificationDuration, forKey: "notificationDuration") }
    }

    let personality: Personality = .ficino

    // MARK: - Services
    private let musicListener = MusicListener()
    let notificationService = NotificationService()

    private var ficinoCore: FicinoCore?

    private var lastTrackID: String?
    private var trackStartTime: Date?
    private var commentTask: Task<Void, Never>?
    private var hasStarted = false

    private static let historyCapacity = 50

    // MARK: - Lifecycle

    init() {
        let defaults = UserDefaults.standard
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.skipThreshold = defaults.object(forKey: "skipThreshold") as? TimeInterval ?? 5.0
        self.notificationDuration = defaults.object(forKey: "notificationDuration") as? TimeInterval ?? 30.0

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let geniusToken = Self.geniusAccessToken()
            if geniusToken != nil {
                NSLog("[Ficino] Genius API token found, Genius context enabled")
            }
            self.ficinoCore = FicinoCore(
                commentaryService: AppleIntelligenceService(),
                geniusAccessToken: geniusToken
            )
        }
        #endif

        start()
    }

    func startIfNeeded() {
        start()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSLog("[Ficino] Starting services...")

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            Task {
                let status = await FicinoCore.requestMusicKitAuthorization()
                NSLog("[Ficino] MusicKit authorization: %@", String(describing: status))
            }
        } else {
            setupError = "Ficino requires macOS 26 or later for Apple Intelligence"
        }
        #else
        setupError = "Apple Intelligence is not available on this system"
        #endif

        musicListener.onTrackChange = { [weak self] track, playerState in
            guard let self else { return }
            NSLog("[Ficino] Track change: %@ - %@ (state: %@)", track.name, track.artist, playerState)
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
        guard !isPaused else {
            NSLog("[AppState] Paused, ignoring track change")
            return
        }
        guard playerState == "Playing" else {
            NSLog("[AppState] State is '%@', ignoring (only handling Playing)", playerState)
            return
        }
        guard track.id != lastTrackID else {
            NSLog("[AppState] Same track (id=%@), ignoring duplicate", track.id)
            return
        }

        // Skip threshold: ignore tracks that were played too briefly
        if let startTime = trackStartTime, skipThreshold > 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < skipThreshold {
                NSLog("[AppState] Previous track played %.1fs (threshold: %.1fs), skipping commentary for it", elapsed, skipThreshold)
            }
        }
        trackStartTime = Date()

        NSLog("[AppState] New track accepted: \"%@\" by %@ (id=%@)", track.name, track.artist, track.id)

        lastTrackID = track.id
        currentTrack = track
        currentComment = nil
        currentArtwork = nil
        errorMessage = nil
        setupError = nil

        commentTask?.cancel()

        commentTask = Task {
            isLoading = true

            guard let core = ficinoCore else {
                isLoading = false
                errorMessage = "Apple Intelligence is not available"
                return
            }

            NSLog("[AppState] Processing track via FicinoCore...")

            do {
                let result = try await core.process(track.asTrackRequest, personality: personality)

                guard !Task.isCancelled else {
                    NSLog("[AppState] Task cancelled (track changed before response)")
                    return
                }

                let commentary = result.commentary
                guard !commentary.isEmpty else {
                    isLoading = false
                    NSLog("[AppState] Empty comment from Apple Intelligence")
                    errorMessage = "Apple Intelligence returned an empty response"
                    return
                }

                // Load artwork from URL if available
                let artwork = await loadImage(from: result.artworkURL)

                guard !Task.isCancelled else { return }

                currentArtwork = artwork
                currentComment = commentary
                isLoading = false

                NSLog("[AppState] Got comment (%d chars), showing notification", commentary.count)

                // Save to history
                let entry = CommentEntry(
                    track: track,
                    comment: commentary,
                    personality: personality,
                    artwork: artwork
                )
                history.insert(entry, at: 0)
                if history.count > Self.historyCapacity {
                    history.removeLast()
                }
                NSLog("[AppState] History count: %d", history.count)

                // Send floating notification
                notificationService.duration = notificationDuration
                notificationService.send(
                    track: track,
                    comment: commentary,
                    personality: personality,
                    artwork: artwork
                )
                NSLog("[AppState] Floating notification sent (duration: %.0fs)", notificationDuration)

            } catch is CancellationError {
                NSLog("[AppState] Task cancelled")
                return
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                NSLog("[AppState] FicinoCore error: %@", error.localizedDescription)
                errorMessage = error.localizedDescription
            }
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

    private nonisolated func loadImage(from url: URL?) async -> NSImage? {
        guard let url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            NSLog("[AppState] Failed to load artwork: %@", error.localizedDescription)
            return nil
        }
    }
}
