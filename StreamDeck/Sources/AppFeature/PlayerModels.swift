import Database
import Foundation

// MARK: - Playable Item

/// A unified representation of any playable content (channel or VOD item).
public struct PlayableItem: Equatable, Sendable {
    public let contentID: String
    public let playlistID: String?
    public let name: String
    public let streamURL: String
    public let groupName: String?
    public let posterURL: String?

    public init(contentID: String, playlistID: String? = nil, name: String, streamURL: String, groupName: String? = nil, posterURL: String? = nil) {
        self.contentID = contentID
        self.playlistID = playlistID
        self.name = name
        self.streamURL = streamURL
        self.groupName = groupName
        self.posterURL = posterURL
    }

    public init(channel: ChannelRecord) {
        self.contentID = channel.id
        self.playlistID = channel.playlistID
        self.name = channel.name
        self.streamURL = channel.streamURL
        self.groupName = channel.groupName
        self.posterURL = channel.logoURL
    }

    public init(vodItem: VodItemRecord) {
        self.contentID = vodItem.id
        self.playlistID = vodItem.playlistID
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

// MARK: - Preferred Player Engine

public enum PreferredPlayerEngine: String, Equatable, Sendable, CaseIterable {
    case auto
    case avPlayer
    case vlcKit

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .avPlayer: "AVPlayer"
        case .vlcKit: "VLCKit"
        }
    }
}

// MARK: - User Preferences

public struct UserPreferences: Equatable, Sendable {
    public var preferredEngine: PreferredPlayerEngine
    public var resumePlaybackEnabled: Bool
    public var bufferTimeoutSeconds: Int

    public init(
        preferredEngine: PreferredPlayerEngine = .auto,
        resumePlaybackEnabled: Bool = true,
        bufferTimeoutSeconds: Int = 10
    ) {
        self.preferredEngine = preferredEngine
        self.resumePlaybackEnabled = resumePlaybackEnabled
        self.bufferTimeoutSeconds = bufferTimeoutSeconds
    }

    public static func load(from client: UserDefaultsClient) -> UserPreferences {
        let engine = client.stringForKey(UserDefaultsKey.preferredPlayerEngine)
            .flatMap(PreferredPlayerEngine.init(rawValue:)) ?? .auto

        let resumeStr = client.stringForKey(UserDefaultsKey.resumePlaybackEnabled)
        let resumeEnabled = resumeStr.map { $0 == "true" } ?? true

        let timeoutStr = client.stringForKey(UserDefaultsKey.bufferTimeoutSeconds)
        let bufferTimeout = timeoutStr.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } ?? 10

        return UserPreferences(
            preferredEngine: engine,
            resumePlaybackEnabled: resumeEnabled,
            bufferTimeoutSeconds: bufferTimeout
        )
    }

    public func save(to client: UserDefaultsClient) {
        client.setString(preferredEngine.rawValue, UserDefaultsKey.preferredPlayerEngine)
        client.setString(resumePlaybackEnabled ? "true" : "false", UserDefaultsKey.resumePlaybackEnabled)
        client.setString(String(bufferTimeoutSeconds), UserDefaultsKey.bufferTimeoutSeconds)
    }
}
