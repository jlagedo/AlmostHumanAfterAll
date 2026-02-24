import Foundation

public enum LastFmError: LocalizedError, Sendable {
    case notConfigured
    case notAuthenticated
    case authFailed(String)
    case httpError(statusCode: Int, body: String?)
    case networkError(underlying: any Error)
    case apiError(code: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Last.fm API key or shared secret not configured"
        case .notAuthenticated:
            return "Not authenticated with Last.fm"
        case .authFailed(let message):
            return "Last.fm authentication failed: \(message)"
        case .httpError(let statusCode, let body):
            return "Last.fm HTTP \(statusCode)\(body.map { ": \($0.prefix(200))" } ?? "")"
        case .networkError(let underlying):
            return "Last.fm network error: \(underlying.localizedDescription)"
        case .apiError(let code, let message):
            return "Last.fm error \(code): \(message)"
        case .invalidResponse:
            return "Last.fm returned an invalid response"
        }
    }
}
