import Foundation

/// Errors that can occur during Emby API operations.
public enum EmbyError: Error, Equatable, Sendable {
    /// HTTP response was not an HTTPURLResponse.
    case invalidResponse
    /// Server returned a non-2xx status code.
    case httpError(statusCode: Int)
    /// Authentication failed (invalid credentials or 401).
    case authenticationFailed
    /// Server returned data that could not be decoded.
    case decodingFailed(description: String)
    /// The server URL is malformed or cannot form a valid request.
    case invalidURL(String)
    /// Network-level error (timeout, no connection, etc.).
    case networkError(String)
}
