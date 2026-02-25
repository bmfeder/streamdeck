#if os(tvOS) || os(iOS)
import AVKit
import SwiftUI

/// Wraps AVPlayerViewController for tvOS with standard transport controls and Siri Remote support.
struct AVPlayerWrapperView: UIViewControllerRepresentable {
    let url: URL
    let onStatusChange: @Sendable (PlaybackStatus) -> Void
    let onError: @Sendable (PlayerError) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        context.coordinator.player = player
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
        Coordinator(onStatusChange: onStatusChange, onError: onError)
    }

    final class Coordinator: NSObject, Sendable {
        nonisolated(unsafe) var player: AVPlayer?
        nonisolated(unsafe) var statusObservation: NSKeyValueObservation?
        nonisolated(unsafe) var timeControlObservation: NSKeyValueObservation?
        nonisolated(unsafe) var errorObservation: NSKeyValueObservation?

        let onStatusChange: @Sendable (PlaybackStatus) -> Void
        let onError: @Sendable (PlayerError) -> Void

        init(
            onStatusChange: @escaping @Sendable (PlaybackStatus) -> Void,
            onError: @escaping @Sendable (PlayerError) -> Void
        ) {
            self.onStatusChange = onStatusChange
            self.onError = onError
        }

        func setupObservers(player: AVPlayer) {
            // Observe player item status
            statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
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
        }

        func removeObservers() {
            statusObservation?.invalidate()
            statusObservation = nil
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            errorObservation?.invalidate()
            errorObservation = nil
            player = nil
        }
    }
}
#endif
