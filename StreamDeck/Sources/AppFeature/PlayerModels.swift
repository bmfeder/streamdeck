import Foundation

// MARK: - Player Engine

public enum PlayerEngine: String, Equatable, Sendable {
    case avPlayer
    case vlcKit
}

// MARK: - Stream Route

public struct StreamRoute: Equatable, Sendable {
    public let recommendedEngine: PlayerEngine
    public let url: URL
    public let reason: String

    public init(recommendedEngine: PlayerEngine, url: URL, reason: String) {
        self.recommendedEngine = recommendedEngine
        self.url = url
        self.reason = reason
    }
}

// MARK: - Playback Status

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case routing
    case loading
    case playing
    case paused
    case error(PlayerError)
    case retrying(attempt: Int, engine: PlayerEngine)
    case failed
}

// MARK: - Player Error

public enum PlayerError: Equatable, Sendable {
    case streamUnavailable
    case networkLost
    case decodingFailed
    case unknown(String)
}

// MARK: - Player Command

public enum PlayerCommand: Equatable, Sendable {
    case play(url: URL, engine: PlayerEngine)
    case stop
    case none
}
