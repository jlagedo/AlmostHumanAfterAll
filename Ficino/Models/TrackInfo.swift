import Foundation

struct TrackInfo: Identifiable, Equatable {
    let id: String // PersistentID
    let name: String
    let artist: String
    let album: String
    let genre: String
    let totalTime: TimeInterval // seconds
    let timestamp: Date

    init?(userInfo: [AnyHashable: Any]) {
        guard let name = userInfo["Name"] as? String,
              let artist = userInfo["Artist"] as? String else {
            return nil
        }

        self.name = name
        self.artist = artist
        self.album = userInfo["Album"] as? String ?? "Unknown Album"
        self.genre = userInfo["Genre"] as? String ?? ""

        if let ms = userInfo["Total Time"] as? Int {
            self.totalTime = TimeInterval(ms) / 1000.0
        } else {
            self.totalTime = 0
        }

        if let pid = userInfo["PersistentID"] as? Int {
            self.id = String(pid)
        } else {
            self.id = "\(name)-\(artist)-\(Date().timeIntervalSince1970)"
        }

        self.timestamp = Date()
    }

    var durationString: String {
        let minutes = Int(totalTime) / 60
        let seconds = Int(totalTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
