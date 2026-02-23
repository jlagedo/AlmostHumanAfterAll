import SwiftUI
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

    // MARK: - Services

    let coordinator: MusicCoordinator
    private(set) lazy var settingsWindowController = SettingsWindowController(appState: self)

    // MARK: - Lifecycle

    init(coordinator: MusicCoordinator? = nil) {
        let c = coordinator ?? MusicCoordinator()
        self.coordinator = c
        c.onStateUpdate = { [weak self] update in
            self?.apply(update)
        }
    }

    func startIfNeeded() {
        coordinator.start(preferences: preferences)
    }

    func stop() {
        coordinator.stop()
    }

    // MARK: - User Actions

    func openSettings() {
        settingsWindowController.showSettings()
    }

    func regenerate() {
        guard let track = currentTrack else { return }
        currentComment = nil
        errorMessage = nil
        coordinator.regenerate(track: track, preferences: preferences)
    }

    func toggleFavorite(id: UUID) {
        coordinator.toggleFavorite(id: id)
    }

    func deleteHistoryRecord(id: UUID) {
        coordinator.deleteHistoryRecord(id: id)
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
        }
    }
}
