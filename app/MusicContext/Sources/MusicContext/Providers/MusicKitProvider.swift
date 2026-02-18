import Foundation
import MusicKit

public actor MusicKitProvider {

    public init() {}

    /// Request user authorization for MusicKit access.
    public static func authorize() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    /// Search for a song by artist and track name.
    public func searchSong(artist: String, track: String, album: String? = nil) async throws -> Song {
        let searchTerm: String
        if let album {
            searchTerm = "\(artist) \(track) \(album)"
        } else {
            searchTerm = "\(artist) \(track)"
        }

        var request = MusicCatalogSearchRequest(term: searchTerm, types: [Song.self])
        request.limit = 25

        let response = try await request.response()

        guard let song = bestMatch(from: response.songs, artist: artist, track: track) else {
            throw MusicContextError.noResults(query: searchTerm)
        }

        return try await loadRelationships(for: song)
    }

    /// Fetch a song by its Apple Music catalog ID.
    public func fetchSong(catalogID: String) async throws -> Song {
        guard !catalogID.isEmpty, catalogID.allSatisfy(\.isNumber) else {
            throw MusicContextError.invalidCatalogID(catalogID)
        }

        let id = MusicItemID(catalogID)
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
        let response = try await request.response()

        guard let song = response.items.first else {
            throw MusicContextError.noResults(query: catalogID)
        }

        return try await loadRelationships(for: song)
    }

    /// Load all available relationships for a song.
    private func loadRelationships(for song: Song) async throws -> Song {
        try await song.with(.albums, .artists, .composers, .genres, .musicVideos, .audioVariants)
    }

    /// Fetch full album details by ID (includes editorial notes, record labels, etc.)
    public func fetchAlbum(id: MusicItemID) async throws -> Album {
        let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id)
        let response = try await request.response()
        guard let album = response.items.first else {
            throw MusicContextError.noResults(query: id.rawValue)
        }
        return try await album.with(.artists, .genres, .tracks, .recordLabels, .relatedAlbums, .appearsOn, .audioVariants)
    }

    /// Fetch full artist details by ID (includes editorial notes, genres, etc.)
    public func fetchArtist(id: MusicItemID) async throws -> Artist {
        let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: id)
        let response = try await request.response()
        guard let artist = response.items.first else {
            throw MusicContextError.noResults(query: id.rawValue)
        }
        return try await artist.with(.genres, .topSongs, .similarArtists, .fullAlbums, .latestRelease, .appearsOnAlbums, .compilationAlbums, .featuredAlbums, .liveAlbums, .featuredPlaylists)
    }

    /// Search for a playlist by name.
    public func searchPlaylist(name: String) async throws -> Playlist {
        var request = MusicCatalogSearchRequest(term: name, types: [Playlist.self])
        request.limit = 25

        let response = try await request.response()

        guard let playlist = bestPlaylistMatch(from: response.playlists, name: name) else {
            throw MusicContextError.noResults(query: name)
        }

        return playlist
    }

    /// Load tracks for a playlist.
    public func fetchPlaylistTracks(playlist: Playlist) async throws -> MusicItemCollection<Track> {
        let detailed = try await playlist.with(.tracks)

        guard let tracks = detailed.tracks, !tracks.isEmpty else {
            throw MusicContextError.noResults(query: playlist.name)
        }

        return tracks
    }

    // MARK: - Private

    private func bestPlaylistMatch(from playlists: MusicItemCollection<Playlist>, name: String) -> Playlist? {
        let normalized = name.lowercased()

        for playlist in playlists {
            if playlist.name.lowercased() == normalized {
                return playlist
            }
        }

        for playlist in playlists {
            if playlist.name.lowercased().contains(normalized) {
                return playlist
            }
        }

        return playlists.first
    }

    private func bestMatch(from songs: MusicItemCollection<Song>, artist: String, track: String) -> Song? {
        let normalizedArtist = artist.lowercased()
        let normalizedTrack = track.lowercased()

        for song in songs {
            if song.artistName.lowercased() == normalizedArtist &&
               song.title.lowercased() == normalizedTrack {
                return song
            }
        }

        for song in songs {
            if song.artistName.lowercased().contains(normalizedArtist) &&
               song.title.lowercased() == normalizedTrack {
                return song
            }
        }

        for song in songs {
            if song.title.lowercased() == normalizedTrack {
                return song
            }
        }

        return songs.first
    }
}
