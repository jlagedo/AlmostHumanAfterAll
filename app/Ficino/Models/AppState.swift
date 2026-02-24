import SwiftUI
import Combine
import FicinoCore
import os

private let logger = Logger(subsystem: "com.ficino", category: "AppState")

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
    @Published var lastFmAuthInProgress = false
    @Published var lastFmAuthError: String?

    // MARK: - Services

    let coordinator: MusicCoordinator
    private(set) lazy var settingsWindowController = SettingsWindowController(appState: self)
    private var preferencesSink: AnyCancellable?

    // MARK: - Lifecycle

    init(coordinator: MusicCoordinator? = nil) {
        let sessionKey = UserDefaults.standard.string(forKey: PreferencesStore.Key.lastFmSessionKey)
        let c = coordinator ?? MusicCoordinator(lastFmSessionKey: sessionKey)
        self.coordinator = c
        c.onStateUpdate = { [weak self] update in
            self?.apply(update)
        }
        // Forward PreferencesStore changes so SwiftUI views re-render
        preferencesSink = preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Start services eagerly — don't wait for the menu to be opened
        c.start(preferences: preferences)
    }

    func stop() {
        coordinator.stop()
    }

    // MARK: - User Actions

    func openSettings() {
        settingsWindowController.showSettings()
    }

    func toggleFavorite(id: UUID) {
        coordinator.toggleFavorite(id: id)
    }

    func deleteHistoryRecord(id: UUID) {
        coordinator.deleteHistoryRecord(id: id)
    }

    // MARK: - Last.fm

    func connectLastFm() {
        coordinator.startLastFmAuth()
    }

    func disconnectLastFm() {
        coordinator.disconnectLastFm()
        preferences.lastFmSessionKey = nil
        preferences.lastFmUsername = nil
        preferences.lastFmEnabled = false
        lastFmAuthInProgress = false
        lastFmAuthError = nil
    }

    // MARK: - State Updates

    private func apply(_ update: MusicCoordinator.StateUpdate) {
        switch update {
        case .trackChanged(let track):
            currentTrack = track
            currentComment = nil
            currentArtwork = nil
            errorMessage = nil
            setupError = nil
        case .loading(let loading):
            isLoading = loading
        case .commentaryReceived(let commentary, let artwork, _):
            currentArtwork = artwork
            currentComment = commentary
            isLoading = false
        case .error(let msg):
            isLoading = false
            errorMessage = msg
        case .historyUpdated(let records):
            history = records
        case .setupError(let msg):
            setupError = msg
        case .clearError:
            errorMessage = nil
        case .lastFmAuthStarted:
            lastFmAuthInProgress = true
            lastFmAuthError = nil
        case .lastFmAuthCompleted(let username, let sessionKey):
            lastFmAuthInProgress = false
            lastFmAuthError = nil
            preferences.lastFmUsername = username
            preferences.lastFmSessionKey = sessionKey
            preferences.lastFmEnabled = true
            logger.info("Last.fm connected as \(username)")
        case .lastFmAuthFailed(let msg):
            lastFmAuthInProgress = false
            lastFmAuthError = msg
            logger.warning("Last.fm auth failed: \(msg)")
        }
    }
}
