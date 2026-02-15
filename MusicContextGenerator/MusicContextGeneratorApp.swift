import SwiftUI
import MusicKit
import MusicContext

@main
struct MusicContextGeneratorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        if !args.isEmpty {
            Task {
                await runFromCommandLine(args)
                exit(0)
            }
        }
    }
}

private func runFromCommandLine(_ args: [String]) async {
    do {
        let parsed = try parseArguments(args)

        switch parsed.arguments {
        case .musicBrainz(let artist, let album, let track, let durationMs):
            let provider = MusicBrainzProvider(
                appName: "MusicContextGenerator",
                version: "0.1.0",
                contact: "musiccontext@example.com"
            )

            let durationInfo = durationMs.map { " (\($0)ms)" } ?? ""
            print("Fetching context for: \"\(track)\" by \(artist) from \"\(album)\"\(durationInfo)...")
            print()

            let context = try await provider.fetchContext(
                artist: artist, track: track, album: album, durationMs: durationMs
            )
            printMusicBrainzContext(context)

        case .musicKit(let artist, let album, let track):
            try await ensureAuthorized()

            let provider = MusicKitProvider()
            print("Searching Apple Music for: \"\(track)\" by \(artist) from \"\(album)\"...")
            print()

            let song = try await provider.searchSong(artist: artist, track: track, album: album)
            printSong(song)
            await printFullContext(song: song, provider: provider)

        case .musicKitID(let catalogID):
            try await ensureAuthorized()

            let provider = MusicKitProvider()
            print("Fetching song with catalog ID: \(catalogID)...")
            print()

            let song = try await provider.fetchSong(catalogID: catalogID)
            printSong(song)
            await printFullContext(song: song, provider: provider)
        }

        print("Done.")

    } catch let error as ArgumentError {
        print("Error: \(error.description)")
        exit(1)
    } catch let error as MusicContextError {
        print("Error: \(error.description)")
        exit(1)
    } catch {
        print("Error: \(error)")
        // Print the full error details for debugging
        print("  Type: \(type(of: error))")
        if let localizedError = error as? LocalizedError {
            if let reason = localizedError.failureReason {
                print("  Reason: \(reason)")
            }
            if let suggestion = localizedError.recoverySuggestion {
                print("  Suggestion: \(suggestion)")
            }
        }
        exit(1)
    }
}

private func ensureAuthorized() async throws {
    let currentStatus = MusicAuthorization.currentStatus
    print("MusicKit authorization status: \(currentStatus)")

    if currentStatus != .authorized {
        let status = await MusicAuthorization.request()
        print("MusicKit authorization result: \(status)")
        guard status == .authorized else {
            print("Error: MusicKit authorization denied")
            exit(1)
        }
    }
}

// MARK: - Display helpers

private func printSong(_ song: Song) {
    print("── Track (Apple Music) ────────────────────")
    print("  ID:            \(song.id)")
    print("  Title:         \(song.title)")
    print("  Artist:        \(song.artistName)")
    if let artistURL = song.artistURL {
        print("  Artist URL:    \(artistURL)")
    }
    if let albumTitle = song.albumTitle {
        print("  Album:         \(albumTitle)")
    }
    if let trackNumber = song.trackNumber {
        print("  Track #:       \(trackNumber)")
    }
    if let discNumber = song.discNumber {
        print("  Disc #:        \(discNumber)")
    }
    if let duration = song.duration {
        let seconds = Int(duration)
        print("  Duration:      \(seconds / 60):\(String(format: "%02d", seconds % 60))")
    }
    if !song.genreNames.isEmpty {
        print("  Genres:        \(song.genreNames.joined(separator: ", "))")
    }
    if let isrc = song.isrc {
        print("  ISRC:          \(isrc)")
    }
    if let composer = song.composerName {
        print("  Composer:      \(composer)")
    }
    if let releaseDate = song.releaseDate {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        print("  Released:      \(formatter.string(from: releaseDate))")
    }
    if let contentRating = song.contentRating {
        print("  Rating:        \(contentRating)")
    }
    print("  Has Lyrics:    \(song.hasLyrics)")
    if let url = song.url {
        print("  URL:           \(url)")
    }
    if let artwork = song.artwork {
        if let url = artwork.url(width: 600, height: 600) {
            print("  Artwork:       \(url)")
        }
    }

    // Audio quality
    if let audioVariants = song.audioVariants {
        print("  Audio:         \(audioVariants.map { "\($0)" }.joined(separator: ", "))")
    }
    if let isADM = song.isAppleDigitalMaster {
        print("  Digital Master: \(isADM)")
    }

    // Preview
    if let previews = song.previewAssets, !previews.isEmpty {
        for preview in previews {
            if let previewURL = preview.url {
                print("  Preview:       \(previewURL)")
            }
        }
    }

    // Editorial notes
    if let notes = song.editorialNotes {
        if let short = notes.short {
            print("  Notes:         \(short)")
        }
        if let standard = notes.standard {
            print("  Description:   \(standard)")
        }
    }

    // Classical music
    if let workName = song.workName {
        print("  Work:          \(workName)")
    }
    if let movementName = song.movementName {
        print("  Movement:      \(movementName)")
    }
    if let movementNumber = song.movementNumber {
        print("  Movement #:    \(movementNumber)")
    }
    if let movementCount = song.movementCount {
        print("  Movements:     \(movementCount)")
    }
    if let attribution = song.attribution {
        print("  Attribution:   \(attribution)")
    }

    // Playback
  if song.playParameters != nil {
        print("  Playable:      true")
    }

    // Relationships (if loaded)
    if let artists = song.artists {
        let names = artists.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        print("  Artists:       \(names)")
    }
    if let albums = song.albums {
        let titles = albums.map { "\($0.title) (\($0.id))" }.joined(separator: ", ")
        print("  Albums:        \(titles)")
    }
    if let composers = song.composers {
        let names = composers.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        print("  Composers:     \(names)")
    }
    if let genres = song.genres {
        let names = genres.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        print("  Genre IDs:     \(names)")
    }
    if let musicVideos = song.musicVideos {
        let titles = musicVideos.map { "\($0.title) (\($0.id))" }.joined(separator: ", ")
        print("  Music Videos:  \(titles)")
    }
    if let station = song.station {
        print("  Station:       \(station.name) (\(station.id))")
    }

    print()
}

private func printMusicBrainzContext(_ context: MusicContextData) {
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

// MARK: - Full context (Album + Artist details)

private func printFullContext(song: Song, provider: MusicKitProvider) async {
    // Fetch full album
    if let albumID = song.albums?.first?.id {
        do {
            let album = try await provider.fetchAlbum(id: albumID)
            printAlbum(album)
        } catch {
            print("  (Could not fetch album details: \(error))")
        }
    }

    // Fetch full artist
    if let artistID = song.artists?.first?.id {
        do {
            let artist = try await provider.fetchArtist(id: artistID)
            printArtist(artist)
        } catch {
            print("  (Could not fetch artist details: \(error))")
        }
    }
}

private func printAlbum(_ album: Album) {
    print("── Album Detail ───────────────────────────")
    print("  ID:            \(album.id)")
    print("  Title:         \(album.title)")
    print("  Artist:        \(album.artistName)")
    if let releaseDate = album.releaseDate {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        print("  Released:      \(formatter.string(from: releaseDate))")
    }
    if !album.genreNames.isEmpty {
        print("  Genres:        \(album.genreNames.joined(separator: ", "))")
    }
    print("  Track Count:   \(album.trackCount)")
    if let contentRating = album.contentRating {
        print("  Rating:        \(contentRating)")
    }
    if let isCompilation = album.isCompilation {
        print("  Compilation:   \(isCompilation)")
    }
    if let isSingle = album.isSingle {
        print("  Single:        \(isSingle)")
    }
    if let isComplete = album.isComplete {
        print("  Complete:      \(isComplete)")
    }
    if let copyright = album.copyright {
        print("  Copyright:     \(copyright)")
    }
    if let upc = album.upc {
        print("  UPC:           \(upc)")
    }
    if let url = album.url {
        print("  URL:           \(url)")
    }
    if let notes = album.editorialNotes {
        if let short = notes.short {
            print("  Notes:         \(short)")
        }
        if let standard = notes.standard {
            // Truncate long descriptions for readability
            let text = standard.count > 500 ? String(standard.prefix(500)) + "…" : standard
            print("  Description:   \(text)")
        }
    }
    if let audioVariants = album.audioVariants {
        print("  Audio:         \(audioVariants.map { "\($0)" }.joined(separator: ", "))")
    }
    if let recordLabels = album.recordLabels {
        let names = recordLabels.map { $0.name }.joined(separator: ", ")
        print("  Labels:        \(names)")
    }
    if let tracks = album.tracks {
        print("  Tracklist:")
        for track in tracks {
            let num = track.trackNumber ?? 0
            print("    \(String(format: "%2d", num)). \(track.title)")
        }
    }
    if let related = album.relatedAlbums, !related.isEmpty {
        let titles = related.prefix(5).map { $0.title }.joined(separator: ", ")
        print("  Related:       \(titles)")
    }
    print()
}

private func printArtist(_ artist: Artist) {
    print("── Artist Detail ──────────────────────────")
    print("  ID:            \(artist.id)")
    print("  Name:          \(artist.name)")
    if let url = artist.url {
        print("  URL:           \(url)")
    }
    if let genreNames = artist.genreNames, !genreNames.isEmpty {
        print("  Genres:        \(genreNames.joined(separator: ", "))")
    }
    if let notes = artist.editorialNotes {
        if let short = notes.short {
            print("  Bio (short):   \(short)")
        }
        if let standard = notes.standard {
            let text = standard.count > 500 ? String(standard.prefix(500)) + "…" : standard
            print("  Bio:           \(text)")
        }
    }
    if let topSongs = artist.topSongs, !topSongs.isEmpty {
        print("  Top Songs:")
        for song in topSongs.prefix(10) {
            print("    - \(song.title) (\(song.albumTitle ?? ""))")
        }
    }
    if let similar = artist.similarArtists, !similar.isEmpty {
        let names = similar.prefix(10).map { $0.name }.joined(separator: ", ")
        print("  Similar:       \(names)")
    }
    if let latest = artist.latestRelease {
        print("  Latest:        \(latest.title)")
    }
    if let fullAlbums = artist.fullAlbums, !fullAlbums.isEmpty {
        print("  Discography:")
        for album in fullAlbums.prefix(15) {
            let year = album.releaseDate.map { Calendar.current.component(.year, from: $0) }
            let yearStr = year.map { " (\($0))" } ?? ""
            print("    - \(album.title)\(yearStr)")
        }
    }
    print()
}
