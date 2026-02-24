import Foundation

/// A content category (shared type for live, VOD, and series).
public struct XtreamCategory: Equatable, Sendable, Decodable {
    public let categoryId: LenientString
    public let categoryName: String
    public let parentId: LenientInt

    public init(categoryId: String, categoryName: String, parentId: Int = 0) {
        self.categoryId = LenientString(value: categoryId)
        self.categoryName = categoryName
        self.parentId = LenientInt(value: parentId)
    }
}
