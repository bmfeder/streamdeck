import Foundation

/// Result of a batch channel import via PowerSync.
/// Mirrors `ImportResult` in Repositories module.
public struct SyncImportResult: Equatable, Sendable {
    public let added: Int
    public let updated: Int
    public let softDeleted: Int
    public let unchanged: Int

    public init(added: Int, updated: Int, softDeleted: Int, unchanged: Int) {
        self.added = added
        self.updated = updated
        self.softDeleted = softDeleted
        self.unchanged = unchanged
    }
}

/// Result of a VOD batch import via PowerSync.
/// Mirrors `VodImportResult` in Repositories module.
public struct SyncVodImportResult: Equatable, Sendable {
    public let imported: Int

    public init(imported: Int) {
        self.imported = imported
    }
}
