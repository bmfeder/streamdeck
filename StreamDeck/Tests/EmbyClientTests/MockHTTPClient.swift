import Foundation
@testable import XtreamClient

/// Mock HTTP client that returns pre-configured responses for testing.
final class EmbyMockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [(matcher: String, data: Data, statusCode: Int)] = []
    private(set) var requestsMade: [URLRequest] = []
    var errorToThrow: Error?

    func enqueue(for urlContaining: String, json: String, statusCode: Int = 200) {
        responses.append((urlContaining, Data(json.utf8), statusCode))
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

        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://mock.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data("{}".utf8), httpResponse)
    }
}
