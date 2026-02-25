import Foundation

/// An Emby library (view) returned by `/Users/{userId}/Views`.
public struct EmbyLibrary: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let collectionType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
    }

    public init(id: String, name: String, collectionType: String? = nil) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

/// Response wrapper for the libraries endpoint.
public struct EmbyLibrariesResponse: Equatable, Sendable, Decodable {
    public let items: [EmbyLibrary]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
