import Database
import Foundation

// MARK: - Playable Item

/// A unified representation of any playable content (channel or VOD item).
public struct PlayableItem: Equatable, Sendable {
    public let name: String
    public let streamURL: String
    public let groupName: String?
    public let posterURL: String?

    public init(name: String, streamURL: String, groupName: String? = nil, posterURL: String? = nil) {
        self.name = name
        self.streamURL = streamURL
        self.groupName = groupName
        self.posterURL = posterURL
    }

    public init(channel: ChannelRecord) {
        self.name = channel.name
        self.streamURL = channel.streamURL
        self.groupName = channel.groupName
        self.posterURL = channel.logoURL
    }

    public init(vodItem: VodItemRecord) {
        self.name = vodItem.title
        self.streamURL = vodItem.streamURL ?? ""
        self.groupName = vodItem.genre
        self.posterURL = vodItem.posterURL
    }
}

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
