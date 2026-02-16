import Foundation
import MusicKit
import MusicContext

enum MusicKitFormatter {
    static func printSong(_ song: Song) {
        print("── Track (Apple Music) ────────────────────")
        print("  ID:            \(song.id)")
        print("  Title:         \(song.title)")
        print("  Artist:        \(song.artistName)")
        print("  Artist URL:    \(CLIHelpers.opt(song.artistURL))")
        print("  Album:         \(CLIHelpers.opt(song.albumTitle))")
        print("  Track #:       \(CLIHelpers.opt(song.trackNumber))")
        print("  Disc #:        \(CLIHelpers.opt(song.discNumber))")
        if let duration = song.duration {
            let seconds = Int(duration)
            let ms = Int(duration * 1000)
            print("  Duration:      \(seconds / 60):\(String(format: "%02d", seconds % 60)) (\(ms)ms)")
        } else {
            print("  Duration:      nil")
        }
        print("  Genres:        \(song.genreNames.isEmpty ? "(none)" : song.genreNames.joined(separator: ", "))")
        print("  ISRC:          \(CLIHelpers.opt(song.isrc))")
        print("  Composer:      \(CLIHelpers.opt(song.composerName))")
        print("  Released:      \(CLIHelpers.optDate(song.releaseDate))")
        print("  Rating:        \(CLIHelpers.opt(song.contentRating))")
        print("  Has Lyrics:    \(song.hasLyrics)")

        // Library & playback stats
        print("  Play Count:    \(CLIHelpers.opt(song.playCount))")
        print("  Last Played:   \(CLIHelpers.optDate(song.lastPlayedDate, time: true))")
        print("  Added to Lib:  \(CLIHelpers.optDate(song.libraryAddedDate))")

        print("  URL:           \(CLIHelpers.opt(song.url))")
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
        print("  Digital Master: \(CLIHelpers.opt(song.isAppleDigitalMaster))")

        // Preview
        if let previews = song.previewAssets {
            if previews.isEmpty {
                print("  Preview:       (none)")
            } else {
                for preview in previews {
                    print("  Preview URL:   \(CLIHelpers.opt(preview.url))")
                }
            }
        } else {
            print("  Preview:       nil")
        }

        // Editorial notes
        print("  Notes (short): \(CLIHelpers.opt(song.editorialNotes?.short))")
        print("  Notes (std):   \(CLIHelpers.opt(song.editorialNotes?.standard))")

        // Classical music
        print("  Work:          \(CLIHelpers.opt(song.workName))")
        print("  Movement:      \(CLIHelpers.opt(song.movementName))")
        print("  Movement #:    \(CLIHelpers.opt(song.movementNumber))")
        print("  Movements:     \(CLIHelpers.opt(song.movementCount))")
        print("  Attribution:   \(CLIHelpers.opt(song.attribution))")

        // Playback
        print("  Playable:      \(song.playParameters != nil)")

        // Relationships
        let artists = song.artists.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
        print("  Artists:       \(CLIHelpers.opt(artists))")

        let albums = song.albums.map { $0.map { "\($0.title) (\($0.id))" }.joined(separator: ", ") }
        print("  Albums:        \(CLIHelpers.opt(albums))")

        let composers = song.composers.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
        print("  Composers:     \(CLIHelpers.opt(composers))")

        let genres = song.genres.map { $0.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
        print("  Genre IDs:     \(CLIHelpers.opt(genres))")

        let musicVideos = song.musicVideos.map { $0.map { "\($0.title) (\($0.id))" }.joined(separator: ", ") }
        print("  Music Videos:  \(CLIHelpers.opt(musicVideos))")

        let station = song.station.map { "\($0.name) (\($0.id))" }
        print("  Station:       \(CLIHelpers.opt(station))")

        print()
    }

    static func printAlbum(_ album: Album) {
        print("── Album Detail ───────────────────────────")
        print("  ID:            \(album.id)")
        print("  Title:         \(album.title)")
        print("  Artist:        \(album.artistName)")
        print("  Artist URL:    \(CLIHelpers.opt(album.artistURL))")
        if let artwork = album.artwork, let url = artwork.url(width: 600, height: 600) {
            print("  Artwork:       \(url)")
        } else {
            print("  Artwork:       nil")
        }
        print("  Released:      \(CLIHelpers.optDate(album.releaseDate))")
        print("  Genres:        \(album.genreNames.isEmpty ? "(none)" : album.genreNames.joined(separator: ", "))")
        print("  Track Count:   \(album.trackCount)")
        print("  Rating:        \(CLIHelpers.opt(album.contentRating))")
        print("  Compilation:   \(CLIHelpers.opt(album.isCompilation))")
        print("  Single:        \(CLIHelpers.opt(album.isSingle))")
        print("  Complete:      \(CLIHelpers.opt(album.isComplete))")
        print("  Copyright:     \(CLIHelpers.opt(album.copyright))")
        print("  UPC:           \(CLIHelpers.opt(album.upc))")
        print("  URL:           \(CLIHelpers.opt(album.url))")
        print("  Notes (short): \(CLIHelpers.opt(album.editorialNotes?.short))")
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

    static func printArtist(_ artist: Artist) {
        print("── Artist Detail ──────────────────────────")
        print("  ID:            \(artist.id)")
        print("  Name:          \(artist.name)")
        print("  URL:           \(CLIHelpers.opt(artist.url))")
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
        print("  Bio (short):   \(CLIHelpers.opt(artist.editorialNotes?.short))")
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

        print("  Latest:        \(CLIHelpers.opt(artist.latestRelease?.title))")

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

    static func printFullContext(song: Song, provider: MusicKitProvider) async {
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

    private static func printAlbumList(_ title: String, _ albums: MusicItemCollection<Album>?) {
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
}
