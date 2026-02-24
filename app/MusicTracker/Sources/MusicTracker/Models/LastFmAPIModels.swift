import Foundation

// MARK: - Auth

struct LastFmTokenResponse: Codable, Sendable {
    let token: String
}

struct LastFmSessionResponse: Codable, Sendable {
    let session: Session

    struct Session: Codable, Sendable {
        let name: String
        let key: String
    }
}

// MARK: - Scrobble

struct LastFmScrobbleResponse: Codable, Sendable {
    let scrobbles: Scrobbles

    struct Scrobbles: Sendable {
        let attr: Attr
        let scrobble: [ScrobbleResult]
    }

    struct ScrobbleResult: Codable, Sendable {
        let ignoredMessage: IgnoredMessage

        struct IgnoredMessage: Codable, Sendable {
            let code: String
        }
    }

    struct Attr: Codable, Sendable {
        let accepted: Int
        let ignored: Int
    }
}

extension LastFmScrobbleResponse.Scrobbles: Codable {
    enum CodingKeys: String, CodingKey {
        case attr = "@attr"
        case scrobble
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attr = try container.decode(LastFmScrobbleResponse.Attr.self, forKey: .attr)
        // Last.fm returns a single object for 1 scrobble, array for multiple
        if let array = try? container.decode([LastFmScrobbleResponse.ScrobbleResult].self, forKey: .scrobble) {
            scrobble = array
        } else if let single = try? container.decode(LastFmScrobbleResponse.ScrobbleResult.self, forKey: .scrobble) {
            scrobble = [single]
        } else {
            scrobble = []
        }
    }
}

// MARK: - Loved Tracks

struct LastFmLovedTracksResponse: Codable, Sendable {
    let lovedtracks: LovedTracks

    struct LovedTracks: Sendable {
        let track: [LovedTrack]
    }

    struct LovedTrack: Codable, Sendable {
        let name: String
        let artist: Artist

        struct Artist: Codable, Sendable {
            let name: String
        }
    }
}

extension LastFmLovedTracksResponse.LovedTracks: Codable {
    enum CodingKeys: String, CodingKey {
        case track
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let array = try? container.decode([LastFmLovedTracksResponse.LovedTrack].self, forKey: .track) {
            track = array
        } else if let single = try? container.decode(LastFmLovedTracksResponse.LovedTrack.self, forKey: .track) {
            track = [single]
        } else {
            track = []
        }
    }
}

// MARK: - Error

struct LastFmErrorResponse: Codable, Sendable {
    let error: Int
    let message: String
}

// MARK: - JSON Parsing

enum LastFmJSON {
    private static let decoder = JSONDecoder()

    /// Check for an explicit `"error"` key in the JSON — Last.fm error responses
    /// always have `{"error": <int>, "message": <string>}` at the top level.
    private static func checkError(from data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["error"] as? Int,
              let message = json["message"] as? String else { return }
        throw LastFmError.apiError(code: code, message: message)
    }

    static func parseToken(from data: Data) throws -> LastFmTokenResponse {
        try checkError(from: data)
        return try decoder.decode(LastFmTokenResponse.self, from: data)
    }

    static func parseSession(from data: Data) throws -> LastFmSessionResponse {
        try checkError(from: data)
        return try decoder.decode(LastFmSessionResponse.self, from: data)
    }

    static func parseScrobbleResponse(from data: Data) throws -> LastFmScrobbleResponse {
        try checkError(from: data)
        return try decoder.decode(LastFmScrobbleResponse.self, from: data)
    }

    static func parseNowPlayingResponse(from data: Data) throws {
        try checkError(from: data)
    }

    static func parseLovedTracks(from data: Data) throws -> LastFmLovedTracksResponse {
        try checkError(from: data)
        return try decoder.decode(LastFmLovedTracksResponse.self, from: data)
    }
}
