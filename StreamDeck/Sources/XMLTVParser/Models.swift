import Foundation

// MARK: - Parsed EPG Channel

/// A channel definition from an XMLTV `<channel>` element.
/// The `id` maps to the `channel_epg_id` field in the database for EPG matching.
public struct ParsedEPGChannel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let displayNames: [String]
    public let iconURL: URL?
    public let urls: [URL]

    public init(
        id: String,
        displayName: String,
        displayNames: [String] = [],
        iconURL: URL? = nil,
        urls: [URL] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.displayNames = displayNames.isEmpty ? [displayName] : displayNames
        self.iconURL = iconURL
        self.urls = urls
    }
}

// MARK: - Parsed Program

/// A single programme from an XMLTV `<programme>` element.
/// Maps to the EpgProgram table in the database.
public struct ParsedProgram: Equatable, Sendable {
    public let channelID: String
    public let startTimestamp: Int
    public let stopTimestamp: Int
    public let title: String
    public let description: String?
    public let category: String?
    public let categories: [String]
    public let iconURL: URL?
    public let subtitle: String?
    public let date: String?
    public let episodeNum: String?
    public let rating: String?
    public let extras: [String: String]

    public init(
        channelID: String,
        startTimestamp: Int,
        stopTimestamp: Int,
        title: String,
        description: String? = nil,
        category: String? = nil,
        categories: [String] = [],
        iconURL: URL? = nil,
        subtitle: String? = nil,
        date: String? = nil,
        episodeNum: String? = nil,
        rating: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.channelID = channelID
        self.startTimestamp = startTimestamp
        self.stopTimestamp = stopTimestamp
        self.title = title
        self.description = description
        self.category = category ?? categories.first
        self.categories = categories
        self.iconURL = iconURL
        self.subtitle = subtitle
        self.date = date
        self.episodeNum = episodeNum
        self.rating = rating
        self.extras = extras
    }
}

// MARK: - Parse Result

/// The complete result of parsing an XMLTV file.
public struct XMLTVParseResult: Sendable {
    public let channels: [ParsedEPGChannel]
    public let programs: [ParsedProgram]
    public let errors: [XMLTVParseError]
    public let metadata: XMLTVMetadata

    public var channelCount: Int { channels.count }
    public var programCount: Int { programs.count }
    public var errorCount: Int { errors.count }

    public init(
        channels: [ParsedEPGChannel],
        programs: [ParsedProgram],
        errors: [XMLTVParseError],
        metadata: XMLTVMetadata
    ) {
        self.channels = channels
        self.programs = programs
        self.errors = errors
        self.metadata = metadata
    }
}

// MARK: - Metadata

/// Metadata from the root `<tv>` element.
public struct XMLTVMetadata: Equatable, Sendable {
    public let generatorName: String?
    public let generatorURL: String?
    public let sourceInfoURL: String?
    public let sourceInfoName: String?

    public init(
        generatorName: String? = nil,
        generatorURL: String? = nil,
        sourceInfoURL: String? = nil,
        sourceInfoName: String? = nil
    ) {
        self.generatorName = generatorName
        self.generatorURL = generatorURL
        self.sourceInfoURL = sourceInfoURL
        self.sourceInfoName = sourceInfoName
    }
}

// MARK: - Parse Error

/// A non-fatal error encountered while parsing XMLTV data.
/// The parser is lenient: it skips broken elements and keeps going.
public struct XMLTVParseError: Sendable {
    public let element: String
    public let reason: Reason
    public let rawText: String

    public enum Reason: String, Sendable {
        case missingChannelID = "Channel element missing required 'id' attribute"
        case missingDisplayName = "Channel element missing <display-name>"
        case missingProgrammeChannel = "Programme element missing 'channel' attribute"
        case missingProgrammeStart = "Programme element missing 'start' attribute"
        case missingProgrammeStop = "Programme element missing 'stop' attribute"
        case invalidTimestamp = "Could not parse XMLTV timestamp"
        case missingTitle = "Programme element missing <title>"
        case xmlParserError = "XMLParser reported an error"
        case emptyDocument = "Document contains no <tv> root element"
    }

    public init(element: String, reason: Reason, rawText: String) {
        self.element = element
        self.reason = reason
        self.rawText = String(rawText.prefix(200))
    }
}
