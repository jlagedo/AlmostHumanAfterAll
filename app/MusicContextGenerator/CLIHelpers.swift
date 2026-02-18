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

    static func formatCSV(songs: [Song]) -> String {
        var lines = ["artist,track,album"]
        for song in songs {
            let artist = csvEscape(song.artistName)
            let title = csvEscape(song.title)
            let album = csvEscape(song.albumTitle ?? "")
            lines.append("\(artist),\(title),\(album)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parse RFC 4180 CSV content into rows of (artist, track, album).
    /// Expects header row: `artist,track,album`. Skips header, handles quoted fields.
    static func parseCSV(from path: String) throws -> [(artist: String, track: String, album: String)] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let rows = parseCSVRows(content)

        guard rows.count > 1 else { return [] }

        // Skip header row
        return rows.dropFirst().compactMap { fields in
            guard fields.count >= 3 else { return nil }
            let artist = fields[0].trimmingCharacters(in: .whitespaces)
            let track = fields[1].trimmingCharacters(in: .whitespaces)
            let album = fields[2].trimmingCharacters(in: .whitespaces)
            guard !artist.isEmpty, !track.isEmpty else { return nil }
            return (artist: artist, track: track, album: album)
        }
    }

    /// State-machine CSV parser handling quoted fields per RFC 4180.
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentField = ""
        var currentRow: [String] = []
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote
                        currentField.append("\"")
                        i = text.index(after: next)
                    } else {
                        // End of quoted field
                        inQuotes = false
                        i = text.index(after: i)
                    }
                } else {
                    currentField.append(c)
                    i = text.index(after: i)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i = text.index(after: i)
                } else if c == "," {
                    currentRow.append(currentField)
                    currentField = ""
                    i = text.index(after: i)
                } else if c == "\n" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    i = text.index(after: i)
                } else if c == "\r" {
                    // Skip \r, handle \r\n
                    i = text.index(after: i)
                } else {
                    currentField.append(c)
                    i = text.index(after: i)
                }
            }
        }

        // Final row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
