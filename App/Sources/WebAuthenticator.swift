import AuthenticationServices
import UIKit

/// Runs the server login in the system sign-in sheet (ADR-031-004: never in
/// an embedded web view), so passkeys and password managers work.
@MainActor
final class WebAuthenticator {
    enum Failure: Error { case cancelled, noCallback }

    /// Kept alive for the duration of the login.
    private var current: ASWebAuthenticationSession?
    private var anchorProvider: AnchorProvider?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let provider = AnchorProvider(anchor: window ?? ASPresentationAnchor())
        anchorProvider = provider

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                Task { @MainActor in
                    self?.current = nil
                    self?.anchorProvider = nil
                }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: Failure.noCallback)
                }
            }
            session.presentationContextProvider = provider
            // Ephemeral: the server login cookie must not linger in Safari.
            session.prefersEphemeralWebBrowserSession = true
            current = session
            session.start()
        }
    }
}

/// Hands the sign-in sheet the window it should appear over.
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
