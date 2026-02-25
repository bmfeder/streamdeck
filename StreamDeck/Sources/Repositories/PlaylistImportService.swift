import Foundation
import Database
import EmbyClient
import M3UParser
import XtreamClient

/// Orchestrates the full playlist import pipeline: download → parse → convert → persist.
/// Handles both M3U and Xtream Codes imports.
public struct PlaylistImportService: Sendable {

    private let playlistRepo: PlaylistRepository
    private let channelRepo: ChannelRepository
    private let vodRepo: VodRepository?
    private let httpClient: HTTPClient
    private let uuidGenerator: @Sendable () -> String

    public init(
        playlistRepo: PlaylistRepository,
        channelRepo: ChannelRepository,
        vodRepo: VodRepository? = nil,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        uuidGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.playlistRepo = playlistRepo
        self.channelRepo = channelRepo
        self.vodRepo = vodRepo
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

        // Split live channels from VOD items by duration
        let liveEntries = parseResult.channels.filter { $0.duration <= 0 }
        let vodEntries = parseResult.channels.filter { $0.duration > 0 }

        // Convert and import live channels
        let channels = liveEntries.map { parsed in
            ChannelConverter.fromParsedChannel(parsed, playlistID: playlistID, id: uuidGenerator())
        }
        let importResult = try channelRepo.importChannels(playlistID: playlistID, channels: channels, now: now)

        // Convert and import VOD items
        var vodImportResult: VodImportResult?
        if !vodEntries.isEmpty, let vodRepo {
            let vodItems = vodEntries.map { parsed in
                VodConverter.fromParsedChannel(parsed, playlistID: playlistID, id: uuidGenerator())
            }
            vodImportResult = try vodRepo.importVodItems(playlistID: playlistID, items: vodItems)
        }

        // Collect parse error summaries (truncated for user display)
        let parseErrors = parseResult.errors.prefix(10).map { error in
            "Line \(error.line): \(error.reason.rawValue)"
        }

        return PlaylistImportResult(
            playlist: playlist,
            importResult: importResult,
            vodImportResult: vodImportResult,
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

        // Fetch and import VOD content (non-fatal if it fails)
        var vodImportResult: VodImportResult?
        if let vodRepo {
            do {
                var vodItems: [VodItemRecord] = []

                // Fetch VOD movies
                let vodCategories = try await client.getVODCategories()
                var vodCategoryMap: [String: String] = [:]
                for cat in vodCategories {
                    vodCategoryMap[cat.categoryId.value] = cat.categoryName
                }
                let vodStreams = try await client.getVODStreams()
                for stream in vodStreams {
                    let catName = vodCategoryMap[stream.categoryId.value]
                    let ext = stream.containerExtension ?? "mp4"
                    let url = client.vodStreamURL(
                        streamId: stream.streamId.value,
                        containerExtension: ext
                    ).absoluteString
                    vodItems.append(VodConverter.fromXtreamVODStream(
                        stream, playlistID: playlistID, categoryName: catName,
                        streamURL: url, id: uuidGenerator()
                    ))
                }

                // Fetch series (parent records only — episodes fetched on demand)
                let seriesCategories = try await client.getSeriesCategories()
                var seriesCategoryMap: [String: String] = [:]
                for cat in seriesCategories {
                    seriesCategoryMap[cat.categoryId.value] = cat.categoryName
                }
                let seriesList = try await client.getSeries()
                for series in seriesList {
                    let catName = seriesCategoryMap[series.categoryId.value]
                    vodItems.append(VodConverter.fromXtreamSeries(
                        series, playlistID: playlistID, categoryName: catName,
                        id: uuidGenerator()
                    ))
                }

                if !vodItems.isEmpty {
                    vodImportResult = try vodRepo.importVodItems(playlistID: playlistID, items: vodItems)
                }
            } catch {
                // VOD import failures should not block the overall import
            }
        }

        return PlaylistImportResult(
            playlist: playlist,
            importResult: importResult,
            vodImportResult: vodImportResult
        )
    }

    // MARK: - Emby Import

    /// Authenticates with Emby server, fetches libraries and items,
    /// stores access token in Keychain, and persists to database.
    public func importEmby(
        serverURL: URL,
        username: String,
        password: String,
        name: String
    ) async throws -> PlaylistImportResult {
        let credentials = EmbyCredentials(serverURL: serverURL, username: username, password: password)
        let client = EmbyClient(credentials: credentials, httpClient: httpClient)

        // Authenticate
        let authResponse: EmbyAuthResponse
        do {
            authResponse = try await client.authenticate()
        } catch let error as EmbyError {
            switch error {
            case .authenticationFailed:
                throw PlaylistImportError.authenticationFailed
            default:
                throw PlaylistImportError.networkError(String(describing: error))
            }
        } catch {
            throw PlaylistImportError.authenticationFailed
        }

        let userId = authResponse.user.id
        let accessToken = authResponse.accessToken

        // Store credentials as JSON in Keychain (token for API calls, password for re-auth)
        let playlistID = uuidGenerator()
        let keychainKey = "emby-\(playlistID)"
        let credentialJSON: [String: String] = [
            "userId": userId,
            "accessToken": accessToken,
            "password": password,
        ]
        if let jsonData = try? JSONEncoder().encode(credentialJSON),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            KeychainHelper.save(key: keychainKey, value: jsonString)
        }

        // Create playlist record
        let now = Int(Date().timeIntervalSince1970)
        let playlist = PlaylistRecord(
            id: playlistID,
            name: name,
            type: "emby",
            url: serverURL.absoluteString,
            username: username,
            passwordRef: keychainKey,
            lastSync: now,
            sortOrder: 0
        )
        try playlistRepo.create(playlist)

        // Fetch libraries
        let libraries: [EmbyLibrary]
        do {
            libraries = try await client.getLibraries(userId: userId, accessToken: accessToken)
        } catch {
            throw PlaylistImportError.networkError(error.localizedDescription)
        }

        // Fetch VOD items from movie and tvshows libraries
        var vodItems: [VodItemRecord] = []
        for library in libraries {
            guard let collectionType = library.collectionType,
                  collectionType == "movies" || collectionType == "tvshows" else { continue }

            let itemType = collectionType == "movies" ? "Movie" : "Series"
            var startIndex = 0

            while true {
                let response = try await client.getItems(
                    userId: userId, accessToken: accessToken,
                    parentId: library.id, includeItemTypes: itemType,
                    startIndex: startIndex, limit: 100
                )

                for item in response.items {
                    if collectionType == "movies" {
                        vodItems.append(EmbyConverter.fromEmbyMovie(
                            item, playlistID: playlistID,
                            serverURL: serverURL, accessToken: accessToken
                        ))
                    } else {
                        let seriesRecord = EmbyConverter.fromEmbySeries(
                            item, playlistID: playlistID, serverURL: serverURL
                        )
                        vodItems.append(seriesRecord)

                        // Fetch episodes for this series
                        let episodesResponse = try await client.getItems(
                            userId: userId, accessToken: accessToken,
                            parentId: library.id, includeItemTypes: "Episode",
                            startIndex: 0, limit: 1000
                        )
                        let seriesEpisodes = episodesResponse.items.filter { $0.seriesId == item.id }
                        for ep in seriesEpisodes {
                            vodItems.append(EmbyConverter.fromEmbyEpisode(
                                ep, playlistID: playlistID, seriesID: seriesRecord.id,
                                serverURL: serverURL, accessToken: accessToken
                            ))
                        }
                    }
                }

                startIndex += response.items.count
                if startIndex >= response.totalRecordCount { break }
            }
        }

        // Import VOD items to DB
        var vodImportResult: VodImportResult?
        if !vodItems.isEmpty, let vodRepo {
            vodImportResult = try vodRepo.importVodItems(playlistID: playlistID, items: vodItems)
        }

        return PlaylistImportResult(
            playlist: playlist,
            importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 0),
            vodImportResult: vodImportResult
        )
    }
}
