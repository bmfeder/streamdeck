#if os(tvOS) || os(iOS)
import AVKit
import CoreMedia
import SwiftUI

/// Wraps AVPlayerViewController for tvOS with standard transport controls and Siri Remote support.
struct AVPlayerWrapperView: UIViewControllerRepresentable {
    let url: URL
    let initialSeekMs: Int?
    let onStatusChange: @Sendable (PlaybackStatus) -> Void
    let onError: @Sendable (PlayerError) -> Void
    let onTimeUpdate: @Sendable (Int, Int?) -> Void

    init(
        url: URL,
        initialSeekMs: Int? = nil,
        onStatusChange: @escaping @Sendable (PlaybackStatus) -> Void,
        onError: @escaping @Sendable (PlayerError) -> Void,
        onTimeUpdate: @escaping @Sendable (Int, Int?) -> Void = { _, _ in }
    ) {
        self.url = url
        self.initialSeekMs = initialSeekMs
        self.onStatusChange = onStatusChange
        self.onError = onError
        self.onTimeUpdate = onTimeUpdate
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        context.coordinator.player = player
        context.coordinator.initialSeekMs = initialSeekMs
        context.coordinator.hasPerformedInitialSeek = false
        context.coordinator.setupObservers(player: player)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // If the URL changed, replace the player item
        if let currentURL = (controller.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != url {
            context.coordinator.removeObservers()
            let player = AVPlayer(url: url)
            controller.player = player
            context.coordinator.player = player
            context.coordinator.initialSeekMs = initialSeekMs
            context.coordinator.hasPerformedInitialSeek = false
            context.coordinator.setupObservers(player: player)
            player.play()
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.removeObservers()
        controller.player?.pause()
        controller.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatusChange: onStatusChange, onError: onError, onTimeUpdate: onTimeUpdate)
    }

    final class Coordinator: NSObject, Sendable {
        nonisolated(unsafe) var player: AVPlayer?
        nonisolated(unsafe) var statusObservation: NSKeyValueObservation?
        nonisolated(unsafe) var timeControlObservation: NSKeyValueObservation?
        nonisolated(unsafe) var errorObservation: NSKeyValueObservation?
        nonisolated(unsafe) var periodicTimeObserver: Any?
        nonisolated(unsafe) var initialSeekMs: Int?
        nonisolated(unsafe) var hasPerformedInitialSeek: Bool = false

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

        func setupObservers(player: AVPlayer) {
            // Observe player item status
            statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.performInitialSeekIfNeeded()
                    self.onStatusChange(.loading)
                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown playback error"
                    self.onError(.unknown(message))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }

            // Observe time control status for play/pause/waiting
            timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.onStatusChange(.playing)
                case .paused:
                    // Only report paused if the item is ready (not failed/finished)
                    if player.currentItem?.status == .readyToPlay {
                        self.onStatusChange(.paused)
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.onStatusChange(.loading)
                @unknown default:
                    break
                }
            }

            // Observe item error
            errorObservation = player.currentItem?.observe(\.error, options: [.new]) { [weak self] item, _ in
                guard let self, let error = item.error else { return }
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    self.onError(.networkLost)
                } else {
                    self.onError(.unknown(error.localizedDescription))
                }
            }

            // Periodic time observer for progress tracking (every 10 seconds)
            let interval = CMTime(seconds: 10, preferredTimescale: 1)
            periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self, let player = self.player, let item = player.currentItem else { return }
                let positionMs = Int(time.seconds * 1000)
                let duration = item.duration
                let durationMs: Int? = duration.isValid && !duration.isIndefinite
                    ? Int(duration.seconds * 1000)
                    : nil
                self.onTimeUpdate(positionMs, durationMs)
            }
        }

        private func performInitialSeekIfNeeded() {
            guard !hasPerformedInitialSeek, let seekMs = initialSeekMs, seekMs > 0, let player else { return }
            hasPerformedInitialSeek = true
            let seekTime = CMTime(value: CMTimeValue(seekMs), timescale: 1000)
            player.seek(to: seekTime)
        }

        func removeObservers() {
            statusObservation?.invalidate()
            statusObservation = nil
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            errorObservation?.invalidate()
            errorObservation = nil
            if let observer = periodicTimeObserver, let player {
                player.removeTimeObserver(observer)
            }
            periodicTimeObserver = nil
            player = nil
        }
    }
}
#endif
