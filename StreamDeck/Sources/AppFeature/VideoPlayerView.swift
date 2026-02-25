import ComposableArchitecture
import Database
import SwiftUI

public struct VideoPlayerView: View {
    @Bindable var store: StoreOf<VideoPlayerFeature>

    public init(store: StoreOf<VideoPlayerFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            playerContent

            if store.isOverlayVisible {
                overlay
            }

            statusOverlay
        }
        .onAppear { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
        #if os(tvOS)
        .onPlayPauseCommand { store.send(.toggleOverlayTapped) }
        #endif
    }

    // MARK: - Player Content

    @ViewBuilder
    private var playerContent: some View {
        switch store.playerCommand {
        case let .play(url, engine):
            if engine == .avPlayer {
                #if os(tvOS) || os(iOS)
                AVPlayerWrapperView(
                    url: url,
                    onStatusChange: { status in
                        store.send(.playerStatusChanged(status))
                    },
                    onError: { error in
                        store.send(.playerEncounteredError(error))
                    }
                )
                .ignoresSafeArea()
                #else
                vlcPlaceholder
                #endif
            } else {
                vlcPlaceholder
            }
        case .stop, .none:
            EmptyView()
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
            HStack {
                Button {
                    store.send(.dismissTapped)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                if let engine = store.activeEngine {
                    Text(engine == .avPlayer ? "AVPlayer" : "VLCKit")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding()

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.item.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let group = store.item.groupName {
                        Text(group)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Status Overlay

    @ViewBuilder
    private var statusOverlay: some View {
        switch store.status {
        case .idle, .routing, .loading:
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

        case let .retrying(attempt, engine):
            retryingView(attempt: attempt, engine: engine)

        case .failed:
            failedView

        case let .error(error):
            errorView(error)

        case .playing, .paused:
            EmptyView()
        }
    }

    private func retryingView(attempt: Int, engine: PlayerEngine) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Reconnecting (\(attempt)/\(VideoPlayerFeature.State.maxRetriesPerEngine))...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Text(engine == .avPlayer ? "AVPlayer" : "VLCKit")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Playback Failed")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Unable to play this stream after multiple attempts.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Retry") {
                    store.send(.retryTapped)
                }
                .buttonStyle(.borderedProminent)
                Button("Close") {
                    store.send(.dismissTapped)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func errorView(_ error: PlayerError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text(errorMessage(for: error))
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Retry") {
                store.send(.retryTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func errorMessage(for error: PlayerError) -> String {
        switch error {
        case .streamUnavailable: return "Stream URL is not available."
        case .networkLost: return "Network connection lost."
        case .decodingFailed: return "Unable to decode this stream format."
        case let .unknown(msg): return msg
        }
    }

    // MARK: - VLC Placeholder

    private var vlcPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text("VLCKit playback coming soon")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
