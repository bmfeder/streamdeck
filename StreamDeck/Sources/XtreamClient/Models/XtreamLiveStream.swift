import Foundation

/// A live stream entry from get_live_streams.
public struct XtreamLiveStream: Equatable, Sendable, Decodable {
    public let num: LenientInt
    public let name: String
    public let streamType: String?
    public let streamId: LenientInt
    public let streamIcon: String?
    public let epgChannelId: String?
    public let added: LenientOptionalInt?
    public let categoryId: LenientString
    public let customSid: String?
    public let tvArchive: LenientInt
    public let directSource: String?
    public let tvArchiveDuration: LenientOptionalInt?

    /// Parsed logo URL, nil if empty or invalid.
    public var logoURL: URL? {
        guard let icon = streamIcon, !icon.isEmpty else { return nil }
        return URL(string: icon)
    }
}
