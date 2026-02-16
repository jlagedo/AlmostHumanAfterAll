import Foundation
import MusicContext

enum MusicBrainzFormatter {
    static func printContext(_ context: MusicContextData) {
        print("── Track (MusicBrainz) ────────────────────")
        print("  Title:       \(context.track.title)")
        if let ms = context.track.durationMs {
            let seconds = ms / 1000
            print("  Duration:    \(seconds / 60):\(String(format: "%02d", seconds % 60))")
        }
        if !context.track.genres.isEmpty {
            print("  Genres:      \(context.track.genres.joined(separator: ", "))")
        }
        if !context.track.tags.isEmpty {
            print("  Tags:        \(context.track.tags.prefix(10).joined(separator: ", "))")
        }
        if let isrc = context.track.isrc {
            print("  ISRC:        \(isrc)")
        }
        if let rating = context.track.communityRating {
            print("  Rating:      \(String(format: "%.1f", rating))/5")
        }
        if let mbid = context.track.musicBrainzId {
            print("  MBID:        \(mbid)")
        }
        print()

        print("── Artist ─────────────────────────────────")
        print("  Name:        \(context.artist.name)")
        if let type = context.artist.type {
            print("  Type:        \(type)")
        }
        if let country = context.artist.country {
            print("  Country:     \(country)")
        }
        if let since = context.artist.activeSince {
            let until = context.artist.activeUntil ?? "present"
            print("  Active:      \(since) – \(until)")
        }
        if let mbid = context.artist.musicBrainzId {
            print("  MBID:        \(mbid)")
        }
        print()

        print("── Album ──────────────────────────────────")
        print("  Title:       \(context.album.title)")
        if let date = context.album.releaseDate {
            print("  Released:    \(date)")
        }
        if let label = context.album.label {
            print("  Label:       \(label)")
        }
        if let count = context.album.trackCount {
            print("  Tracks:      \(count)")
        }
        if let type = context.album.albumType {
            print("  Type:        \(type)")
        }
        if let mbid = context.album.musicBrainzId {
            print("  MBID:        \(mbid)")
        }
        print()
    }
}
