import Foundation

/// Paginated response from Emby items endpoint.
public struct EmbyItemsResponse: Equatable, Sendable, Decodable {
    public let items: [EmbyItem]
    public let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }

    public init(items: [EmbyItem], totalRecordCount: Int) {
        self.items = items
        self.totalRecordCount = totalRecordCount
    }
}
