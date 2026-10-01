import XCTest
@testable import LifeOSKit

final class DocumentsTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3_600)))
        return APIClient(baseURL: URL(string: "https://lifeos.example")!, tokens: tokens, session: URLSession(configuration: config))
    }

    func testListDecodesDocumentsAppsAndSnippets() async throws {
        StubURLProtocol.replies["/api/v1/documents"] = [.init(status: 200, body: #"""
        {"data":[{"id":"d1","app":"finance","title":"Mietvertrag","resource_type":"pdf","document_type":"contract","status":"available","source":null,"links_count":2,
        "current_version":{"id":"v1","version_number":1,"role":"original","derived_from_version_id":null,"original_filename":"vertrag.pdf","mime_type":"application/pdf",
        "file_size_bytes":2048,"checksum_sha256":"abc","status":"available","created_at":"2026-10-01T10:00:00+00:00"},"created_at":"2026-10-01T10:00:00+00:00",
        "snippet":"…Kündigungsfrist…"}],
        "meta":{"apps":[{"id":"study","label":"Study Hub","locked":false},{"id":"health","label":"Health","locked":true}],"current_page":1,"last_page":1,"per_page":25,"total":1}}
        """#)]

        let list = try await makeClient().documents(app: "finance", query: "Kündigungsfrist")

        XCTAssertEqual(list.data.first?.title, "Mietvertrag")
        XCTAssertEqual(list.data.first?.linksCount, 2)
        XCTAssertEqual(list.data.first?.snippet, "…Kündigungsfrist…")
        XCTAssertEqual(list.data.first?.currentVersion?.isAvailable, true)
        XCTAssertEqual(list.meta.apps.map(\.locked), [false, true])
        let query = URLComponents(url: StubURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query, [URLQueryItem(name: "app", value: "finance"), URLQueryItem(name: "q", value: "Kündigungsfrist")])
    }

    func testFileURLComesBackAsSignedLink() async throws {
        StubURLProtocol.replies["/api/v1/documents/d1/versions/v1/file"] = [.init(status: 200, body: #"{"data":{"url":"https://r2.example/x.pdf?sig=1","expires_in":300}}"#)]

        let url = try await makeClient().documentFileURL(documentId: "d1", versionId: "v1")

        XCTAssertEqual(url.absoluteString, "https://r2.example/x.pdf?sig=1")
        XCTAssertEqual(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testLockedDocumentReportsTheApp() async {
        StubURLProtocol.replies["/api/v1/documents/d1/versions/v1/file"] = [.init(status: 423, body: #"{"message":"Gesperrt.","code":"step_up_required","app":"finance"}"#)]

        do {
            _ = try await makeClient().documentFileURL(documentId: "d1", versionId: "v1")
            XCTFail("expected locked")
        } catch APIError.locked(let app) {
            XCTAssertEqual(app, "finance")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testDemoSearchFiltersByText() async throws {
        let demo = DemoService()
        let all = try await demo.documents(app: nil, query: nil)
        let found = try await demo.documents(app: nil, query: "kündigung")
        XCTAssertEqual(all.data.count, 2)
        XCTAssertNil(all.data.first?.snippet)
        XCTAssertEqual(found.data.map(\.title), ["Mietvertrag"])
    }
}
