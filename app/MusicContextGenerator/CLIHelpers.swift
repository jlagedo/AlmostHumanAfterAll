import Foundation
import MusicKit

enum CLIHelpers {
    static func printErr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func opt(_ value: Any?) -> String {
        guard let value else { return "nil" }
        return "\(value)"
    }

    static func optDate(_ date: Date?, time: Bool = false) -> String {
        guard let date else { return "nil" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if time { formatter.timeStyle = .short }
        return formatter.string(from: date)
    }

    static func formatCSV(tracks: MusicItemCollection<Track>) -> String {
        var lines = ["artist,track,album"]
        for track in tracks {
            let artist = csvEscape(track.artistName)
            let title = csvEscape(track.title)
            let album = csvEscape(track.albumTitle ?? "")
            lines.append("\(artist),\(title),\(album)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
