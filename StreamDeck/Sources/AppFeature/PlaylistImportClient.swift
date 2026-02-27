import ComposableArchitecture
import EmbyClient
import Foundation
import Database
import M3UParser
import Repositories
import SyncDatabase
import XtreamClient

/// TCA dependency client for playlist import operations.
/// Wraps PlaylistImportService for use in reducers.
public struct PlaylistImportClient: Sendable {

    /// Import an M3U playlist from a URL.
    public var importM3U: @Sendable (
        _ url: URL,
        _ name: String,
        _ epgURL: URL?
    ) async throws -> PlaylistImportResult

    /// Import an Xtream Codes account.
    public var importXtream: @Sendable (
        _ serverURL: URL,
        _ username: String,
        _ password: String,
        _ name: String
    ) async throws -> PlaylistImportResult

    /// Import an Emby server.
    public var importEmby: @Sendable (
        _ serverURL: URL,
        _ username: String,
        _ password: String,
        _ name: String
    ) async throws -> PlaylistImportResult

    /// Delete a playlist and all its associated content (channels, VOD, progress).
    public var deletePlaylist: @Sendable (_ id: String) async throws -> Void

    /// Refresh an existing playlist by re-downloading and re-importing content.
    public var refreshPlaylist: @Sendable (_ id: String) async throws -> PlaylistImportResult

    /// Update playlist metadata (name, EPG URL, refresh interval).
    public var updatePlaylist: @Sendable (_ record: PlaylistRecord) async throws -> Void

    /// Validate an M3U URL is reachable (HEAD request).
    public var validateM3U: @Sendable (_ url: URL) async throws -> Void

    /// Validate Xtream credentials (authenticate only).
    public var validateXtream: @Sendable (
        _ serverURL: URL,
        _ username: String,
        _ password: String
    ) async throws -> Void

    /// Validate Emby credentials (authenticate only).
    public var validateEmby: @Sendable (
        _ serverURL: URL,
        _ username: String,
        _ password: String
    ) async throws -> Void

    /// Create a playlist record and store credentials without importing content.
    public var createPlaylist: @Sendable (_ params: PlaylistImportParams) async throws -> PlaylistRecord
}

// MARK: - Dependency Registration

extension PlaylistImportClient: DependencyKey {
    public static var liveValue: PlaylistImportClient {
        let db = SyncDatabaseManager.shared.db
        let playlistRepo = SyncPlaylistRepository(db: db)
        let channelRepo = SyncChannelRepository(db: db)
        let vodRepo = SyncVodRepository(db: db)

        return PlaylistImportClient(
            importM3U: { url, name, epgURL in
                // Download
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw PlaylistImportError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }

                // Parse
                let parser = M3UParser()
                let parseResult = parser.parse(data: data)
                guard !parseResult.channels.isEmpty else {
                    throw PlaylistImportError.emptyPlaylist
                }

                let resolvedEpgURL = epgURL?.absoluteString ?? parseResult.metadata.urlTvg

                // Create playlist
                let playlistID = UUID().uuidString
                let now = Int(Date().timeIntervalSince1970)
                let playlist = PlaylistRecord(
                    id: playlistID, name: name, type: "m3u",
                    url: url.absoluteString, epgURL: resolvedEpgURL,
                    lastSync: now, sortOrder: 0
                )
                try await playlistRepo.create(playlist)

                // Import channels + VOD
                let liveEntries = parseResult.channels.filter { $0.duration <= 0 }
                let vodEntries = parseResult.channels.filter { $0.duration > 0 }

                let channels = liveEntries.map {
                    ChannelConverter.fromParsedChannel($0, playlistID: playlistID, id: UUID().uuidString)
                }
                let syncImportResult = try await channelRepo.importChannels(
                    playlistID: playlistID, channels: channels, now: now
                )

                var vodImportResult: VodImportResult?
                if !vodEntries.isEmpty {
                    let vodItems = vodEntries.map {
                        VodConverter.fromParsedChannel($0, playlistID: playlistID, id: UUID().uuidString)
                    }
                    let syncVodResult = try await vodRepo.importVodItems(
                        playlistID: playlistID, items: vodItems
                    )
                    vodImportResult = VodImportResult(added: syncVodResult.imported, removed: 0)
                }

                let parseErrors = parseResult.errors.prefix(10).map { "Line \($0.line): \($0.reason.rawValue)" }
                return PlaylistImportResult(
                    playlist: playlist,
                    importResult: syncImportResult.toImportResult(),
                    vodImportResult: vodImportResult,
                    parseErrors: Array(parseErrors)
                )
            },
            importXtream: { serverURL, username, password, name in
                let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)
                let client = XtreamClient(credentials: credentials, httpClient: URLSessionHTTPClient())

                do {
                    _ = try await client.authenticate()
                } catch let error as XtreamError {
                    switch error {
                    case .accountExpired: throw PlaylistImportError.accountExpired
                    case .authenticationFailed: throw PlaylistImportError.authenticationFailed
                    default: throw PlaylistImportError.networkError(String(describing: error))
                    }
                }

                let categories = try await client.getLiveCategories()
                let streams = try await client.getLiveStreams()
                guard !streams.isEmpty else { throw PlaylistImportError.emptyPlaylist }

                var categoryMap: [String: String] = [:]
                for cat in categories { categoryMap[cat.categoryId.value] = cat.categoryName }

                let playlistID = UUID().uuidString
                let keychainKey = "xtream-\(playlistID)"
                KeychainHelper.save(key: keychainKey, value: password)

                let now = Int(Date().timeIntervalSince1970)
                let playlist = PlaylistRecord(
                    id: playlistID, name: name, type: "xtream",
                    url: serverURL.absoluteString, username: username,
                    passwordRef: keychainKey, lastSync: now, sortOrder: 0
                )
                try await playlistRepo.create(playlist)

                let channels = streams.map { stream in
                    let catName = categoryMap[stream.categoryId.value]
                    let streamURL = client.liveStreamURL(streamId: stream.streamId.value).absoluteString
                    return ChannelConverter.fromXtreamLiveStream(
                        stream, playlistID: playlistID, categoryName: catName,
                        streamURL: streamURL, id: UUID().uuidString
                    )
                }
                let syncImportResult = try await channelRepo.importChannels(
                    playlistID: playlistID, channels: channels, now: now
                )

                // VOD (non-fatal)
                var vodImportResult: VodImportResult?
                do {
                    var vodItems: [VodItemRecord] = []
                    let vodCats = try await client.getVODCategories()
                    var vodCatMap: [String: String] = [:]
                    for cat in vodCats { vodCatMap[cat.categoryId.value] = cat.categoryName }
                    let vodStreams = try await client.getVODStreams()
                    for stream in vodStreams {
                        let catName = vodCatMap[stream.categoryId.value]
                        let ext = stream.containerExtension ?? "mp4"
                        let url = client.vodStreamURL(streamId: stream.streamId.value, containerExtension: ext).absoluteString
                        vodItems.append(VodConverter.fromXtreamVODStream(
                            stream, playlistID: playlistID, categoryName: catName, streamURL: url, id: UUID().uuidString
                        ))
                    }
                    let seriesCats = try await client.getSeriesCategories()
                    var seriesCatMap: [String: String] = [:]
                    for cat in seriesCats { seriesCatMap[cat.categoryId.value] = cat.categoryName }
                    let seriesList = try await client.getSeries()
                    for series in seriesList {
                        let catName = seriesCatMap[series.categoryId.value]
                        vodItems.append(VodConverter.fromXtreamSeries(
                            series, playlistID: playlistID, categoryName: catName, id: UUID().uuidString
                        ))
                    }
                    if !vodItems.isEmpty {
                        let r = try await vodRepo.importVodItems(playlistID: playlistID, items: vodItems)
                        vodImportResult = VodImportResult(added: r.imported, removed: 0)
                    }
                } catch {}

                return PlaylistImportResult(
                    playlist: playlist, importResult: syncImportResult.toImportResult(),
                    vodImportResult: vodImportResult
                )
            },
            importEmby: { serverURL, username, password, name in
                let credentials = EmbyCredentials(serverURL: serverURL, username: username, password: password)
                let client = EmbyClient(credentials: credentials, httpClient: URLSessionHTTPClient())

                let authResponse: EmbyAuthResponse
                do {
                    authResponse = try await client.authenticate()
                } catch let error as EmbyError {
                    switch error {
                    case .authenticationFailed: throw PlaylistImportError.authenticationFailed
                    default: throw PlaylistImportError.networkError(String(describing: error))
                    }
                }

                let userId = authResponse.user.id
                let accessToken = authResponse.accessToken

                let playlistID = UUID().uuidString
                let keychainKey = "emby-\(playlistID)"
                let credJSON: [String: String] = ["userId": userId, "accessToken": accessToken, "password": password]
                if let jsonData = try? JSONEncoder().encode(credJSON),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    KeychainHelper.save(key: keychainKey, value: jsonString)
                }

                let now = Int(Date().timeIntervalSince1970)
                let playlist = PlaylistRecord(
                    id: playlistID, name: name, type: "emby",
                    url: serverURL.absoluteString, username: username,
                    passwordRef: keychainKey, lastSync: now, sortOrder: 0
                )
                try await playlistRepo.create(playlist)

                let vodItems = try await fetchEmbyVodItems(
                    client: client, userId: userId, accessToken: accessToken,
                    playlistID: playlistID, serverURL: serverURL
                )

                var vodImportResult: VodImportResult?
                if !vodItems.isEmpty {
                    let r = try await vodRepo.importVodItems(playlistID: playlistID, items: vodItems)
                    vodImportResult = VodImportResult(added: r.imported, removed: 0)
                }

                return PlaylistImportResult(
                    playlist: playlist,
                    importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 0),
                    vodImportResult: vodImportResult
                )
            },
            deletePlaylist: { id in
                try await playlistRepo.delete(id: id)
            },
            refreshPlaylist: { id in
                guard let playlist = try await playlistRepo.get(id: id) else {
                    throw PlaylistImportError.playlistNotFound
                }

                let result: PlaylistImportResult
                switch playlist.type {
                case "m3u":
                    result = try await refreshM3U(playlist: playlist, playlistRepo: playlistRepo, channelRepo: channelRepo, vodRepo: vodRepo)
                case "xtream":
                    result = try await refreshXtream(playlist: playlist, playlistRepo: playlistRepo, channelRepo: channelRepo, vodRepo: vodRepo)
                case "emby":
                    result = try await refreshEmby(playlist: playlist, playlistRepo: playlistRepo, vodRepo: vodRepo)
                default:
                    throw PlaylistImportError.playlistNotFound
                }

                // Purge channels soft-deleted more than 30 days ago
                let thirtyDaysAgo = Int(Date().timeIntervalSince1970) - (30 * 24 * 60 * 60)
                _ = try? await channelRepo.purgeDeleted(olderThan: thirtyDaysAgo)

                return result
            },
            updatePlaylist: { record in
                try await playlistRepo.update(record)
            },
            validateM3U: { url in
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 15
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...399).contains(httpResponse.statusCode) else {
                    throw PlaylistImportError.downloadFailed("URL is not reachable")
                }
            },
            validateXtream: { serverURL, username, password in
                let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)
                let client = XtreamClient(credentials: credentials, httpClient: URLSessionHTTPClient())
                do {
                    _ = try await client.authenticate()
                } catch let error as XtreamError {
                    switch error {
                    case .accountExpired: throw PlaylistImportError.accountExpired
                    case .authenticationFailed: throw PlaylistImportError.authenticationFailed
                    default: throw PlaylistImportError.networkError(String(describing: error))
                    }
                }
            },
            validateEmby: { serverURL, username, password in
                let credentials = EmbyCredentials(serverURL: serverURL, username: username, password: password)
                let client = EmbyClient(credentials: credentials, httpClient: URLSessionHTTPClient())
                do {
                    _ = try await client.authenticate()
                } catch let error as EmbyError {
                    switch error {
                    case .authenticationFailed: throw PlaylistImportError.authenticationFailed
                    default: throw PlaylistImportError.networkError(String(describing: error))
                    }
                }
            },
            createPlaylist: { params in
                let playlistID = UUID().uuidString
                let record: PlaylistRecord

                switch params {
                case let .m3u(url, name, epgURL):
                    record = PlaylistRecord(
                        id: playlistID, name: name, type: "m3u",
                        url: url.absoluteString, epgURL: epgURL?.absoluteString,
                        lastSync: nil, sortOrder: 0
                    )
                case let .xtream(serverURL, username, password, name):
                    let keychainKey = "xtream-\(playlistID)"
                    KeychainHelper.save(key: keychainKey, value: password)
                    record = PlaylistRecord(
                        id: playlistID, name: name, type: "xtream",
                        url: serverURL.absoluteString, username: username,
                        passwordRef: keychainKey, lastSync: nil, sortOrder: 0
                    )
                case let .emby(serverURL, username, password, name):
                    let keychainKey = "emby-\(playlistID)"
                    let credJSON = try JSONEncoder().encode(["password": password])
                    KeychainHelper.save(key: keychainKey, value: String(data: credJSON, encoding: .utf8)!)
                    record = PlaylistRecord(
                        id: playlistID, name: name, type: "emby",
                        url: serverURL.absoluteString, username: username,
                        passwordRef: keychainKey, lastSync: nil, sortOrder: 0
                    )
                }

                try await playlistRepo.create(record)
                return record
            }
        )
    }

    public static var testValue: PlaylistImportClient {
        PlaylistImportClient(
            importM3U: unimplemented("PlaylistImportClient.importM3U"),
            importXtream: unimplemented("PlaylistImportClient.importXtream"),
            importEmby: unimplemented("PlaylistImportClient.importEmby"),
            deletePlaylist: unimplemented("PlaylistImportClient.deletePlaylist"),
            refreshPlaylist: unimplemented("PlaylistImportClient.refreshPlaylist"),
            updatePlaylist: unimplemented("PlaylistImportClient.updatePlaylist"),
            validateM3U: unimplemented("PlaylistImportClient.validateM3U"),
            validateXtream: unimplemented("PlaylistImportClient.validateXtream"),
            validateEmby: unimplemented("PlaylistImportClient.validateEmby"),
            createPlaylist: unimplemented("PlaylistImportClient.createPlaylist")
        )
    }
}

// MARK: - Refresh Helpers

private func refreshM3U(
    playlist: PlaylistRecord,
    playlistRepo: SyncPlaylistRepository,
    channelRepo: SyncChannelRepository,
    vodRepo: SyncVodRepository
) async throws -> PlaylistImportResult {
    guard let url = URL(string: playlist.url) else {
        throw PlaylistImportError.downloadFailed("Invalid URL")
    }

    let request = URLRequest(url: url)
    let data: Data
    do {
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlaylistImportError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        data = responseData
    } catch let error as PlaylistImportError { throw error }
    catch { throw PlaylistImportError.networkError(error.localizedDescription) }

    let parser = M3UParser()
    let parseResult = parser.parse(data: data)
    guard !parseResult.channels.isEmpty else { throw PlaylistImportError.emptyPlaylist }

    let now = Int(Date().timeIntervalSince1970)
    let liveEntries = parseResult.channels.filter { $0.duration <= 0 }
    let vodEntries = parseResult.channels.filter { $0.duration > 0 }

    let channels = liveEntries.map {
        ChannelConverter.fromParsedChannel($0, playlistID: playlist.id, id: UUID().uuidString)
    }
    let syncResult = try await channelRepo.importChannels(playlistID: playlist.id, channels: channels, now: now)

    var vodImportResult: VodImportResult?
    if !vodEntries.isEmpty {
        let vodItems = vodEntries.map {
            VodConverter.fromParsedChannel($0, playlistID: playlist.id, id: UUID().uuidString)
        }
        let r = try await vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
        vodImportResult = VodImportResult(added: r.imported, removed: 0)
    }

    try await playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)
    let parseErrors = parseResult.errors.prefix(10).map { "Line \($0.line): \($0.reason.rawValue)" }

    var updatedPlaylist = playlist
    updatedPlaylist.lastSync = now
    return PlaylistImportResult(
        playlist: updatedPlaylist, importResult: syncResult.toImportResult(),
        vodImportResult: vodImportResult, parseErrors: Array(parseErrors)
    )
}

private func refreshXtream(
    playlist: PlaylistRecord,
    playlistRepo: SyncPlaylistRepository,
    channelRepo: SyncChannelRepository,
    vodRepo: SyncVodRepository
) async throws -> PlaylistImportResult {
    guard let serverURL = URL(string: playlist.url),
          let username = playlist.username,
          let passwordRef = playlist.passwordRef,
          let password = KeychainHelper.load(key: passwordRef)
    else { throw PlaylistImportError.authenticationFailed }

    let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)
    let client = XtreamClient(credentials: credentials, httpClient: URLSessionHTTPClient())

    do { _ = try await client.authenticate() }
    catch let error as XtreamError {
        switch error {
        case .accountExpired: throw PlaylistImportError.accountExpired
        case .authenticationFailed: throw PlaylistImportError.authenticationFailed
        default: throw PlaylistImportError.networkError(String(describing: error))
        }
    } catch { throw PlaylistImportError.authenticationFailed }

    let categories = try await client.getLiveCategories()
    let streams = try await client.getLiveStreams()
    guard !streams.isEmpty else { throw PlaylistImportError.emptyPlaylist }

    var categoryMap: [String: String] = [:]
    for cat in categories { categoryMap[cat.categoryId.value] = cat.categoryName }

    let now = Int(Date().timeIntervalSince1970)
    let channels = streams.map { stream in
        let catName = categoryMap[stream.categoryId.value]
        let streamURL = client.liveStreamURL(streamId: stream.streamId.value).absoluteString
        return ChannelConverter.fromXtreamLiveStream(
            stream, playlistID: playlist.id, categoryName: catName,
            streamURL: streamURL, id: UUID().uuidString
        )
    }
    let syncResult = try await channelRepo.importChannels(playlistID: playlist.id, channels: channels, now: now)

    var vodImportResult: VodImportResult?
    do {
        var vodItems: [VodItemRecord] = []
        let vodCats = try await client.getVODCategories()
        var vodCatMap: [String: String] = [:]
        for cat in vodCats { vodCatMap[cat.categoryId.value] = cat.categoryName }
        let vodStreams = try await client.getVODStreams()
        for stream in vodStreams {
            let catName = vodCatMap[stream.categoryId.value]
            let ext = stream.containerExtension ?? "mp4"
            let url = client.vodStreamURL(streamId: stream.streamId.value, containerExtension: ext).absoluteString
            vodItems.append(VodConverter.fromXtreamVODStream(
                stream, playlistID: playlist.id, categoryName: catName, streamURL: url, id: UUID().uuidString
            ))
        }
        let seriesCats = try await client.getSeriesCategories()
        var seriesCatMap: [String: String] = [:]
        for cat in seriesCats { seriesCatMap[cat.categoryId.value] = cat.categoryName }
        let seriesList = try await client.getSeries()
        for series in seriesList {
            let catName = seriesCatMap[series.categoryId.value]
            vodItems.append(VodConverter.fromXtreamSeries(
                series, playlistID: playlist.id, categoryName: catName, id: UUID().uuidString
            ))
        }
        if !vodItems.isEmpty {
            let r = try await vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
            vodImportResult = VodImportResult(added: r.imported, removed: 0)
        }
    } catch {}

    try await playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)

    var updatedPlaylist = playlist
    updatedPlaylist.lastSync = now
    return PlaylistImportResult(
        playlist: updatedPlaylist, importResult: syncResult.toImportResult(),
        vodImportResult: vodImportResult
    )
}

private func refreshEmby(
    playlist: PlaylistRecord,
    playlistRepo: SyncPlaylistRepository,
    vodRepo: SyncVodRepository
) async throws -> PlaylistImportResult {
    guard let serverURL = URL(string: playlist.url),
          let username = playlist.username,
          let passwordRef = playlist.passwordRef,
          let credentialJSON = KeychainHelper.load(key: passwordRef),
          let jsonData = credentialJSON.data(using: .utf8),
          let creds = try? JSONDecoder().decode([String: String].self, from: jsonData),
          let password = creds["password"]
    else { throw PlaylistImportError.authenticationFailed }

    let credentials = EmbyCredentials(serverURL: serverURL, username: username, password: password)
    let client = EmbyClient(credentials: credentials, httpClient: URLSessionHTTPClient())

    let authResponse: EmbyAuthResponse
    do { authResponse = try await client.authenticate() }
    catch { throw PlaylistImportError.authenticationFailed }

    let userId = authResponse.user.id
    let accessToken = authResponse.accessToken

    // Update Keychain with new token
    let newCreds: [String: String] = ["userId": userId, "accessToken": accessToken, "password": password]
    if let newJsonData = try? JSONEncoder().encode(newCreds),
       let jsonString = String(data: newJsonData, encoding: .utf8) {
        KeychainHelper.save(key: passwordRef, value: jsonString)
    }

    let vodItems = try await fetchEmbyVodItems(
        client: client, userId: userId, accessToken: accessToken,
        playlistID: playlist.id, serverURL: serverURL
    )

    var vodImportResult: VodImportResult?
    if !vodItems.isEmpty {
        let r = try await vodRepo.importVodItems(playlistID: playlist.id, items: vodItems)
        vodImportResult = VodImportResult(added: r.imported, removed: 0)
    }

    let now = Int(Date().timeIntervalSince1970)
    try await playlistRepo.updateSyncTimestamp(playlist.id, timestamp: now)

    var updatedPlaylist = playlist
    updatedPlaylist.lastSync = now
    return PlaylistImportResult(
        playlist: updatedPlaylist,
        importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 0),
        vodImportResult: vodImportResult
    )
}

private func fetchEmbyVodItems(
    client: EmbyClient,
    userId: String,
    accessToken: String,
    playlistID: String,
    serverURL: URL
) async throws -> [VodItemRecord] {
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
                        item, playlistID: playlistID, serverURL: serverURL, accessToken: accessToken
                    ))
                } else {
                    let seriesRecord = EmbyConverter.fromEmbySeries(item, playlistID: playlistID, serverURL: serverURL)
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
    return vodItems
}

// MARK: - Result Mapping

extension SyncImportResult {
    func toImportResult() -> ImportResult {
        ImportResult(added: added, updated: updated, softDeleted: softDeleted, unchanged: unchanged)
    }
}

extension DependencyValues {
    public var playlistImportClient: PlaylistImportClient {
        get { self[PlaylistImportClient.self] }
        set { self[PlaylistImportClient.self] = newValue }
    }
}
