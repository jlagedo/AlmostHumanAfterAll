import Foundation
import os

private let logger = Logger(subsystem: "com.ficino", category: "TrackGatekeeper")

public struct TrackGatekeeper: Sendable {
    public struct Configuration: Sendable {
        public let isPaused: Bool
        public let skipThreshold: TimeInterval

        public init(isPaused: Bool, skipThreshold: TimeInterval) {
            self.isPaused = isPaused
            self.skipThreshold = skipThreshold
        }
    }

    public enum Decision: Sendable {
        case accept
        case reject(reason: String)
    }

    private var lastTrackID: String?
    private var trackStartTime: Date?

    public init() {}

    public mutating func evaluate(
        trackID: String,
        playerState: String,
        configuration: Configuration
    ) -> Decision {
        guard !configuration.isPaused else {
            logger.debug("Paused, ignoring track change")
            return .reject(reason: "paused")
        }

        guard playerState == "Playing" else {
            logger.debug("State is '\(playerState)', ignoring (only handling Playing)")
            return .reject(reason: "not playing")
        }

        guard trackID != lastTrackID else {
            logger.debug("Same track (id=\(trackID)), ignoring duplicate")
            return .reject(reason: "duplicate")
        }

        // Skip threshold: reject if previous track was played too briefly
        if let startTime = trackStartTime, configuration.skipThreshold > 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < configuration.skipThreshold {
                logger.info("Previous track played \(elapsed, format: .fixed(precision: 1))s (threshold: \(configuration.skipThreshold, format: .fixed(precision: 1))s), skipping commentary")
                trackStartTime = Date()
                lastTrackID = trackID
                return .reject(reason: "skip threshold")
            }
        }
        trackStartTime = Date()
        lastTrackID = trackID

        return .accept
    }
}
