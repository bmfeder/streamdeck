import Foundation

/// A VOD entry from get_vod_streams.
public struct XtreamVODStream: Equatable, Sendable, Decodable {
    public let num: LenientInt
    public let name: String
    public let streamType: String?
    public let streamId: LenientInt
    public let streamIcon: String?
    public let rating: LenientOptionalDouble?
    public let added: LenientOptionalInt?
    public let categoryId: LenientString
    public let containerExtension: String?
    public let customSid: String?
    public let directSource: String?

    /// Parsed poster URL, nil if empty or invalid.
    public var posterURL: URL? {
        guard let icon = streamIcon, !icon.isEmpty else { return nil }
        return URL(string: icon)
    }
}
