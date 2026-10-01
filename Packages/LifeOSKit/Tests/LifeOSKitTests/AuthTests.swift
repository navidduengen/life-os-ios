import XCTest
@testable import LifeOSKit

final class AuthTests: XCTestCase {
    func testPKCEChallengeIsBase64URLSHA256() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ0kZDA2SWhWP4xxtUy5uDFQb2Pw6tu", state: "s")
        XCTAssertEqual(pkce.challenge, "iOYRj7SPs-SYxJeDe-U_F1wB0XTSCyrYu94g5mdE3rE")
    }

    func testRandomPKCEIsURLSafe() {
        let pkce = PKCE()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43, "RFC 7636 minimum length")
        XCTAssertNil(pkce.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(PKCE().verifier, pkce.verifier)
    }

    func testAuthorizeURLCarriesChallengeAndRedirect() throws {
        let auth = NativeAuth(baseURL: URL(string: "https://lifeos.example")!)
        let pkce = PKCE(verifier: "v", state: "abc")
        let url = auth.authorizeURL(pkce: pkce, deviceName: "iPhone von Navid")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.path, "/auth/native/authorize")
        XCTAssertEqual(items.first { $0.name == "redirect_uri" }?.value, "lifeos://auth/callback")
        XCTAssertEqual(items.first { $0.name == "code_challenge" }?.value, pkce.challenge)
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "abc")
    }

    func testCallbackValidation() throws {
        let auth = NativeAuth(baseURL: URL(string: "https://lifeos.example")!)
        let pkce = PKCE(verifier: "v", state: "abc")
        XCTAssertEqual(try auth.code(from: URL(string: "lifeos://auth/callback?code=123&state=abc")!, pkce: pkce), "123")
        XCTAssertThrowsError(try auth.code(from: URL(string: "lifeos://auth/callback?code=123&state=evil")!, pkce: pkce)) {
            XCTAssertEqual($0 as? NativeAuth.CallbackError, .stateMismatch)
        }
        XCTAssertThrowsError(try auth.code(from: URL(string: "lifeos://auth/callback?error=access_denied")!, pkce: pkce)) {
            XCTAssertEqual($0 as? NativeAuth.CallbackError, .denied("access_denied"))
        }
    }

    func testTokenRefreshWindow() {
        let now = Date()
        XCTAssertTrue(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(30)).needsRefresh(now: now))
        XCTAssertFalse(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(600)).needsRefresh(now: now))
    }
}
