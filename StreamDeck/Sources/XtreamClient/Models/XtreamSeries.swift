import Foundation

/// A series listing from get_series.
public struct XtreamSeries: Equatable, Sendable, Decodable {
    public let num: LenientInt
    public let name: String
    public let seriesId: LenientInt
    public let cover: String?
    public let plot: String?
    public let cast: String?
    public let director: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: LenientOptionalDouble?
    public let categoryId: LenientString
    public let backdropPath: LenientStringOrArray?

    /// Parsed poster URL, nil if empty or invalid.
    public var coverURL: URL? {
        guard let c = cover, !c.isEmpty else { return nil }
        return URL(string: c)
    }
}
