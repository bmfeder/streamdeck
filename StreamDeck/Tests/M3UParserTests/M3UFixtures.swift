import Foundation

// MARK: - M3U Test Fixtures
// Real-world-inspired test playlists covering every edge case
// the parser will encounter in production.

enum M3UFixtures {

    // ──────────────────────────────────────────────────
    // 1. Standard well-formed playlist
    // ──────────────────────────────────────────────────
    static let standard = """
    #EXTM3U
    #EXTINF:-1 tvg-id="BBC1.uk" tvg-name="BBC One" tvg-logo="https://cdn.example.com/bbc1.png" group-title="UK Entertainment",BBC One HD
    http://stream.example.com/live/bbc1/index.m3u8
    #EXTINF:-1 tvg-id="CNN.us" tvg-name="CNN" tvg-logo="https://cdn.example.com/cnn.png" group-title="US News",CNN International
    http://stream.example.com/live/cnn/index.m3u8
    #EXTINF:-1 tvg-id="ESPN.us" tvg-name="ESPN" tvg-logo="https://cdn.example.com/espn.png" group-title="US Sports",ESPN HD
    http://stream.example.com/live/espn/index.m3u8
    """

    // ──────────────────────────────────────────────────
    // 2. UTF-8 BOM + Windows CRLF line endings
    // ──────────────────────────────────────────────────
    static let bomAndCRLF = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1 tvg-id=\"CH1\" group-title=\"Test\",Channel One\r\nhttp://stream.example.com/ch1\r\n#EXTINF:-1 tvg-id=\"CH2\" group-title=\"Test\",Channel Two\r\nhttp://stream.example.com/ch2\r\n"

    // ──────────────────────────────────────────────────
    // 3. Missing group-title on some entries
    // ──────────────────────────────────────────────────
    static let missingGroupTitle = """
    #EXTM3U
    #EXTINF:-1 tvg-id="BBC1",BBC One
    http://stream.example.com/bbc1
    #EXTINF:-1 group-title="News",CNN
    http://stream.example.com/cnn
    #EXTINF:-1,No Attributes Channel
    http://stream.example.com/noattr
    """

    // ──────────────────────────────────────────────────
    // 4. Non-standard tags mixed in (#EXTVLCOPT, #KODIPROP, etc.)
    // ──────────────────────────────────────────────────
    static let nonStandardTags = """
    #EXTM3U
    #EXTINF:-1 tvg-id="CH1" group-title="Mixed",Channel One
    #EXTVLCOPT:http-user-agent=Mozilla/5.0
    #EXTVLCOPT:http-referrer=http://example.com
    #KODIPROP:inputstreamaddon=inputstream.adaptive
    http://stream.example.com/ch1
    #EXTINF:-1 tvg-id="CH2" group-title="Mixed",Channel Two
    #EXTGRP:Sports
    http://stream.example.com/ch2
    """

    // ──────────────────────────────────────────────────
    // 5. Empty lines and whitespace scattered throughout
    // ──────────────────────────────────────────────────
    static let extraWhitespace = """
    #EXTM3U

        #EXTINF:-1 tvg-id="CH1" group-title="Test",Channel One

    http://stream.example.com/ch1

        #EXTINF:-1 tvg-id="CH2" group-title="Test",Channel Two

    http://stream.example.com/ch2

    """

    // ──────────────────────────────────────────────────
    // 6. Huge playlist simulation (5000+ entries built programmatically)
    // ──────────────────────────────────────────────────
    static func hugePlaylist(count: Int = 5000) -> String {
        var lines = ["#EXTM3U"]
        for i in 1...count {
            let group = ["Sports", "News", "Entertainment", "Kids", "Music"][i % 5]
            lines.append("#EXTINF:-1 tvg-id=\"CH\(i)\" tvg-name=\"Channel \(i)\" tvg-logo=\"https://cdn.example.com/\(i).png\" group-title=\"\(group)\",Channel \(i)")
            lines.append("http://stream.example.com/live/ch\(i)/stream.m3u8")
        }
        return lines.joined(separator: "\n")
    }

    // ──────────────────────────────────────────────────
    // 7. Totally broken — HTML error page instead of playlist
    // ──────────────────────────────────────────────────
    static let htmlErrorPage = """
    <!DOCTYPE html>
    <html>
    <head><title>403 Forbidden</title></head>
    <body>
    <h1>Forbidden</h1>
    <p>You don't have permission to access this resource.</p>
    </body>
    </html>
    """

    // ──────────────────────────────────────────────────
    // 8. Single-quoted attributes (some providers use these)
    // ──────────────────────────────────────────────────
    static let singleQuotedAttributes = """
    #EXTM3U
    #EXTINF:-1 tvg-id='BBC1' tvg-name='BBC One' tvg-logo='https://cdn.example.com/bbc1.png' group-title='UK TV',BBC One
    http://stream.example.com/bbc1
    #EXTINF:-1 tvg-id='ITV1' group-title='UK TV',ITV One
    http://stream.example.com/itv1
    """

    // ──────────────────────────────────────────────────
    // 9. Commas inside attribute values (common trap)
    // ──────────────────────────────────────────────────
    static let commasInAttributes = """
    #EXTM3U
    #EXTINF:-1 tvg-id="MOVIE1" group-title="Movies, Drama",The Good, The Bad and The Ugly
    http://stream.example.com/movie1
    #EXTINF:-1 tvg-id="MOVIE2" group-title="Action, Thriller",Die Hard
    http://stream.example.com/movie2
    """

    // ──────────────────────────────────────────────────
    // 10. URLs with tokens, query params, and special characters
    // ──────────────────────────────────────────────────
    static let complexURLs = """
    #EXTM3U
    #EXTINF:-1 tvg-id="CH1" group-title="Test",Token Stream
    http://cdn.example.com/live/stream.m3u8?token=abc123def456&expires=1709251200&sig=a1b2c3
    #EXTINF:-1 tvg-id="CH2" group-title="Test",Xtream URL
    http://provider.example.com:8080/live/username/password/12345.ts
    #EXTINF:-1 tvg-id="CH3" group-title="Test",HTTPS with Path
    https://secure.cdn.example.com/hls/channel_3/master.m3u8?key=xyz&quality=hd
    """

    // ──────────────────────────────────────────────────
    // 11. Mixed valid and invalid entries (real-world degradation)
    // ──────────────────────────────────────────────────
    static let mixedValidInvalid = """
    #EXTM3U
    #EXTINF:-1 tvg-id="OK1" group-title="Working",Good Channel 1
    http://stream.example.com/ok1
    #EXTINF:-1 tvg-id="BROKEN1" group-title="Working",Missing URL Channel
    #EXTINF:-1 tvg-id="OK2" group-title="Working",Good Channel 2
    http://stream.example.com/ok2
    not_a_url_at_all
    #EXTINF:-1 tvg-id="OK3" group-title="Working",Good Channel 3
    http://stream.example.com/ok3
    #EXTINF:GARBAGE_DURATION group-title="Bad",Malformed Duration
    http://stream.example.com/bad_dur
    http://stream.example.com/orphan
    """

    // ──────────────────────────────────────────────────
    // 12. Empty input
    // ──────────────────────────────────────────────────
    static let emptyString = ""

    // ──────────────────────────────────────────────────
    // 13. Just the header, no entries
    // ──────────────────────────────────────────────────
    static let headerOnly = "#EXTM3U\n"

    // ──────────────────────────────────────────────────
    // 14. Header with EPG URL metadata
    // ──────────────────────────────────────────────────
    static let headerWithEPG = """
    #EXTM3U x-tvg-url="http://epg.example.com/guide.xml" tvg-shift="0" catchup-source="http://catchup.example.com"
    #EXTINF:-1 tvg-id="CH1" group-title="Test",Channel One
    http://stream.example.com/ch1
    """

    // ──────────────────────────────────────────────────
    // 15. Channel numbers (tvg-chno and channel-number variants)
    // ──────────────────────────────────────────────────
    static let channelNumbers = """
    #EXTM3U
    #EXTINF:-1 tvg-id="BBC1" tvg-chno="101" group-title="UK",BBC One
    http://stream.example.com/bbc1
    #EXTINF:-1 tvg-id="BBC2" tvg-chno="102" group-title="UK",BBC Two
    http://stream.example.com/bbc2
    #EXTINF:-1 tvg-id="ITV" channel-number="103" group-title="UK",ITV
    http://stream.example.com/itv
    #EXTINF:-1 tvg-id="CH4" group-title="UK",Channel 4
    http://stream.example.com/ch4
    """

    // ──────────────────────────────────────────────────
    // 16. VOD entries with duration (not -1)
    // ──────────────────────────────────────────────────
    static let vodEntries = """
    #EXTM3U
    #EXTINF:7200 tvg-id="MOV1" group-title="Movies",The Matrix (1999)
    http://vod.example.com/movies/matrix.mp4
    #EXTINF:5400 tvg-id="MOV2" group-title="Movies",Inception (2010)
    http://vod.example.com/movies/inception.mkv
    #EXTINF:-1 tvg-id="LIVE1" group-title="Live",Live Stream
    http://stream.example.com/live1
    """

    // ──────────────────────────────────────────────────
    // 17. RTSP/RTMP/UDP protocols (not just HTTP)
    // ──────────────────────────────────────────────────
    static let alternativeProtocols = """
    #EXTM3U
    #EXTINF:-1 tvg-id="RTSP1" group-title="Cameras",Security Camera 1
    rtsp://192.168.1.100:554/live/stream1
    #EXTINF:-1 tvg-id="RTMP1" group-title="Live",RTMP Stream
    rtmp://live.example.com/app/stream_key
    #EXTINF:-1 tvg-id="UDP1" group-title="Multicast",UDP Multicast
    udp://@239.0.0.1:1234
    """

    // ──────────────────────────────────────────────────
    // 18. Unicode channel names (Arabic, Chinese, Cyrillic, emoji)
    // ──────────────────────────────────────────────────
    static let unicodeNames = """
    #EXTM3U
    #EXTINF:-1 tvg-id="AR1" group-title="العربية",الجزيرة
    http://stream.example.com/aljazeera
    #EXTINF:-1 tvg-id="CN1" group-title="中文",中央电视台
    http://stream.example.com/cctv
    #EXTINF:-1 tvg-id="RU1" group-title="Русский",Первый канал
    http://stream.example.com/perviy
    #EXTINF:-1 tvg-id="EM1" group-title="Fun",🔥 Fire TV 📺
    http://stream.example.com/fire
    """

    // ──────────────────────────────────────────────────
    // 19. Duplicate tvg-id values (common in the wild)
    // ──────────────────────────────────────────────────
    static let duplicateTvgIds = """
    #EXTM3U
    #EXTINF:-1 tvg-id="ESPN" group-title="Sports",ESPN HD
    http://stream.example.com/espn-hd
    #EXTINF:-1 tvg-id="ESPN" group-title="Sports",ESPN SD
    http://stream.example.com/espn-sd
    #EXTINF:-1 tvg-id="ESPN" group-title="Sports Backup",ESPN Backup
    http://stream.example.com/espn-backup
    """

    // ──────────────────────────────────────────────────
    // 20. No #EXTM3U header (some providers omit it)
    // ──────────────────────────────────────────────────
    static let noHeader = """
    #EXTINF:-1 tvg-id="CH1" group-title="Test",Channel One
    http://stream.example.com/ch1
    #EXTINF:-1 tvg-id="CH2" group-title="Test",Channel Two
    http://stream.example.com/ch2
    """
}
