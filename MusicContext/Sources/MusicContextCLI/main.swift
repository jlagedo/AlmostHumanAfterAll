import Foundation
import MusicContext
import MusicKit

// Parse command-line arguments
let args = Array(CommandLine.arguments.dropFirst())

do {
    let parsed = try parseArguments(args)

    switch parsed.arguments {
    case .musicBrainz(let artist, let album, let track, let durationMs):
        // MusicBrainz provider
        let provider = MusicBrainzProvider(
            appName: "MusicContextCLI",
            version: "0.1.0",
            contact: "musiccontext@example.com"
        )

        let durationInfo = durationMs.map { " (\($0)ms)" } ?? ""
        print("Fetching context for: \"\(track)\" by \(artist) from \"\(album)\"\(durationInfo)...")
        print()

        let context = try await provider.fetchContext(artist: artist, track: track, album: album, durationMs: durationMs)

        // Display Track
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

        // Display Artist
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
        if let dis = context.artist.disambiguation, !dis.isEmpty {
            print("  Disambig:    \(dis)")
        }
        if let mbid = context.artist.musicBrainzId {
            print("  MBID:        \(mbid)")
        }
        print()

        // Display Album
        print("── Album ──────────────────────────────────")
        print("  Title:       \(context.album.title)")
        if let date = context.album.releaseDate {
            print("  Released:    \(date)")
        }
        if let country = context.album.country {
            print("  Country:     \(country)")
        }
        if let label = context.album.label {
            print("  Label:       \(label)")
        }
        if let count = context.album.trackCount {
            print("  Tracks:      \(count)")
        }
        if let status = context.album.status {
            print("  Status:      \(status)")
        }
        if let type = context.album.albumType {
            print("  Type:        \(type)")
        }
        if let mbid = context.album.musicBrainzId {
            print("  MBID:        \(mbid)")
        }
        print()

    case .musicKit(let artist, let album, let track):
        // MusicKit search mode — authorize if needed
        let authStatus = await MusicKitProvider.authorize()
        guard authStatus == .authorized else {
            print("Error: MusicKit authorization required (status: \(authStatus))")
            exit(1)
        }

        let provider = MusicKitProvider()
        print("Searching Apple Music for: \"\(track)\" by \(artist) from \"\(album)\"...")
        print()

        let song = try await provider.searchSong(artist: artist, track: track, album: album)
        printSong(song)

    case .musicKitID(let catalogID):
        // MusicKit catalog ID lookup — authorize if needed
        let authStatus = await MusicKitProvider.authorize()
        guard authStatus == .authorized else {
            print("Error: MusicKit authorization required (status: \(authStatus))")
            exit(1)
        }

        let provider = MusicKitProvider()
        print("Fetching song with catalog ID: \(catalogID)...")
        print()

        let song = try await provider.fetchSong(catalogID: catalogID)
        printSong(song)
    }

    print("Done.")
    exit(0)

} catch let error as ArgumentError {
    print("Error: \(error.description)")
    exit(1)
} catch let error as MusicContextError {
    print("Error: \(error.description)")
    exit(1)
} catch {
    print("Unexpected error: \(error)")
    exit(1)
}

// MARK: - Display helpers

func printSong(_ song: AppleMusicSong) {
    print("── Track (Apple Music) ────────────────────")
    print("  ID:          \(song.id)")
    print("  Title:       \(song.name)")
    print("  Artist:      \(song.artistName)")
    print("  Album:       \(song.albumName)")
    if let duration = song.durationMs {
        let seconds = duration / 1000
        print("  Duration:    \(seconds / 60):\(String(format: "%02d", seconds % 60))")
    }
    if !song.genreNames.isEmpty {
        print("  Genres:      \(song.genreNames.joined(separator: ", "))")
    }
    if let isrc = song.isrc {
        print("  ISRC:        \(isrc)")
    }
    if let composer = song.composerName {
        print("  Composer:    \(composer)")
    }
    if let releaseDate = song.releaseDate {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        print("  Released:    \(formatter.string(from: releaseDate))")
    }
    if let contentRating = song.contentRating {
        print("  Rating:      \(contentRating)")
    }
    if song.hasLyrics {
        print("  Lyrics:      Available")
    }
    if let artworkURL = song.artworkURL {
        print("  Artwork:     \(artworkURL)")
    }
    print()
}
