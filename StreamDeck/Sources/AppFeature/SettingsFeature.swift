import ComposableArchitecture
import SwiftUI

@Reducer
public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            }
        }
    }
}

public struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Sources") {
                    Label("Add Playlist", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                    Label("Add Xtream Login", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("Build", value: "1")
                }
            }
            .navigationTitle(Tab.settings.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
