import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: "isPaused") }
    }
    @Published var skipThreshold: TimeInterval {
        didSet { UserDefaults.standard.set(skipThreshold, forKey: "skipThreshold") }
    }
    @Published var notificationDuration: TimeInterval {
        didSet { UserDefaults.standard.set(notificationDuration, forKey: "notificationDuration") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var notificationPosition: NotificationPosition {
        didSet { UserDefaults.standard.set(notificationPosition.rawValue, forKey: "notificationPosition") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.skipThreshold = defaults.object(forKey: "skipThreshold") as? TimeInterval ?? 5.0
        self.notificationDuration = defaults.object(forKey: "notificationDuration") as? TimeInterval ?? 30.0
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        if let posRaw = defaults.string(forKey: "notificationPosition"),
           let pos = NotificationPosition(rawValue: posRaw) {
            self.notificationPosition = pos
        } else {
            self.notificationPosition = .topRight
        }
    }
}
