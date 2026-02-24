import Foundation

// MARK: - XMLTV Parser

/// Incremental SAX-style parser for XMLTV EPG data.
///
/// Uses Foundation's `XMLParser` internally so the XML DOM is never loaded
/// into memory — safe for 50–200MB EPG files on tvOS.
///
/// The parser is lenient: it skips broken elements and collects errors
/// without crashing. All models are `Sendable`.
public final class XMLTVParser: Sendable {

    public init() {}

    // MARK: - Public API

    /// Parse XMLTV from a string.
    public func parse(content: String) -> XMLTVParseResult {
        guard let data = content.data(using: .utf8) else {
            return XMLTVParseResult(
                channels: [],
                programs: [],
                errors: [XMLTVParseError(element: "document", reason: .emptyDocument, rawText: "")],
                metadata: XMLTVMetadata()
            )
        }
        return parse(data: data)
    }

    /// Parse XMLTV from raw data. XMLParser handles encoding detection.
    public func parse(data: Data) -> XMLTVParseResult {
        guard !data.isEmpty else {
            return XMLTVParseResult(
                channels: [],
                programs: [],
                errors: [],
                metadata: XMLTVMetadata()
            )
        }
        let delegate = XMLTVParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.parse()
        return delegate.buildResult()
    }

    /// Parse XMLTV from a local file URL.
    /// Uses `XMLParser(contentsOf:)` which streams from disk.
    public func parse(fileURL: URL) throws -> XMLTVParseResult {
        guard let xmlParser = XMLParser(contentsOf: fileURL) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let delegate = XMLTVParserDelegate()
        xmlParser.delegate = delegate
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.parse()
        return delegate.buildResult()
    }
}

// MARK: - Internal Delegate

/// XMLParser delegate that implements the SAX-style state machine.
/// Created fresh per parse call — never shared across threads.
private final class XMLTVParserDelegate: NSObject, XMLParserDelegate {

    // Accumulated results
    private var channels: [ParsedEPGChannel] = []
    private var programs: [ParsedProgram] = []
    private var errors: [XMLTVParseError] = []
    private var metadata = XMLTVMetadata()
    private var foundTVElement = false

    // Text accumulator (XMLParser may deliver text in multiple callbacks)
    private var currentText = ""

    // Channel-building state
    private var inChannel = false
    private var channelID: String?
    private var channelDisplayNames: [String] = []
    private var channelIconURL: URL?
    private var channelURLs: [URL] = []

    // Programme-building state
    private var inProgramme = false
    private var programmeChannelID: String?
    private var programmeStart: String?
    private var programmeStop: String?
    private var programmeTitle: String?
    private var programmeDesc: String?
    private var programmeCategories: [String] = []
    private var programmeIconURL: URL?
    private var programmeSubtitle: String?
    private var programmeDate: String?
    private var programmeEpisodeNum: String?
    private var programmeRating: String?
    private var inRating = false

    // Current element name for text routing
    private var currentElement = ""

    func buildResult() -> XMLTVParseResult {
        XMLTVParseResult(
            channels: channels,
            programs: programs,
            errors: errors,
            metadata: metadata
        )
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        currentElement = elementName

        switch elementName {
        case "tv":
            foundTVElement = true
            metadata = XMLTVMetadata(
                generatorName: attributeDict["generator-info-name"],
                generatorURL: attributeDict["generator-info-url"],
                sourceInfoURL: attributeDict["source-info-url"],
                sourceInfoName: attributeDict["source-info-name"]
            )

        case "channel":
            inChannel = true
            channelID = attributeDict["id"]
            channelDisplayNames = []
            channelIconURL = nil
            channelURLs = []

        case "programme":
            inProgramme = true
            programmeChannelID = attributeDict["channel"]
            programmeStart = attributeDict["start"]
            programmeStop = attributeDict["stop"]
            programmeTitle = nil
            programmeDesc = nil
            programmeCategories = []
            programmeIconURL = nil
            programmeSubtitle = nil
            programmeDate = nil
            programmeEpisodeNum = nil
            programmeRating = nil

        case "icon":
            if let src = attributeDict["src"], let url = URL(string: src) {
                if inProgramme {
                    programmeIconURL = url
                } else if inChannel {
                    channelIconURL = url
                }
            }

        case "rating":
            if inProgramme {
                inRating = true
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "channel":
            finalizeChannel()
            inChannel = false

        case "programme":
            finalizeProgramme()
            inProgramme = false
            inRating = false

        case "display-name":
            if inChannel && !text.isEmpty {
                channelDisplayNames.append(text)
            }

        case "url":
            if inChannel, !text.isEmpty, let url = URL(string: text) {
                channelURLs.append(url)
            }

        case "title":
            if inProgramme && programmeTitle == nil && !text.isEmpty {
                programmeTitle = text
            }

        case "desc":
            if inProgramme && !text.isEmpty {
                programmeDesc = text
            }

        case "category":
            if inProgramme && !text.isEmpty {
                programmeCategories.append(text)
            }

        case "sub-title":
            if inProgramme && !text.isEmpty {
                programmeSubtitle = text
            }

        case "date":
            if inProgramme && !text.isEmpty {
                programmeDate = text
            }

        case "episode-num":
            if inProgramme && !text.isEmpty {
                programmeEpisodeNum = text
            }

        case "value":
            if inProgramme && inRating && !text.isEmpty {
                programmeRating = text
            }

        case "rating":
            inRating = false

        default:
            break
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        let nsError = parseError as NSError
        errors.append(XMLTVParseError(
            element: "xml",
            reason: .xmlParserError,
            rawText: "Line \(parser.lineNumber): \(nsError.localizedDescription)"
        ))
    }

    // MARK: - Finalization

    private func finalizeChannel() {
        guard let id = channelID, !id.isEmpty else {
            errors.append(XMLTVParseError(
                element: "channel",
                reason: .missingChannelID,
                rawText: "id=\(channelID ?? "(nil)")"
            ))
            return
        }

        guard !channelDisplayNames.isEmpty else {
            errors.append(XMLTVParseError(
                element: "channel[\(id)]",
                reason: .missingDisplayName,
                rawText: "channel id=\(id)"
            ))
            return
        }

        let channel = ParsedEPGChannel(
            id: id,
            displayName: channelDisplayNames[0],
            displayNames: channelDisplayNames,
            iconURL: channelIconURL,
            urls: channelURLs
        )
        channels.append(channel)
    }

    private func finalizeProgramme() {
        // Validate required attributes
        guard let channelID = programmeChannelID, !channelID.isEmpty else {
            errors.append(XMLTVParseError(
                element: "programme",
                reason: .missingProgrammeChannel,
                rawText: formatProgrammeContext()
            ))
            return
        }

        guard let startStr = programmeStart else {
            errors.append(XMLTVParseError(
                element: "programme[channel=\(channelID)]",
                reason: .missingProgrammeStart,
                rawText: formatProgrammeContext()
            ))
            return
        }

        guard let stopStr = programmeStop else {
            errors.append(XMLTVParseError(
                element: "programme[channel=\(channelID)]",
                reason: .missingProgrammeStop,
                rawText: formatProgrammeContext()
            ))
            return
        }

        // Parse timestamps
        guard let startEpoch = XMLTVTimestamp.parse(startStr) else {
            errors.append(XMLTVParseError(
                element: "programme[channel=\(channelID)]",
                reason: .invalidTimestamp,
                rawText: "start=\(startStr)"
            ))
            return
        }

        guard let stopEpoch = XMLTVTimestamp.parse(stopStr) else {
            errors.append(XMLTVParseError(
                element: "programme[channel=\(channelID)]",
                reason: .invalidTimestamp,
                rawText: "stop=\(stopStr)"
            ))
            return
        }

        // Title is required
        guard let title = programmeTitle else {
            errors.append(XMLTVParseError(
                element: "programme[channel=\(channelID)]",
                reason: .missingTitle,
                rawText: "start=\(startStr)"
            ))
            return
        }

        let program = ParsedProgram(
            channelID: channelID,
            startTimestamp: startEpoch,
            stopTimestamp: stopEpoch,
            title: title,
            description: programmeDesc,
            categories: programmeCategories,
            iconURL: programmeIconURL,
            subtitle: programmeSubtitle,
            date: programmeDate,
            episodeNum: programmeEpisodeNum,
            rating: programmeRating
        )
        programs.append(program)
    }

    private func formatProgrammeContext() -> String {
        var parts: [String] = []
        if let ch = programmeChannelID { parts.append("channel=\(ch)") }
        if let s = programmeStart { parts.append("start=\(s)") }
        if let t = programmeTitle { parts.append("title=\(t)") }
        return parts.joined(separator: " ")
    }
}
