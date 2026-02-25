import ComposableArchitecture
import Database
import Foundation
import Repositories

public struct EPGClient: Sendable {

    public var fetchNowPlaying: @Sendable (_ channelEpgID: String) async throws -> EpgProgramRecord?

    public var fetchNowPlayingBatch: @Sendable (_ channelEpgIDs: [String]) async throws -> [String: EpgProgramRecord]

    public var syncEPG: @Sendable (_ playlistID: String) async throws -> EpgImportResult

    public init(
        fetchNowPlaying: @escaping @Sendable (_ channelEpgID: String) async throws -> EpgProgramRecord?,
        fetchNowPlayingBatch: @escaping @Sendable (_ channelEpgIDs: [String]) async throws -> [String: EpgProgramRecord],
        syncEPG: @escaping @Sendable (_ playlistID: String) async throws -> EpgImportResult
    ) {
        self.fetchNowPlaying = fetchNowPlaying
        self.fetchNowPlayingBatch = fetchNowPlayingBatch
        self.syncEPG = syncEPG
    }
}

// MARK: - Dependency Registration

extension EPGClient: DependencyKey {
    public static var liveValue: EPGClient {
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let epgRepo = EpgRepository(dbManager: dbManager)
        let playlistRepo = PlaylistRepository(dbManager: dbManager)
        let service = EpgImportService(
            epgRepo: epgRepo,
            playlistRepo: playlistRepo
        )
        return EPGClient(
            fetchNowPlaying: { channelEpgID in
                let now = Int(Date().timeIntervalSince1970)
                return try epgRepo.getCurrentProgram(channelEpgID: channelEpgID, at: now)
            },
            fetchNowPlayingBatch: { channelEpgIDs in
                let now = Int(Date().timeIntervalSince1970)
                var result: [String: EpgProgramRecord] = [:]
                for epgID in channelEpgIDs {
                    if let program = try epgRepo.getCurrentProgram(channelEpgID: epgID, at: now) {
                        result[epgID] = program
                    }
                }
                return result
            },
            syncEPG: { playlistID in
                try await service.importEPG(playlistID: playlistID)
            }
        )
    }

    public static var testValue: EPGClient {
        EPGClient(
            fetchNowPlaying: unimplemented("EPGClient.fetchNowPlaying"),
            fetchNowPlayingBatch: unimplemented("EPGClient.fetchNowPlayingBatch"),
            syncEPG: unimplemented("EPGClient.syncEPG")
        )
    }

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("StreamDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("streamdeck.db").path
    }
}

extension DependencyValues {
    public var epgClient: EPGClient {
        get { self[EPGClient.self] }
        set { self[EPGClient.self] = newValue }
    }
}
