import Foundation

/// Parameters for creating a new playlist, passed from validation to background import.
public enum PlaylistImportParams: Equatable, Sendable {
    case m3u(url: URL, name: String, epgURL: URL?)
    case xtream(serverURL: URL, username: String, password: String, name: String)
    case emby(serverURL: URL, username: String, password: String, name: String)
}
