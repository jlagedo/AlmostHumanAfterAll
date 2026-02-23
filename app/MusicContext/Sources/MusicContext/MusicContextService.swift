import Foundation
import MusicKit
import os

private let logger = Logger(subsystem: "com.ficino", category: "MusicContext")

public actor MusicContextService: MusicContextProvider {
    private let musicKit: MusicKitProvider
    private let genius: GeniusProvider?

    public init(geniusAccessToken: String? = nil) {
        self.musicKit = MusicKitProvider()
        self.genius = geniusAccessToken.map { GeniusProvider(accessToken: $0) }
    }

    /// Fetch metadata from MusicKit + Genius in parallel.
    /// Both lookups are non-fatal — returns whatever data was available.
    public func fetch(name: String, artist: String, album: String, genre: String) async -> MetadataResult {
        // MusicKit + Genius in parallel (both non-fatal)
        async let songResult: Song? = {
            do {
                let result = try await musicKit.searchSong(artist: artist, track: name, album: album)
                logger.info("MusicKit match: \"\(result.title)\" by \(result.artistName)")
                return result
            } catch {
                logger.warning("MusicKit lookup failed (non-fatal): \(error.localizedDescription)")
                return nil
            }
        }()

        async let geniusResult: MusicContextData? = {
            guard let genius else {
                logger.debug("Genius: skipped (no token)")
                return nil
            }
            do {
                logger.info("Genius: searching \"\(name)\" by \(artist)")
                let data = try await genius.fetchContext(artist: artist, track: name, album: album)
                logger.info("Genius match: \"\(data.track.title)\" by \(data.artist.name)")
                return data
            } catch {
                logger.warning("Genius lookup failed (non-fatal): \(error.localizedDescription)")
                return nil
            }
        }()

        let song = await songResult
        let geniusData = await geniusResult

        return MetadataResult(
            song: song.map { Self.mapSongMetadata($0) },
            geniusData: geniusData,
            appleMusicURL: song?.url
        )
    }

    /// Request MusicKit authorization.
    public static func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicKitProvider.authorize()
    }

    /// Whether MusicKit authorization has been granted.
    public static func isAuthorized() async -> Bool {
        await requestAuthorization() == .authorized
    }

    // MARK: - Private

    private static func mapSongMetadata(_ song: Song) -> SongMetadata {
        // Extract primary genres (mid-level: has parent but parent has no parent)
        var genres: [String] = []
        if let songGenres = song.genres, !songGenres.isEmpty {
            let primary = songGenres
                .filter { $0.parent != nil && $0.parent?.parent == nil }
                .map(\.name)
            if !primary.isEmpty {
                genres = primary
            }
        }
        if genres.isEmpty {
            genres = song.genreNames.filter { $0 != "Music" }
        }

        // Extract editorial notes
        let albumEditorial: String? = {
            guard let album = song.albums?.first, let notes = album.editorialNotes else { return nil }
            if let short = notes.short, !short.isEmpty { return short }
            if let standard = notes.standard, !standard.isEmpty { return standard }
            return nil
        }()

        let artistEditorial: String? = {
            guard let artist = song.artists?.first, let notes = artist.editorialNotes else { return nil }
            if let short = notes.short, !short.isEmpty { return short }
            if let standard = notes.standard, !standard.isEmpty { return standard }
            return nil
        }()

        return SongMetadata(
            releaseDate: song.releaseDate,
            genres: genres,
            albumEditorialNotes: albumEditorial,
            artistEditorialNotes: artistEditorial
        )
    }
}
