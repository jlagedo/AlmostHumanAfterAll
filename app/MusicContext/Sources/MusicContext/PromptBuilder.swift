import Foundation

public struct PromptBuilder {

    // MARK: - Build

    /// Build v17 `[Section]...[End Section]` prompt from MusicKit + Genius data.
    /// Always returns at least a `[Song]` block.
    public static func build(
        name: String, artist: String, album: String, genre: String,
        song: SongMetadata?, geniusData: MusicContextData?
    ) -> String {
        var sections: [String] = []

        // [Song] — always present
        sections.append(buildSongSection(
            name: name, artist: artist, album: album,
            genre: genre, song: song
        ))

        // [TrackDescription] — Genius wiki summary (full, no cap)
        if let wiki = geniusData?.track.wikiSummary, !isJunk(wiki) {
            sections.append("[TrackDescription]\n\(stripURLs(wiki))\n[End TrackDescription]")
        }

        // [ArtistBio] — Genius artist bio
        if let bio = geniusData?.artist.bio, !isJunk(bio) {
            sections.append("[ArtistBio]\n\(stripURLs(bio))\n[End ArtistBio]")
        }

        // [Album Editorial] — MusicKit album editorial notes
        if let albumEditorial = song?.albumEditorialNotes {
            let cleaned = stripHTML(albumEditorial)
            if !isCTA(cleaned) {
                sections.append("[Album Editorial]\n\(cleaned)\n[End Album Editorial]")
            }
        }

        // [Artist Editorial] — MusicKit artist editorial notes
        if let artistEditorial = song?.artistEditorialNotes {
            let cleaned = stripHTML(artistEditorial)
            if !isCTA(cleaned) {
                sections.append("[Artist Editorial]\n\(cleaned)\n[End Artist Editorial]")
            }
        }

        // [Samples Used]
        if let samples = geniusData?.trivia.samples, !samples.isEmpty {
            sections.append("[Samples Used]\n\(samples.joined(separator: "; "))\n[End Samples Used]")
        }

        // [Sampled By]
        if let sampledBy = geniusData?.trivia.sampledBy, !sampledBy.isEmpty {
            sections.append("[Sampled By]\n\(sampledBy.joined(separator: "; "))\n[End Sampled By]")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Song Section

    private static func buildSongSection(
        name: String, artist: String, album: String,
        genre: String, song: SongMetadata?
    ) -> String {
        var parts = [name, artist, album]

        // Genres from metadata (already filtered) or fallback
        let genres: [String]
        if let songGenres = song?.genres, !songGenres.isEmpty {
            genres = songGenres
        } else if !genre.isEmpty {
            genres = [genre]
        } else {
            genres = []
        }
        if !genres.isEmpty {
            parts.append("Genre: \(genres.joined(separator: ", "))")
        }

        // Release date
        if let releaseDate = song?.releaseDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parts.append("Released: \(formatter.string(from: releaseDate))")
        }

        return "[Song]\n\(parts.joined(separator: "\n"))\n[End Song]"
    }

    // MARK: - Text Cleaning

    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    static func stripURLs(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let ctaPhrases = [
        "Pre-add", "pre-add", "Pre-save", "pre-save",
        "Listen now", "listen now", "Stream now", "stream now",
    ]

    static func isCTA(_ text: String) -> Bool {
        ctaPhrases.contains { text.contains($0) }
    }

    private static let junkPhrases = [
        "Click here to learn how to translate",
        "Spotify is a music",
        "OVO Sound Radio",
        "Every Friday, Spotify compiles",
    ]

    static func isJunk(_ text: String) -> Bool {
        junkPhrases.contains { text.contains($0) }
    }
}
