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
        public var refreshingPlaylistID: String?
        public var preferences: UserPreferences = UserPreferences()
        @Presents public var addPlaylist: AddPlaylistFeature.State?

        // Edit playlist
        public var editingPlaylist: PlaylistRecord?
        public var editName: String = ""
        public var editEpgURL: String = ""
        public var editRefreshHrs: Int = 24

        // Clear watch history
        public var showClearHistoryConfirmation: Bool = false

        // CloudKit sync
        public var isCloudKitAvailable: Bool = false
        public var isSyncing: Bool = false
        public var lastSyncResult: SyncPullResult?

        // Background import tracking
        public var importingPlaylistIDs: Set<String> = []
        public var importErrors: [String: String] = [:]

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case playlistsLoaded(Result<[PlaylistRecord], Error>)
        case deletePlaylistTapped(PlaylistRecord)
        case deletePlaylistConfirmed
        case deletePlaylistCancelled
        case playlistDeleted(Result<String, Error>)
        case refreshPlaylistTapped(PlaylistRecord)
        case playlistRefreshed(Result<PlaylistImportResult, Error>)
        case addM3UTapped
        case addXtreamTapped
        case addEmbyTapped
        case addPlaylist(PresentationAction<AddPlaylistFeature.Action>)
        // Playback preferences
        case preferencesLoaded(UserPreferences)
        case preferredEngineChanged(PreferredPlayerEngine)
        case resumePlaybackToggled(Bool)
        case bufferTimeoutChanged(Int)
        // Edit playlist
        case editPlaylistTapped(PlaylistRecord)
        case editNameChanged(String)
        case editEpgURLChanged(String)
        case editRefreshHrsChanged(Int)
        case editPlaylistSaved
        case editPlaylistCancelled
        case playlistUpdated(Result<String, Error>)
        // Clear watch history
        case clearHistoryTapped
        case clearHistoryConfirmed
        case clearHistoryCancelled
        case historyCleared(Result<Void, Error>)
        // CloudKit sync
        case cloudKitStatusLoaded(Bool)
        case syncNowTapped
        case syncCompleted(Result<SyncPullResult, Error>)
        // Background import
        case backgroundImportStarted(playlistID: String)
        case backgroundImportCompleted(playlistID: String)
        case backgroundImportFailed(playlistID: String, error: String)
        case dismissImportError(playlistID: String)
    }

    @Dependency(\.epgClient) var epgClient
    @Dependency(\.vodListClient) var vodListClient
    @Dependency(\.playlistImportClient) var playlistImportClient
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.watchProgressClient) var watchProgressClient
    @Dependency(\.cloudKitSyncClient) var cloudKitSyncClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let defaults = userDefaultsClient
                let client = vodListClient
                let sync = cloudKitSyncClient
                let prefs = UserPreferences.load(from: defaults)
                return .merge(
                    .send(.preferencesLoaded(prefs)),
                    .run { send in
                        let playlists = try await client.fetchPlaylists()
                        await send(.playlistsLoaded(.success(playlists)))
                    } catch: { error, send in
                        await send(.playlistsLoaded(.failure(error)))
                    },
                    .run { send in
                        let available = await sync.isAvailable()
                        await send(.cloudKitStatusLoaded(available))
                    }
                )

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
                state.importingPlaylistIDs.remove(id)
                state.importErrors.removeValue(forKey: id)
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
                let sync = cloudKitSyncClient
                return .run { _ in
                    try? await sync.pushPlaylistDeletion(id)
                }

            case .playlistDeleted(.failure):
                return .none

            case let .refreshPlaylistTapped(playlist):
                guard state.refreshingPlaylistID == nil else { return .none }
                state.refreshingPlaylistID = playlist.id
                let client = playlistImportClient
                let id = playlist.id
                return .run { send in
                    let result = try await client.refreshPlaylist(id)
                    await send(.playlistRefreshed(.success(result)))
                } catch: { error, send in
                    await send(.playlistRefreshed(.failure(error)))
                }

            case .playlistRefreshed(.success):
                state.refreshingPlaylistID = nil
                let client = vodListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { _, _ in }

            case .playlistRefreshed(.failure):
                state.refreshingPlaylistID = nil
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

            case let .preferencesLoaded(prefs):
                state.preferences = prefs
                return .none

            case let .preferredEngineChanged(engine):
                state.preferences.preferredEngine = engine
                let defaults = userDefaultsClient
                state.preferences.save(to: defaults)
                return pushCurrentPreferences(state.preferences)

            case let .resumePlaybackToggled(enabled):
                state.preferences.resumePlaybackEnabled = enabled
                let defaults = userDefaultsClient
                state.preferences.save(to: defaults)
                return pushCurrentPreferences(state.preferences)

            case let .bufferTimeoutChanged(seconds):
                state.preferences.bufferTimeoutSeconds = seconds
                let defaults = userDefaultsClient
                state.preferences.save(to: defaults)
                return pushCurrentPreferences(state.preferences)

            // Edit playlist
            case let .editPlaylistTapped(playlist):
                state.editingPlaylist = playlist
                state.editName = playlist.name
                state.editEpgURL = playlist.epgURL ?? ""
                state.editRefreshHrs = playlist.refreshHrs
                return .none

            case let .editNameChanged(name):
                state.editName = name
                return .none

            case let .editEpgURLChanged(url):
                state.editEpgURL = url
                return .none

            case let .editRefreshHrsChanged(hrs):
                state.editRefreshHrs = hrs
                return .none

            case .editPlaylistSaved:
                guard var playlist = state.editingPlaylist else { return .none }
                let trimmedName = state.editName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return .none }
                playlist.name = trimmedName
                playlist.epgURL = state.editEpgURL.isEmpty ? nil : state.editEpgURL
                playlist.refreshHrs = state.editRefreshHrs
                state.editingPlaylist = nil
                let client = playlistImportClient
                let updatedPlaylist = playlist
                return .run { send in
                    try await client.updatePlaylist(updatedPlaylist)
                    await send(.playlistUpdated(.success(updatedPlaylist.id)))
                } catch: { error, send in
                    await send(.playlistUpdated(.failure(error)))
                }

            case .editPlaylistCancelled:
                state.editingPlaylist = nil
                return .none

            case .playlistUpdated(.success):
                let client = vodListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { _, _ in }

            case .playlistUpdated(.failure):
                return .none

            // Clear watch history
            case .clearHistoryTapped:
                state.showClearHistoryConfirmation = true
                return .none

            case .clearHistoryConfirmed:
                state.showClearHistoryConfirmation = false
                let client = watchProgressClient
                return .run { send in
                    try await client.clearAll()
                    await send(.historyCleared(.success(())))
                } catch: { error, send in
                    await send(.historyCleared(.failure(error)))
                }

            case .clearHistoryCancelled:
                state.showClearHistoryConfirmation = false
                return .none

            case .historyCleared:
                return .none

            // CloudKit sync
            case let .cloudKitStatusLoaded(available):
                state.isCloudKitAvailable = available
                return .none

            case .syncNowTapped:
                state.isSyncing = true
                let sync = cloudKitSyncClient
                return .run { send in
                    let result = try await sync.pullAll()
                    await send(.syncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.syncCompleted(.failure(error)))
                }

            case let .syncCompleted(.success(result)):
                state.isSyncing = false
                state.lastSyncResult = result
                return .none

            case .syncCompleted(.failure):
                state.isSyncing = false
                return .none

            // Background import — triggered by AddPlaylistFeature validation success
            case let .addPlaylist(.presented(.delegate(.validationSucceeded(params)))):
                let client = playlistImportClient
                let epg = epgClient
                let vod = vodListClient
                return .run { send in
                    let playlist = try await client.createPlaylist(params)
                    let playlistID = playlist.id

                    // Reload so the new playlist appears immediately
                    let playlists = try await vod.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                    await send(.backgroundImportStarted(playlistID: playlistID))

                    // Run the full import in background (reuses refreshPlaylist)
                    do {
                        _ = try await client.refreshPlaylist(playlistID)
                        await send(.backgroundImportCompleted(playlistID: playlistID))
                        _ = try? await epg.syncEPG(playlistID)
                        let updatedPlaylists = try await vod.fetchPlaylists()
                        await send(.playlistsLoaded(.success(updatedPlaylists)))
                    } catch {
                        await send(.backgroundImportFailed(
                            playlistID: playlistID,
                            error: AddPlaylistFeature.userFacingMessage(for: error)
                        ))
                    }
                } catch: { _, _ in }

            case .addPlaylist:
                return .none

            // Background import lifecycle
            case let .backgroundImportStarted(playlistID):
                state.importingPlaylistIDs.insert(playlistID)
                state.importErrors.removeValue(forKey: playlistID)
                return .none

            case let .backgroundImportCompleted(playlistID):
                state.importingPlaylistIDs.remove(playlistID)
                return .none

            case let .backgroundImportFailed(playlistID, error):
                state.importingPlaylistIDs.remove(playlistID)
                if state.playlists.contains(where: { $0.id == playlistID }) {
                    state.importErrors[playlistID] = error
                }
                return .none

            case let .dismissImportError(playlistID):
                state.importErrors.removeValue(forKey: playlistID)
                return .none
            }
        }
        .ifLet(\.$addPlaylist, action: \.addPlaylist) {
            AddPlaylistFeature()
        }
    }

    private func pushCurrentPreferences(_ prefs: UserPreferences) -> Effect<Action> {
        let sync = cloudKitSyncClient
        let syncablePrefs = SyncablePreferences(
            preferredEngine: prefs.preferredEngine.rawValue,
            resumePlaybackEnabled: prefs.resumePlaybackEnabled,
            bufferTimeoutSeconds: prefs.bufferTimeoutSeconds,
            updatedAt: Int(Date().timeIntervalSince1970)
        )
        return .run { _ in
            try? await sync.pushPreferences(syncablePrefs)
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
                            Button {
                                store.send(.editPlaylistTapped(playlist))
                            } label: {
                                playlistRow(playlist)
                            }
                            .buttonStyle(.plain)
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
                Section("Playback") {
                    Picker(
                        "Player Engine",
                        selection: $store.preferences.preferredEngine.sending(\.preferredEngineChanged)
                    ) {
                        ForEach(PreferredPlayerEngine.allCases, id: \.self) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    Toggle(
                        "Resume Playback",
                        isOn: $store.preferences.resumePlaybackEnabled.sending(\.resumePlaybackToggled)
                    )
                    Picker(
                        "Buffer Warning",
                        selection: $store.preferences.bufferTimeoutSeconds.sending(\.bufferTimeoutChanged)
                    ) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                    }
                }
                Section("Data") {
                    Button(role: .destructive) {
                        store.send(.clearHistoryTapped)
                    } label: {
                        Label("Clear Watch History", systemImage: "trash")
                    }
                }
                Section("iCloud Sync") {
                    HStack {
                        Image(systemName: store.isCloudKitAvailable ? "checkmark.icloud" : "xmark.icloud")
                            .foregroundStyle(store.isCloudKitAvailable ? .green : .secondary)
                        Text(store.isCloudKitAvailable ? "iCloud Available" : "iCloud Unavailable")
                    }
                    Button {
                        store.send(.syncNowTapped)
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if store.isSyncing {
                                ProgressView()
                                    #if os(tvOS)
                                    .scaleEffect(0.8)
                                    #endif
                            }
                        }
                    }
                    .disabled(!store.isCloudKitAvailable || store.isSyncing)
                    if let result = store.lastSyncResult {
                        Text("\(result.playlistsUpdated) playlists, \(result.favoritesUpdated) favorites, \(result.progressUpdated) progress synced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .alert(
                "Clear Watch History",
                isPresented: Binding(
                    get: { store.showClearHistoryConfirmation },
                    set: { if !$0 { store.send(.clearHistoryCancelled) } }
                )
            ) {
                Button("Clear", role: .destructive) {
                    store.send(.clearHistoryConfirmed)
                }
                Button("Cancel", role: .cancel) {
                    store.send(.clearHistoryCancelled)
                }
            } message: {
                Text("This will remove all watch progress and continue watching data. This cannot be undone.")
            }
            .sheet(
                isPresented: Binding(
                    get: { store.editingPlaylist != nil },
                    set: { if !$0 { store.send(.editPlaylistCancelled) } }
                )
            ) {
                editPlaylistSheet
            }
        }
    }

    // MARK: - Edit Playlist Sheet

    private var editPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(
                        "Playlist Name",
                        text: $store.editName.sending(\.editNameChanged)
                    )
                }
                Section("EPG Guide URL") {
                    TextField(
                        "https://example.com/epg.xml",
                        text: $store.editEpgURL.sending(\.editEpgURLChanged)
                    )
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    #endif
                }
                Section("Auto-Refresh") {
                    Picker(
                        "Refresh Interval",
                        selection: $store.editRefreshHrs.sending(\.editRefreshHrsChanged)
                    ) {
                        Text("Every hour").tag(1)
                        Text("Every 6 hours").tag(6)
                        Text("Every 12 hours").tag(12)
                        Text("Every 24 hours").tag(24)
                        Text("Every 48 hours").tag(48)
                        Text("Manual only").tag(0)
                    }
                }
            }
            .navigationTitle("Edit Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.send(.editPlaylistCancelled)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.send(.editPlaylistSaved)
                    }
                    .disabled(store.editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func playlistRow(_ playlist: PlaylistRecord) -> some View {
        let isRefreshing = store.refreshingPlaylistID == playlist.id
        let isImporting = store.importingPlaylistIDs.contains(playlist.id)
        let importError = store.importErrors[playlist.id]

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                if isImporting {
                    Text("Importing...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let error = importError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let lastSync = playlist.lastSync {
                    Text("Synced \(formattedDate(lastSync))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not yet synced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isImporting || isRefreshing {
                ProgressView()
                    #if os(tvOS)
                    .scaleEffect(0.8)
                    #endif
            } else if importError != nil {
                Button {
                    store.send(.dismissImportError(playlistID: playlist.id))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    store.send(.refreshPlaylistTapped(playlist))
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            Text(playlist.type.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(typeColor(playlist.type).opacity(0.15))
                .foregroundStyle(typeColor(playlist.type))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
