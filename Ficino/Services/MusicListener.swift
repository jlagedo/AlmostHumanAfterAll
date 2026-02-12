import Foundation

final class MusicListener {
    private let notificationCenter = DistributedNotificationCenter.default()
    private var observer: NSObjectProtocol?

    var onTrackChange: ((TrackInfo, String) -> Void)?

    func start() {
        NSLog("[MusicListener] Subscribing to com.apple.Music.playerInfo")
        observer = notificationCenter.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }

    func stop() {
        NSLog("[MusicListener] Stopping")
        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            NSLog("[MusicListener] Notification with no userInfo, ignoring")
            return
        }

        let playerState = userInfo["Player State"] as? String ?? "unknown"
        let name = userInfo["Name"] as? String ?? "?"
        let artist = userInfo["Artist"] as? String ?? "?"
        NSLog("[MusicListener] Raw notification: \"%@\" by %@ (state: %@)", name, artist, playerState)

        guard let track = TrackInfo(userInfo: userInfo) else {
            NSLog("[MusicListener] Could not parse TrackInfo, ignoring")
            return
        }

        onTrackChange?(track, playerState)
    }

    deinit {
        stop()
    }
}
