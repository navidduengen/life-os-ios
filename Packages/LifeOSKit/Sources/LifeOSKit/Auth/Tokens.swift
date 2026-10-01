import Foundation

/// Bearer token pair for native clients (ADR-031-004 §2: short-lived access
/// token plus rotating refresh token, named per device, revocable).
public struct TokenPair: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Refresh a little early so a request never starts with a token that
    /// expires in flight.
    public func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) < leeway
    }
}

/// Server response of the token and refresh endpoints.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    func pair(now: Date = Date()) -> TokenPair {
        TokenPair(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

public protocol TokenStore: AnyObject, Sendable {
    func load() -> TokenPair?
    func save(_ tokens: TokenPair?)
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: TokenPair?

    public init(_ tokens: TokenPair? = nil) { self.tokens = tokens }

    public func load() -> TokenPair? { lock.withLock { tokens } }
    public func save(_ tokens: TokenPair?) { lock.withLock { self.tokens = tokens } }
}
