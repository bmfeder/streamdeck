import Foundation

// MARK: - Parsed Channel Model

/// Represents a single channel/stream entry parsed from an M3U playlist.
/// Maps directly to the Channel table in the data model spec.
public struct ParsedChannel: Equatable, Sendable {
    public let name: String
    public let streamURL: URL
    public let groupTitle: String?
    public let tvgId: String?
    public let tvgName: String?
    public let tvgLogo: URL?
    public let tvgLanguage: String?
    public let channelNumber: Int?
    public let duration: Int // -1 for live streams
    public let extras: [String: String] // any unrecognized attributes

    public init(
        name: String,
        streamURL: URL,
        groupTitle: String? = nil,
        tvgId: String? = nil,
        tvgName: String? = nil,
        tvgLogo: URL? = nil,
        tvgLanguage: String? = nil,
        channelNumber: Int? = nil,
        duration: Int = -1,
        extras: [String: String] = [:]
    ) {
        self.name = name
        self.streamURL = streamURL
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.tvgName = tvgName
        self.tvgLogo = tvgLogo
        self.tvgLanguage = tvgLanguage
        self.channelNumber = channelNumber
        self.duration = duration
        self.extras = extras
    }
}

// MARK: - Parse Result

/// The complete result of parsing an M3U playlist, including
/// successfully parsed channels and any errors encountered.
public struct M3UParseResult: Sendable {
    public let channels: [ParsedChannel]
    public let errors: [M3UParseError]
    public let metadata: PlaylistMetadata

    public var successCount: Int { channels.count }
    public var errorCount: Int { errors.count }
    public var totalEntries: Int { successCount + errorCount }

    public init(
        channels: [ParsedChannel],
        errors: [M3UParseError],
        metadata: PlaylistMetadata
    ) {
        self.channels = channels
        self.errors = errors
        self.metadata = metadata
    }
}

// MARK: - Playlist Metadata

/// Top-level metadata extracted from the #EXTM3U header.
public struct PlaylistMetadata: Sendable {
    public let urlTvg: String?      // x-tvg-url (EPG source)
    public let tvgShift: String?    // tvg-shift
    public let catchupSource: String?
    public let hasExtM3UHeader: Bool

    public init(
        urlTvg: String? = nil,
        tvgShift: String? = nil,
        catchupSource: String? = nil,
        hasExtM3UHeader: Bool = false
    ) {
        self.urlTvg = urlTvg
        self.tvgShift = tvgShift
        self.catchupSource = catchupSource
        self.hasExtM3UHeader = hasExtM3UHeader
    }
}

// MARK: - Parse Error

/// A non-fatal error encountered while parsing a specific entry.
/// The parser is lenient: it skips broken entries and keeps going.
public struct M3UParseError: Sendable {
    public let line: Int
    public let reason: Reason
    public let rawText: String

    public enum Reason: String, Sendable {
        case missingStreamURL = "Missing or invalid stream URL after #EXTINF"
        case malformedExtinf = "Malformed #EXTINF line"
        case invalidURL = "Stream URL is not a valid URL"
        case emptyName = "Channel name is empty"
        case orphanedURL = "Stream URL without preceding #EXTINF"
    }

    public init(line: Int, reason: Reason, rawText: String) {
        self.line = line
        self.reason = reason
        self.rawText = String(rawText.prefix(200)) // truncate for safety
    }
}
