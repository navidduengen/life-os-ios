import XCTest
@testable import LifeOSKit

/// Serves canned responses per path and records requests.
final class StubURLProtocol: URLProtocol {
    struct Reply { let status: Int; let body: String }

    nonisolated(unsafe) static var replies: [String: [Reply]] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() { replies = [:]; requests = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.append(request)
        let path = request.url!.path
        var queue = Self.replies[path] ?? []
        let reply = queue.isEmpty ? Reply(status: 404, body: #"{"message":"Nicht gefunden."}"#) : queue.removeFirst()
        Self.replies[path] = queue
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class APIClientTests: XCTestCase {
    private let sessionJSON = #"{"data":{"id":"u1","name":"Navid","full_name":null,"email":"n@example.com","roles":[],"onboarding_completed":true}}"#

    override func setUp() {
        StubURLProtocol.reset()
    }

    private func makeClient(tokens: TokenStore) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://lifeos.example")!, tokens: tokens, session: URLSession(configuration: config))
    }

    private func validTokens(_ access: String = "access-1") -> InMemoryTokenStore {
        InMemoryTokenStore(TokenPair(accessToken: access, refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(3_600)))
    }

    func testSendsBearerTokenAndDecodesEnvelope() async throws {
        StubURLProtocol.replies["/api/v1/session"] = [.init(status: 200, body: sessionJSON)]
        let user = try await makeClient(tokens: validTokens()).session()
        XCTAssertEqual(user.displayName, "Navid")
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testRefreshesOnceAfter401AndRetries() async throws {
        let tokens = validTokens()
        StubURLProtocol.replies["/api/v1/session"] = [
            .init(status: 401, body: #"{"message":"Unauthenticated."}"#),
            .init(status: 200, body: sessionJSON),
        ]
        StubURLProtocol.replies["/auth/native/refresh"] = [
            .init(status: 200, body: #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":900}"#),
        ]
        _ = try await makeClient(tokens: tokens).session()
        XCTAssertEqual(tokens.load()?.refreshToken, "refresh-2", "rotated refresh token is stored")
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testSignsOutWhenRefreshFails() async {
        let tokens = validTokens()
        StubURLProtocol.replies["/api/v1/session"] = [.init(status: 401, body: "{}")]
        StubURLProtocol.replies["/auth/native/refresh"] = [.init(status: 401, body: "{}")]
        do {
            _ = try await makeClient(tokens: tokens).session()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertNil(tokens.load())
    }

    func testRefreshesProactivelyWhenTokenIsAboutToExpire() async throws {
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "old", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(10)))
        StubURLProtocol.replies["/auth/native/refresh"] = [
            .init(status: 200, body: #"{"access_token":"fresh","refresh_token":"refresh-2","expires_in":900}"#),
        ]
        StubURLProtocol.replies["/api/v1/session"] = [.init(status: 200, body: sessionJSON)]
        _ = try await makeClient(tokens: tokens).session()
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, ["/auth/native/refresh", "/api/v1/session"])
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
    }

    func testMapsErrorStatuses() async {
        StubURLProtocol.replies["/api/v1/tasks/t1/transition"] = [
            .init(status: 422, body: #"{"message":"Ungültiger Übergang.","errors":{"status":["Nicht erlaubt."]}}"#),
        ]
        StubURLProtocol.replies["/api/v1/today"] = [
            .init(status: 423, body: #"{"message":"Bitte entsperren.","code":"step_up_required"}"#),
        ]
        let client = makeClient(tokens: validTokens())
        do {
            _ = try await client.transitionTask(id: "t1", to: .completed)
            XCTFail("expected validation error")
        } catch {
            XCTAssertEqual(error as? APIError, .validation(message: "Ungültiger Übergang.", errors: ["status": ["Nicht erlaubt."]]))
        }
        do {
            _ = try await client.today()
            XCTFail("expected locked")
        } catch {
            XCTAssertEqual(error as? APIError, .locked("Bitte entsperren."))
        }
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "PATCH")
    }

    func testSignOutRefreshesAnExpiredTokenBeforeRevoking() async {
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "expired", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(-60)))
        StubURLProtocol.replies["/auth/native/refresh"] = [
            .init(status: 200, body: #"{"access_token":"fresh","refresh_token":"refresh-2","expires_in":900}"#),
        ]
        StubURLProtocol.replies["/auth/native/token"] = [.init(status: 204, body: "")]
        await makeClient(tokens: tokens).signOut()
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, ["/auth/native/refresh", "/auth/native/token"])
        XCTAssertEqual(StubURLProtocol.requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
        XCTAssertNil(tokens.load())
    }

    func testExchangeStoresTokens() async throws {
        let tokens = InMemoryTokenStore()
        StubURLProtocol.replies["/auth/native/token"] = [
            .init(status: 200, body: #"{"access_token":"a","refresh_token":"r","expires_in":900}"#),
        ]
        try await makeClient(tokens: tokens).exchange(code: "c", pkce: PKCE(verifier: "v", state: "s"), deviceName: "iPhone")
        XCTAssertEqual(tokens.load()?.accessToken, "a")
        XCTAssertNil(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
}

final class PushClientTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3_600)))
        return APIClient(baseURL: URL(string: "https://lifeos.example")!, tokens: tokens, session: URLSession(configuration: config))
    }

    func testPushPreferencesKeepServerIDs() async throws {
        StubURLProtocol.replies["/api/v1/push/preferences"] = [.init(status: 200, body: #"{"data":{"tasks_due":true,"lab_report_ready":false}}"#)]
        let preferences = try await makeClient().pushPreferences()
        XCTAssertEqual(preferences, ["tasks_due": true, "lab_report_ready": false])
    }

    func testPushConfigAndDeviceRegistration() async throws {
        StubURLProtocol.replies["/api/v1/push/config"] = [.init(status: 200, body: #"{"data":{"enabled":false,"kinds":[{"id":"tasks_due","label":"Fällige Aufgaben"}]}}"#)]
        StubURLProtocol.replies["/api/v1/push/devices"] = [
            .init(status: 201, body: #"{"data":{"id":"d1","platform":"ios","environment":"sandbox","device_name":null,"last_seen_at":null}}"#),
            .init(status: 204, body: ""),
        ]
        let client = makeClient()
        let config = try await client.pushConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.kinds.first?.id, "tasks_due")

        try await client.registerPushDevice(PushDeviceRegistration(deviceToken: "ab", environment: .sandbox, deviceName: "iPhone"))
        try await client.unregisterPushDevice(token: "ab")
        XCTAssertEqual(StubURLProtocol.requests.map(\.httpMethod), ["GET", "POST", "DELETE"])
    }

    func testDeviceTokenHex() {
        XCTAssertEqual(PushDeviceRegistration.hex(Data([0x0A, 0xFF, 0x00])), "0aff00")
    }
}
