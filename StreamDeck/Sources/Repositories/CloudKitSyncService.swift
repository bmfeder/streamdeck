import CloudKit
import Database
import Foundation

/// Handles all CloudKit private database operations for syncing playlists,
/// favorites, watch progress, and user preferences across devices.
/// Thread-safe via actor isolation.
public actor CloudKitSyncService {
    private let database: any CloudKitDatabaseProtocol
    private let playlistRepo: PlaylistRepository
    private let channelRepo: ChannelRepository
    private let watchProgressRepo: WatchProgressRepository
    private let deviceID: String

    public init(
        database: any CloudKitDatabaseProtocol,
        dbManager: DatabaseManager,
        deviceID: String? = nil
    ) {
        self.database = database
        self.playlistRepo = PlaylistRepository(dbManager: dbManager)
        self.channelRepo = ChannelRepository(dbManager: dbManager)
        self.watchProgressRepo = WatchProgressRepository(dbManager: dbManager)
        self.deviceID = deviceID ?? Self.getOrCreateDeviceID()
    }

    // MARK: - Push: Playlists

    public func pushPlaylist(_ record: PlaylistRecord) async throws {
        let ckRecord = CKRecord(
            recordType: "SDPlaylist",
            recordID: CKRecord.ID(recordName: record.id)
        )
        ckRecord["name"] = record.name
        ckRecord["type"] = record.type
        ckRecord["url"] = record.url
        ckRecord["username"] = record.username
        ckRecord["epgURL"] = record.epgURL
        ckRecord["refreshHrs"] = record.refreshHrs as NSNumber
        ckRecord["isActive"] = (record.isActive ? 1 : 0) as NSNumber
        ckRecord["sortOrder"] = record.sortOrder as NSNumber
        ckRecord["isDeleted"] = 0 as NSNumber
        ckRecord["deviceID"] = deviceID
        _ = try await database.save(ckRecord)
    }

    public func pushPlaylistDeletion(_ playlistID: String) async throws {
        let recordID = CKRecord.ID(recordName: playlistID)
        do {
            let existing = try await database.record(for: recordID)
            existing["isDeleted"] = 1 as NSNumber
            existing["deviceID"] = deviceID
            _ = try await database.save(existing)
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone from cloud
        }
    }

    // MARK: - Push: Favorites

    public func pushFavorite(channelID: String, playlistID: String, isFavorite: Bool) async throws {
        let ckRecord = CKRecord(
            recordType: "SDFavorite",
            recordID: CKRecord.ID(recordName: channelID)
        )
        ckRecord["channelID"] = channelID
        ckRecord["playlistID"] = playlistID
        ckRecord["isFavorite"] = (isFavorite ? 1 : 0) as NSNumber
        ckRecord["deviceID"] = deviceID
        _ = try await database.save(ckRecord)
    }

    // MARK: - Push: Watch Progress

    public func pushWatchProgress(_ record: WatchProgressRecord) async throws {
        let ckRecord = CKRecord(
            recordType: "SDWatchProgress",
            recordID: CKRecord.ID(recordName: record.contentID)
        )
        ckRecord["playlistID"] = record.playlistID
        ckRecord["positionMs"] = record.positionMs as NSNumber
        if let durationMs = record.durationMs {
            ckRecord["durationMs"] = durationMs as NSNumber
        }
        ckRecord["updatedAt"] = record.updatedAt as NSNumber
        ckRecord["deviceID"] = deviceID
        _ = try await database.save(ckRecord)
    }

    // MARK: - Push: User Preferences

    public func pushPreferences(_ prefs: SyncablePreferences) async throws {
        let ckRecord = CKRecord(
            recordType: "SDUserPreference",
            recordID: CKRecord.ID(recordName: "userPreferences")
        )
        ckRecord["preferredEngine"] = prefs.preferredEngine
        ckRecord["resumePlaybackEnabled"] = (prefs.resumePlaybackEnabled ? 1 : 0) as NSNumber
        ckRecord["bufferTimeoutSeconds"] = prefs.bufferTimeoutSeconds as NSNumber
        ckRecord["updatedAt"] = prefs.updatedAt as NSNumber
        ckRecord["deviceID"] = deviceID
        _ = try await database.save(ckRecord)
    }

    // MARK: - Pull All

    public func pullAll() async throws -> SyncPullResult {
        async let p = pullPlaylists()
        async let f = pullFavorites()
        async let w = pullWatchProgress()
        async let prefs = pullPreferences()

        let (pCount, fCount, wCount, prefsUpdated) = try await (p, f, w, prefs)
        return SyncPullResult(
            playlistsUpdated: pCount,
            favoritesUpdated: fCount,
            progressUpdated: wCount,
            preferencesUpdated: prefsUpdated
        )
    }

    // MARK: - Pull: Playlists

    public func pullPlaylists() async throws -> Int {
        let query = CKQuery(recordType: "SDPlaylist", predicate: NSPredicate(value: true))
        let results = try await database.fetchRecords(matching: query)

        var updated = 0
        for ckRecord in results {
            let remoteID = ckRecord.recordID.recordName
            let isDeleted = (ckRecord["isDeleted"] as? NSNumber)?.intValue == 1

            if isDeleted {
                if (try? playlistRepo.get(id: remoteID)) != nil {
                    try? playlistRepo.delete(id: remoteID)
                    updated += 1
                }
                continue
            }

            if let local = try? playlistRepo.get(id: remoteID) {
                var merged = local
                merged.name = ckRecord["name"] as? String ?? local.name
                merged.type = ckRecord["type"] as? String ?? local.type
                merged.url = ckRecord["url"] as? String ?? local.url
                merged.username = ckRecord["username"] as? String
                merged.epgURL = ckRecord["epgURL"] as? String
                merged.refreshHrs = (ckRecord["refreshHrs"] as? NSNumber)?.intValue ?? local.refreshHrs
                merged.isActive = (ckRecord["isActive"] as? NSNumber)?.intValue == 1
                merged.sortOrder = (ckRecord["sortOrder"] as? NSNumber)?.intValue ?? local.sortOrder
                try? playlistRepo.update(merged)
                updated += 1
            } else {
                let newPlaylist = PlaylistRecord(
                    id: remoteID,
                    name: ckRecord["name"] as? String ?? "Synced Playlist",
                    type: ckRecord["type"] as? String ?? "m3u",
                    url: ckRecord["url"] as? String ?? "",
                    username: ckRecord["username"] as? String,
                    epgURL: ckRecord["epgURL"] as? String,
                    refreshHrs: (ckRecord["refreshHrs"] as? NSNumber)?.intValue ?? 24,
                    isActive: (ckRecord["isActive"] as? NSNumber)?.intValue == 1,
                    sortOrder: (ckRecord["sortOrder"] as? NSNumber)?.intValue ?? 0
                )
                try? playlistRepo.create(newPlaylist)
                updated += 1
            }
        }
        return updated
    }

    // MARK: - Pull: Favorites

    public func pullFavorites() async throws -> Int {
        let query = CKQuery(recordType: "SDFavorite", predicate: NSPredicate(value: true))
        let results = try await database.fetchRecords(matching: query)

        var updated = 0
        for ckRecord in results {
            let channelID = ckRecord.recordID.recordName
            let isFavorite = (ckRecord["isFavorite"] as? NSNumber)?.intValue == 1

            if let local = try? channelRepo.get(id: channelID), local.isFavorite != isFavorite {
                try? channelRepo.setFavorite(id: channelID, isFavorite: isFavorite)
                updated += 1
            }
        }
        return updated
    }

    // MARK: - Pull: Watch Progress

    public func pullWatchProgress() async throws -> Int {
        let query = CKQuery(recordType: "SDWatchProgress", predicate: NSPredicate(value: true))
        let results = try await database.fetchRecords(matching: query)

        var updated = 0
        for ckRecord in results {
            let contentID = ckRecord.recordID.recordName
            let remoteUpdatedAt = (ckRecord["updatedAt"] as? NSNumber)?.intValue ?? 0

            // Last-write-wins: only update if remote is newer
            if let local = try? watchProgressRepo.get(contentID: contentID) {
                guard remoteUpdatedAt > local.updatedAt else { continue }
            }

            let record = WatchProgressRecord(
                contentID: contentID,
                playlistID: ckRecord["playlistID"] as? String,
                positionMs: (ckRecord["positionMs"] as? NSNumber)?.intValue ?? 0,
                durationMs: (ckRecord["durationMs"] as? NSNumber)?.intValue,
                updatedAt: remoteUpdatedAt
            )
            try? watchProgressRepo.upsert(record)
            updated += 1
        }
        return updated
    }

    // MARK: - Pull: Preferences

    public func pullPreferences() async throws -> Bool {
        let recordID = CKRecord.ID(recordName: "userPreferences")
        do {
            let ckRecord = try await database.record(for: recordID)
            let prefs = SyncablePreferences(
                preferredEngine: ckRecord["preferredEngine"] as? String ?? "auto",
                resumePlaybackEnabled: (ckRecord["resumePlaybackEnabled"] as? NSNumber)?.intValue == 1,
                bufferTimeoutSeconds: (ckRecord["bufferTimeoutSeconds"] as? NSNumber)?.intValue ?? 10,
                updatedAt: (ckRecord["updatedAt"] as? NSNumber)?.intValue ?? 0
            )
            // Store preferences in UserDefaults for the app to read
            let defaults = UserDefaults.standard
            defaults.set(prefs.preferredEngine, forKey: "preferredPlayerEngine")
            defaults.set(prefs.resumePlaybackEnabled ? "true" : "false", forKey: "resumePlaybackEnabled")
            defaults.set(String(prefs.bufferTimeoutSeconds), forKey: "bufferTimeoutSeconds")
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    // MARK: - Account Status

    public static func checkAccountStatus(
        container: CKContainer = CKContainer(identifier: "iCloud.net.lctechnology.StreamDeck")
    ) async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: - Device ID

    private static func getOrCreateDeviceID() -> String {
        let key = "cloudkit_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
