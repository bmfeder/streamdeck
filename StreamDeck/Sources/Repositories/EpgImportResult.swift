import Foundation

public struct EpgImportResult: Equatable, Sendable {
    public let programsImported: Int
    public let programsPurged: Int
    public let parseErrorCount: Int

    public init(programsImported: Int, programsPurged: Int, parseErrorCount: Int) {
        self.programsImported = programsImported
        self.programsPurged = programsPurged
        self.parseErrorCount = parseErrorCount
    }
}

public enum EpgImportError: Error, Equatable, Sendable {
    case downloadFailed(String)
    case networkError(String)
    case noEpgURL
}
