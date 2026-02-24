import Foundation
@testable import XtreamClient

/// Mock HTTP client that returns pre-configured responses for testing.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    /// Responses keyed by a string that must appear in the request URL.
    private var responses: [(matcher: String, data: Data, statusCode: Int)] = []

    /// All requests that were made, for verification.
    private(set) var requestsMade: [URLRequest] = []

    /// Error to throw on the next request.
    var errorToThrow: Error?

    func enqueue(for urlContaining: String, json: String, statusCode: Int = 200) {
        responses.append((urlContaining, Data(json.utf8), statusCode))
    }

    func enqueue(for urlContaining: String, data: Data, statusCode: Int = 200) {
        responses.append((urlContaining, data, statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestsMade.append(request)

        if let error = errorToThrow {
            throw error
        }

        let urlString = request.url?.absoluteString ?? ""
        for (index, entry) in responses.enumerated() {
            if urlString.contains(entry.matcher) {
                responses.remove(at: index)
                let httpResponse = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://mock.test")!,
                    statusCode: entry.statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (entry.data, httpResponse)
            }
        }

        // Default: 200 with empty JSON object
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://mock.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data("{}".utf8), httpResponse)
    }
}
