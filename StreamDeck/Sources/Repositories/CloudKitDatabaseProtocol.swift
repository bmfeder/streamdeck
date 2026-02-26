import CloudKit
import Foundation

/// Protocol abstracting CloudKit database operations for testability.
/// Live implementation uses CKDatabase; tests use MockCloudKitDatabase.
public protocol CloudKitDatabaseProtocol: Sendable {
    func save(_ record: CKRecord) async throws -> CKRecord
    func record(for recordID: CKRecord.ID) async throws -> CKRecord
    func fetchRecords(matching query: CKQuery) async throws -> [CKRecord]
}

extension CKDatabase: CloudKitDatabaseProtocol {
    public func fetchRecords(matching query: CKQuery) async throws -> [CKRecord] {
        let (results, _) = try await self.records(matching: query)
        return results.compactMap { _, result in try? result.get() }
    }
}
