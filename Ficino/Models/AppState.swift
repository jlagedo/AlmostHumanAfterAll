import SwiftUI
import Combine
import MusicModel

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
    private let artworkService = ArtworkService()
    let notificationService = NotificationService()

    private var appleIntelligenceService: (any CommentaryService)?

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
            self.appleIntelligenceService = AppleIntelligenceService()
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
            // Service already initialized in init()
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
        Task { await appleIntelligenceService?.cancelCurrent() }
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

            guard let service = appleIntelligenceService else {
                isLoading = false
                errorMessage = "Apple Intelligence is not available"
                return
            }

            NSLog("[AppState] Fetching artwork + commentary in parallel (engine: Apple Intelligence)...")

            // Fetch artwork and commentary in parallel
            async let artworkResult = artworkService.fetchArtwork()
            async let commentResult: Result<String, Error> = {
                do {
                    let result = try await service.getCommentary(for: track.asTrackInput, personality: personality)
                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }()

            let artwork = await artworkResult
            let result = await commentResult

            guard !Task.isCancelled else {
                NSLog("[AppState] Task cancelled (track changed before response)")
                return
            }

            currentArtwork = artwork
            isLoading = false

            switch result {
            case .success(let comment) where comment.isEmpty:
                NSLog("[AppState] Empty comment from Apple Intelligence")
                errorMessage = "Apple Intelligence returned an empty response"

            case .success(let comment):
                NSLog("[AppState] Got comment (%d chars), showing notification", comment.count)
                currentComment = comment

                // Save to history
                let entry = CommentEntry(
                    track: track,
                    comment: comment,
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
                    comment: comment,
                    personality: personality,
                    artwork: artwork
                )
                NSLog("[AppState] Floating notification sent (duration: %.0fs)", notificationDuration)

            case .failure(let error):
                NSLog("[AppState] Apple Intelligence error: %@", error.localizedDescription)
                if error is CancellationError {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

}
