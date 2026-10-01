import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636, S256) for the native login.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        self.init(verifier: Self.randomURLSafe(byteCount: 32), state: Self.randomURLSafe(byteCount: 16))
    }

    public init(verifier: String, state: String) {
        self.verifier = verifier
        self.state = state
        self.challenge = Self.challenge(for: verifier)
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
