import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The Secure Enclave key that unlocks vault apps (ADR-031-004 §4). It can
/// only sign after Face ID / Touch ID of the currently enrolled biometrics;
/// the private key never leaves the Secure Enclave. The Keychain only keeps
/// its opaque handle.
enum DeviceKey {
    enum Failure: Error {
        case unavailable
        case cancelled
        case failed(String)
    }

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Creates a fresh key (replacing an old one) and returns its public point, base64 X9.63.
    static func create() throws -> String {
        guard isAvailable else { throw Failure.unavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw Failure.failed(error?.takeRetainedValue().localizedDescription ?? "Zugriffsschutz")
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        Keychain.save(key.dataRepresentation)
        return key.publicKey.x963Representation.base64EncodedString()
    }

    static var exists: Bool { Keychain.load() != nil }

    static func delete() { Keychain.save(nil) }

    /// Asks for Face ID / Touch ID and signs `message`; returns the DER signature, base64.
    static func sign(_ message: Data, reason: String) async throws -> String {
        guard let handle = Keychain.load() else { throw Failure.unavailable }
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw Failure.cancelled
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle, authenticationContext: context)
            return try key.signature(for: message).derRepresentation.base64EncodedString()
        } catch {
            // biometrics changed since pairing: the key is gone for good
            throw Failure.failed(error.localizedDescription)
        }
    }

    /// Only a local check, for the demo where there is no server key.
    static func confirmPresence(reason: String) async throws {
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw Failure.cancelled
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }

    private enum Keychain {
        static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.lifeos.ios.vault-key",
            kSecAttrAccount as String: "device-key",
        ]

        static func load() -> Data? {
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }

        static func save(_ data: Data?) {
            SecItemDelete(query as CFDictionary)
            guard let data else { return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
