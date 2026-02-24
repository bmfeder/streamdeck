import Foundation

// MARK: - M3U Parser

/// A lenient, production-grade M3U/M3U8 playlist parser.
///
/// Design principles:
/// - Never crashes on malformed input. Ever.
/// - Skips broken entries and keeps parsing (logs errors).
/// - Handles real-world edge cases: BOM, CRLF, encoding issues,
///   missing fields, non-standard tags, HTML error pages.
/// - Reports both successful parses and per-entry errors.
///
/// Usage:
/// ```swift
/// let parser = M3UParser()
/// let result = parser.parse(content: m3uString)
/// print("\(result.successCount) channels, \(result.errorCount) errors")
/// ```
public final class M3UParser: Sendable {

    public init() {}

    // MARK: - Public API

    /// Parse an M3U playlist from a string.
    public func parse(content: String) -> M3UParseResult {
        let cleaned = preprocess(content)
        let lines = cleaned.components(separatedBy: "\n")
        return parseLines(lines)
    }

    /// Parse an M3U playlist from raw data, auto-detecting encoding.
    public func parse(data: Data) -> M3UParseResult {
        let content = decodeData(data)
        return parse(content: content)
    }

    /// Parse from a local file URL.
    public func parse(fileURL: URL) throws -> M3UParseResult {
        let data = try Data(contentsOf: fileURL)
        return parse(data: data)
    }

    // MARK: - Preprocessing

    /// Clean raw input: strip BOM, normalize line endings, trim whitespace.
    private func preprocess(_ raw: String) -> String {
        var s = raw

        // Strip UTF-8 BOM (EF BB BF) — appears as \u{FEFF}
        if s.hasPrefix("\u{FEFF}") {
            s = String(s.dropFirst())
        }

        // Normalize line endings: \r\n → \n, stray \r → \n
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")

        return s
    }

    /// Auto-detect encoding from raw bytes. Tries UTF-8 first, then
    /// falls back to ISO-8859-1 (which accepts any byte sequence).
    private func decodeData(_ data: Data) -> String {
        // Strip BOM bytes if present
        var raw = data
        if raw.starts(with: [0xEF, 0xBB, 0xBF]) {
            raw = raw.dropFirst(3) as! Data
        }

        // Try UTF-8 first (most common)
        if let utf8 = String(data: raw, encoding: .utf8) {
            return utf8
        }

        // Fallback: ISO-8859-1 never fails
        return String(data: raw, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Line-by-Line Parsing

    private func parseLines(_ lines: [String]) -> M3UParseResult {
        var channels: [ParsedChannel] = []
        var errors: [M3UParseError] = []
        var metadata = PlaylistMetadata()

        // State machine
        var pendingExtinf: ExtinfData? = nil
        var pendingExtinfLine: Int = 0

        for (index, rawLine) in lines.enumerated() {
            let lineNum = index + 1 // 1-indexed for error reporting
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments (non-#EXTINF / #EXTM3U)
            if line.isEmpty { continue }

            // --- #EXTM3U header ---
            if line.uppercased().hasPrefix("#EXTM3U") {
                metadata = parseHeaderMetadata(line)
                continue
            }

            // --- #EXTINF line ---
            if line.uppercased().hasPrefix("#EXTINF:") || line.uppercased().hasPrefix("#EXTINF :") {
                // If we had a pending EXTINF without a URL, that's an error
                if let pending = pendingExtinf {
                    errors.append(M3UParseError(
                        line: pendingExtinfLine,
                        reason: .missingStreamURL,
                        rawText: pending.rawLine
                    ))
                }

                if let data = parseExtinfLine(line) {
                    pendingExtinf = data
                    pendingExtinfLine = lineNum
                } else {
                    errors.append(M3UParseError(
                        line: lineNum,
                        reason: .malformedExtinf,
                        rawText: line
                    ))
                    pendingExtinf = nil
                }
                continue
            }

            // --- Other # directives (skip but don't error) ---
            if line.hasPrefix("#") {
                // Known tags we silently skip: #EXTVLCOPT, #EXTGRP, #KODIPROP, etc.
                continue
            }

            // --- Stream URL line ---
            // Could be http(s), rtsp, rtmp, mms, or even a local path
            if looksLikeStreamURL(line) {
                guard let url = parseStreamURL(line) else {
                    errors.append(M3UParseError(
                        line: lineNum,
                        reason: .invalidURL,
                        rawText: line
                    ))
                    pendingExtinf = nil
                    continue
                }

                if let extinf = pendingExtinf {
                    let name = extinf.name.isEmpty ? url.lastPathComponent : extinf.name

                    if name.trimmingCharacters(in: .whitespaces).isEmpty {
                        errors.append(M3UParseError(
                            line: pendingExtinfLine,
                            reason: .emptyName,
                            rawText: extinf.rawLine
                        ))
                    }

                    let channel = ParsedChannel(
                        name: name,
                        streamURL: url,
                        groupTitle: extinf.attributes["group-title"],
                        tvgId: extinf.attributes["tvg-id"],
                        tvgName: extinf.attributes["tvg-name"],
                        tvgLogo: extinf.attributes["tvg-logo"].flatMap { URL(string: $0) },
                        tvgLanguage: extinf.attributes["tvg-language"],
                        channelNumber: extinf.attributes["tvg-chno"].flatMap { Int($0) }
                            ?? extinf.attributes["channel-number"].flatMap { Int($0) },
                        duration: extinf.duration,
                        extras: extinf.extraAttributes()
                    )
                    channels.append(channel)
                } else {
                    // URL without a preceding #EXTINF — still usable, just warn
                    let channel = ParsedChannel(
                        name: url.lastPathComponent,
                        streamURL: url
                    )
                    channels.append(channel)
                    errors.append(M3UParseError(
                        line: lineNum,
                        reason: .orphanedURL,
                        rawText: line
                    ))
                }

                pendingExtinf = nil
                continue
            }

            // If we get here, it's an unrecognized line — skip silently.
            // This handles HTML error pages, random text, etc.
        }

        // Handle trailing EXTINF with no URL
        if let pending = pendingExtinf {
            errors.append(M3UParseError(
                line: pendingExtinfLine,
                reason: .missingStreamURL,
                rawText: pending.rawLine
            ))
        }

        return M3UParseResult(
            channels: channels,
            errors: errors,
            metadata: metadata
        )
    }

    // MARK: - #EXTM3U Header Parsing

    private func parseHeaderMetadata(_ line: String) -> PlaylistMetadata {
        let attrs = parseAttributes(in: line)
        return PlaylistMetadata(
            urlTvg: attrs["x-tvg-url"] ?? attrs["url-tvg"],
            tvgShift: attrs["tvg-shift"],
            catchupSource: attrs["catchup-source"],
            hasExtM3UHeader: true
        )
    }

    // MARK: - #EXTINF Line Parsing

    /// Intermediate data from a parsed #EXTINF line, before we have the URL.
    private struct ExtinfData {
        let duration: Int
        let name: String
        let attributes: [String: String]
        let rawLine: String

        /// Return attributes that aren't part of the known set.
        func extraAttributes() -> [String: String] {
            let known: Set<String> = [
                "tvg-id", "tvg-name", "tvg-logo", "tvg-language",
                "tvg-chno", "channel-number", "group-title"
            ]
            return attributes.filter { !known.contains($0.key.lowercased()) }
        }
    }

    /// Parse a line like:
    /// `#EXTINF:-1 tvg-id="BBC1" tvg-logo="http://..." group-title="UK",BBC One HD`
    private func parseExtinfLine(_ line: String) -> ExtinfData? {
        // Strip the "#EXTINF:" prefix (case-insensitive, with optional space)
        guard let colonRange = line.range(of: ":", options: [], range: line.startIndex..<line.endIndex) else {
            return nil
        }
        let afterColon = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Extract duration (the number before the first space or comma)
        var duration: Int = -1
        var rest = afterColon

        // Duration is everything up to the first space or comma
        if let match = afterColon.firstMatch(of: /^(-?\d+)/) {
            duration = Int(match.1) ?? -1
            rest = String(afterColon[match.range.upperBound...])
        }

        // Parse attributes (key="value" pairs)
        let attributes = parseAttributes(in: rest)

        // Channel name is everything after the last comma (not inside quotes)
        let name = extractChannelName(from: rest)

        return ExtinfData(
            duration: duration,
            name: name,
            attributes: attributes,
            rawLine: line
        )
    }

    // MARK: - Attribute Parsing

    /// Extract key="value" pairs from a string. Handles:
    /// - Double-quoted values: `tvg-id="BBC.uk"`
    /// - Single-quoted values: `tvg-id='BBC.uk'`
    /// - Values with spaces, commas, special chars inside quotes
    /// - Case-insensitive keys (normalized to lowercase)
    private func parseAttributes(in text: String) -> [String: String] {
        var attrs: [String: String] = [:]

        // Regex: word-chars/hyphens = "quoted value" or 'quoted value'
        let pattern = /([a-zA-Z][a-zA-Z0-9_-]*)=["']([^"']*)["']/
        for match in text.matches(of: pattern) {
            let key = String(match.1).lowercased()
            let value = String(match.2)
            attrs[key] = value
        }

        return attrs
    }

    /// Extract the channel name — the text after the FIRST unquoted comma.
    /// In `tvg-id="MOVIE1" group-title="Movies, Drama",The Good, The Bad and The Ugly`
    /// → "The Good, The Bad and The Ugly"
    ///
    /// Uses the FIRST unquoted comma because that's the standard M3U delimiter
    /// between attributes and channel name. Channel names can contain commas.
    private func extractChannelName(from text: String) -> String {
        var inQuote: Character? = nil

        for i in text.indices {
            let ch = text[i]
            if inQuote != nil {
                if ch == inQuote {
                    inQuote = nil
                }
            } else {
                if ch == "\"" || ch == "'" {
                    inQuote = ch
                } else if ch == "," {
                    // First unquoted comma = name delimiter
                    let name = String(text[text.index(after: i)...])
                        .trimmingCharacters(in: .whitespaces)
                    return name
                }
            }
        }

        // No comma found — might be a malformed line, return empty
        return ""
    }

    // MARK: - URL Handling

    /// Check if a line looks like a stream URL (not a comment, not empty).
    private func looksLikeStreamURL(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let schemes = ["http://", "https://", "rtsp://", "rtmp://",
                       "mms://", "mmsh://", "rtp://", "udp://"]
        return schemes.contains(where: { lowered.hasPrefix($0) })
    }

    /// Parse and validate a stream URL string.
    /// Handles URLs with special characters, query params, tokens, etc.
    private func parseStreamURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct URL construction first
        if let url = URL(string: trimmed) {
            return url
        }

        // If that fails, try percent-encoding the parts that need it
        // (some providers have spaces or unicode in URLs)
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            return url
        }

        return nil
    }
}
