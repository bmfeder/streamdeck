import Foundation
import GRDB

/// Manages the SQLite database lifecycle: creation, migrations, and access.
/// Thread-safe via GRDB's DatabaseQueue.
public final class DatabaseManager: Sendable {
    /// The underlying GRDB database queue for thread-safe access.
    public let dbQueue: DatabaseQueue

    /// Creates a file-backed database at the given path.
    /// Runs all pending migrations on init.
    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrate()
    }

    /// Creates an in-memory database (for tests).
    /// Runs all pending migrations on init.
    public init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerAll(in: &migrator)
        try migrator.migrate(dbQueue)
    }
}
