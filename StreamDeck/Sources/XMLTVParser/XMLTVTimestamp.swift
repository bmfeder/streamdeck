import Foundation

/// Parses XMLTV timestamp strings to epoch seconds (UTC).
///
/// XMLTV format: `YYYYMMDDHHMMSS [+/-HHMM]`
/// Examples:
/// - `20240301120000 +0000`
/// - `20240301120000+0530`
/// - `20240301120000` (no offset, treated as UTC)
/// - `2024030112` (truncated, minutes/seconds zero-filled)
enum XMLTVTimestamp {

    /// Parse an XMLTV timestamp string to epoch seconds (UTC).
    /// Returns `nil` if the timestamp cannot be parsed.
    static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split into datetime part and optional timezone offset
        let (datetimePart, offsetSeconds) = splitDatetimeAndOffset(trimmed)

        guard datetimePart.count >= 8 else { return nil }
        let digits = Array(datetimePart.unicodeScalars)

        // Validate all characters are ASCII digits
        for scalar in digits {
            guard scalar.value >= 0x30 && scalar.value <= 0x39 else { return nil }
        }

        // Extract components with zero-fill for truncated timestamps
        guard let year = intFromScalars(digits, start: 0, count: 4),
              let month = intFromScalars(digits, start: 4, count: 2),
              year >= 1970, month >= 1, month <= 12 else {
            return nil
        }

        let day = intFromScalars(digits, start: 6, count: 2) ?? 1
        let hour = intFromScalars(digits, start: 8, count: 2) ?? 0
        let minute = intFromScalars(digits, start: 10, count: 2) ?? 0
        let second = intFromScalars(digits, start: 12, count: 2) ?? 0

        guard day >= 1, day <= 31, hour <= 23, minute <= 59, second <= 59 else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        guard let date = calendar.date(from: components) else { return nil }

        // Convert to epoch and apply timezone offset
        // The timestamp is in local time with the given offset, so subtract offset to get UTC
        return Int(date.timeIntervalSince1970) - offsetSeconds
    }

    // MARK: - Private Helpers

    /// Split a timestamp string into the datetime digits and timezone offset in seconds.
    /// Returns (datetimePart, offsetSeconds) where offsetSeconds defaults to 0 (UTC).
    private static func splitDatetimeAndOffset(_ input: String) -> (String, Int) {
        // Find + or - after position 8 (to avoid date digits)
        let scalars = Array(input.unicodeScalars)
        var splitIndex: Int?

        guard scalars.count > 8 else {
            let digits = String(String.UnicodeScalarView(scalars.prefix(while: {
                $0.value >= 0x30 && $0.value <= 0x39
            })))
            return (digits, 0)
        }

        for i in 8..<scalars.count {
            let c = scalars[i]
            if c == "+" || c == "-" {
                splitIndex = i
                break
            }
        }

        guard let idx = splitIndex else {
            // No offset found — strip any non-digit trailing chars and assume UTC
            let digits = String(input.unicodeScalars.prefix(while: {
                $0.value >= 0x30 && $0.value <= 0x39
            }))
            return (digits, 0)
        }

        let datetimePart = String(String.UnicodeScalarView(scalars[0..<idx]))
            .trimmingCharacters(in: .whitespaces)
        let offsetPart = String(String.UnicodeScalarView(scalars[idx...]))

        let offsetSeconds = parseOffset(offsetPart)
        return (datetimePart, offsetSeconds)
    }

    /// Parse a timezone offset string like "+0530" or "-0500" to seconds.
    private static func parseOffset(_ offset: String) -> Int {
        guard offset.count >= 5 else { return 0 }
        let scalars = Array(offset.unicodeScalars)

        let sign: Int = scalars[0] == "-" ? -1 : 1
        guard let hours = intFromScalars(Array(scalars[1...]), start: 0, count: 2),
              let minutes = intFromScalars(Array(scalars[1...]), start: 2, count: 2) else {
            return 0
        }

        return sign * (hours * 3600 + minutes * 60)
    }

    /// Extract an integer from a slice of unicode scalars.
    /// Returns nil if start + count exceeds the array bounds.
    private static func intFromScalars(_ scalars: [Unicode.Scalar], start: Int, count: Int) -> Int? {
        guard start + count <= scalars.count else { return nil }
        var result = 0
        for i in start..<(start + count) {
            let digit = Int(scalars[i].value) - 0x30
            guard digit >= 0 && digit <= 9 else { return nil }
            result = result * 10 + digit
        }
        return result
    }
}
