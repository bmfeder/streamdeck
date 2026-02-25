import Foundation
import Database
import M3UParser
import XtreamClient

/// Orchestrates the full playlist import pipeline: download → parse → convert → persist.
/// Handles both M3U and Xtream Codes imports.
public struct PlaylistImportService: Sendable {

    private let playlistRepo: PlaylistRepository
    private let channelRepo: ChannelRepository
    private let httpClient: HTTPClient
    private let uuidGenerator: @Sendable () -> String

    public init(
        playlistRepo: PlaylistRepository,
        channelRepo: ChannelRepository,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        uuidGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.playlistRepo = playlistRepo
        self.channelRepo = channelRepo
        self.httpClient = httpClient
        self.uuidGenerator = uuidGenerator
    }

    // MARK: - M3U Import

    /// Downloads M3U from URL, parses, converts channels, and persists to database.
    public func importM3U(
        url: URL,
        name: String,
        epgURL: URL? = nil
    ) async throws -> PlaylistImportResult {
        // Download
        let request = URLRequest(url: url)
        let data: Data
        do {
            let (responseData, response) = try await httpClient.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                throw PlaylistImportError.downloadFailed("HTTP \(response.statusCode)")
            }
            data = responseData
        } catch let error as PlaylistImportError {
            throw error
        } catch {
            throw PlaylistImportError.networkError(error.localizedDescription)
        }

        return try importM3UData(data, name: name, sourceURL: url.absoluteString, epgURL: epgURL)
    }

    /// Imports from pre-loaded M3U data (for testing or local file import).
    public func importM3UData(
        _ data: Data,
        name: String,
        sourceURL: String,
        epgURL: URL? = nil
    ) throws -> PlaylistImportResult {
        // Parse
        let parser = M3UParser()
        let parseResult = parser.parse(data: data)

        guard !parseResult.channels.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        // Auto-detect EPG URL from playlist metadata if not provided
        let resolvedEpgURL: String? = epgURL?.absoluteString ?? parseResult.metadata.urlTvg

        // Create playlist record
        let playlistID = uuidGenerator()
        let now = Int(Date().timeIntervalSince1970)
        let playlist = PlaylistRecord(
            id: playlistID,
            name: name,
            type: "m3u",
            url: sourceURL,
            epgURL: resolvedEpgURL,
            lastSync: now,
            sortOrder: 0
        )
        try playlistRepo.create(playlist)

        // Convert and import channels
        let channels = parseResult.channels.map { parsed in
            ChannelConverter.fromParsedChannel(parsed, playlistID: playlistID, id: uuidGenerator())
        }
        let importResult = try channelRepo.importChannels(playlistID: playlistID, channels: channels, now: now)

        // Collect parse error summaries (truncated for user display)
        let parseErrors = parseResult.errors.prefix(10).map { error in
            "Line \(error.line): \(error.reason.rawValue)"
        }

        return PlaylistImportResult(
            playlist: playlist,
            importResult: importResult,
            parseErrors: Array(parseErrors)
        )
    }

    // MARK: - Xtream Import

    /// Authenticates with Xtream server, fetches categories + live streams,
    /// stores password in Keychain, and persists to database.
    public func importXtream(
        serverURL: URL,
        username: String,
        password: String,
        name: String
    ) async throws -> PlaylistImportResult {
        let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)
        let client = XtreamClient(credentials: credentials, httpClient: httpClient)

        // Authenticate
        do {
            _ = try await client.authenticate()
        } catch let error as XtreamError {
            switch error {
            case .accountExpired:
                throw PlaylistImportError.accountExpired
            case .authenticationFailed:
                throw PlaylistImportError.authenticationFailed
            default:
                throw PlaylistImportError.networkError(String(describing: error))
            }
        } catch {
            throw PlaylistImportError.authenticationFailed
        }

        // Fetch categories and streams
        let categories: [XtreamCategory]
        let streams: [XtreamLiveStream]
        do {
            categories = try await client.getLiveCategories()
            streams = try await client.getLiveStreams()
        } catch {
            throw PlaylistImportError.networkError(error.localizedDescription)
        }

        guard !streams.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        // Build category lookup
        var categoryMap: [String: String] = [:]
        for category in categories {
            categoryMap[category.categoryId.value] = category.categoryName
        }

        // Store password in Keychain
        let playlistID = uuidGenerator()
        let keychainKey = "xtream-\(playlistID)"
        KeychainHelper.save(key: keychainKey, value: password)

        // Create playlist record
        let now = Int(Date().timeIntervalSince1970)
        let playlist = PlaylistRecord(
            id: playlistID,
            name: name,
            type: "xtream",
            url: serverURL.absoluteString,
            username: username,
            passwordRef: keychainKey,
            lastSync: now,
            sortOrder: 0
        )
        try playlistRepo.create(playlist)

        // Convert and import channels
        let channels = streams.map { stream in
            let categoryName = categoryMap[stream.categoryId.value]
            let streamURL = client.liveStreamURL(streamId: stream.streamId.value).absoluteString
            return ChannelConverter.fromXtreamLiveStream(
                stream,
                playlistID: playlistID,
                categoryName: categoryName,
                streamURL: streamURL,
                id: uuidGenerator()
            )
        }
        let importResult = try channelRepo.importChannels(playlistID: playlistID, channels: channels, now: now)

        return PlaylistImportResult(
            playlist: playlist,
            importResult: importResult
        )
    }
}
