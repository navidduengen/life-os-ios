import Foundation
import LifeOSKit
import Observation
import UIKit

/// Unlock state of the vault apps for this device. The server decides: an
/// app counts as unlocked only after it accepted a Face ID signature, and a
/// 423 from any request locks it again here.
@MainActor
@Observable
final class VaultManager {
    private(set) var status: VaultStatus?
    private(set) var unlockedUntil: [String: Date] = [:]
    private(set) var isWorking = false
    var lastError: String?

    @ObservationIgnored var serviceProvider: () -> LifeOSService = { DemoService() }
    @ObservationIgnored var isDemo: () -> Bool = { false }

    private var service: LifeOSService { serviceProvider() }

    func isUnlocked(_ app: String) -> Bool {
        if let status, !status.enforced { return true }
        guard let until = unlockedUntil[app] else { return false }
        return until > Date()
    }

    /// Server state, and pairing right after sign-in while the server still allows it.
    func refresh() async {
        do {
            let status = try await service.vaultStatus()
            self.status = status
            unlockedUntil = Dictionary(uniqueKeysWithValues: status.apps.compactMap { app in
                app.unlocked ? app.expiresAt.map { (app.id, $0) } : nil
            })
            if !isDemo(), status.canPairDevice, status.deviceCredential == nil || !DeviceKey.exists {
                try await pair(deviceName: status.deviceCredential?.deviceName)
            }
        } catch {
            // Older servers have no vault endpoint; the apps then stay locked in the client.
        }
    }

    func unlock(_ apps: [String]? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            if isDemo() {
                try await DeviceKey.confirmPresence(reason: "Tresor-Bereiche entsperren")
                let until = try await service.unlockVault(challengeId: "demo", credentialId: "demo", signature: "demo")
                unlockedUntil.merge(until) { _, new in new }
                return
            }
            if status == nil { await refresh() }
            guard let credential = status?.deviceCredential, DeviceKey.exists else {
                lastError = status?.canPairDevice == true
                    ? "Das Gerät konnte nicht gekoppelt werden. Bitte erneut versuchen."
                    : "Dieses Gerät ist noch nicht gekoppelt. Melde dich ab und neu an, um es zu koppeln."
                return
            }
            let challenge = try await service.vaultChallenge(apps: apps)
            let signature = try await DeviceKey.sign(challenge.message, reason: "Tresor-Bereiche entsperren")
            let until = try await service.unlockVault(challengeId: challenge.id, credentialId: credential.id, signature: signature)
            unlockedUntil.merge(until) { _, new in new }
        } catch DeviceKey.Failure.cancelled {
            // user cancelled Face ID
        } catch DeviceKey.Failure.unavailable {
            lastError = "Face ID bzw. Touch ID ist auf diesem Gerät nicht verfügbar."
        } catch let error as APIError {
            lastError = error.message
        } catch {
            lastError = "Entsperren fehlgeschlagen. Bitte erneut versuchen."
        }
    }

    /// Locks everything, e.g. when the app goes to the background.
    func lockAll() async {
        guard !unlockedUntil.isEmpty else { return }
        unlockedUntil = [:]
        try? await service.lockVault(app: nil)
    }

    /// A request answered 423: the server no longer sees an unlock.
    func markLocked(_ app: String) {
        unlockedUntil[app] = nil
    }

    func reset() {
        status = nil
        unlockedUntil = [:]
        DeviceKey.delete()
    }

    private func pair(deviceName: String?) async throws {
        guard DeviceKey.isAvailable else { return }
        let publicKey = try DeviceKey.create()
        _ = try await service.registerVaultDeviceKey(publicKey: publicKey, deviceName: deviceName ?? UIDevice.current.name)
        status = try await service.vaultStatus()
    }
}
