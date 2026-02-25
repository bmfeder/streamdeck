import ComposableArchitecture
import Database
import Repositories
import SwiftUI

@Reducer
public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var playlists: [PlaylistRecord] = []
        public var playlistToDelete: PlaylistRecord?
        @Presents public var addPlaylist: AddPlaylistFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case playlistsLoaded(Result<[PlaylistRecord], Error>)
        case deletePlaylistTapped(PlaylistRecord)
        case deletePlaylistConfirmed
        case deletePlaylistCancelled
        case playlistDeleted(Result<String, Error>)
        case addM3UTapped
        case addXtreamTapped
        case addEmbyTapped
        case addPlaylist(PresentationAction<AddPlaylistFeature.Action>)
    }

    @Dependency(\.epgClient) var epgClient
    @Dependency(\.vodListClient) var vodListClient
    @Dependency(\.playlistImportClient) var playlistImportClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let client = vodListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { error, send in
                    await send(.playlistsLoaded(.failure(error)))
                }

            case let .playlistsLoaded(.success(playlists)):
                state.playlists = playlists
                return .none

            case .playlistsLoaded(.failure):
                return .none

            case let .deletePlaylistTapped(playlist):
                state.playlistToDelete = playlist
                return .none

            case .deletePlaylistConfirmed:
                guard let playlist = state.playlistToDelete else { return .none }
                state.playlistToDelete = nil
                let id = playlist.id
                let client = playlistImportClient
                return .run { send in
                    try await client.deletePlaylist(id)
                    await send(.playlistDeleted(.success(id)))
                } catch: { error, send in
                    await send(.playlistDeleted(.failure(error)))
                }

            case .deletePlaylistCancelled:
                state.playlistToDelete = nil
                return .none

            case let .playlistDeleted(.success(id)):
                state.playlists.removeAll { $0.id == id }
                return .none

            case .playlistDeleted(.failure):
                return .none

            case .addM3UTapped:
                state.addPlaylist = AddPlaylistFeature.State(sourceType: .m3u)
                return .none
            case .addXtreamTapped:
                state.addPlaylist = AddPlaylistFeature.State(sourceType: .xtream)
                return .none
            case .addEmbyTapped:
                state.addPlaylist = AddPlaylistFeature.State(sourceType: .emby)
                return .none

            case .addPlaylist(.presented(.delegate(.importCompleted(playlistID: let playlistID)))):
                let epg = epgClient
                let vod = vodListClient
                return .merge(
                    .run { _ in
                        _ = try? await epg.syncEPG(playlistID)
                    },
                    .run { send in
                        let playlists = try await vod.fetchPlaylists()
                        await send(.playlistsLoaded(.success(playlists)))
                    } catch: { _, _ in }
                )

            case .addPlaylist:
                return .none
            }
        }
        .ifLet(\.$addPlaylist, action: \.addPlaylist) {
            AddPlaylistFeature()
        }
    }
}

// MARK: - View

public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                if !store.playlists.isEmpty {
                    Section("My Playlists") {
                        ForEach(store.playlists, id: \.id) { playlist in
                            playlistRow(playlist)
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                store.send(.deletePlaylistTapped(store.playlists[index]))
                            }
                        }
                    }
                }
                Section("Add Source") {
                    Button {
                        store.send(.addM3UTapped)
                    } label: {
                        Label("Add Playlist", systemImage: "plus.circle")
                    }
                    Button {
                        store.send(.addXtreamTapped)
                    } label: {
                        Label("Add Xtream Login", systemImage: "plus.circle")
                    }
                    Button {
                        store.send(.addEmbyTapped)
                    } label: {
                        Label("Add Emby Server", systemImage: "server.rack")
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("Build", value: "1")
                }
            }
            .navigationTitle(Tab.settings.title)
            .onAppear { store.send(.onAppear) }
            .sheet(item: $store.scope(state: \.addPlaylist, action: \.addPlaylist)) { addStore in
                AddPlaylistView(store: addStore)
            }
            .alert(
                "Delete Playlist",
                isPresented: Binding(
                    get: { store.playlistToDelete != nil },
                    set: { if !$0 { store.send(.deletePlaylistCancelled) } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    store.send(.deletePlaylistConfirmed)
                }
                Button("Cancel", role: .cancel) {
                    store.send(.deletePlaylistCancelled)
                }
            } message: {
                if let playlist = store.playlistToDelete {
                    Text("Delete \"\(playlist.name)\"? This will remove all channels and content from this source.")
                }
            }
        }
    }

    private func playlistRow(_ playlist: PlaylistRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                if let lastSync = playlist.lastSync {
                    Text("Synced \(formattedDate(lastSync))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(playlist.type.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(typeColor(playlist.type).opacity(0.15))
                .foregroundStyle(typeColor(playlist.type))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "m3u": .blue
        case "xtream": .orange
        case "emby": .purple
        default: .secondary
        }
    }

    private func formattedDate(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
