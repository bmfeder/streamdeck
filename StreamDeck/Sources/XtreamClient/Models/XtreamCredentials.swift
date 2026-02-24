import Foundation

/// Xtream Codes server connection credentials.
public struct XtreamCredentials: Equatable, Sendable {
    public let serverURL: URL
    public let username: String
    public let password: String

    public init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }

    /// Base URL for player_api.php requests.
    var apiBaseURL: URL {
        serverURL.appendingPathComponent("player_api.php")
    }
}
