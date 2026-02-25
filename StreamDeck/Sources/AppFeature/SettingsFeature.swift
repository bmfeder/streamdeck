import ComposableArchitecture
import Repositories
import SwiftUI

@Reducer
public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        @Presents public var addPlaylist: AddPlaylistFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case addM3UTapped
        case addXtreamTapped
        case addEmbyTapped
        case addPlaylist(PresentationAction<AddPlaylistFeature.Action>)
    }

    @Dependency(\.epgClient) var epgClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
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
            case let .addPlaylist(.presented(.delegate(.importCompleted(playlistID: playlistID)))):
                let client = epgClient
                return .run { _ in
                    _ = try? await client.syncEPG(playlistID)
                }
            case .addPlaylist:
                return .none
            }
        }
        .ifLet(\.$addPlaylist, action: \.addPlaylist) {
            AddPlaylistFeature()
        }
    }
}

public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Sources") {
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
        }
    }
}
