import SwiftUI
import Combine

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

    @Published var personality: Personality {
        didSet { UserDefaults.standard.set(personality.rawValue, forKey: "personality") }
    }
    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: "isPaused") }
    }
    @Published var skipThreshold: TimeInterval {
        didSet { UserDefaults.standard.set(skipThreshold, forKey: "skipThreshold") }
    }
    @Published var notificationDuration: TimeInterval {
        didSet { UserDefaults.standard.set(notificationDuration, forKey: "notificationDuration") }
    }
    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }
    @Published var engine: AIEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "aiEngine") }
    }

    // MARK: - Services
    private let musicListener = MusicListener()
    private let claudeService = ClaudeService()
    private let artworkService = ArtworkService()
    let notificationService = NotificationService()

    private var appleIntelligenceService: (any CommentaryService)?

    private var activeService: any CommentaryService {
        switch engine {
        case .claude:
            return claudeService
        case .appleIntelligence:
            if let service = appleIntelligenceService {
                return service
            }
            return claudeService // fallback
        }
    }

    private var lastTrackID: String?
    private var trackStartTime: Date?
    private var commentTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var hasStarted = false
    private var songsSinceLastReview = 0

    private static let historyCapacity = 50

    // MARK: - Lifecycle

    init() {
        // Restore persisted settings
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "personality"),
           let p = Personality(rawValue: saved) {
            self.personality = p
        } else {
            self.personality = .claudy
        }
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.skipThreshold = defaults.object(forKey: "skipThreshold") as? TimeInterval ?? 5.0
        self.notificationDuration = defaults.object(forKey: "notificationDuration") as? TimeInterval ?? 30.0
        self.claudeModel = defaults.string(forKey: "claudeModel") ?? "claude-haiku-4-5-20251001"

        if let savedEngine = defaults.string(forKey: "aiEngine"),
           let e = AIEngine(rawValue: savedEngine) {
            self.engine = e
        } else {
            self.engine = .claude
        }

        // Create Apple Intelligence service on macOS 26+
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

        // First-run validation: check Claude CLI is accessible (only when using Claude engine)
        if engine == .claude {
            Task {
                do {
                    try await claudeService.validateSetup()
                    NSLog("[Ficino] Claude CLI validation passed")
                } catch {
                    NSLog("[Ficino] Setup validation failed: %@", error.localizedDescription)
                    setupError = error.localizedDescription
                }
            }
        }

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
        Task { await activeService.cancelCurrent() }
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
            let service = activeService
            NSLog("[AppState] Fetching artwork + commentary in parallel (engine: %@)...", engine.rawValue)

            // Sync model setting to Claude service when using Claude
            if engine == .claude {
                await claudeService.setModel(claudeModel)
            }

            // Fetch artwork and commentary in parallel
            async let artworkResult = artworkService.fetchArtwork()
            async let commentResult: Result<String, Error> = {
                do {
                    let result = try await service.getCommentary(for: track, personality: personality)
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
                NSLog("[AppState] Empty comment from %@", engine.rawValue)
                errorMessage = "\(engine.rawValue) returned an empty response"

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

                // 5-song review counter
                songsSinceLastReview += 1
                if songsSinceLastReview >= 5 {
                    songsSinceLastReview = 0
                    // Run review in its own task so it isn't cancelled by the next track change
                    reviewTask?.cancel()
                    reviewTask = Task { [personality, notificationDuration] in
                        await self.requestReview(personality: personality, notificationDuration: notificationDuration)
                    }
                }

            case .failure(let error):
                NSLog("[AppState] %@ error: %@", engine.rawValue, error.localizedDescription)
                if error is CancellationError {
                    // Don't show error for intentional cancellation
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 5-Song Review

    private func requestReview(personality: Personality, notificationDuration: Double) async {
        guard !Task.isCancelled else { return }

        let service = activeService
        NSLog("[AppState] Requesting 5-song review (engine: %@)...", engine.rawValue)

        do {
            // Fetch review and wait for song notification to finish in parallel
            async let reviewResult = service.getReview(personality: personality)
            try await Task.sleep(nanoseconds: UInt64((notificationDuration + 1) * 1_000_000_000))

            let review = try await reviewResult

            guard !Task.isCancelled else { return }

            if review.isEmpty {
                NSLog("[AppState] Empty review from Claude, skipping")
                return
            }

            NSLog("[AppState] Got review (%d chars)", review.count)

            let entry = CommentEntry(reviewComment: review, personality: personality)
            history.insert(entry, at: 0)
            if history.count > Self.historyCapacity {
                history.removeLast()
            }

            notificationService.duration = notificationDuration
            notificationService.sendReview(comment: review, personality: personality)
            NSLog("[AppState] Review notification sent")
        } catch {
            if error is CancellationError {
                NSLog("[AppState] Review cancelled")
            } else {
                NSLog("[AppState] Review failed: %@", error.localizedDescription)
            }
        }
    }
}
