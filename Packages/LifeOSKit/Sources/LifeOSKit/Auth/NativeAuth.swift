import Foundation

/// URLs and requests of the native login flow. The backend side does not
/// exist yet; the contract is described in `docs/backend-vertrag.md`.
///
/// 1. The app opens `authorizeURL` in `ASWebAuthenticationSession` (never in a
///    WebView). The server runs its normal login (WorkOS today, Pocket ID
///    after the cutover) and redirects to `lifeos://auth/callback?code=…&state=…`.
/// 2. The app exchanges the one-time code plus PKCE verifier for a token pair.
public struct NativeAuth: Sendable {
    public static let callbackScheme = "lifeos"
    public static let redirectURI = "lifeos://auth/callback"

    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func authorizeURL(pkce: PKCE, deviceName: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/native/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "device_name", value: deviceName),
        ]
        return components.url!
    }

    public enum CallbackError: Error, Equatable {
        case stateMismatch
        case missingCode
        case denied(String)
    }

    /// Validates the redirect and returns the one-time code.
    public func code(from callback: URL, pkce: PKCE) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw CallbackError.denied(error) }
        guard value("state") == pkce.state else { throw CallbackError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        return code
    }
}
