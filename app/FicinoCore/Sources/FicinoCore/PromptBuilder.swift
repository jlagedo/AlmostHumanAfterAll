import Foundation
import MusicKit
import MusicModel
import MusicContext

struct PromptBuilder {

    /// Build a TrackInput from a TrackRequest, enriched with MusicKit and Genius metadata when available.
    static func buildTrackInput(from request: TrackRequest, song: Song?, geniusData: MusicContextData? = nil) -> TrackInput {
        let minutes = request.durationMs / 60_000
        let seconds = (request.durationMs % 60_000) / 1000
        let durationString = String(format: "%d:%02d", minutes, seconds)

        let musicKitContext = song.flatMap { buildContext(from: $0) }
        let geniusContext = geniusData.flatMap { buildGeniusContext(from: $0) }

        NSLog("[PromptBuilder] MusicKit context: %@, Genius context: %@",
              musicKitContext != nil ? "\(musicKitContext!.count) chars" : "none",
              geniusContext != nil ? "\(geniusContext!.count) chars" : "none")

        // Merge context sections
        let context: String? = switch (musicKitContext, geniusContext) {
        case let (.some(mk), .some(g)): mk + "\n" + g
        case let (.some(mk), .none): mk
        case let (.none, .some(g)): g
        case (.none, .none): nil
        }

        if let context {
            NSLog("[PromptBuilder] Final context (%d chars):\n%@", context.count, context)
        }

        return TrackInput(
            name: request.name,
            artist: request.artist,
            album: request.album,
            genre: request.genre,
            durationString: durationString,
            context: context
        )
    }

    /// Extract all available MusicKit metadata from a Song into a context string for the LLM.
    private static func buildContext(from song: Song) -> String? {
        var parts: [String] = []

        // Primary genres — one level below the "Music" root in MusicKit's genre tree
        if let genres = song.genres, !genres.isEmpty {
            let primary = genres
                .filter { $0.parent != nil && $0.parent?.parent == nil }
                .map(\.name)
            if !primary.isEmpty {
                parts.append("Genres: \(primary.joined(separator: ", "))")
            }
        } else if !song.genreNames.isEmpty {
            if let first = song.genreNames.first, first != "Music" {
                parts.append("Genre: \(first)")
            }
        }

        // Release date (direct property on Song)
        if let releaseDate = song.releaseDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parts.append("Release date: \(formatter.string(from: releaseDate))")
        }

        // Editorial notes (Apple Music editorial descriptions — very rich context)
        if let notes = song.editorialNotes {
            if let standard = notes.standard, !standard.isEmpty {
                parts.append("Editorial notes: \(stripHTML(standard))")
            } else if let short = notes.short, !short.isEmpty {
                parts.append("Editorial notes: \(stripHTML(short))")
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// Extract high-value Genius metadata into a context string for the LLM.
    private static func buildGeniusContext(from data: MusicContextData) -> String? {
        var parts: [String] = []

        if !data.trivia.samples.isEmpty {
            parts.append("Samples: \(data.trivia.samples.joined(separator: "; "))")
        }

        if let description = data.track.wikiSummary {
            // Truncate long descriptions — shorter keeps the model focused on specifics
            let truncated = description.count > 250
                ? String(description.prefix(250)) + "..."
                : description
            parts.append("Song description: \(truncated)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// Extract artwork URL from a MusicKit Song.
    static func artworkURL(from song: Song, width: Int = 600, height: Int = 600) -> URL? {
        song.artwork?.url(width: width, height: height)
    }

    /// Strip HTML tags from editorial notes.
    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
