import ComposableArchitecture
import Foundation

/// TCA dependency that analyzes a stream URL and recommends a playback engine.
/// Uses URL extension → scheme → HEAD Content-Type → default (AVPlayer) strategy.
public struct StreamRouterClient: Sendable {
    public var route: @Sendable (_ url: URL) async -> StreamRoute

    public init(route: @escaping @Sendable (_ url: URL) async -> StreamRoute) {
        self.route = route
    }
}

// MARK: - Dependency Registration

extension StreamRouterClient: DependencyKey {
    public static var liveValue: StreamRouterClient {
        StreamRouterClient { url in
            // 1. Check URL extension
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "m3u8":
                return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "HLS stream (.m3u8)")
            case "m3u":
                return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "M3U playlist (.m3u)")
            case "mp4", "mov":
                return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "Native container (.\(ext))")
            case "ts":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MPEG-TS container (.ts)")
            case "mkv":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "Matroska container (.mkv)")
            case "avi":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "AVI container (.avi)")
            default:
                break
            }

            // 2. Check URL scheme
            let scheme = url.scheme?.lowercased() ?? ""
            switch scheme {
            case "rtsp":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "RTSP protocol")
            case "rtmp":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "RTMP protocol")
            case "mms":
                return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MMS protocol")
            default:
                break
            }

            // 3. Try HEAD request for Content-Type
            if let contentType = await headContentType(url: url) {
                let ct = contentType.lowercased()
                if ct.contains("mpegurl") || ct.contains("x-mpegurl") {
                    return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "Content-Type: HLS")
                }
                if ct.contains("mp4") || ct.contains("quicktime") {
                    return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "Content-Type: \(ct)")
                }
                if ct.contains("mp2t") || ct.contains("mpeg-ts") {
                    return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "Content-Type: MPEG-TS")
                }
                if ct.contains("matroska") || ct.contains("x-matroska") {
                    return StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "Content-Type: Matroska")
                }
            }

            // 4. Default to AVPlayer (handles most HTTP streams)
            return StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "Default (AVPlayer)")
        }
    }

    public static var testValue: StreamRouterClient {
        StreamRouterClient(
            route: unimplemented("StreamRouterClient.route")
        )
    }

    private static func headContentType(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        } catch {
            return nil
        }
    }
}

extension DependencyValues {
    public var streamRouterClient: StreamRouterClient {
        get { self[StreamRouterClient.self] }
        set { self[StreamRouterClient.self] = newValue }
    }
}
