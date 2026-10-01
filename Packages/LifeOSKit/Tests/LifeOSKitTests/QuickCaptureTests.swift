import XCTest
@testable import LifeOSKit

final class QuickCaptureTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    func testNoteEncodesAsTipTapDocument() throws {
        let data = try LifeOSJSON.makeEncoder().encode(NewNote(title: "Idee", body: "Zeile 1\n\nZeile 3"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Idee")
        let doc = try XCTUnwrap(json["content_json"] as? [String: Any])
        XCTAssertEqual(doc["type"] as? String, "doc")
        let paragraphs = try XCTUnwrap(doc["content"] as? [[String: Any]])
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertNil(paragraphs[1]["content"], "an empty line is an empty paragraph")
        let text = try XCTUnwrap((paragraphs[0]["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(text["type"] as? String, "text")
        XCTAssertEqual(text["text"] as? String, "Zeile 1")
    }

    func testCreateNotePostsAndDecodes() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3_600)))
        let client = APIClient(baseURL: URL(string: "https://lifeos.example")!, tokens: tokens, session: URLSession(configuration: config))
        StubURLProtocol.replies["/api/v1/notes"] = [.init(status: 201, body: #"{"data":{"id":"n1","title":"Idee","body_text":"x","topics":[]}}"#)]

        let note = try await client.createNote(NewNote(title: "Idee", body: "x"))

        XCTAssertEqual(note.id, "n1")
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "POST")
    }
}
