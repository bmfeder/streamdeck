import Database
import Foundation
import XMLTVParser
import XtreamClient

public struct EpgImportService: Sendable {

    private let epgRepo: EpgRepository
    private let playlistRepo: PlaylistRepository
    private let httpClient: HTTPClient
    private let uuidGenerator: @Sendable () -> String
    private let nowProvider: @Sendable () -> Int

    private static let retentionSeconds = 7 * 24 * 3600

    public init(
        epgRepo: EpgRepository,
        playlistRepo: PlaylistRepository,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        uuidGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        nowProvider: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
    ) {
        self.epgRepo = epgRepo
        self.playlistRepo = playlistRepo
        self.httpClient = httpClient
        self.uuidGenerator = uuidGenerator
        self.nowProvider = nowProvider
    }

    public func importEPG(playlistID: String) async throws -> EpgImportResult {
        guard let playlist = try playlistRepo.get(id: playlistID),
              let epgURLString = playlist.epgURL,
              let epgURL = URL(string: epgURLString) else {
            throw EpgImportError.noEpgURL
        }
        return try await importEPG(url: epgURL, playlistID: playlistID)
    }

    public func importEPG(url: URL, playlistID: String) async throws -> EpgImportResult {
        let request = URLRequest(url: url)
        let data: Data
        do {
            let (responseData, response) = try await httpClient.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                throw EpgImportError.downloadFailed("HTTP \(response.statusCode)")
            }
            data = responseData
        } catch let error as EpgImportError {
            throw error
        } catch {
            throw EpgImportError.networkError(error.localizedDescription)
        }

        return try persistEPGData(data, playlistID: playlistID)
    }

    public func persistEPGData(_ data: Data, playlistID: String) throws -> EpgImportResult {
        let parser = XMLTVParser()
        let parseResult = parser.parse(data: data)

        let uuidGen = uuidGenerator
        let records = EpgConverter.fromParsedPrograms(parseResult.programs) {
            uuidGen()
        }

        let imported = try epgRepo.importPrograms(records)

        let now = nowProvider()
        let purgeThreshold = now - Self.retentionSeconds
        let purged = try epgRepo.purgeOldPrograms(olderThan: purgeThreshold)

        try playlistRepo.updateEpgSyncTimestamp(playlistID, timestamp: now)

        return EpgImportResult(
            programsImported: imported,
            programsPurged: purged,
            parseErrorCount: parseResult.errorCount
        )
    }
}
