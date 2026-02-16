import Foundation

// MARK: - Errors

public enum MusicContextError: Error, CustomStringConvertible {
    case networkError(underlying: Error)
    case httpError(statusCode: Int, body: String?)
    case decodingError(underlying: Error, body: String?)
    case rateLimited(retryAfterSeconds: Int?)
    case noResults(query: String)
    case invalidURL(String)
    case appleMusicUnavailable
    case invalidCatalogID(String)

    public var description: String {
        switch self {
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .httpError(let code, let body):
            return "HTTP \(code)\(body.map { ": \($0.prefix(200))" } ?? "")"
        case .decodingError(let err, let body):
            return "Decoding error: \(err.localizedDescription)\(body.map { "\nBody: \($0.prefix(300))" } ?? "")"
        case .rateLimited(let retry):
            return "Rate limited\(retry.map { " (retry after \($0)s)" } ?? "")"
        case .noResults(let query):
            return "No results for: \(query)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .appleMusicUnavailable:
            return "Apple Music/MusicKit is not available on this system"
        case .invalidCatalogID(let id):
            return "Invalid Apple Music catalog ID: \(id)"
        }
    }
}

// MARK: - Provider

public actor MusicBrainzProvider {
    private static let baseURL = "https://musicbrainz.org/ws/2"
    private let userAgent: String
    private let session: URLSession
    private let rateLimiter = RateLimiter(requestsPerSecond: 1)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public init(appName: String, version: String, contact: String) {
        self.userAgent = "\(appName)/\(version) ( \(contact) )"
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": self.userAgent, "Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// - Parameters:
    ///   - artist: Artist name
    ///   - track: Track name
    ///   - album: Album name (optional, helps match the correct release)
    ///   - durationMs: Track duration in milliseconds from Apple Music (optional, helps pick the correct recording)
    public func fetchContext(artist: String, track: String, album: String?, durationMs: Int? = nil) async throws -> MusicContextData {
        // Normalize Apple Music naming conventions
        let normalizedAlbum = album.flatMap { Self.stripAppleMusicSuffix($0) }
        let normalizedTrack = Self.stripFeaturingCredit(track)
        let normalizedArtist = Self.stripFeaturingCredit(artist)
        // If artist has "&" or "," it may be a collaboration — try the first name as fallback
        let primaryArtist = Self.primaryArtist(artist)

        // Step 1: Search with progressively looser queries until we get results
        let searchResults = try await searchWithFallbacks(
            artist: artist, track: track, album: album,
            normalizedAlbum: normalizedAlbum, normalizedTrack: normalizedTrack,
            normalizedArtist: normalizedArtist, primaryArtist: primaryArtist
        )

        guard !searchResults.recordings.isEmpty else {
            throw MusicContextError.noResults(query: "\(artist) - \(track)")
        }

        // Step 2: Select best recording match (use normalized album for matching)
        let matchAlbum = normalizedAlbum ?? album
        let best = selectBestRecording(from: searchResults.recordings, album: matchAlbum, durationMs: durationMs)
        let recordingId = best.id
        let artistId = best.artistCredit?.first?.artist.id

        // Step 3: Find the original release via release-group browse
        // Get the release group ID from the search results, then browse all releases in that group
        let releaseGroupId = selectBestRelease(from: best.releases, album: matchAlbum)?.releaseGroup?.id
        var releaseId: String?
        if let rgid = releaseGroupId {
            let allReleases = try await browseReleases(releaseGroupId: rgid)
            releaseId = selectOriginalRelease(from: allReleases.releases)?.id
        }

        // Step 4: Lookup recording for tags/genres/rating/ISRCs
        let recordingDetail = try await lookupRecording(id: recordingId)

        // Step 5: Lookup artist for life-span
        var artistDetail: MBArtistFull?
        if let artistId {
            artistDetail = try await lookupArtist(id: artistId)
        }

        // Step 6: Lookup the original release for label/track-count/album-type
        var releaseDetail: MBReleaseLookup?
        if let releaseId {
            releaseDetail = try await lookupRelease(id: releaseId)
        }

        // Step 7: Map to domain models
        return mapToDomain(
            searchResult: best,
            recording: recordingDetail,
            artist: artistDetail,
            release: releaseDetail
        )
    }

    // MARK: - API Calls

    private func searchRecording(artist: String, track: String, release: String?) async throws -> MBRecordingSearchResponse {
        var query = "artist:\"\(luceneEscape(artist))\" AND recording:\"\(luceneEscape(track))\""
        if let release {
            query += " AND release:\"\(luceneEscape(release))\""
        }
        guard var components = URLComponents(string: "\(Self.baseURL)/recording") else {
            throw MusicContextError.invalidURL("recording search")
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        return try await fetch(url: components, as: MBRecordingSearchResponse.self)
    }

    private func lookupRecording(id: String) async throws -> MBRecordingLookup {
        guard var components = URLComponents(string: "\(Self.baseURL)/recording/\(id)") else {
            throw MusicContextError.invalidURL("recording lookup")
        }
        components.queryItems = [
            URLQueryItem(name: "inc", value: "tags+genres+ratings+isrcs+artist-credits"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return try await fetch(url: components, as: MBRecordingLookup.self)
    }

    private func lookupArtist(id: String) async throws -> MBArtistFull {
        guard var components = URLComponents(string: "\(Self.baseURL)/artist/\(id)") else {
            throw MusicContextError.invalidURL("artist lookup")
        }
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return try await fetch(url: components, as: MBArtistFull.self)
    }

    private func browseReleases(releaseGroupId: String) async throws -> MBReleaseBrowseResponse {
        guard var components = URLComponents(string: "\(Self.baseURL)/release") else {
            throw MusicContextError.invalidURL("release browse")
        }
        components.queryItems = [
            URLQueryItem(name: "release-group", value: releaseGroupId),
            URLQueryItem(name: "inc", value: "media"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        return try await fetch(url: components, as: MBReleaseBrowseResponse.self)
    }

    private func lookupRelease(id: String) async throws -> MBReleaseLookup {
        guard var components = URLComponents(string: "\(Self.baseURL)/release/\(id)") else {
            throw MusicContextError.invalidURL("release lookup")
        }
        components.queryItems = [
            URLQueryItem(name: "inc", value: "labels+release-groups+media"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return try await fetch(url: components, as: MBReleaseLookup.self)
    }

    // MARK: - Networking

    private func fetch<T: Decodable & Sendable>(url components: URLComponents, as type: T.Type) async throws -> T {
        guard let url = components.url else {
            throw MusicContextError.invalidURL(components.string ?? "unknown")
        }

        try await rateLimiter.wait()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
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

    // MARK: - Best Match Selection

    private func selectBestRecording(from recordings: [MBRecordingSearchResult], album: String?, durationMs: Int?) -> MBRecordingSearchResult {
        // If album provided, filter to recordings that have a matching release (exact first, then fuzzy)
        if let album, !album.isEmpty {
            let albumLower = album.lowercased()

            // Exact album title match
            let exactMatches = recordings.filter { recording in
                recording.releases?.contains { $0.title.lowercased() == albumLower } ?? false
            }
            if let best = Self.bestRecording(from: exactMatches, durationMs: durationMs) { return best }

            // Fuzzy: contains
            let fuzzyMatches = recordings.filter { recording in
                recording.releases?.contains { release in
                    let t = release.title.lowercased()
                    return t.contains(albumLower) || albumLower.contains(t)
                } ?? false
            }
            if let best = Self.bestRecording(from: fuzzyMatches, durationMs: durationMs) { return best }
        }

        // Fall back to all recordings
        return Self.bestRecording(from: recordings, durationMs: durationMs) ?? recordings.first!
    }

    /// Pick the best recording: if we have a known duration, prefer the closest match. Otherwise, highest score then longest.
    private static func bestRecording(from recordings: [MBRecordingSearchResult], durationMs: Int?) -> MBRecordingSearchResult? {
        guard !recordings.isEmpty else { return nil }

        if let target = durationMs {
            // Duration tolerance: within 10 seconds counts as a match
            let tolerance = 10_000
            let durationMatches = recordings.filter { r in
                guard let len = r.length else { return false }
                return abs(len - target) <= tolerance
            }
            // If we have duration matches, pick the closest one (then by score)
            if !durationMatches.isEmpty {
                return durationMatches.sorted { a, b in
                    let aDiff = abs((a.length ?? 0) - target)
                    let bDiff = abs((b.length ?? 0) - target)
                    if aDiff != bDiff { return aDiff < bDiff }
                    return (a.score ?? 0) > (b.score ?? 0)
                }.first
            }
        }

        // No duration or no duration matches: highest score, then longest
        return recordings.sorted { a, b in
            let aScore = a.score ?? 0
            let bScore = b.score ?? 0
            if aScore != bScore { return aScore > bScore }
            return (a.length ?? 0) > (b.length ?? 0)
        }.first
    }

    private func selectBestRelease(from releases: [MBReleaseSearchResult]?, album: String?) -> MBReleaseSearchResult? {
        guard let releases, !releases.isEmpty else { return nil }

        // Filter candidates by title match if album provided
        var candidates = releases
        if let album, !album.isEmpty {
            let albumLower = album.lowercased()
            let exact = releases.filter { $0.title.lowercased() == albumLower }
            if !exact.isEmpty {
                candidates = exact
            } else {
                let fuzzy = releases.filter {
                    $0.title.lowercased().contains(albumLower) || albumLower.contains($0.title.lowercased())
                }
                if !fuzzy.isEmpty { candidates = fuzzy }
            }
        }

        // Among candidates, prefer: Official → has date → earliest year → fewest tracks
        return candidates
            .sorted { Self.compareRelease(dateA: $0.date, statusA: $0.status, tracksA: $0.trackCount, dateB: $1.date, statusB: $1.status, tracksB: $1.trackCount) }
            .first
    }

    /// Select original release from a full browse of all releases in a release group.
    /// Prefers: Official → has date → earliest year → fewest tracks (standard pressing over box sets/deluxe).
    private func selectOriginalRelease(from releases: [MBReleaseBrowseResult]) -> MBReleaseBrowseResult? {
        guard !releases.isEmpty else { return nil }
        return releases
            .sorted { Self.compareRelease(dateA: $0.date, statusA: $0.status, tracksA: $0.totalTrackCount, dateB: $1.date, statusB: $1.status, tracksB: $1.totalTrackCount) }
            .first
    }

    /// Shared comparison: Official → has date → earliest year → fewest tracks
    private static func compareRelease(dateA: String?, statusA: String?, tracksA: Int?, dateB: String?, statusB: String?, tracksB: Int?) -> Bool {
        let aOfficial = statusA == "Official"
        let bOfficial = statusB == "Official"
        if aOfficial != bOfficial { return aOfficial }
        let aYear = dateA.flatMap { $0.isEmpty ? nil : String($0.prefix(4)) }
        let bYear = dateB.flatMap { $0.isEmpty ? nil : String($0.prefix(4)) }
        if aYear != nil && bYear == nil { return true }
        if aYear == nil && bYear != nil { return false }
        if let aY = aYear, let bY = bYear, aY != bY { return aY < bY }
        // Same year (or both nil): prefer fewest tracks
        return (tracksA ?? Int.max) < (tracksB ?? Int.max)
    }

    // MARK: - Domain Mapping

    private func mapToDomain(
        searchResult: MBRecordingSearchResult,
        recording: MBRecordingLookup,
        artist: MBArtistFull?,
        release: MBReleaseLookup?
    ) -> MusicContextData {
        let trackGenres = (recording.genres ?? [])
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            .map(\.name)

        let trackTags = (recording.tags ?? [])
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            .map(\.name)

        let track = TrackContext(
            title: recording.title,
            durationMs: recording.length,
            genres: trackGenres,
            tags: trackTags,
            isrc: recording.isrcs?.first,
            communityRating: recording.rating?.value,
            musicBrainzId: recording.id
        )

        let artistCredit = searchResult.artistCredit?.first
        let artistContext = ArtistContext(
            name: artist?.name ?? artistCredit?.artist.name ?? "Unknown",
            type: artist?.type,
            country: artist?.country,
            activeSince: artist?.lifeSpan?.begin,
            activeUntil: artist?.lifeSpan?.ended == true ? artist?.lifeSpan?.end : nil,
            disambiguation: artist?.disambiguation,
            musicBrainzId: artist?.id ?? artistCredit?.artist.id
        )

        let selectedRelease = selectBestRelease(from: searchResult.releases, album: nil)
        let label = release?.labelInfo?.first(where: { $0.label != nil })?.label?.name
        let albumType = release?.releaseGroup?.primaryType ?? selectedRelease?.releaseGroup?.primaryType
        let totalTrackCount = release?.media?.reduce(0) { $0 + ($1.trackCount ?? 0) }

        let albumContext = AlbumContext(
            title: release?.title ?? selectedRelease?.title ?? "Unknown",
            releaseDate: release?.date ?? selectedRelease?.date,
            country: release?.country ?? selectedRelease?.country,
            label: label,
            trackCount: totalTrackCount ?? selectedRelease?.trackCount,
            status: release?.status ?? selectedRelease?.status,
            albumType: albumType,
            musicBrainzId: release?.id ?? selectedRelease?.id
        )

        return MusicContextData(
            track: track,
            artist: artistContext,
            album: albumContext
        )
    }

    // MARK: - Search Fallbacks

    /// Tries progressively looser search queries until results are found.
    private func searchWithFallbacks(
        artist: String, track: String, album: String?,
        normalizedAlbum: String?, normalizedTrack: String,
        normalizedArtist: String, primaryArtist: String?
    ) async throws -> MBRecordingSearchResponse {
        // Build a list of (artist, track, release) combinations to try, most specific first
        var attempts: [(artist: String, track: String, release: String?)] = []

        if let album, !album.isEmpty {
            attempts.append((artist, track, album))
            if let na = normalizedAlbum, na != album {
                attempts.append((artist, track, na))
            }
        }
        attempts.append((artist, track, nil))

        // If track has featuring credit, retry without it
        if normalizedTrack != track {
            attempts.append((artist, normalizedTrack, nil))
        }

        // If artist was normalized (featuring stripped), try that
        if normalizedArtist != artist {
            attempts.append((normalizedArtist, normalizedTrack, nil))
        }

        // If artist has "&" or ",", try the primary artist alone
        if let primary = primaryArtist, primary != artist && primary != normalizedArtist {
            attempts.append((primary, normalizedTrack, nil))
        }

        // Strip all parenthetical content as a last resort: "(Edit)", "(Remix)", "(Live)", etc.
        let strippedTrack = Self.stripAllParenthetical(normalizedTrack)
        if strippedTrack != normalizedTrack && !strippedTrack.isEmpty {
            attempts.append((normalizedArtist, strippedTrack, nil))
            if let primary = primaryArtist, primary != normalizedArtist {
                attempts.append((primary, strippedTrack, nil))
            }
        }

        for attempt in attempts {
            let results = try await searchRecording(artist: attempt.artist, track: attempt.track, release: attempt.release)
            if !results.recordings.isEmpty {
                return results
            }
        }

        return MBRecordingSearchResponse(created: nil, count: 0, offset: 0, recordings: [])
    }

    // MARK: - Apple Music Normalization

    /// Strips suffixes Apple Music appends to album names (e.g. "Shiver - EP" → "Shiver")
    private static func stripAppleMusicSuffix(_ album: String) -> String {
        let suffixes = [" - EP", " - Single", " (Deluxe Edition)", " (Deluxe)", " (Remastered)", " (Expanded Edition)"]
        for suffix in suffixes {
            if album.hasSuffix(suffix) {
                return String(album.dropLast(suffix.count))
            }
        }
        return album
    }

    /// Strips "(feat. ...)" or "(ft. ...)" from track/artist names
    private static func stripFeaturingCredit(_ name: String) -> String {
        // Match "(feat. ...)", "(ft. ...)", "[feat. ...]" at end or mid-string
        var result = name
        if let range = result.range(of: #"\s*[\(\[](feat\.?|ft\.?)\s+[^\)\]]+[\)\]]"#, options: .regularExpression, range: result.startIndex..<result.endIndex) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Strips all parenthetical/bracket content: "(Edit)", "(Remix)", "(Live)", "(2024 Remaster)", etc.
    private static func stripAllParenthetical(_ name: String) -> String {
        var result = name
        while let range = result.range(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Extracts the primary artist from collaborations: "A & B" → "A", "A, B & C" → "A"
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

    // MARK: - Helpers

    /// Escapes special Lucene query characters for MusicBrainz search.
    /// Strips double quotes since the caller wraps the result in phrase quotes.
    private func luceneEscape(_ input: String) -> String {
        let special: Set<Character> = ["+", "-", "&", "|", "!", "(", ")", "{", "}", "[", "]", "^", "~", "*", "?", ":", "\\", "/"]
        var result = ""
        for char in input {
            if char == "\"" { continue } // strip — caller adds phrase quotes
            if special.contains(char) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }
}
