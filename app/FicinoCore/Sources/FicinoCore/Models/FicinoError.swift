import Foundation

public enum FicinoError: LocalizedError, Sendable {
    case aiUnavailable(String)
    case emptyResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .aiUnavailable(let message):
            return message
        case .emptyResponse:
            return "Apple Intelligence returned an empty response"
        case .cancelled:
            return "Commentary generation was cancelled"
        }
    }
}
