import Foundation
import os

private let logger = Logger(subsystem: "com.ficino", category: "LastFm")

public actor LastFmService: ScrobbleService {
    private static let apiBase = "https://ws.audioscrobbler.com/2.0/?format=json"
    private static let authBase = "https://www.last.fm/api/auth/"
    private static let maxPending = 50

    private static let formUnreserved: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return allowed
    }()

    /// Percent-encode for application/x-www-form-urlencoded (spaces become `+`).
    private static func formEncode(_ string: String) -> String {
        let percentEncoded = string.addingPercentEncoding(withAllowedCharacters: formUnreserved) ?? string
        return percentEncoded.replacingOccurrences(of: "%20", with: "+")
    }

    private let apiKey: String
    private let sharedSecret: String
    private let session: URLSession
    private var sessionKey: String?
    private var pendingScrobbles: [PendingScrobble] = []

    struct PendingScrobble: Codable, Sendable {
        let artist: String
        let track: String
        let album: String
        let timestamp: Date
        let duration: TimeInterval
    }

    public init(apiKey: String, sharedSecret: String, sessionKey: String? = nil) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.sessionKey = sessionKey
        self.pendingScrobbles = Self.loadPending()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        let pendingCount = pendingScrobbles.count
        if pendingCount > 0 {
            logger.info("Loaded \(pendingCount) pending scrobbles from disk")
        }
    }

    // MARK: - Auth

    public func getRequestToken() async throws -> String {
        var params: [String: String] = [
            "method": "auth.getToken",
            "api_key": apiKey,
        ]
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        let data = try await post(params: params)
        let response = try LastFmJSON.parseToken(from: data)
        logger.info("Got auth token")
        return response.token
    }

    public nonisolated func authURL(token: String) -> URL {
        var components = URLComponents(string: Self.authBase)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url!
    }

    public func getSession(token: String) async throws -> (sessionKey: String, username: String) {
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token,
        ]
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        let data = try await post(params: params)
        let response = try LastFmJSON.parseSession(from: data)
        self.sessionKey = response.session.key
        logger.info("Authenticated as \(response.session.name)")
        return (sessionKey: response.session.key, username: response.session.name)
    }

    public func setSessionKey(_ key: String?) {
        self.sessionKey = key
        if key != nil {
            logger.debug("Session key updated")
        } else {
            logger.debug("Session key cleared")
        }
    }

    public var isAuthenticated: Bool {
        sessionKey != nil
    }

    // MARK: - Scrobble

    public func scrobble(artist: String, track: String, album: String,
                         timestamp: Date, duration: TimeInterval) async {
        guard let sk = sessionKey else {
            logger.debug("Skipping scrobble (not authenticated)")
            return
        }

        logger.debug("Submitting scrobble: \"\(track)\" by \(artist) (album: \(album), duration: \(Int(duration))s, ts: \(Int(timestamp.timeIntervalSince1970)))")

        // Flush any pending scrobbles first
        await flushPending(sk: sk)

        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sk,
            "artist[0]": artist,
            "track[0]": track,
            "timestamp[0]": String(Int(timestamp.timeIntervalSince1970)),
        ]
        if !album.isEmpty {
            params["album[0]"] = album
        }
        if duration > 0 {
            params["duration[0]"] = String(Int(duration))
        }
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        do {
            let data = try await post(params: params)
            let response = try LastFmJSON.parseScrobbleResponse(from: data)
            logger.info("Scrobbled: \(track) by \(artist) (accepted: \(response.scrobbles.attr.accepted), ignored: \(response.scrobbles.attr.ignored))")
        } catch {
            logger.warning("Scrobble failed, queuing: \(error.localizedDescription)")
            queueScrobble(artist: artist, track: track, album: album,
                         timestamp: timestamp, duration: duration)
        }
    }

    public func updateNowPlaying(artist: String, track: String,
                                 album: String, duration: TimeInterval) async {
        guard let sk = sessionKey else {
            logger.debug("Skipping now playing (not authenticated)")
            return
        }

        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sk,
            "artist": artist,
            "track": track,
        ]
        if !album.isEmpty {
            params["album"] = album
        }
        if duration > 0 {
            params["duration"] = String(Int(duration))
        }
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        do {
            let data = try await post(params: params)
            try LastFmJSON.parseNowPlayingResponse(from: data)
            logger.info("Now playing: \(track) by \(artist)")
        } catch {
            logger.warning("Now playing update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Loved Tracks

    public func love(artist: String, track: String) async {
        guard let sk = sessionKey else {
            logger.debug("Skipping love (not authenticated)")
            return
        }

        var params: [String: String] = [
            "method": "track.love",
            "api_key": apiKey,
            "sk": sk,
            "artist": artist,
            "track": track,
        ]
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        do {
            _ = try await post(params: params)
            logger.debug("Loved: \(track) by \(artist)")
        } catch {
            logger.warning("Failed to love track: \(error.localizedDescription)")
        }
    }

    public func unlove(artist: String, track: String) async {
        guard let sk = sessionKey else {
            logger.debug("Skipping unlove (not authenticated)")
            return
        }

        var params: [String: String] = [
            "method": "track.unlove",
            "api_key": apiKey,
            "sk": sk,
            "artist": artist,
            "track": track,
        ]
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        do {
            _ = try await post(params: params)
            logger.debug("Unloved: \(track) by \(artist)")
        } catch {
            logger.warning("Failed to unlove track: \(error.localizedDescription)")
        }
    }

    public func getLovedTracks(username: String, limit: Int = 1000) async -> Set<String> {
        let params: [String: String] = [
            "method": "user.getLovedTracks",
            "api_key": apiKey,
            "user": username,
            "limit": String(limit),
        ]

        do {
            let data = try await post(params: params)
            let response = try LastFmJSON.parseLovedTracks(from: data)
            let keys = Set(response.lovedtracks.track.map {
                Self.lovedTrackKey(artist: $0.artist.name, track: $0.name)
            })
            logger.info("Fetched \(keys.count) loved tracks from Last.fm")
            return keys
        } catch {
            logger.warning("Failed to fetch loved tracks: \(error.localizedDescription)")
            return []
        }
    }

    /// Normalized key for matching loved tracks: lowercased "artist\ttrack".
    public static func lovedTrackKey(artist: String, track: String) -> String {
        "\(artist.lowercased())\t\(track.lowercased())"
    }

    // MARK: - Retry Queue

    private func queueScrobble(artist: String, track: String, album: String,
                               timestamp: Date, duration: TimeInterval) {
        let pending = PendingScrobble(
            artist: artist, track: track, album: album,
            timestamp: timestamp, duration: duration
        )
        pendingScrobbles.append(pending)
        if pendingScrobbles.count > Self.maxPending {
            pendingScrobbles.removeFirst(pendingScrobbles.count - Self.maxPending)
        }
        persistPending()
        logger.debug("Queued scrobble (\(self.pendingScrobbles.count) pending)")
    }

    private func flushPending(sk: String) async {
        guard !pendingScrobbles.isEmpty else { return }

        // Last.fm accepts max 50 scrobbles per batch request
        let batch = Array(pendingScrobbles.prefix(Self.maxPending))
        logger.debug("Flushing \(batch.count) pending scrobbles")

        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sk,
        ]

        for (i, scrobble) in batch.enumerated() {
            params["artist[\(i)]"] = scrobble.artist
            params["track[\(i)]"] = scrobble.track
            params["timestamp[\(i)]"] = String(Int(scrobble.timestamp.timeIntervalSince1970))
            if !scrobble.album.isEmpty {
                params["album[\(i)]"] = scrobble.album
            }
            if scrobble.duration > 0 {
                params["duration[\(i)]"] = String(Int(scrobble.duration))
            }
        }
        params["api_sig"] = LastFmSigning.sign(params: params, secret: sharedSecret)

        do {
            let data = try await post(params: params)
            let response = try LastFmJSON.parseScrobbleResponse(from: data)

            // Re-queue scrobbles rejected due to daily limit (code 5) — drop all others
            let results = response.scrobbles.scrobble
            var requeue: [PendingScrobble] = []
            for (i, scrobble) in batch.enumerated() {
                if i < results.count, results[i].ignoredMessage.code == "5" {
                    requeue.append(scrobble)
                }
            }

            pendingScrobbles.removeFirst(batch.count)
            if !requeue.isEmpty {
                pendingScrobbles.insert(contentsOf: requeue, at: 0)
            }
            persistPending()
            logger.info("Flushed \(batch.count) pending scrobbles (accepted: \(response.scrobbles.attr.accepted), ignored: \(response.scrobbles.attr.ignored))")
        } catch {
            logger.warning("Failed to flush pending scrobbles: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private static var pendingFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ficino", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending_scrobbles.json")
    }

    private func persistPending() {
        do {
            if pendingScrobbles.isEmpty {
                try? FileManager.default.removeItem(at: Self.pendingFileURL)
            } else {
                let data = try JSONEncoder().encode(pendingScrobbles)
                try data.write(to: Self.pendingFileURL, options: .atomic)
            }
        } catch {
            logger.warning("Failed to persist pending scrobbles: \(error.localizedDescription)")
        }
    }

    private static func loadPending() -> [PendingScrobble] {
        guard let data = try? Data(contentsOf: pendingFileURL),
              let scrobbles = try? JSONDecoder().decode([PendingScrobble].self, from: data) else {
            return []
        }
        return scrobbles
    }

    // MARK: - Networking

    private func post(params: [String: String]) async throws -> Data {
        guard let url = URL(string: Self.apiBase) else {
            throw LastFmError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params.map { key, value in
            let encodedKey = Self.formEncode(key)
            let encodedValue = Self.formEncode(value)
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LastFmError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LastFmError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw LastFmError.httpError(statusCode: http.statusCode, body: body)
        }

        return data
    }
}
