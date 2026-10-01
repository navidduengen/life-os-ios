import Foundation

/// `GET /api/v1/session` — the signed-in user.
public struct UserSession: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fullName: String?
    public let email: String
    public let roles: [String]
    public let onboardingCompleted: Bool

    public init(id: String, name: String, fullName: String?, email: String, roles: [String], onboardingCompleted: Bool) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.email = email
        self.roles = roles
        self.onboardingCompleted = onboardingCompleted
    }

    public var displayName: String { fullName ?? name }
}
