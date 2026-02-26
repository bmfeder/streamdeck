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
        public var isValidating: Bool = false
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
        case addButtonTapped
        case validationResponse(Result<Void, Error>)
        case dismissTapped
        case dismissErrorTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case validationSucceeded(PlaylistImportParams)
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

            case .addButtonTapped:
                guard state.isFormValid, !state.isValidating else { return .none }
                state.isValidating = true
                state.errorMessage = nil

                let client = importClient
                switch state.sourceType {
                case .m3u:
                    let url = URL(string: state.m3uURL.trimmingCharacters(in: .whitespacesAndNewlines))!
                    return .run { send in
                        try await client.validateM3U(url)
                        await send(.validationResponse(.success(())))
                    } catch: { error, send in
                        await send(.validationResponse(.failure(error)))
                    }

                case .xtream:
                    let serverURL = URL(string: state.xtreamServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
                    let username = state.xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = state.xtreamPassword
                    return .run { send in
                        try await client.validateXtream(serverURL, username, password)
                        await send(.validationResponse(.success(())))
                    } catch: { error, send in
                        await send(.validationResponse(.failure(error)))
                    }

                case .emby:
                    let serverURL = URL(string: state.embyServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
                    let username = state.embyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = state.embyPassword
                    return .run { send in
                        try await client.validateEmby(serverURL, username, password)
                        await send(.validationResponse(.success(())))
                    } catch: { error, send in
                        await send(.validationResponse(.failure(error)))
                    }
                }

            case .validationResponse(.success):
                state.isValidating = false
                let params = Self.buildParams(from: state)
                let dismissEffect = dismiss
                return .merge(
                    .send(.delegate(.validationSucceeded(params))),
                    .run { _ in await dismissEffect() }
                )

            case let .validationResponse(.failure(error)):
                state.isValidating = false
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

    static func userFacingMessage(for error: Error) -> String {
        switch error {
        case PlaylistImportError.downloadFailed:
            return "Could not download the playlist. Check the URL and your internet connection."
        case PlaylistImportError.emptyPlaylist:
            return "The playlist contains no channels."
        case PlaylistImportError.authenticationFailed:
            return "Authentication failed. Check your username and password."
        case PlaylistImportError.accountExpired:
            return "This account has expired."
        case PlaylistImportError.networkError(let detail) where detail.contains("timed out"):
            return "Connection timed out. Check the server URL and try again."
        case PlaylistImportError.networkError:
            return "Network error. Check your internet connection and try again."
        default:
            return "An unexpected error occurred. Please try again."
        }
    }

    private static func buildParams(from state: State) -> PlaylistImportParams {
        switch state.sourceType {
        case .m3u:
            let url = URL(string: state.m3uURL.trimmingCharacters(in: .whitespacesAndNewlines))!
            let name = state.m3uName.isEmpty ? (url.host() ?? "Playlist") : state.m3uName
            let epgURLString = state.m3uEpgURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let epgURL = epgURLString.isEmpty ? nil : URL(string: epgURLString)
            return .m3u(url: url, name: name, epgURL: epgURL)
        case .xtream:
            let serverURL = URL(string: state.xtreamServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
            let username = state.xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = state.xtreamPassword
            let name = state.xtreamName.isEmpty ? (serverURL.host() ?? "Xtream") : state.xtreamName
            return .xtream(serverURL: serverURL, username: username, password: password, name: name)
        case .emby:
            let serverURL = URL(string: state.embyServerURL.trimmingCharacters(in: .whitespacesAndNewlines))!
            let username = state.embyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = state.embyPassword
            let name = state.embyName.isEmpty ? (serverURL.host() ?? "Emby") : state.embyName
            return .emby(serverURL: serverURL, username: username, password: password, name: name)
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

            if let error = store.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                    Button("Dismiss") {
                        store.send(.dismissErrorTapped)
                    }
                }
            }

            Section {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    HStack {
                        Spacer()
                        if store.isValidating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Validating...")
                            }
                        } else {
                            Text("Add")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!store.isFormValid || store.isValidating)

                Button(role: .cancel) {
                    store.send(.dismissTapped)
                } label: {
                    HStack {
                        Spacer()
                        Text("Cancel")
                        Spacer()
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
