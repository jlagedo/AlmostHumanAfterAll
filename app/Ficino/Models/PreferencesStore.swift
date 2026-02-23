import Foundation

enum NotificationPosition: String {
    case topRight, topLeft, bottomRight, bottomLeft
}

@MainActor
final class PreferencesStore: ObservableObject {
    private enum Key {
        static let isPaused = "isPaused"
        static let skipThreshold = "skipThreshold"
        static let notificationDuration = "notificationDuration"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationPosition = "notificationPosition"
    }

    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Key.isPaused) }
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

    init() {
        let defaults = UserDefaults.standard
        self.isPaused = defaults.bool(forKey: Key.isPaused)
        self.skipThreshold = defaults.object(forKey: Key.skipThreshold) as? TimeInterval ?? 5.0
        self.notificationDuration = defaults.object(forKey: Key.notificationDuration) as? TimeInterval ?? 30.0
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        if let posRaw = defaults.string(forKey: Key.notificationPosition),
           let pos = NotificationPosition(rawValue: posRaw) {
            self.notificationPosition = pos
        } else {
            self.notificationPosition = .topRight
        }
    }
}
