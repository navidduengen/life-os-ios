import Foundation

/// `GET /api/v1/vault`: whether the server enforces the vault lock, which
/// vault apps are unlocked for this device, and whether it can pair a key.
public struct VaultStatus: Decodable, Equatable, Sendable {
    public struct AppState: Decodable, Equatable, Sendable {
        public let id: String
        public let unlocked: Bool
        public let expiresAt: Date?
    }

    public struct Credential: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let kind: String
        public let deviceName: String
        public let currentDevice: Bool
    }

    public let enforced: Bool
    public let apps: [AppState]
    public let credentials: [Credential]
    public let canPairDevice: Bool

    public init(enforced: Bool, apps: [AppState], credentials: [Credential], canPairDevice: Bool) {
        self.enforced = enforced
        self.apps = apps
        self.credentials = credentials
        self.canPairDevice = canPairDevice
    }

    /// The key paired on this device, if any.
    public var deviceCredential: Credential? {
        credentials.first { $0.currentDevice && $0.kind == "device_key" }
    }
}

extension VaultStatus.AppState {
    public init(id: String, unlocked: Bool, expiresAt: Date?) {
        self.id = id
        self.unlocked = unlocked
        self.expiresAt = expiresAt
    }
}

extension VaultStatus.Credential {
    public init(id: String, kind: String, deviceName: String, currentDevice: Bool) {
        self.id = id
        self.kind = kind
        self.deviceName = deviceName
        self.currentDevice = currentDevice
    }
}

/// `POST /api/v1/vault/challenge`: sign `VaultChallenge.message` with the device key.
public struct VaultChallenge: Decodable, Equatable, Sendable {
    public let id: String
    public let challenge: String
    public let expiresIn: Int

    public init(id: String, challenge: String, expiresIn: Int) {
        self.id = id
        self.challenge = challenge
        self.expiresIn = expiresIn
    }

    /// Exactly what the server verifies (`VaultLock::message`).
    public var message: Data { Data("lifeos-unlock:\(challenge)".utf8) }
}

/// A finance document (receipt, invoice, contract, other).
public struct FinanceDocument: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let counterparty: String?
    public let amount: Double?
    public let currency: String
    public let documentDate: String?
    public let originalFilename: String

    public var kindLabel: String {
        switch kind {
        case "receipt": "Quittung"
        case "invoice": "Rechnung"
        case "contract": "Vertrag"
        default: "Sonstiges"
        }
    }
}

/// A lab report as listed in Health › Bluttests.
public struct LabReport: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let labName: String?
    public let takenOn: String?
    public let status: String
    public let valuesCount: Int
    public let flaggedCount: Int
}
