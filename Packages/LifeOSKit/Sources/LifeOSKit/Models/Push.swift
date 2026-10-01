import Foundation

/// `GET /api/v1/push/config`. `enabled` stays false until push is switched
/// on and the APNs key is configured on the server; the app hides every
/// push control until then.
public struct PushConfig: Decodable, Equatable, Sendable {
    public struct Kind: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
    }

    public let enabled: Bool
    public let kinds: [Kind]

    public init(enabled: Bool, kinds: [Kind] = []) {
        self.enabled = enabled
        self.kinds = kinds
    }

    public static let disabled = PushConfig(enabled: false)
}

public enum PushEnvironment: String, Encodable, Sendable {
    /// Builds run from Xcode.
    case sandbox
    /// TestFlight and App Store builds.
    case production
}

public struct PushDeviceRegistration: Encodable, Sendable {
    public let deviceToken: String
    public let environment: PushEnvironment
    public let deviceName: String?

    public init(deviceToken: String, environment: PushEnvironment, deviceName: String?) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.deviceName = deviceName
    }

    /// APNs hands out raw bytes; the server wants lowercase hex.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
