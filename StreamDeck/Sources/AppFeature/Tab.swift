import Foundation

/// The tabs available in the app sidebar.
public enum Tab: String, CaseIterable, Hashable, Sendable {
    case home
    case liveTV
    case guide
    case movies
    case tvShows
    case emby
    case favorites
    case settings

    public var title: String {
        switch self {
        case .home: "Home"
        case .liveTV: "Live TV"
        case .guide: "Guide"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .emby: "Emby"
        case .favorites: "Favorites"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "house"
        case .liveTV: "play.tv"
        case .guide: "calendar.day.timeline.left"
        case .movies: "film"
        case .tvShows: "tv"
        case .emby: "server.rack"
        case .favorites: "star"
        case .settings: "gearshape"
        }
    }

    public var emptyStateMessage: String {
        switch self {
        case .home: "Welcome to StreamDeck. Add a playlist source to get started."
        case .liveTV: "No channels yet. Add an M3U playlist or Xtream login."
        case .guide: "Guide data unavailable. Import EPG data from Settings to see program listings."
        case .movies: "No movies found. Add a source with VOD content."
        case .tvShows: "No TV shows found. Add a source with series content."
        case .emby: "No Emby server configured. Add your server in Settings."
        case .favorites: "No favorites yet. Long-press a channel to add it."
        case .settings: ""
        }
    }
}
