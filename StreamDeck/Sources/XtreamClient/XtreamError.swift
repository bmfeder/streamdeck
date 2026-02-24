import Foundation

/// Errors that can occur during Xtream API operations.
public enum XtreamError: Error, Equatable, Sendable {
    /// HTTP response was not an HTTPURLResponse.
    case invalidResponse
    /// Server returned a non-2xx status code.
    case httpError(statusCode: Int)
    /// Authentication failed (auth field is 0).
    case authenticationFailed
    /// Account has expired.
    case accountExpired
    /// Server returned data that could not be decoded.
    case decodingFailed(description: String)
    /// The server URL is malformed or cannot form a valid request.
    case invalidURL(String)
    /// Network-level error (timeout, no connection, etc.).
    case networkError(String)
}
