import Foundation

enum NotificationPosition: String {
    case topRight, topLeft, bottomRight, bottomLeft
}

@MainActor
final class PreferencesStore: ObservableObject {
    enum Key {
        static let skipThreshold = "skipThreshold"
        static let notificationDuration = "notificationDuration"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationPosition = "notificationPosition"
        static let lastFmEnabled = "lastFmEnabled"
        static let lastFmSessionKey = "lastFmSessionKey"
        static let lastFmUsername = "lastFmUsername"
    }

    @Published var skipThreshold: TimeInterval {
        didSet { UserDefaults.standard.set(skipThreshold, forKey: Key.skipThreshold) }
    }
    @Published var notificationDuration: TimeInterval {
        didSet { UserDefaults.standard.set(notificationDuration, forKey: Key.notificationDuration) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    @Published var notificationPosition: NotificationPosition {
        didSet { UserDefaults.standard.set(notificationPosition.rawValue, forKey: Key.notificationPosition) }
    }

    // Last.fm
    @Published var lastFmEnabled: Bool {
        didSet { UserDefaults.standard.set(lastFmEnabled, forKey: Key.lastFmEnabled) }
    }
    @Published var lastFmSessionKey: String? {
        didSet { UserDefaults.standard.set(lastFmSessionKey, forKey: Key.lastFmSessionKey) }
    }
    @Published var lastFmUsername: String? {
        didSet { UserDefaults.standard.set(lastFmUsername, forKey: Key.lastFmUsername) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.skipThreshold = defaults.object(forKey: Key.skipThreshold) as? TimeInterval ?? 5.0
        self.notificationDuration = defaults.object(forKey: Key.notificationDuration) as? TimeInterval ?? 30.0
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        if let posRaw = defaults.string(forKey: Key.notificationPosition),
           let pos = NotificationPosition(rawValue: posRaw) {
            self.notificationPosition = pos
        } else {
            self.notificationPosition = .topRight
        }

        // Last.fm
        self.lastFmEnabled = defaults.bool(forKey: Key.lastFmEnabled)
        self.lastFmSessionKey = defaults.string(forKey: Key.lastFmSessionKey)
        self.lastFmUsername = defaults.string(forKey: Key.lastFmUsername)
    }
}
