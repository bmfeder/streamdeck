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

            // Transparent tap target — sits above the player but below overlays
            // so taps aren't swallowed by AVPlayerViewController's gesture recognizers
            #if os(iOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.send(.toggleOverlayTapped) }
            #endif

            if store.isOverlayVisible {
                overlay
            }

            statusOverlay

            if store.isSleepTimerPickerVisible {
                sleepTimerPicker
            }

            if store.isNumberEntryVisible {
                numberEntryOverlay
            }

            if store.isSwitcherVisible {
                switcherOverlay
            }
        }
        .onAppear { store.send(.onAppear) }
        // Note: cleanup is handled by dismissTapped (save progress + cancel timers).
        // Sending onDisappear from fullScreenCover causes a TCA ifLet warning
        // because the parent nils state before SwiftUI fires onDisappear.
        #if os(tvOS)
        .onPlayPauseCommand { store.send(.playPauseTapped) }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                if store.isLiveChannel && !store.isSwitcherVisible {
                    store.send(.showSwitcher)
                }
            case .up:
                if store.isSwitcherVisible {
                    store.send(.hideSwitcher)
                } else {
                    store.send(.toggleOverlayTapped)
                }
            default:
                break
            }
        }
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
                    initialSeekMs: store.resumePositionMs,
                    playPauseToggleCount: store.playPauseToggleCount,
                    seekToggleCount: store.seekToggleCount,
                    seekTargetMs: store.seekTargetMs,
                    onStatusChange: { status in
                        store.send(.playerStatusChanged(status))
                    },
                    onError: { error in
                        store.send(.playerEncounteredError(error))
                    },
                    onTimeUpdate: { positionMs, durationMs in
                        store.send(.timeUpdated(positionMs: positionMs, durationMs: durationMs))
                    },
                    onPlayPause: {
                        store.send(.playPauseTapped)
                    }
                )
                .ignoresSafeArea()
                #else
                vlcPlaceholder
                #endif
            } else {
                #if os(tvOS) || os(iOS)
                VLCKitWrapperView(
                    url: url,
                    initialSeekMs: store.resumePositionMs,
                    playPauseToggleCount: store.playPauseToggleCount,
                    seekToggleCount: store.seekToggleCount,
                    seekTargetMs: store.seekTargetMs,
                    onStatusChange: { status in
                        store.send(.playerStatusChanged(status))
                    },
                    onError: { error in
                        store.send(.playerEncounteredError(error))
                    },
                    onTimeUpdate: { positionMs, durationMs in
                        store.send(.timeUpdated(positionMs: positionMs, durationMs: durationMs))
                    },
                    onPlayPause: {
                        store.send(.playPauseTapped)
                    }
                )
                .ignoresSafeArea()
                #else
                vlcPlaceholder
                #endif
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
                        .font(.title)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                sleepTimerButton

                if let engine = store.activeEngine {
                    Text(engine == .avPlayer ? "AVPlayer" : "VLCKit")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding()

            Spacer()

            // Transport controls
            transportControls

            // Scrubber (VOD only — live channels have no duration)
            if !store.isLiveChannel, let duration = store.currentDurationMs, duration > 0 {
                scrubberBar(duration: duration)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

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

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button {
                store.send(.seekBackwardTapped)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                store.send(.playPauseTapped)
            } label: {
                Image(systemName: store.status == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                store.send(.seekForwardTapped)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Scrubber

    #if os(iOS)
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    #endif

    private func scrubberBar(duration: Int) -> some View {
        #if os(iOS)
        let position = isScrubbing ? scrubPosition : Double(store.currentPositionMs)
        #else
        let position = Double(store.currentPositionMs)
        #endif
        let durationDouble = Double(duration)

        return HStack(spacing: 12) {
            Text(formatTime(Int(position)))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)

            #if os(iOS)
            Slider(
                value: Binding(
                    get: { position },
                    set: { newValue in
                        scrubPosition = newValue
                    }
                ),
                in: 0...durationDouble
            ) { editing in
                isScrubbing = editing
                if !editing {
                    store.send(.scrubberSeeked(positionMs: Int(scrubPosition)))
                }
            }
            .tint(.white)
            #else
            // tvOS: visual-only progress bar (seek via ±10s buttons / Siri Remote)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: durationDouble > 0
                                ? geo.size.width * CGFloat(position / durationDouble)
                                : 0,
                            height: 8
                        )
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)
            #endif

            Text("-\(formatTime(max(0, duration - Int(position))))")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Status Overlay

    @ViewBuilder
    private var statusOverlay: some View {
        switch store.status {
        case .idle, .routing:
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
                .allowsHitTesting(false)

        case .loading:
            // Don't show spinner during brief re-buffering once playback has started
            if store.hasStartedPlaying && store.bufferingElapsedSeconds < 3 {
                EmptyView()
            } else {
                bufferingView
                    .allowsHitTesting(false)
            }

        case let .retrying(attempt, engine):
            retryingView(attempt: attempt, engine: engine)
                .allowsHitTesting(false)

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
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
            Text(engine == .avPlayer ? "AVPlayer" : "VLCKit")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text("Playback Failed")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Unable to play this stream after multiple attempts.")
                .font(.body)
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func errorView(_ error: PlayerError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text(errorMessage(for: error))
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Retry") {
                store.send(.retryTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial)
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

    // MARK: - Buffering View

    private var bufferingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            if store.bufferingElapsedSeconds >= store.bufferTimeoutSeconds {
                Text("Stream is slow...")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))

                if store.bufferingElapsedSeconds >= store.bufferTimeoutSeconds + 20 {
                    HStack(spacing: 16) {
                        Button("Retry") {
                            store.send(.retryTapped)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Try Other Player") {
                            store.send(.tryAlternateEngineTapped)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if store.bufferingElapsedSeconds > 0 {
                Text("\(store.bufferingElapsedSeconds)s")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Sleep Timer

    private var sleepTimerButton: some View {
        Button {
            store.send(.sleepTimerButtonTapped)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.sleepTimerEndDate != nil ? "moon.fill" : "moon.zzz")
                    .font(.caption)
                if let remaining = store.sleepTimerMinutesRemaining, remaining > 0 {
                    Text("\(remaining)m")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                store.sleepTimerEndDate != nil
                    ? Color.purple.opacity(0.6)
                    : Color.clear
            )
            .background(.regularMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }

    private var sleepTimerPicker: some View {
        VStack(spacing: 12) {
            Text("Sleep Timer")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach([15, 30, 60, 90], id: \.self) { minutes in
                Button {
                    store.send(.sleepTimerSelected(minutes: minutes))
                } label: {
                    Text("\(minutes) minutes")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if store.sleepTimerEndDate != nil {
                Button {
                    store.send(.sleepTimerSelected(minutes: nil))
                } label: {
                    Text("Turn Off")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 200)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button {
                store.send(.sleepTimerButtonTapped)
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Channel Number Entry

    private var numberEntryOverlay: some View {
        VStack(spacing: 16) {
            Text("Channel")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Text(store.numberEntryDigits.isEmpty ? "_" : store.numberEntryDigits)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 140)

            numberEntryStatusLine

            numberPad
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var numberEntryStatusLine: some View {
        switch store.numberEntryResult {
        case .searching:
            ProgressView()
                .tint(.white)
        case let .found(channel):
            Text("\(channel.name)\(channel.groupName.map { " (\($0))" } ?? "")")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .notFound:
            Text("No channel \(store.numberEntryDigits)")
                .font(.subheadline)
                .foregroundStyle(.red)
        case nil:
            Text("Enter channel number")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var numberPad: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        numberPadButton(String(digit))
                    }
                }
            }
            HStack(spacing: 8) {
                numberPadButton("", disabled: true)
                numberPadButton("0")
                Button {
                    store.send(.numberEntryCancelled)
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 44)
                        .background(Color.red.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func numberPadButton(_ digit: String, disabled: Bool = false) -> some View {
        Button {
            store.send(.numberDigitPressed(digit))
        } label: {
            Text(digit)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 52, height: 44)
                .background(Color.white.opacity(disabled ? 0.0 : 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Channel Switcher

    #if os(tvOS)
    private let switcherTileWidth: CGFloat = 160
    private let switcherTileHeight: CGFloat = 96
    #else
    private let switcherTileWidth: CGFloat = 100
    private let switcherTileHeight: CGFloat = 60
    #endif

    private var switcherOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                HStack {
                    Text("Now: \(store.item.name)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("Favorites")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 40)

                if store.switcherChannels.isEmpty {
                    Text("No favorite channels")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: switcherTileHeight)
                } else {
                    switcherChannelRow
                }
            }
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var switcherChannelRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(store.switcherChannels, id: \.id) { channel in
                    Button {
                        store.send(.switcherChannelSelected(channel))
                    } label: {
                        switcherTile(channel: channel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
        }
    }

    private func switcherTile(channel: ChannelRecord) -> some View {
        let isCurrent = channel.id == store.item.contentID
        let nowPlaying = store.switcherNowPlaying[channel.epgID ?? ""]
            ?? store.switcherNowPlaying[channel.tvgID ?? ""]
        return VStack(spacing: 4) {
            ZStack {
                Color.white.opacity(0.1)
                if let logoURLString = channel.logoURL,
                   let logoURL = URL(string: logoURLString) {
                    AsyncImage(url: logoURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "tv")
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                } else {
                    Image(systemName: "tv")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: switcherTileWidth, height: switcherTileHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(channel.name)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: switcherTileWidth)

            if let nowPlaying {
                Text(nowPlaying)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(width: switcherTileWidth)
            }
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
