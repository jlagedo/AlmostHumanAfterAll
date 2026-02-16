import Foundation

// MARK: - Provider

public actor GeniusProvider {
    private static let baseURL = "https://api.genius.com"
    private let accessToken: String
    private let session: URLSession
    private let rateLimiter = RateLimiter(requestsPerSecond: 5)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public init(accessToken: String) {
        self.accessToken = accessToken
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    public func fetchContext(artist: String, track: String, album: String? = nil) async throws -> MusicContextData {
        let songResult = try await searchWithFallbacks(artist: artist, track: track)

        // Fetch full song detail
        let songDetail = try await lookupSong(id: songResult.id)

        // Fetch full artist detail
        let artistDetail = try await lookupArtist(id: songResult.primaryArtist.id)

        return mapToDomain(
            searchResult: songResult,
            song: songDetail,
            artist: artistDetail,
            albumName: album
        )
    }

    // MARK: - API Calls

    private func searchSong(query: String) async throws -> GeniusSearchResponse {
        guard var components = URLComponents(string: "\(Self.baseURL)/search") else {
            throw MusicContextError.invalidURL("genius search")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
        ]
        return try await fetch(url: components, as: GeniusSearchResponse.self)
    }

    private func lookupSong(id: Int) async throws -> GeniusSongFull {
        guard var components = URLComponents(string: "\(Self.baseURL)/songs/\(id)") else {
            throw MusicContextError.invalidURL("genius song lookup")
        }
        components.queryItems = [
            URLQueryItem(name: "text_format", value: "plain"),
        ]
        let response: GeniusSongResponse = try await fetch(url: components, as: GeniusSongResponse.self)
        return response.response.song
    }

    private func lookupArtist(id: Int) async throws -> GeniusArtistFull {
        guard var components = URLComponents(string: "\(Self.baseURL)/artists/\(id)") else {
            throw MusicContextError.invalidURL("genius artist lookup")
        }
        components.queryItems = [
            URLQueryItem(name: "text_format", value: "plain"),
        ]
        let response: GeniusArtistResponse = try await fetch(url: components, as: GeniusArtistResponse.self)
        return response.response.artist
    }

    // MARK: - Networking

    private func fetch<T: Decodable & Sendable>(url components: URLComponents, as type: T.Type) async throws -> T {
        guard let url = components.url else {
            throw MusicContextError.invalidURL(components.string ?? "unknown")
        }

        try await rateLimiter.wait()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MusicContextError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MusicContextError.networkError(underlying: URLError(.badServerResponse))
        }

        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw MusicContextError.rateLimited(retryAfterSeconds: retry)
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw MusicContextError.httpError(statusCode: http.statusCode, body: body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8)
            throw MusicContextError.decodingError(underlying: error, body: body)
        }
    }

    // MARK: - Search Fallbacks

    private func searchWithFallbacks(artist: String, track: String) async throws -> GeniusSearchSong {
        let normalizedTrack = Self.stripFeaturingCredit(track)
        let normalizedArtist = Self.stripFeaturingCredit(artist)
        let primary = Self.primaryArtist(artist)

        // Build search queries from most specific to least
        var queries: [String] = []
        queries.append("\(artist) \(track)")

        if normalizedTrack != track || normalizedArtist != artist {
            queries.append("\(normalizedArtist) \(normalizedTrack)")
        }

        if let primary, primary != artist && primary != normalizedArtist {
            queries.append("\(primary) \(normalizedTrack)")
        }

        let strippedTrack = Self.stripAllParenthetical(normalizedTrack)
        if strippedTrack != normalizedTrack && !strippedTrack.isEmpty {
            queries.append("\(normalizedArtist) \(strippedTrack)")
        }

        for query in queries {
            let response = try await searchSong(query: query)
            let songs = response.response.hits
                .filter { $0.type == "song" }
                .map(\.result)

            if let best = selectBestMatch(from: songs, artist: artist, track: track,
                                          normalizedArtist: normalizedArtist, normalizedTrack: normalizedTrack) {
                return best
            }
        }

        throw MusicContextError.noResults(query: "\(artist) - \(track)")
    }

    // MARK: - Best Match Selection

    private func selectBestMatch(
        from songs: [GeniusSearchSong],
        artist: String, track: String,
        normalizedArtist: String, normalizedTrack: String
    ) -> GeniusSearchSong? {
        guard !songs.isEmpty else { return nil }

        let artistLower = artist.lowercased()
        let trackLower = track.lowercased()
        let normArtistLower = normalizedArtist.lowercased()
        let normTrackLower = normalizedTrack.lowercased()

        // Exact artist + exact title
        if let exact = songs.first(where: {
            $0.primaryArtist.name.lowercased() == artistLower &&
            $0.title.lowercased() == trackLower
        }) {
            return exact
        }

        // Exact artist + normalized title
        if let match = songs.first(where: {
            $0.primaryArtist.name.lowercased() == normArtistLower &&
            $0.title.lowercased() == normTrackLower
        }) {
            return match
        }

        // Fuzzy: artist contains + title contains
        if let fuzzy = songs.first(where: {
            let a = $0.primaryArtist.name.lowercased()
            let t = $0.title.lowercased()
            return (a.contains(normArtistLower) || normArtistLower.contains(a)) &&
                   (t.contains(normTrackLower) || normTrackLower.contains(t))
        }) {
            return fuzzy
        }

        // Title-only match (any artist)
        if let titleOnly = songs.first(where: {
            $0.title.lowercased() == normTrackLower
        }) {
            return titleOnly
        }

        // Fall back to first result
        return songs.first
    }

    // MARK: - Domain Mapping

    private func mapToDomain(
        searchResult: GeniusSearchSong,
        song: GeniusSongFull,
        artist: GeniusArtistFull,
        albumName: String?
    ) -> MusicContextData {
        let songwriters = (song.writerArtists ?? []).map(\.name)
        let producers = (song.producerArtists ?? []).map(\.name)

        // Extract song relationships by type
        let relationships = song.songRelationships ?? []
        let samples = Self.relatedSongNames(relationships, type: "samples")
        let sampledBy = Self.relatedSongNames(relationships, type: "sampled_in")

        // Cover of and interpolations both map to influences
        let interpolates = Self.relatedSongNames(relationships, type: "interpolates")
        let coverOf = Self.relatedSongNames(relationships, type: "cover_of")
        let influences = interpolates + coverOf

        // Build track description from Genius description
        let trackDescription = song.songDescription?.plain?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wikiSummary: String? = if let desc = trackDescription, desc != "?" && !desc.isEmpty {
            desc
        } else {
            nil
        }

        let trackContext = TrackContext(
            title: song.title,
            wikiSummary: wikiSummary
        )

        // Artist bio from Genius
        let artistBio = artist.artistDescription?.plain?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio: String? = if let b = artistBio, b != "?" && !b.isEmpty {
            b
        } else {
            nil
        }

        let artistContext = ArtistContext(
            name: artist.name,
            bio: bio
        )

        let albumTitle = song.album?.name ?? albumName ?? "Unknown"
        let albumContext = AlbumContext(title: albumTitle)

        // Custom performances (e.g., "Guitar", "Mixing Engineer") to additional credits
        let customPerfs = song.customPerformances ?? []
        let additionalCredits = customPerfs.compactMap { perf -> String? in
            guard let label = perf.label, let artists = perf.artists, !artists.isEmpty else { return nil }
            let names = artists.map(\.name).joined(separator: ", ")
            return "\(label): \(names)"
        }

        // Record label from album info
        let recordLabel: String? = nil // Genius doesn't provide label info directly

        let triviaContext = TriviaContext(
            songwriters: songwriters,
            producers: producers,
            samples: samples,
            sampledBy: sampledBy,
            influences: influences,
            recordLabel: recordLabel
        )

        return MusicContextData(
            track: trackContext,
            artist: artistContext,
            album: albumContext,
            trivia: triviaContext
        )
    }

    private static func relatedSongNames(_ relationships: [GeniusSongRelationship], type: String) -> [String] {
        relationships
            .filter { ($0.relationshipType ?? $0.type) == type }
            .flatMap { $0.songs ?? [] }
            .map { "\($0.title) by \($0.primaryArtist.name)" }
    }

    // MARK: - Normalization Helpers

    private static func stripFeaturingCredit(_ name: String) -> String {
        var result = name
        if let range = result.range(of: #"\s*[\(\[](feat\.?|ft\.?)\s+[^\)\]]+[\)\]]"#, options: .regularExpression, range: result.startIndex..<result.endIndex) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func stripAllParenthetical(_ name: String) -> String {
        var result = name
        while let range = result.range(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func primaryArtist(_ artist: String) -> String? {
        let separators = [" & ", ", ", " x ", " X "]
        for sep in separators {
            if let range = artist.range(of: sep) {
                let primary = String(artist[artist.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !primary.isEmpty { return primary }
            }
        }
        return nil
    }
}
