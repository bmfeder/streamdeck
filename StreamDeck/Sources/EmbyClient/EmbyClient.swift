import Foundation
import XtreamClient

/// Emby Server API client. All methods are async and throw EmbyError on failure.
///
/// Usage:
/// ```swift
/// let client = EmbyClient(
///     credentials: EmbyCredentials(serverURL: url, username: "user", password: "pass"),
///     httpClient: URLSessionHTTPClient()
/// )
/// let auth = try await client.authenticate()
/// let libraries = try await client.getLibraries(userId: auth.user.id, accessToken: auth.accessToken)
/// ```
public final class EmbyClient: Sendable {

    private let credentials: EmbyCredentials
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder
    private let deviceId: String

    public init(
        credentials: EmbyCredentials,
        httpClient: HTTPClient,
        deviceId: String = UUID().uuidString
    ) {
        self.credentials = credentials
        self.httpClient = httpClient
        self.deviceId = deviceId
        self.decoder = JSONDecoder()
    }

    // MARK: - Authentication

    /// Authenticate with username and password. Returns user info and access token.
    public func authenticate() async throws -> EmbyAuthResponse {
        let url = credentials.serverURL.appendingPathComponent("Users/AuthenticateByName")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")

        let body: [String: String] = [
            "Username": credentials.username,
            "Pw": credentials.password,
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw EmbyError.networkError(error.localizedDescription)
        }

        if response.statusCode == 401 {
            throw EmbyError.authenticationFailed
        }

        guard (200...299).contains(response.statusCode) else {
            throw EmbyError.httpError(statusCode: response.statusCode)
        }

        do {
            return try decoder.decode(EmbyAuthResponse.self, from: data)
        } catch {
            throw EmbyError.decodingFailed(description: error.localizedDescription)
        }
    }

    // MARK: - Libraries

    /// Fetch the user's library views (Movies, TV Shows, etc.).
    public func getLibraries(userId: String, accessToken: String) async throws -> [EmbyLibrary] {
        let url = credentials.serverURL
            .appendingPathComponent("Users")
            .appendingPathComponent(userId)
            .appendingPathComponent("Views")

        let response: EmbyLibrariesResponse = try await fetchAuthenticated(url: url, accessToken: accessToken)
        return response.items
    }

    // MARK: - Items

    /// Fetch items within a library, paginated.
    public func getItems(
        userId: String,
        accessToken: String,
        parentId: String,
        includeItemTypes: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) async throws -> EmbyItemsResponse {
        guard var components = URLComponents(
            url: credentials.serverURL
                .appendingPathComponent("Users")
                .appendingPathComponent(userId)
                .appendingPathComponent("Items"),
            resolvingAgainstBaseURL: false
        ) else {
            throw EmbyError.invalidURL(credentials.serverURL.absoluteString)
        }

        components.queryItems = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,OfficialRating"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
        ]

        guard let url = components.url else {
            throw EmbyError.invalidURL("Failed to construct items URL")
        }

        return try await fetchAuthenticated(url: url, accessToken: accessToken)
    }

    /// Fetch a single item by ID.
    public func getItem(userId: String, accessToken: String, itemId: String) async throws -> EmbyItem {
        let url = credentials.serverURL
            .appendingPathComponent("Users")
            .appendingPathComponent(userId)
            .appendingPathComponent("Items")
            .appendingPathComponent(itemId)

        return try await fetchAuthenticated(url: url, accessToken: accessToken)
    }

    // MARK: - URL Builders

    /// Build an image URL for an Emby item.
    public static func imageURL(
        serverURL: URL,
        itemId: String,
        imageType: String,
        tag: String?,
        maxWidth: Int
    ) -> URL {
        var url = serverURL
            .appendingPathComponent("Items")
            .appendingPathComponent(itemId)
            .appendingPathComponent("Images")
            .appendingPathComponent(imageType)

        if let tag {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "tag", value: tag),
            ]
            url = components.url!
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            ]
            url = components.url!
        }
        return url
    }

    /// Build a direct stream URL for an Emby item.
    public static func directStreamURL(serverURL: URL, itemId: String, accessToken: String) -> URL {
        var components = URLComponents(
            url: serverURL
                .appendingPathComponent("Videos")
                .appendingPathComponent(itemId)
                .appendingPathComponent("stream"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "api_key", value: accessToken),
        ]
        return components.url!
    }

    // MARK: - Private

    private var authorizationHeader: String {
        "MediaBrowser Client=\"StreamDeck\", Device=\"Apple TV\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
    }

    private func fetchAuthenticated<T: Decodable>(url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw EmbyError.networkError(error.localizedDescription)
        }

        if response.statusCode == 401 {
            throw EmbyError.authenticationFailed
        }

        guard (200...299).contains(response.statusCode) else {
            throw EmbyError.httpError(statusCode: response.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EmbyError.decodingFailed(description: error.localizedDescription)
        }
    }
}
