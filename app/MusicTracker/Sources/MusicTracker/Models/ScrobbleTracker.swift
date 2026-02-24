import Foundation
import os

private let logger = Logger(subsystem: "com.ficino", category: "ScrobbleTracker")

public struct ScrobbleTracker: Sendable {
    public struct PlayingTrack: Sendable {
        public let artist: String
        public let track: String
        public let album: String
        public let duration: TimeInterval // seconds
        public let startedAt: Date

        var accumulatedPlayTime: TimeInterval = 0
        var lastResumedAt: Date

        public init(artist: String, track: String, album: String,
                    duration: TimeInterval, startedAt: Date) {
            self.artist = artist
            self.track = track
            self.album = album
            self.duration = duration
            self.startedAt = startedAt
            self.lastResumedAt = startedAt
        }

        func playTime(isPlaying: Bool) -> TimeInterval {
            if isPlaying {
                return accumulatedPlayTime + Date().timeIntervalSince(lastResumedAt)
            } else {
                return accumulatedPlayTime
            }
        }
    }

    public struct ScrobbleCandidate: Sendable {
        public let artist: String
        public let track: String
        public let album: String
        public let duration: TimeInterval
        public let timestamp: Date
    }

    private var current: PlayingTrack?
    private var isPlaying: Bool = false
    private var scrobbled: Bool = false

    public init() {}

    /// Call when a new track starts playing. Resets scrobble state for the new track.
    public mutating func trackStarted(_ track: PlayingTrack) {
        current = track
        isPlaying = true
        scrobbled = false
    }

    /// Call when playback is paused.
    public mutating func pause() {
        guard isPlaying, var track = current else { return }
        track.accumulatedPlayTime += Date().timeIntervalSince(track.lastResumedAt)
        current = track
        isPlaying = false
    }

    /// Call when playback is resumed.
    public mutating func resume() {
        guard !isPlaying, var track = current else { return }
        track.lastResumedAt = Date()
        current = track
        isPlaying = true
    }

    /// Whether the current track has already been scrobbled.
    public var isScrobbled: Bool { scrobbled }

    /// Mark the current track as scrobbled (called after successful submission).
    public mutating func markScrobbled() {
        scrobbled = true
    }

    /// Seconds of play time remaining until the scrobble threshold.
    /// Returns `nil` if track is too short, already scrobbled, or already eligible.
    public func timeUntilScrobblePoint() -> TimeInterval? {
        guard let track = current, !scrobbled else { return nil }
        guard track.duration > 30 else {
            logger.debug("Timer: \"\(track.track)\" too short to scrobble (\(Int(track.duration))s)")
            return nil
        }

        let elapsed = track.playTime(isPlaying: isPlaying)
        let threshold = min(track.duration * 0.5, 240)
        let remaining = threshold - elapsed
        guard remaining > 0 else { return 0 }

        logger.debug("Timer: \"\(track.track)\" scrobble in \(Int(remaining))s (elapsed: \(Int(elapsed))s, threshold: \(Int(threshold))s)")
        return remaining
    }

    /// Build a scrobble candidate from the current track. Returns nil if no track
    /// or track is too short. Does NOT check play time — caller is responsible for
    /// timing (via `timeUntilScrobblePoint`).
    public func candidate() -> ScrobbleCandidate? {
        guard let track = current, track.duration > 30 else { return nil }
        return ScrobbleCandidate(
            artist: track.artist,
            track: track.track,
            album: track.album,
            duration: track.duration,
            timestamp: track.startedAt
        )
    }

    /// Clear the current track (e.g., when scrobbling is disabled).
    public mutating func reset() {
        current = nil
        isPlaying = false
        scrobbled = false
    }
}
