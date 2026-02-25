import Database
import Foundation
import XMLTVParser

public enum EpgConverter {

    public static func fromParsedProgram(
        _ parsed: ParsedProgram,
        id: String
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id,
            channelEpgID: parsed.channelID,
            title: parsed.title,
            description: parsed.description,
            startTime: parsed.startTimestamp,
            endTime: parsed.stopTimestamp,
            category: parsed.category,
            iconURL: parsed.iconURL?.absoluteString
        )
    }

    public static func fromParsedPrograms(
        _ programs: [ParsedProgram],
        uuidGenerator: () -> String = { UUID().uuidString }
    ) -> [EpgProgramRecord] {
        programs.map { fromParsedProgram($0, id: uuidGenerator()) }
    }
}
