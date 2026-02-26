import ComposableArchitecture
import Foundation
import Repositories

@Reducer
public struct AddPlaylistFeature {

    /// Which type of source the user is adding.
    public enum SourceType: String, CaseIterable, Equatable, Sendable {
        case m3u = "M3U Playlist"
        case xtream = "Xtream Codes"
        case emby = "Emby Server"
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var sourceType: SourceType
        public var m3uURL: String = ""
        public var m3uName: String = ""
        public var m3uEpgURL: String = ""
        public var xtreamServerURL: String = ""
        public var xtreamUsername: String = ""
        public var xtreamPassword: String = ""
        public var xtreamName: String = ""
        public var embyServerURL: String = ""
        public var embyUsername: String = ""
        public var embyPassword: String = ""
        public var embyName: String = ""
        public var isImporting: Bool = false
        public var importResult: ImportResultState? = nil
        public var errorMessage: String? = nil

        public var isFormValid: Bool {
            switch sourceType {
            case .m3u:
                let url = m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty, let parsed = URL(string: url) else { return false }
                return parsed.scheme == "http" || parsed.scheme == "https"
            case .xtream:
                let server = xtreamServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !server.isEmpty, let parsed = URL(string: server) else { return false }
                return (parsed.scheme == "http" || parsed.scheme == "https")
                    && !xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !xtreamPassword.isEmpty
            case .emby:
                let server = embyServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !server.isEmpty, let parsed = URL(string: server) else { return false }
                return (parsed.scheme == "http" || parsed.scheme == "https")
                    && !embyUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !embyPassword.isEmpty
            }
        }

        public init(sourceType: SourceType = .m3u) {
            self.sourceType = sourceType
        }
    }

    /// Snapshot of a successful import for display.
    public struct ImportResultState: Equatable, Sendable {
        public let playlistName: String
        public let channelsAdded: Int
        public let parseWarnings: Int
    }

    public enum Action: Sendable {
        case sourceTypeChanged(SourceType)
        case m3uURLChanged(String)
        case m3uNameChanged(String)
        case m3uEpgURLChanged(String)
        case xtreamServerURLChanged(String)
        case xtreamUsernameChanged(String)
        case xtreamPasswordChanged(String)
        case xtreamNameChanged(String)
        case embyServerURLChanged(String)
        case embyUsernameChanged(String)
        case embyPasswordChanged(String)
        case embyNameChanged(String)
        case importButtonTapped
        case importResponse(Result<PlaylistImportResult, Error>)
        case dismissTapped
        case dismissErrorTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case importCompleted(playlistID: String)
        }
    }

    @Dependency(\.playlistImportClient) var importClient
    @Dependency(\.dismiss) var dismiss

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .sourceTypeChanged(type):
                state.sourceType = type
                state.errorMessage = nil
                state.importResult = nil
                return .none

            case let .m3uURLChanged(url):
                state.m3uURL = url
                if state.m3uName.isEmpty,
                   let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    state.m3uName = parsed.host() ?? ""
                }
                return .none

            case let .m3uNameChanged(name):
                state.m3uName = name
                return .none

            case let .m3uEpgURLChanged(url):
                state.m3uEpgURL = url
                return .none

            case let .xtreamServerURLChanged(url):
                state.xtreamServerURL = url
                if state.xtreamName.isEmpty,
                   let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    state.xtreamName = parsed.host() ?? ""
                }
                return .none

            case let .xtreamUsernameChanged(username):
                state.xtreamUsername = username
                return .none

            case let .xtreamPasswordChanged(password):
                state.xtreamPassword = password
                return .none

            case let .xtreamNameChanged(name):
                state.xtreamName = name
                return .none

            case let .embyServerURLChanged(url):
                state.embyServerURL = url
                if state.embyName.isEmpty,
                   let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    state.embyName = parsed.host() ?? ""
                }
                return .none

            case let .embyUsernameChanged(username):
                state.embyUsername = username
                return .none

            case let .embyPasswordChanged(password):
                state.embyPassword = password
                return .none

            case let .embyNameChanged(name):
                state.embyName = name
                return .none

            case .importButtonTapped:
                guard state.isFormValid, !state.isImporting else { return .none }
                state.isImporting = true
                state.errorMessage = nil
                state.importResult = nil

                let client = importClient
                switch state.sourceType {
                case .m3u:
                    let urlString = state.m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = URL(string: urlString)!
                    let name = state.m3uName.isEmpty ? (url.host() ?? "Playlist") : state.m3uName
                    let epgURLString = state.m3uEpgURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let epgURL = epgURLString.isEmpty ? nil : URL(string: epgURLString)

                    return .run { send in
                        let result = try await client.importM3U(url, name, epgURL)
                        await send(.importResponse(.success(result)))
                    } catch: { error, send in
                        await send(.importResponse(.failure(error)))
                    }

                case .xtream:
                    let serverURL = URL(string: state.xtreamServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
                    let username = state.xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = state.xtreamPassword
                    let name = state.xtreamName.isEmpty ? (serverURL.host() ?? "Xtream") : state.xtreamName

                    return .run { send in
                        let result = try await client.importXtream(serverURL, username, password, name)
                        await send(.importResponse(.success(result)))
                    } catch: { error, send in
                        await send(.importResponse(.failure(error)))
                    }

                case .emby:
                    let serverURL = URL(string: state.embyServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
                    let username = state.embyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = state.embyPassword
                    let name = state.embyName.isEmpty ? (serverURL.host() ?? "Emby") : state.embyName

                    return .run { send in
                        let result = try await client.importEmby(serverURL, username, password, name)
                        await send(.importResponse(.success(result)))
                    } catch: { error, send in
                        await send(.importResponse(.failure(error)))
                    }
                }

            case let .importResponse(.success(result)):
                state.isImporting = false
                state.importResult = ImportResultState(
                    playlistName: result.playlist.name,
                    channelsAdded: result.importResult.added,
                    parseWarnings: result.parseErrors.count
                )
                return .send(.delegate(.importCompleted(playlistID: result.playlist.id)))

            case let .importResponse(.failure(error)):
                state.isImporting = false
                state.errorMessage = Self.userFacingMessage(for: error)
                return .none

            case .dismissTapped:
                let dismissEffect = dismiss
                return .run { _ in await dismissEffect() }

            case .dismissErrorTapped:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        switch error {
        case PlaylistImportError.downloadFailed:
            return "Could not download the playlist. Check the URL and your internet connection."
        case PlaylistImportError.emptyPlaylist:
            return "The playlist contains no channels."
        case PlaylistImportError.authenticationFailed:
            return "Authentication failed. Check your username and password."
        case PlaylistImportError.accountExpired:
            return "This account has expired."
        case PlaylistImportError.networkError:
            return "Network error. Check your internet connection and try again."
        default:
            return "An unexpected error occurred. Please try again."
        }
    }
}

// MARK: - View

import SwiftUI

public struct AddPlaylistView: View {
    @Bindable var store: StoreOf<AddPlaylistFeature>

    public init(store: StoreOf<AddPlaylistFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source Type", selection: $store.sourceType.sending(\.sourceTypeChanged)) {
                        ForEach(AddPlaylistFeature.SourceType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch store.sourceType {
                case .m3u:
                    m3uFields
                case .xtream:
                    xtreamFields
                case .emby:
                    embyFields
                }

                Section {
                    Button {
                        store.send(.importButtonTapped)
                    } label: {
                        if store.isImporting {
                            ProgressView()
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(!store.isFormValid || store.isImporting)
                }

                if let result = store.importResult {
                    Section("Import Complete") {
                        LabeledContent("Playlist", value: result.playlistName)
                        LabeledContent("Channels Added", value: "\(result.channelsAdded)")
                        if result.parseWarnings > 0 {
                            LabeledContent("Warnings", value: "\(result.parseWarnings)")
                        }
                    }
                }

                if let error = store.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                        Button("Dismiss") {
                            store.send(.dismissErrorTapped)
                        }
                    }
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.dismissTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isImporting {
                        ProgressView()
                    } else {
                        Button("Import") { store.send(.importButtonTapped) }
                            .disabled(!store.isFormValid)
                    }
                }
            }
        }
    }

    private var m3uFields: some View {
        Section("M3U Playlist") {
            TextField("Playlist URL", text: $store.m3uURL.sending(\.m3uURLChanged))
                .textContentType(.URL)
                .autocorrectionDisabled()
            TextField("Name (optional)", text: $store.m3uName.sending(\.m3uNameChanged))
            TextField("EPG URL (optional)", text: $store.m3uEpgURL.sending(\.m3uEpgURLChanged))
                .textContentType(.URL)
                .autocorrectionDisabled()
        }
    }

    private var xtreamFields: some View {
        Section("Xtream Codes") {
            TextField("Server URL", text: $store.xtreamServerURL.sending(\.xtreamServerURLChanged))
                .textContentType(.URL)
                .autocorrectionDisabled()
            TextField("Username", text: $store.xtreamUsername.sending(\.xtreamUsernameChanged))
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField("Password", text: $store.xtreamPassword.sending(\.xtreamPasswordChanged))
            TextField("Name (optional)", text: $store.xtreamName.sending(\.xtreamNameChanged))
        }
    }

    private var embyFields: some View {
        Section("Emby Server") {
            TextField("Server URL", text: $store.embyServerURL.sending(\.embyServerURLChanged))
                .textContentType(.URL)
                .autocorrectionDisabled()
            TextField("Username", text: $store.embyUsername.sending(\.embyUsernameChanged))
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField("Password", text: $store.embyPassword.sending(\.embyPasswordChanged))
            TextField("Name (optional)", text: $store.embyName.sending(\.embyNameChanged))
        }
    }
}
