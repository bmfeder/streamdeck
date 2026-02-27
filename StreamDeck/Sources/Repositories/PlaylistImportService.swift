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

    // MARK: - Create Record

    /// Creates a playlist record and stores credentials without importing content.
    /// The record is ready for `refreshPlaylist(id:)` to perform the actual import.
    public func createPlaylistRecord(params: PlaylistImportParams) throws -> PlaylistRecord {
        let playlistID = uuidGenerator()
        let record: PlaylistRecord

        switch params {
        case let .m3u(url, name, epgURL):
            record = PlaylistRecord(
                id: playlistID,
                name: name,
                type: "m3u",
                url: url.absoluteString,
                epgURL: epgURL?.absoluteString,
                lastSync: nil,
                sortOrder: 0
            )

        case let .xtream(serverURL, username, password, name):
            let keychainKey = "xtream-\(playlistID)"
            KeychainHelper.save(key: keychainKey, value: password)
            record = PlaylistRecord(
                id: playlistID,
                name: name,
                type: "xtream",
                url: serverURL.absoluteString,
                username: username,
                passwordRef: keychainKey,
                lastSync: nil,
                sortOrder: 0
            )

        case let .emby(serverURL, username, password, name):
            let keychainKey = "emby-\(playlistID)"
            let credJSON = try JSONEncoder().encode(["password": password])
            KeychainHelper.save(key: keychainKey, value: String(data: credJSON, encoding: .utf8)!)
            record = PlaylistRecord(
                id: playlistID,
                name: name,
                type: "emby",
                url: serverURL.absoluteString,
                username: username,
                passwordRef: keychainKey,
                lastSync: nil,
                sortOrder: 0
            )
        }

        try playlistRepo.create(record)
        return record
    }

    // MARK: - Refresh

    /// Re-imports content for an existing playlist, preserving favorites and watch progress.
    /// Detects playlist type and routes to the appropriate import pipeline.
    public func refreshPlaylist(id: String) async throws -> PlaylistImportResult {
        guard let playlist = try playlistRepo.get(id: id) else {
            throw PlaylistImportError.playlistNotFound
        }

        let result: PlaylistImportResult
        switch playlist.type {
        case "m3u":
            result = try await refreshM3U(playlist: playlist)
        case "xtream":
            result = try await refreshXtream(playlist: playlist)
        case "emby":
            result = try await refreshEmby(playlist: playlist)
        default:
            throw PlaylistImportError.playlistNotFound
        }

        // Purge channels soft-deleted more than 30 days ago
        let thirtyDaysAgo = Int(Date().timeIntervalSince1970) - (30 * 24 * 60 * 60)
        try? channelRepo.purgeDeleted(olderThan: thirtyDaysAgo)

        return result
    }

    private func refreshM3U(playlist: PlaylistRecord) async throws -> PlaylistImportResult {
        guard let url = URL(string: playlist.url) else {
            throw PlaylistImportError.downloadFailed("Invalid URL")
        }

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

        // Parse
        let parser = M3UParser()
        let parseResult = parser.parse(data: data)
        guard !parseResult.channels.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        let now = Int(Date().timeIntervalSince1970)
        let liveEntries = parseResult.channels.filter { $0.duration <= 0 }
        let vodEntries = parseResult.channels.filter { $0.duration > 0 }

        // Import live channels
        let channels = liveEntries.map { parsed in
            ChannelConverter.fromParsedChannel(parsed, playlistID: playlist.id, id: uuidGenerator())
        }
        let importResult = try channelRepo.importChannels(playlistID: playlist.id, channels: channels, now: now)

        // Import VOD items
        var vodImportResult: VodImportResult?
        if !vodEntries.isEmpty, let vodRepo {
            let vodItems = vodEntries.map { parsed in
                VodConverter.fromParsedChannel(parsed, playlistID: playlist.id, id: uuidGenerator())
            }
            vodImportResult = try vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
        }

        // Update sync timestamp
        try playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)

        let parseErrors = parseResult.errors.prefix(10).map { "Line \($0.line): \($0.reason.rawValue)" }

        var updatedPlaylist = playlist
        updatedPlaylist.lastSync = now
        return PlaylistImportResult(
            playlist: updatedPlaylist,
            importResult: importResult,
            vodImportResult: vodImportResult,
            parseErrors: Array(parseErrors)
        )
    }

    private func refreshXtream(playlist: PlaylistRecord) async throws -> PlaylistImportResult {
        guard let serverURL = URL(string: playlist.url),
              let username = playlist.username,
              let passwordRef = playlist.passwordRef,
              let password = KeychainHelper.load(key: passwordRef)
        else {
            throw PlaylistImportError.authenticationFailed
        }

        let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)
        let client = XtreamClient(credentials: credentials, httpClient: httpClient)

        // Authenticate
        do {
            _ = try await client.authenticate()
        } catch let error as XtreamError {
            switch error {
            case .accountExpired: throw PlaylistImportError.accountExpired
            case .authenticationFailed: throw PlaylistImportError.authenticationFailed
            default: throw PlaylistImportError.networkError(String(describing: error))
            }
        } catch {
            throw PlaylistImportError.authenticationFailed
        }

        // Fetch categories and streams
        let categories = try await client.getLiveCategories()
        let streams = try await client.getLiveStreams()
        guard !streams.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        var categoryMap: [String: String] = [:]
        for category in categories {
            categoryMap[category.categoryId.value] = category.categoryName
        }

        let now = Int(Date().timeIntervalSince1970)
        let channels = streams.map { stream in
            let categoryName = categoryMap[stream.categoryId.value]
            let streamURL = client.liveStreamURL(streamId: stream.streamId.value).absoluteString
            return ChannelConverter.fromXtreamLiveStream(
                stream, playlistID: playlist.id, categoryName: categoryName,
                streamURL: streamURL, id: uuidGenerator()
            )
        }
        let importResult = try channelRepo.importChannels(playlistID: playlist.id, channels: channels, now: now)

        // Fetch and import VOD content (non-fatal)
        var vodImportResult: VodImportResult?
        if let vodRepo {
            do {
                var vodItems: [VodItemRecord] = []
                let vodCategories = try await client.getVODCategories()
                var vodCategoryMap: [String: String] = [:]
                for cat in vodCategories { vodCategoryMap[cat.categoryId.value] = cat.categoryName }
                let vodStreams = try await client.getVODStreams()
                for stream in vodStreams {
                    let catName = vodCategoryMap[stream.categoryId.value]
                    let ext = stream.containerExtension ?? "mp4"
                    let url = client.vodStreamURL(streamId: stream.streamId.value, containerExtension: ext).absoluteString
                    vodItems.append(VodConverter.fromXtreamVODStream(
                        stream, playlistID: playlist.id, categoryName: catName, streamURL: url, id: uuidGenerator()
                    ))
                }
                let seriesCategories = try await client.getSeriesCategories()
                var seriesCategoryMap: [String: String] = [:]
                for cat in seriesCategories { seriesCategoryMap[cat.categoryId.value] = cat.categoryName }
                let seriesList = try await client.getSeries()
                for series in seriesList {
                    let catName = seriesCategoryMap[series.categoryId.value]
                    vodItems.append(VodConverter.fromXtreamSeries(
                        series, playlistID: playlist.id, categoryName: catName, id: uuidGenerator()
                    ))
                }
                if !vodItems.isEmpty {
                    vodImportResult = try vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
                }
            } catch {
                // VOD import failures should not block the overall refresh
            }
        }

        try playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)

        var updatedPlaylist = playlist
        updatedPlaylist.lastSync = now
        return PlaylistImportResult(playlist: updatedPlaylist, importResult: importResult, vodImportResult: vodImportResult)
    }

    private func refreshEmby(playlist: PlaylistRecord) async throws -> PlaylistImportResult {
        guard let serverURL = URL(string: playlist.url),
              let username = playlist.username,
              let passwordRef = playlist.passwordRef,
              let credentialJSON = KeychainHelper.load(key: passwordRef),
              let jsonData = credentialJSON.data(using: .utf8),
              let creds = try? JSONDecoder().decode([String: String].self, from: jsonData),
              let password = creds["password"]
        else {
            throw PlaylistImportError.authenticationFailed
        }

        let credentials = EmbyCredentials(serverURL: serverURL, username: username, password: password)
        let client = EmbyClient(credentials: credentials, httpClient: httpClient)

        // Re-authenticate to get fresh token
        let authResponse: EmbyAuthResponse
        do {
            authResponse = try await client.authenticate()
        } catch {
            throw PlaylistImportError.authenticationFailed
        }

        let userId = authResponse.user.id
        let accessToken = authResponse.accessToken

        // Update Keychain with new token
        let newCreds: [String: String] = [
            "userId": userId,
            "accessToken": accessToken,
            "password": password,
        ]
        if let newJsonData = try? JSONEncoder().encode(newCreds),
           let jsonString = String(data: newJsonData, encoding: .utf8) {
            KeychainHelper.save(key: passwordRef, value: jsonString)
        }

        // Fetch libraries and items
        let libraries = try await client.getLibraries(userId: userId, accessToken: accessToken)
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
                            item, playlistID: playlist.id, serverURL: serverURL, accessToken: accessToken
                        ))
                    } else {
                        let seriesRecord = EmbyConverter.fromEmbySeries(item, playlistID: playlist.id, serverURL: serverURL)
                        vodItems.append(seriesRecord)
                        var epStartIndex = 0
                        while true {
                            let episodesResponse = try await client.getItems(
                                userId: userId, accessToken: accessToken,
                                parentId: item.id, includeItemTypes: "Episode",
                                startIndex: epStartIndex, limit: 100
                            )
                            for ep in episodesResponse.items {
                                vodItems.append(EmbyConverter.fromEmbyEpisode(
                                    ep, playlistID: playlist.id, seriesID: seriesRecord.id,
                                    serverURL: serverURL, accessToken: accessToken
                                ))
                            }
                            epStartIndex += episodesResponse.items.count
                            if epStartIndex >= episodesResponse.totalRecordCount { break }
                        }
                    }
                }
                startIndex += response.items.count
                if startIndex >= response.totalRecordCount { break }
            }
        }

        var vodImportResult: VodImportResult?
        if !vodItems.isEmpty, let vodRepo {
            vodImportResult = try vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
        }

        let now = Int(Date().timeIntervalSince1970)
        try playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)

        var updatedPlaylist = playlist
        updatedPlaylist.lastSync = now
        return PlaylistImportResult(
            playlist: updatedPlaylist,
            importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 0),
            vodImportResult: vodImportResult
        )
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
                        var epStartIndex = 0
                        while true {
                            let episodesResponse = try await client.getItems(
                                userId: userId, accessToken: accessToken,
                                parentId: item.id, includeItemTypes: "Episode",
                                startIndex: epStartIndex, limit: 100
                            )
                            for ep in episodesResponse.items {
                                vodItems.append(EmbyConverter.fromEmbyEpisode(
                                    ep, playlistID: playlistID, seriesID: seriesRecord.id,
                                    serverURL: serverURL, accessToken: accessToken
                                ))
                            }
                            epStartIndex += episodesResponse.items.count
                            if epStartIndex >= episodesResponse.totalRecordCount { break }
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
