import Foundation

/// Supported live stream output formats.
public enum StreamFormat: String, Sendable {
    case ts = "ts"
    case m3u8 = "m3u8"
}

/// Xtream Codes API client. All methods are async and throw XtreamError on failure.
///
/// Usage:
/// ```swift
/// let client = XtreamClient(
///     credentials: XtreamCredentials(serverURL: url, username: "user", password: "pass"),
///     httpClient: URLSessionHTTPClient()
/// )
/// let auth = try await client.authenticate()
/// let categories = try await client.getLiveCategories()
/// ```
public final class XtreamClient: Sendable {

    private let credentials: XtreamCredentials
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder

    public init(credentials: XtreamCredentials, httpClient: HTTPClient) {
        self.credentials = credentials
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        self.httpClient = httpClient
    }

    // MARK: - Authentication

    /// Authenticate and get account + server info.
    public func authenticate() async throws -> XtreamAuthResponse {
        let response: XtreamAuthResponse = try await fetch(XtreamAuthResponse.self)

        guard response.isAuthenticated else {
            throw XtreamError.authenticationFailed
        }

        if response.isExpired {
            throw XtreamError.accountExpired
        }

        return response
    }

    // MARK: - Live TV

    /// Get all live stream categories.
    public func getLiveCategories() async throws -> [XtreamCategory] {
        try await fetch([XtreamCategory].self, action: "get_live_categories")
    }

    /// Get live streams, optionally filtered by category.
    public func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        var params: [String: String] = [:]
        if let categoryId { params["category_id"] = categoryId }
        return try await fetch([XtreamLiveStream].self, action: "get_live_streams", params: params)
    }

    // MARK: - VOD

    /// Get all VOD categories.
    public func getVODCategories() async throws -> [XtreamCategory] {
        try await fetch([XtreamCategory].self, action: "get_vod_categories")
    }

    /// Get VOD streams, optionally filtered by category.
    public func getVODStreams(categoryId: String? = nil) async throws -> [XtreamVODStream] {
        var params: [String: String] = [:]
        if let categoryId { params["category_id"] = categoryId }
        return try await fetch([XtreamVODStream].self, action: "get_vod_streams", params: params)
    }

    /// Get detailed info for a single VOD item.
    public func getVODInfo(vodId: String) async throws -> XtreamVODInfo {
        try await fetch(XtreamVODInfo.self, action: "get_vod_info", params: ["vod_id": vodId])
    }

    // MARK: - Series

    /// Get all series categories.
    public func getSeriesCategories() async throws -> [XtreamCategory] {
        try await fetch([XtreamCategory].self, action: "get_series_categories")
    }

    /// Get series listings, optionally filtered by category.
    public func getSeries(categoryId: String? = nil) async throws -> [XtreamSeries] {
        var params: [String: String] = [:]
        if let categoryId { params["category_id"] = categoryId }
        return try await fetch([XtreamSeries].self, action: "get_series", params: params)
    }

    /// Get detailed series info including seasons and episodes.
    public func getSeriesInfo(seriesId: String) async throws -> XtreamSeriesInfo {
        try await fetch(XtreamSeriesInfo.self, action: "get_series_info", params: ["series_id": seriesId])
    }

    // MARK: - EPG

    /// Get short EPG for a stream.
    public func getShortEPG(streamId: String, limit: Int? = nil) async throws -> [XtreamEPGListing] {
        var params = ["stream_id": streamId]
        if let limit { params["limit"] = String(limit) }
        let response = try await fetch(XtreamEPGResponse.self, action: "get_short_epg", params: params)
        return response.epgListings ?? []
    }

    // MARK: - Stream URL Builder

    /// Build the playback URL for a live stream.
    public func liveStreamURL(streamId: Int, format: StreamFormat = .m3u8) -> URL {
        credentials.serverURL
            .appendingPathComponent("live")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(streamId).\(format.rawValue)")
    }

    /// Build the playback URL for a VOD item.
    public func vodStreamURL(streamId: Int, containerExtension: String) -> URL {
        credentials.serverURL
            .appendingPathComponent("movie")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(streamId).\(containerExtension)")
    }

    /// Build the playback URL for a series episode.
    public func seriesStreamURL(episodeId: Int, containerExtension: String) -> URL {
        credentials.serverURL
            .appendingPathComponent("series")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(episodeId).\(containerExtension)")
    }

    // MARK: - Private Helpers

    private func buildURL(action: String? = nil, params: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(url: credentials.apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidURL(credentials.serverURL.absoluteString)
        }

        var queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
        ]

        if let action {
            queryItems.append(URLQueryItem(name: "action", value: action))
        }

        for (key, value) in params.sorted(by: { $0.key < $1.key }) {
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw XtreamError.invalidURL("Failed to construct URL with action: \(action ?? "none")")
        }
        return url
    }

    private func fetch<T: Decodable>(_ type: T.Type, action: String? = nil, params: [String: String] = [:]) async throws -> T {
        let url = try buildURL(action: action, params: params)
        let request = URLRequest(url: url)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch let error as XtreamError {
            throw error
        } catch {
            throw XtreamError.networkError(error.localizedDescription)
        }

        guard (200...299).contains(response.statusCode) else {
            throw XtreamError.httpError(statusCode: response.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw XtreamError.decodingFailed(description: error.localizedDescription)
        }
    }
}
