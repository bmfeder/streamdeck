import Foundation

/// Short EPG response wrapper from get_short_epg.
struct XtreamEPGResponse: Decodable {
    let epgListings: [XtreamEPGListing]?
}

/// An EPG listing from get_short_epg.
/// Title and description are base64-encoded by the API.
public struct XtreamEPGListing: Equatable, Sendable, Decodable {
    public let id: LenientString
    public let epgId: LenientString?
    public let title: String
    public let lang: String?
    public let start: String?
    public let end: String?
    public let description: String?
    public let channelId: String?
    public let startTimestamp: LenientOptionalInt?
    public let stopTimestamp: LenientOptionalInt?

    /// Decoded title (base64 → UTF-8 string).
    public var decodedTitle: String? {
        decodeBase64(title)
    }

    /// Decoded description (base64 → UTF-8 string).
    public var decodedDescription: String? {
        guard let desc = description else { return nil }
        return decodeBase64(desc)
    }

    private func decodeBase64(_ string: String) -> String? {
        guard let data = Data(base64Encoded: string) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
