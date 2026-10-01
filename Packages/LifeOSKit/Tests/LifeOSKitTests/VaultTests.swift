import CryptoKit
import XCTest
@testable import LifeOSKit

final class VaultTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3_600)))
        return APIClient(baseURL: URL(string: "https://lifeos.example")!, tokens: tokens, session: URLSession(configuration: config))
    }

    func testChallengeMessageMatchesServer() {
        let challenge = VaultChallenge(id: "c1", challenge: "abc_-123", expiresIn: 120)
        XCTAssertEqual(String(decoding: challenge.message, as: UTF8.self), "lifeos-unlock:abc_-123")
    }

    func testStatusDecodesAndFindsTheDeviceKey() async throws {
        StubURLProtocol.replies["/api/v1/vault"] = [.init(status: 200, body: #"""
        {"data":{"enforced":true,"apps":[{"id":"health","unlocked":true,"expires_at":"2026-10-01T18:15:00+00:00"},{"id":"finance","unlocked":false,"expires_at":null}],
        "credentials":[{"id":"k1","kind":"device_key","device_name":"iPhone","created_at":"2026-10-01T18:00:00+00:00","last_used_at":null,"current_device":true}],
        "can_pair_device":false}}
        """#)]
        let status = try await makeClient().vaultStatus()
        XCTAssertTrue(status.enforced)
        XCTAssertEqual(status.apps.map(\.id), ["health", "finance"])
        XCTAssertNotNil(status.apps.first?.expiresAt)
        XCTAssertEqual(status.deviceCredential?.id, "k1")
        XCTAssertFalse(status.canPairDevice)
    }

    func testUnlockFlowAndLockedError() async throws {
        StubURLProtocol.replies["/api/v1/vault/device-key"] = [.init(status: 201, body: #"{"data":{"credential_id":"k1"}}"#)]
        StubURLProtocol.replies["/api/v1/vault/challenge"] = [.init(status: 200, body: #"{"data":{"id":"c1","challenge":"xyz","expires_in":120}}"#)]
        StubURLProtocol.replies["/api/v1/vault/unlock"] = [.init(status: 200, body: #"{"data":{"apps":{"health":"2026-10-01T18:15:00+00:00","finance":"2026-10-01T18:15:00+00:00"}}}"#)]
        StubURLProtocol.replies["/api/v1/vault/lock"] = [.init(status: 204, body: "")]
        StubURLProtocol.replies["/api/v1/finance/documents"] = [.init(status: 423, body: #"{"message":"Dieser Bereich ist gesperrt. Bitte entsperren.","code":"step_up_required","app":"finance"}"#)]

        let client = makeClient()
        let credential = try await client.registerVaultDeviceKey(publicKey: "BASE64", deviceName: "iPhone")
        XCTAssertEqual(credential, "k1")
        let challenge = try await client.vaultChallenge(apps: nil)
        XCTAssertEqual(challenge.id, "c1")
        let unlocked = try await client.unlockVault(challengeId: challenge.id, credentialId: credential, signature: "SIG")
        XCTAssertEqual(Set(unlocked.keys), ["health", "finance"])
        try await client.lockVault(app: nil)

        do {
            _ = try await client.financeDocuments()
            XCTFail("expected 423")
        } catch let error as APIError {
            XCTAssertEqual(error, .locked("Dieser Bereich ist gesperrt. Bitte entsperren."))
        }
    }

    /// The server expects the X9.63 point (65 bytes) and a DER signature over the message.
    func testKeyAndSignatureFormatsMatchTheServerContract() throws {
        let key = P256.Signing.PrivateKey()
        XCTAssertEqual(key.publicKey.x963Representation.count, 65)
        XCTAssertEqual(key.publicKey.x963Representation.first, 0x04)

        let message = VaultChallenge(id: "c", challenge: "abc", expiresIn: 1).message
        let signature = try key.signature(for: message)
        let der = signature.derRepresentation
        XCTAssertEqual(der.first, 0x30)
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: der)
        XCTAssertTrue(key.publicKey.isValidSignature(parsed, for: message))
    }
}
