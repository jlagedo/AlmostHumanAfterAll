import Foundation

actor RateLimiter {
    private let minimumInterval: Duration
    private var lastRequestTime: ContinuousClock.Instant?

    init(requestsPerSecond: Int = 1) {
        self.minimumInterval = .seconds(1) / requestsPerSecond
    }

    func wait() async throws {
        if let last = lastRequestTime {
            let elapsed = ContinuousClock.now - last
            if elapsed < minimumInterval {
                try await Task.sleep(for: minimumInterval - elapsed)
            }
        }
        lastRequestTime = .now
    }
}
