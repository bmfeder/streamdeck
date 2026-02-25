import Foundation
import GRDB

/// A playlist/provider source configuration stored in the database.
/// Credentials are stored via Keychain reference — never plaintext passwords.
public struct PlaylistRecord: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlist"

    public var id: String
    public var name: String
    public var type: String // m3u, xtream, emby
    public var url: String
    public var username: String?
    public var passwordRef: String? // Keychain reference key
    public var epgURL: String?
    public var refreshHrs: Int
    public var lastSync: Int?
    public var lastEpgSync: Int?
    public var lastSyncEtag: String?
    public var lastSyncHash: String?
    public var isActive: Bool
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        type: String,
        url: String,
        username: String? = nil,
        passwordRef: String? = nil,
        epgURL: String? = nil,
        refreshHrs: Int = 24,
        lastSync: Int? = nil,
        lastEpgSync: Int? = nil,
        lastSyncEtag: String? = nil,
        lastSyncHash: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.username = username
        self.passwordRef = passwordRef
        self.epgURL = epgURL
        self.refreshHrs = refreshHrs
        self.lastSync = lastSync
        self.lastEpgSync = lastEpgSync
        self.lastSyncEtag = lastSyncEtag
        self.lastSyncHash = lastSyncHash
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, url, username
        case passwordRef = "password_ref"
        case epgURL = "epg_url"
        case refreshHrs = "refresh_hrs"
        case lastSync = "last_sync"
        case lastEpgSync = "last_epg_sync"
        case lastSyncEtag = "last_sync_etag"
        case lastSyncHash = "last_sync_hash"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }
}
