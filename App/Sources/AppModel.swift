import Foundation
import LifeOSKit
import Observation
import UIKit

/// App-wide state: which backend we talk to, who is signed in, which apps
/// the server has enabled.
@MainActor
@Observable
final class AppModel {
    enum Phase { case launching, signedOut, signedIn }

    private(set) var phase: Phase = .launching
    private(set) var service: LifeOSService = DemoService()
    private(set) var user: UserSession?
    private(set) var modules: [AppModule] = []
    private(set) var isDemo = false
    var loginError: String?
    var isSigningIn = false

    var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Keys.serverURL) }
    }

    private let defaults = UserDefaults.standard
    private let tokens = KeychainTokenStore()
    private let authenticator = WebAuthenticator()

    private enum Keys {
        static let serverURL = "serverURL"
        static let demo = "demoMode"
    }

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Keys.serverURL) ?? "https://"
    }

    var serverURL: URL? {
        guard let url = URL(string: serverURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1",
              url.host != nil
        else { return nil }
        return url
    }

    /// Apps for the launcher (kind `app`), in web launcher order.
    var apps: [AppModule] {
        AppModuleCatalog.sorted(modules.filter { $0.kind == .app })
    }

    func start() async {
        guard phase == .launching else { return }
        if defaults.bool(forKey: Keys.demo) {
            await enterDemo()
        } else if let url = serverURL, tokens.load() != nil {
            service = makeClient(url)
            await loadAccount()
        } else {
            phase = .signedOut
        }
    }

    func enterDemo() async {
        isDemo = true
        defaults.set(true, forKey: Keys.demo)
        service = DemoService()
        await loadAccount()
    }

    func signIn() async {
        guard let url = serverURL else {
            loginError = "Bitte eine gültige https-Adresse deines Life OS eingeben."
            return
        }
        isSigningIn = true
        loginError = nil
        defer { isSigningIn = false }

        let client = makeClient(url)
        let pkce = PKCE()
        let auth = NativeAuth(baseURL: url)
        let deviceName = UIDevice.current.name
        do {
            let callback = try await authenticator.authenticate(url: auth.authorizeURL(pkce: pkce, deviceName: deviceName), callbackScheme: NativeAuth.callbackScheme)
            let code = try auth.code(from: callback, pkce: pkce)
            try await client.exchange(code: code, pkce: pkce, deviceName: deviceName)
            isDemo = false
            defaults.set(false, forKey: Keys.demo)
            service = client
            await loadAccount()
        } catch WebAuthenticator.Failure.cancelled {
            // User closed the sheet; stay on the login screen.
        } catch let error as APIError {
            loginError = error.message
        } catch {
            loginError = "Anmeldung fehlgeschlagen. Unterstützt dein Server schon den App-Login?"
        }
    }

    func signOut() async {
        await service.signOut()
        defaults.set(false, forKey: Keys.demo)
        isDemo = false
        user = nil
        modules = []
        service = DemoService()
        phase = .signedOut
    }

    private func loadAccount() async {
        do {
            async let user = service.session()
            async let modules = service.appModules()
            self.user = try await user
            self.modules = try await modules
            phase = .signedIn
        } catch {
            loginError = (error as? APIError)?.message ?? "Konto konnte nicht geladen werden."
            phase = .signedOut
        }
    }

    private func makeClient(_ url: URL) -> APIClient {
        let client = APIClient(baseURL: url, tokens: tokens)
        client.onSignedOut = { [weak self] in
            Task { @MainActor in self?.handleSessionExpired() }
        }
        return client
    }

    private func handleSessionExpired() {
        user = nil
        loginError = "Deine Sitzung ist abgelaufen. Bitte melde dich erneut an."
        phase = .signedOut
    }
}
