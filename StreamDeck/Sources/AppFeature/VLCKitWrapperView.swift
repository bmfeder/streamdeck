#if os(tvOS) || os(iOS)
import SwiftUI
import VLCKitSPM

/// Wraps VLCMediaPlayer for tvOS/iOS playback of TS, MKV, AVI, RTSP, RTMP, and other formats
/// that AVPlayer cannot handle natively. Mirrors AVPlayerWrapperView's callback interface.
/// Focusable UIView subclass that intercepts Siri Remote presses on tvOS.
class VLCPlayerView: UIView {
    var onPlayPause: (() -> Void)?

    #if os(tvOS)
    override var canBecomeFocused: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .playPause {
                onPlayPause?()
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
    #endif
}

struct VLCKitWrapperView: UIViewRepresentable {
    let url: URL
    let initialSeekMs: Int?
    let playPauseToggleCount: Int
    let seekToggleCount: Int
    let seekTargetMs: Int?
    let onStatusChange: @Sendable (PlaybackStatus) -> Void
    let onError: @Sendable (PlayerError) -> Void
    let onTimeUpdate: @Sendable (Int, Int?) -> Void
    let onPlayPause: () -> Void

    init(
        url: URL,
        initialSeekMs: Int? = nil,
        playPauseToggleCount: Int = 0,
        seekToggleCount: Int = 0,
        seekTargetMs: Int? = nil,
        onStatusChange: @escaping @Sendable (PlaybackStatus) -> Void,
        onError: @escaping @Sendable (PlayerError) -> Void,
        onTimeUpdate: @escaping @Sendable (Int, Int?) -> Void = { _, _ in },
        onPlayPause: @escaping () -> Void = {}
    ) {
        self.url = url
        self.initialSeekMs = initialSeekMs
        self.playPauseToggleCount = playPauseToggleCount
        self.seekToggleCount = seekToggleCount
        self.seekTargetMs = seekTargetMs
        self.onStatusChange = onStatusChange
        self.onError = onError
        self.onTimeUpdate = onTimeUpdate
        self.onPlayPause = onPlayPause
    }

    func makeUIView(context: Context) -> VLCPlayerView {
        let view = VLCPlayerView()
        view.backgroundColor = .black
        view.onPlayPause = onPlayPause

        let player = VLCMediaPlayer()
        player.drawable = view
        player.delegate = context.coordinator
        context.coordinator.player = player
        context.coordinator.initialSeekMs = initialSeekMs
        context.coordinator.hasPerformedInitialSeek = false

        let media = VLCMedia(url: url)
        player.media = media
        player.play()

        return view
    }

    func updateUIView(_ view: VLCPlayerView, context: Context) {
        guard let player = context.coordinator.player else { return }
        // If the URL changed, replace the media
        if let currentURL = player.media?.url, currentURL != url {
            player.stop()
            let media = VLCMedia(url: url)
            player.media = media
            context.coordinator.initialSeekMs = initialSeekMs
            context.coordinator.hasPerformedInitialSeek = false
            player.play()
        }
        // Play/pause toggle
        if context.coordinator.lastPlayPauseToggle != playPauseToggleCount {
            context.coordinator.lastPlayPauseToggle = playPauseToggleCount
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        }
        // Seek
        if context.coordinator.lastSeekToggle != seekToggleCount, let targetMs = seekTargetMs {
            context.coordinator.lastSeekToggle = seekToggleCount
            player.time = VLCTime(int: Int32(targetMs))
        }
    }

    static func dismantleUIView(_ view: VLCPlayerView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatusChange: onStatusChange, onError: onError, onTimeUpdate: onTimeUpdate)
    }

    final class Coordinator: NSObject, @preconcurrency VLCMediaPlayerDelegate, Sendable {
        nonisolated(unsafe) var player: VLCMediaPlayer?
        nonisolated(unsafe) var initialSeekMs: Int?
        nonisolated(unsafe) var hasPerformedInitialSeek: Bool = false
        nonisolated(unsafe) var lastReportedTimeMs: Int = 0
        nonisolated(unsafe) var lastPlayPauseToggle: Int = 0
        nonisolated(unsafe) var lastSeekToggle: Int = 0

        let onStatusChange: @Sendable (PlaybackStatus) -> Void
        let onError: @Sendable (PlayerError) -> Void
        let onTimeUpdate: @Sendable (Int, Int?) -> Void

        init(
            onStatusChange: @escaping @Sendable (PlaybackStatus) -> Void,
            onError: @escaping @Sendable (PlayerError) -> Void,
            onTimeUpdate: @escaping @Sendable (Int, Int?) -> Void
        ) {
            self.onStatusChange = onStatusChange
            self.onError = onError
            self.onTimeUpdate = onTimeUpdate
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player else { return }
            switch player.state {
            case .stopped:
                break
            case .opening, .buffering:
                onStatusChange(.loading)
            case .playing:
                performInitialSeekIfNeeded()
                onStatusChange(.playing)
            case .paused:
                onStatusChange(.paused)
            case .ended:
                onStatusChange(.paused)
            case .error:
                onError(.unknown("VLCKit playback error"))
            case .esAdded:
                break
            @unknown default:
                break
            }
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player else { return }
            let positionMs = Int(player.time.intValue)
            let durationMs: Int?
            if let length = player.media?.length, length.intValue > 0 {
                durationMs = Int(length.intValue)
            } else {
                durationMs = nil
            }

            // Report time updates every ~500ms for scrubber responsiveness
            if abs(positionMs - lastReportedTimeMs) >= 500 {
                lastReportedTimeMs = positionMs
                onTimeUpdate(positionMs, durationMs)
            }
        }

        private func performInitialSeekIfNeeded() {
            guard !hasPerformedInitialSeek, let seekMs = initialSeekMs, seekMs > 0, let player else { return }
            hasPerformedInitialSeek = true
            player.time = VLCTime(int: Int32(seekMs))
        }

        func cleanup() {
            player?.stop()
            player?.delegate = nil
            player = nil
        }
    }
}
#endif
