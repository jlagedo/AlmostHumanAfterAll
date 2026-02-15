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

private func opt(_ value: Any?) -> String {
    guard let value else { return "nil" }
    return "\(value)"
}

private func optDate(_ date: Date?, time: Bool = false) -> String {
    guard let date else { return "nil" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    if time { formatter.timeStyle = .short }
    return formatter.string(from: date)
}

private func printSong(_ song: Song) {
    print("── Track (Apple Music) ────────────────────")
    print("  ID:            \(song.id)")
    print("  Title:         \(song.title)")
    print("  Artist:        \(song.artistName)")
    print("  Artist URL:    \(opt(song.artistURL))")
    print("  Album:         \(opt(song.albumTitle))")
    print("  Track #:       \(opt(song.trackNumber))")
    print("  Disc #:        \(opt(song.discNumber))")
    if let duration = song.duration {
        let seconds = Int(duration)
        let ms = Int(duration * 1000)
        print("  Duration:      \(seconds / 60):\(String(format: "%02d", seconds % 60)) (\(ms)ms)")
    } else {
        print("  Duration:      nil")
    }
    print("  Genres:        \(song.genreNames.isEmpty ? "(none)" : song.genreNames.joined(separator: ", "))")
    print("  ISRC:          \(opt(song.isrc))")
    print("  Composer:      \(opt(song.composerName))")
    print("  Released:      \(optDate(song.releaseDate))")
    print("  Rating:        \(opt(song.contentRating))")
    print("  Has Lyrics:    \(song.hasLyrics)")

    // Library & playback stats
    print("  Play Count:    \(opt(song.playCount))")
    print("  Last Played:   \(optDate(song.lastPlayedDate, time: true))")
    print("  Added to Lib:  \(optDate(song.libraryAddedDate))")

    print("  URL:           \(opt(song.url))")
    if let artwork = song.artwork, let url = artwork.url(width: 600, height: 600) {
        print("  Artwork:       \(url)")
    } else {
        print("  Artwork:       nil")
    }

    // Audio quality
    if let audioVariants = song.audioVariants {
        print("  Audio:         \(audioVariants.isEmpty ? "(none)" : audioVariants.map { "\($0)" }.joined(separator: ", "))")
    } else {
        print("  Audio:         nil")
    }
    print("  Digital Master: \(opt(song.isAppleDigitalMaster))")

    // Preview
    if let previews = song.previewAssets {
        if previews.isEmpty {
            print("  Preview:       (none)")
        } else {
            for preview in previews {
                print("  Preview URL:   \(opt(preview.url))")
            }
        }
    } else {
        print("  Preview:       nil")
    }

    // Editorial notes
    print("  Notes (short): \(opt(song.editorialNotes?.short))")
    print("  Notes (std):   \(opt(song.editorialNotes?.standard))")

    // Classical music
    print("  Work:          \(opt(song.workName))")
    print("  Movement:      \(opt(song.movementName))")
    print("  Movement #:    \(opt(song.movementNumber))")
    print("  Movements:     \(opt(song.movementCount))")
    print("  Attribution:   \(opt(song.attribution))")

    // Playback
    print("  Playable:      \(song.playParameters != nil)")

    // Relationships
    let artists = song.artists.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
    print("  Artists:       \(opt(artists))")

    let albums = song.albums.map { $0.map { "\($0.title) (\($0.id))" }.joined(separator: ", ") }
    print("  Albums:        \(opt(albums))")

    let composers = song.composers.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
    print("  Composers:     \(opt(composers))")

    let genres = song.genres.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
    print("  Genre IDs:     \(opt(genres))")

    let musicVideos = song.musicVideos.map { $0.map { "\($0.title) (\($0.id))" }.joined(separator: ", ") }
    print("  Music Videos:  \(opt(musicVideos))")

    let station = song.station.map { "\($0.name) (\($0.id))" }
    print("  Station:       \(opt(station))")

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
    print("  Artist URL:    \(opt(album.artistURL))")
    if let artwork = album.artwork, let url = artwork.url(width: 600, height: 600) {
        print("  Artwork:       \(url)")
    } else {
        print("  Artwork:       nil")
    }
    print("  Released:      \(optDate(album.releaseDate))")
    print("  Genres:        \(album.genreNames.isEmpty ? "(none)" : album.genreNames.joined(separator: ", "))")
    print("  Track Count:   \(album.trackCount)")
    print("  Rating:        \(opt(album.contentRating))")
    print("  Compilation:   \(opt(album.isCompilation))")
    print("  Single:        \(opt(album.isSingle))")
    print("  Complete:      \(opt(album.isComplete))")
    print("  Copyright:     \(opt(album.copyright))")
    print("  UPC:           \(opt(album.upc))")
    print("  URL:           \(opt(album.url))")
    print("  Notes (short): \(opt(album.editorialNotes?.short))")
    if let standard = album.editorialNotes?.standard {
        let text = standard.count > 500 ? String(standard.prefix(500)) + "..." : standard
        print("  Notes (std):   \(text)")
    } else {
        print("  Notes (std):   nil")
    }
    if let audioVariants = album.audioVariants {
        print("  Audio:         \(audioVariants.isEmpty ? "(none)" : audioVariants.map { "\($0)" }.joined(separator: ", "))")
    } else {
        print("  Audio:         nil")
    }
    print("  Playable:      \(album.playParameters != nil)")

    // Relationships
    let labels = album.recordLabels.map { $0.map { $0.name }.joined(separator: ", ") }
    print("  Labels:        \(labels ?? "nil")")

    if let tracks = album.tracks {
        print("  Tracklist (\(tracks.count) tracks):")
        for track in tracks {
            let num = track.trackNumber ?? 0
            print("    \(String(format: "%2d", num)). \(track.title)")
        }
    } else {
        print("  Tracklist:     nil")
    }

    if let related = album.relatedAlbums {
        print("  Related Albums (\(related.count)):")
        for rel in related.prefix(10) {
            print("    - \(rel.title) by \(rel.artistName)")
        }
        if related.count > 10 { print("    ... and \(related.count - 10) more") }
    } else {
        print("  Related:       nil")
    }

    if let appearsOn = album.appearsOn {
        print("  Appears On (\(appearsOn.count) playlists):")
        for playlist in appearsOn.prefix(10) {
            print("    - \(playlist.name)")
        }
        if appearsOn.count > 10 { print("    ... and \(appearsOn.count - 10) more") }
    } else {
        print("  Appears On:    nil")
    }

    print()
}

private func printAlbumList(_ title: String, _ albums: MusicItemCollection<Album>?) {
    guard let albums else {
        print("  \(title): nil")
        return
    }
    if albums.isEmpty {
        print("  \(title): (none)")
        return
    }
    print("  \(title) (\(albums.count)):")
    for album in albums.prefix(15) {
        let year = album.releaseDate.map { Calendar.current.component(.year, from: $0) }
        let yearStr = year.map { " (\($0))" } ?? ""
        print("    - \(album.title)\(yearStr)")
    }
    if albums.count > 15 { print("    ... and \(albums.count - 15) more") }
}

private func printArtist(_ artist: Artist) {
    print("── Artist Detail ──────────────────────────")
    print("  ID:            \(artist.id)")
    print("  Name:          \(artist.name)")
    print("  URL:           \(opt(artist.url))")
    if let artwork = artist.artwork, let url = artwork.url(width: 600, height: 600) {
        print("  Artwork:       \(url)")
    } else {
        print("  Artwork:       nil")
    }
    if let genreNames = artist.genreNames {
        print("  Genres:        \(genreNames.isEmpty ? "(none)" : genreNames.joined(separator: ", "))")
    } else {
        print("  Genres:        nil")
    }
    print("  Bio (short):   \(opt(artist.editorialNotes?.short))")
    if let standard = artist.editorialNotes?.standard {
        let text = standard.count > 500 ? String(standard.prefix(500)) + "..." : standard
        print("  Bio (std):     \(text)")
    } else {
        print("  Bio (std):     nil")
    }

    // Top Songs
    if let topSongs = artist.topSongs {
        if topSongs.isEmpty {
            print("  Top Songs:     (none)")
        } else {
            print("  Top Songs (\(topSongs.count)):")
            for song in topSongs.prefix(10) {
                print("    - \(song.title) (\(song.albumTitle ?? "nil"))")
            }
            if topSongs.count > 10 { print("    ... and \(topSongs.count - 10) more") }
        }
    } else {
        print("  Top Songs:     nil")
    }

    // Similar Artists
    if let similar = artist.similarArtists {
        let names = similar.prefix(10).map { $0.name }.joined(separator: ", ")
        print("  Similar:       \(similar.isEmpty ? "(none)" : names)")
        if similar.count > 10 { print("                 ... and \(similar.count - 10) more") }
    } else {
        print("  Similar:       nil")
    }

    print("  Latest:        \(opt(artist.latestRelease?.title))")

    // Album categories
    printAlbumList("Discography", artist.fullAlbums)
    printAlbumList("Compilations", artist.compilationAlbums)
    printAlbumList("Live Albums", artist.liveAlbums)
    printAlbumList("Featured Albums", artist.featuredAlbums)

    // Appears On (show other artist names)
    if let appearsOn = artist.appearsOnAlbums {
        if appearsOn.isEmpty {
            print("  Appears On:    (none)")
        } else {
            print("  Appears On (\(appearsOn.count) albums):")
            for album in appearsOn.prefix(15) {
                print("    - \(album.title) by \(album.artistName)")
            }
            if appearsOn.count > 15 { print("    ... and \(appearsOn.count - 15) more") }
        }
    } else {
        print("  Appears On:    nil")
    }

    // Featured Playlists
    if let playlists = artist.featuredPlaylists {
        if playlists.isEmpty {
            print("  Playlists:     (none)")
        } else {
            print("  Featured Playlists (\(playlists.count)):")
            for playlist in playlists.prefix(10) {
                print("    - \(playlist.name)")
            }
            if playlists.count > 10 { print("    ... and \(playlists.count - 10) more") }
        }
    } else {
        print("  Playlists:     nil")
    }

    print()
}
