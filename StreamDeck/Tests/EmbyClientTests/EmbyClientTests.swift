import XCTest
@testable import EmbyClient
@testable import XtreamClient

final class EmbyClientTests: XCTestCase {

    private let serverURL = URL(string: "http://emby.local:8096")!

    private func makeClient(httpClient: EmbyMockHTTPClient) -> EmbyClient {
        EmbyClient(
            credentials: EmbyCredentials(
                serverURL: serverURL, username: "testuser", password: "testpass"
            ),
            httpClient: httpClient,
            deviceId: "test-device-id"
        )
    }

    // MARK: - Authentication

    func testAuthenticate_success_returnsUserAndToken() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "AuthenticateByName", json: EmbyFixtures.authResponse)
        let client = makeClient(httpClient: http)

        let result = try await client.authenticate()

        XCTAssertEqual(result.user.id, "user-123")
        XCTAssertEqual(result.user.name, "testuser")
        XCTAssertEqual(result.accessToken, "abc-token-xyz")
    }

    func testAuthenticate_sendsCorrectHeaders() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "AuthenticateByName", json: EmbyFixtures.authResponse)
        let client = makeClient(httpClient: http)

        _ = try await client.authenticate()

        let request = try XCTUnwrap(http.requestsMade.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let authHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Emby-Authorization"))
        XCTAssertTrue(authHeader.contains("Client=\"StreamDeck\""))
        XCTAssertTrue(authHeader.contains("DeviceId=\"test-device-id\""))
    }

    func testAuthenticate_sendsCorrectBody() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "AuthenticateByName", json: EmbyFixtures.authResponse)
        let client = makeClient(httpClient: http)

        _ = try await client.authenticate()

        let request = try XCTUnwrap(http.requestsMade.first)
        let body = try XCTUnwrap(request.httpBody)
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(dict["Username"], "testuser")
        XCTAssertEqual(dict["Pw"], "testpass")
    }

    func testAuthenticate_401_throwsAuthFailed() async {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "AuthenticateByName", json: "{}", statusCode: 401)
        let client = makeClient(httpClient: http)

        do {
            _ = try await client.authenticate()
            XCTFail("Expected EmbyError.authenticationFailed")
        } catch let error as EmbyError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticate_500_throwsHttpError() async {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "AuthenticateByName", json: "{}", statusCode: 500)
        let client = makeClient(httpClient: http)

        do {
            _ = try await client.authenticate()
            XCTFail("Expected EmbyError.httpError")
        } catch let error as EmbyError {
            XCTAssertEqual(error, .httpError(statusCode: 500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticate_networkError_throwsNetworkError() async {
        let http = EmbyMockHTTPClient()
        http.errorToThrow = URLError(.notConnectedToInternet)
        let client = makeClient(httpClient: http)

        do {
            _ = try await client.authenticate()
            XCTFail("Expected EmbyError.networkError")
        } catch let error as EmbyError {
            if case .networkError = error {} else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Libraries

    func testGetLibraries_parsesResponse() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Views", json: EmbyFixtures.librariesResponse)
        let client = makeClient(httpClient: http)

        let libraries = try await client.getLibraries(userId: "user-123", accessToken: "token")

        XCTAssertEqual(libraries.count, 3)
        XCTAssertEqual(libraries[0].name, "Movies")
        XCTAssertEqual(libraries[0].collectionType, "movies")
        XCTAssertEqual(libraries[1].name, "TV Shows")
        XCTAssertEqual(libraries[1].collectionType, "tvshows")
    }

    func testGetLibraries_sendsAuthHeader() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Views", json: EmbyFixtures.librariesResponse)
        let client = makeClient(httpClient: http)

        _ = try await client.getLibraries(userId: "user-123", accessToken: "my-token")

        let request = try XCTUnwrap(http.requestsMade.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "my-token")
    }

    func testGetLibraries_emptyList_returnsEmpty() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Views", json: EmbyFixtures.emptyLibrariesResponse)
        let client = makeClient(httpClient: http)

        let libraries = try await client.getLibraries(userId: "user-123", accessToken: "token")

        XCTAssertTrue(libraries.isEmpty)
    }

    // MARK: - Items

    func testGetItems_movies_parsesAllFields() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Items", json: EmbyFixtures.moviesResponse)
        let client = makeClient(httpClient: http)

        let response = try await client.getItems(
            userId: "user-123", accessToken: "token",
            parentId: "lib-1", includeItemTypes: "Movie"
        )

        XCTAssertEqual(response.totalRecordCount, 2)
        XCTAssertEqual(response.items.count, 2)

        let movie = response.items[0]
        XCTAssertEqual(movie.id, "movie-1")
        XCTAssertEqual(movie.name, "Inception")
        XCTAssertEqual(movie.type, "Movie")
        XCTAssertEqual(movie.overview, "A mind-bending thriller")
        XCTAssertEqual(movie.productionYear, 2010)
        XCTAssertEqual(movie.communityRating, 8.8)
        XCTAssertEqual(movie.imageTags?["Primary"], "tag-abc")
        XCTAssertEqual(movie.genreItems?.count, 2)
    }

    func testGetItems_paginated_sendsCorrectParams() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Items", json: EmbyFixtures.emptyItemsResponse)
        let client = makeClient(httpClient: http)

        _ = try await client.getItems(
            userId: "u1", accessToken: "tok",
            parentId: "lib-1", includeItemTypes: "Movie",
            startIndex: 50, limit: 25
        )

        let request = try XCTUnwrap(http.requestsMade.first)
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("StartIndex=50"))
        XCTAssertTrue(url.contains("Limit=25"))
        XCTAssertTrue(url.contains("ParentId=lib-1"))
        XCTAssertTrue(url.contains("IncludeItemTypes=Movie"))
    }

    func testGetItems_empty_returnsEmpty() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Items", json: EmbyFixtures.emptyItemsResponse)
        let client = makeClient(httpClient: http)

        let response = try await client.getItems(
            userId: "u1", accessToken: "tok",
            parentId: "lib-1", includeItemTypes: "Movie"
        )

        XCTAssertEqual(response.totalRecordCount, 0)
        XCTAssertTrue(response.items.isEmpty)
    }

    func testGetItem_withResumePosition() async throws {
        let http = EmbyMockHTTPClient()
        http.enqueue(for: "Items", json: EmbyFixtures.singleItemWithResume)
        let client = makeClient(httpClient: http)

        let item = try await client.getItem(userId: "u1", accessToken: "tok", itemId: "movie-1")

        XCTAssertEqual(item.id, "movie-1")
        XCTAssertEqual(item.userData?.playbackPositionTicks, 36000000000)
    }

    // MARK: - URL Builders

    func testImageURL_primaryWithTag() {
        let url = EmbyClient.imageURL(
            serverURL: serverURL, itemId: "movie-1",
            imageType: "Primary", tag: "tag-abc", maxWidth: 300
        )
        let str = url.absoluteString
        XCTAssertTrue(str.contains("Items/movie-1/Images/Primary"))
        XCTAssertTrue(str.contains("maxWidth=300"))
        XCTAssertTrue(str.contains("tag=tag-abc"))
    }

    func testImageURL_noTag() {
        let url = EmbyClient.imageURL(
            serverURL: serverURL, itemId: "movie-1",
            imageType: "Backdrop", tag: nil, maxWidth: 1280
        )
        let str = url.absoluteString
        XCTAssertTrue(str.contains("Images/Backdrop"))
        XCTAssertTrue(str.contains("maxWidth=1280"))
        XCTAssertFalse(str.contains("tag="))
    }

    func testDirectStreamURL_format() {
        let url = EmbyClient.directStreamURL(
            serverURL: serverURL, itemId: "movie-1", accessToken: "my-token"
        )
        let str = url.absoluteString
        XCTAssertTrue(str.contains("Videos/movie-1/stream"))
        XCTAssertTrue(str.contains("Static=true"))
        XCTAssertTrue(str.contains("api_key=my-token"))
    }
}
