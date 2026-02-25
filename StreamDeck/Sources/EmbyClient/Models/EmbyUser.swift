import Foundation

/// Emby user returned by authentication.
public struct EmbyUser: Equatable, Sendable, Decodable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
