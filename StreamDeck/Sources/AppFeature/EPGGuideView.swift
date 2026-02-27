import ComposableArchitecture
import Database
import SwiftUI

public struct EPGGuideView: View {
    @Bindable var store: StoreOf<EPGGuideFeature>
    @FocusState private var focusedProgramID: String?
    @State private var scrollOffset: CGPoint = .zero

    public init(store: StoreOf<EPGGuideFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && !store.hasData {
                    loadingView
                } else if let error = store.errorMessage, !store.hasData {
                    errorView(error)
                } else if store.playlists.isEmpty {
                    emptyPlaylistView
                } else if !store.hasData && !store.isLoading {
                    emptyGuideView
                } else {
                    guideContent
                }
            }
            .navigationTitle(Tab.guide.title)
            .onAppear { store.send(.onAppear) }
            .refreshable { store.send(.refreshTapped) }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    store.send(.currentTimeTick)
                }
            }
            #if os(tvOS) || os(iOS)
            .fullScreenCover(
                item: $store.scope(state: \.videoPlayer, action: \.videoPlayer)
            ) { playerStore in
                VideoPlayerView(store: playerStore)
            }
            #else
            .sheet(
                item: $store.scope(state: \.videoPlayer, action: \.videoPlayer)
            ) { playerStore in
                VideoPlayerView(store: playerStore)
            }
            #endif
        }
    }

    // MARK: - Guide Content

    private var guideContent: some View {
        VStack(spacing: 0) {
            if store.playlists.count > 1 {
                playlistPicker
            }

            GeometryReader { outerGeometry in
                let gridWidth = EPGGuideLayout.totalWidth(
                    windowStart: store.windowStart,
                    windowEnd: store.windowEnd
                )

                ZStack(alignment: .topLeading) {
                    // Main scrollable grid
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Spacer for header height
                            Color.clear.frame(height: EPGGuideLayout.headerHeight)

                            // Channel rows
                            LazyVStack(spacing: 0) {
                                ForEach(store.channels, id: \.id) { channel in
                                    channelRow(channel, gridWidth: gridWidth)
                                }
                            }
                        }
                        .padding(.leading, EPGGuideLayout.sidebarWidth)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("guide")).origin
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "guide")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }

                    // Time header (fixed vertically, scrolls horizontally)
                    EPGTimeHeaderView(
                        windowStart: store.windowStart,
                        windowEnd: store.windowEnd,
                        currentTime: store.currentTime
                    )
                    .offset(x: scrollOffset.x + EPGGuideLayout.sidebarWidth)
                    .frame(height: EPGGuideLayout.headerHeight)
                    .background(.regularMaterial)
                    .zIndex(2)

                    // Channel sidebar (fixed horizontally, scrolls vertically)
                    EPGChannelSidebarView(channels: store.channels)
                        .offset(y: scrollOffset.y + EPGGuideLayout.headerHeight)
                        .frame(width: EPGGuideLayout.sidebarWidth)
                        .background(.regularMaterial)
                        .zIndex(2)

                    // Corner cell (top-left intersection)
                    Rectangle()
                        .fill(.regularMaterial)
                        .frame(
                            width: EPGGuideLayout.sidebarWidth,
                            height: EPGGuideLayout.headerHeight
                        )
                        .zIndex(3)

                    // "Now" marker
                    nowMarker
                        .offset(
                            x: EPGGuideLayout.sidebarWidth + scrollOffset.x
                                + EPGGuideLayout.xOffset(
                                    for: store.currentTime,
                                    relativeTo: store.windowStart
                                )
                        )
                        .zIndex(1)
                }
            }
        }
    }

    // MARK: - Channel Row

    private func channelRow(_ channel: ChannelRecord, gridWidth: CGFloat) -> some View {
        let epgID = channel.epgID ?? channel.tvgID ?? ""
        let programs = store.programsByChannel[epgID] ?? []

        return HStack(spacing: 1) {
            if programs.isEmpty {
                // Empty row placeholder
                Text("No program data")
                    .font(.system(size: EPGGuideLayout.subtitleFontSize))
                    .foregroundStyle(.tertiary)
                    .frame(width: gridWidth, height: EPGGuideLayout.rowHeight, alignment: .leading)
                    .padding(.leading, 16)
            } else {
                ForEach(programBlocks(programs, gridWidth: gridWidth), id: \.id) { block in
                    switch block {
                    case let .program(program, width):
                        Button {
                            store.send(.programTapped(program, channel))
                        } label: {
                            EPGProgramBlockView(
                                program: program,
                                isCurrent: store.currentTime >= program.startTime
                                    && store.currentTime < program.endTime,
                                width: width,
                                isFocused: focusedProgramID == program.id
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedProgramID, equals: program.id)

                    case let .gap(width):
                        Color.clear.frame(width: width, height: EPGGuideLayout.rowHeight)
                    }
                }
            }
        }
        .frame(height: EPGGuideLayout.rowHeight)
    }

    // MARK: - Program Block Layout

    private enum GridBlock: Identifiable {
        case program(EpgProgramRecord, width: CGFloat)
        case gap(width: CGFloat)

        var id: String {
            switch self {
            case let .program(p, _): return p.id
            case let .gap(w): return "gap-\(w)"
            }
        }
    }

    private func programBlocks(_ programs: [EpgProgramRecord], gridWidth: CGFloat) -> [GridBlock] {
        var blocks: [GridBlock] = []
        let windowStart = store.windowStart
        let windowEnd = store.windowEnd

        // Leading gap before first program
        if let first = programs.first {
            let clampedStart = max(first.startTime, windowStart)
            if clampedStart > windowStart {
                let gapWidth = EPGGuideLayout.xOffset(for: clampedStart, relativeTo: windowStart)
                if gapWidth > 0 {
                    blocks.append(.gap(width: gapWidth))
                }
            }
        }

        for (index, program) in programs.enumerated() {
            let width = EPGGuideLayout.blockWidth(
                startTime: program.startTime,
                endTime: program.endTime,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            blocks.append(.program(program, width: width))

            // Gap between programs
            if index < programs.count - 1 {
                let next = programs[index + 1]
                let gapSeconds = max(next.startTime, windowStart) - min(program.endTime, windowEnd)
                if gapSeconds > 0 {
                    let gapWidth = CGFloat(gapSeconds) / 60.0 * EPGGuideLayout.pointsPerMinute
                    blocks.append(.gap(width: gapWidth))
                }
            }
        }

        return blocks
    }

    // MARK: - Now Marker

    private var nowMarker: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2)
    }

    // MARK: - Playlist Picker

    private var playlistPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.playlists, id: \.id) { playlist in
                    Button {
                        store.send(.playlistSelected(playlist.id))
                    } label: {
                        Text(playlist.name)
                            .font(.body)
                            .fontWeight(store.selectedPlaylistID == playlist.id ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                store.selectedPlaylistID == playlist.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty / Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading guide...")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                store.send(.retryTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyPlaylistView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.guide.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.guide.title)
                .font(.title)
            Text(Tab.guide.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyGuideView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Guide data unavailable")
                .font(.headline)
            Text("Sync EPG data to see program listings.")
                .foregroundStyle(.secondary)
            Button("Retry") {
                store.send(.retryTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
