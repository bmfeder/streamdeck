import Foundation

/// Protocol enabling dependency injection for HTTP requests.
/// Production code uses URLSessionHTTPClient; tests use MockHTTPClient.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production implementation wrapping URLSession.
public struct URLSessionHTTPClient: HTTPClient, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamError.invalidResponse
        }
        return (data, httpResponse)
    }
}
