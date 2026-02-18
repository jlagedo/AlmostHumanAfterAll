import Foundation

actor RateLimiter {
    private let minimumInterval: Duration
    private var lastRequestTime: ContinuousClock.Instant?

    init(requestsPerSecond: Double = 1) {
        self.minimumInterval = .milliseconds(Int(1000.0 / requestsPerSecond))
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
