import Foundation
import Database
import M3UParser
import XtreamClient

/// Static conversion helpers for transforming parsed data into ChannelRecords.
/// No database access — pure data mapping only.
public enum ChannelConverter {

    /// Converts an M3U ParsedChannel into a ChannelRecord.
    ///
    /// Mapping:
    /// - `tvgId` → `sourceChannelID` and `tvgID` (M3U has no native ID)
    /// - `channelNumber` → `channelNum`
    /// - `tvgLogo` → `logoURL`
    /// - `groupTitle` → `groupName`
    public static func fromParsedChannel(
        _ parsed: ParsedChannel,
        playlistID: String,
        id: String? = nil
    ) -> ChannelRecord {
        ChannelRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            sourceChannelID: parsed.tvgId,
            name: parsed.name,
            groupName: parsed.groupTitle,
            streamURL: parsed.streamURL.absoluteString,
            logoURL: parsed.tvgLogo?.absoluteString,
            tvgID: parsed.tvgId,
            channelNum: parsed.channelNumber
        )
    }

    /// Converts an Xtream live stream into a ChannelRecord.
    ///
    /// Mapping:
    /// - `streamId` → `sourceChannelID` (as String, tier 1 identity)
    /// - `epgChannelId` → `epgID` and `tvgID` (tier 2 identity)
    /// - `categoryId` → resolved via `categoryName` parameter
    /// - Stream URL must be pre-built by the caller (requires credentials)
    public static func fromXtreamLiveStream(
        _ stream: XtreamLiveStream,
        playlistID: String,
        categoryName: String?,
        streamURL: String,
        id: String? = nil
    ) -> ChannelRecord {
        ChannelRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            sourceChannelID: String(stream.streamId.value),
            name: stream.name,
            groupName: categoryName,
            streamURL: streamURL,
            logoURL: stream.streamIcon,
            epgID: stream.epgChannelId,
            tvgID: stream.epgChannelId
        )
    }
}
