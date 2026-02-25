import Foundation

/// Response from Emby `/Users/AuthenticateByName` endpoint.
public struct EmbyAuthResponse: Equatable, Sendable, Decodable {
    public let user: EmbyUser
    public let accessToken: String

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
    }

    public init(user: EmbyUser, accessToken: String) {
        self.user = user
        self.accessToken = accessToken
    }
}
