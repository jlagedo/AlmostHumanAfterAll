import Foundation

struct TimeoutError: Error, LocalizedError {
    let duration: Duration
    var errorDescription: String? { "Operation timed out after \(duration)" }
}

func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError(duration: duration)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
