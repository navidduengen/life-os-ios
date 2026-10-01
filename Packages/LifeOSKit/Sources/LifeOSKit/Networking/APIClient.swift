import Foundation

/// Bearer-token client for `/api/v1`. Refreshes the access token before it
/// expires and retries a request once after a `401`.
public final class APIClient: LifeOSService, @unchecked Sendable {
    public let baseURL: URL
    private let urlSession: URLSession
    private let tokens: TokenStore
    private let refresher: TokenRefresher
    private let decoder = LifeOSJSON.makeDecoder()
    private let encoder = LifeOSJSON.makeEncoder()
    private let timeZone: TimeZone

    /// Called after a refresh failed for good, so the app can show the login.
    public var onSignedOut: (@Sendable () -> Void)?

    public init(baseURL: URL, tokens: TokenStore, session: URLSession = .shared, timeZone: TimeZone = .current) {
        self.baseURL = baseURL
        self.urlSession = session
        self.tokens = tokens
        self.timeZone = timeZone
        self.refresher = TokenRefresher(baseURL: baseURL, tokens: tokens, session: session)
    }

    // MARK: - Login

    /// Exchanges the one-time code from the login redirect for a token pair.
    public func exchange(code: String, pkce: PKCE, deviceName: String) async throws {
        struct Body: Encodable { let code: String; let codeVerifier: String; let deviceName: String }
        let body = Body(code: code, codeVerifier: pkce.verifier, deviceName: deviceName)
        let request = try makeRequest("POST", "auth/native/token", body: body)
        let response: TokenResponse = try await send(request)
        tokens.save(response.pair())
    }

    public func signOut() async {
        if var request = try? makeRequest("DELETE", "auth/native/token", body: Optional<String>.none),
           let current = tokens.load() {
            request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        tokens.save(nil)
    }

    public var isSignedIn: Bool { tokens.load() != nil }

    // MARK: - LifeOSService

    public func session() async throws -> UserSession {
        try await get("session")
    }

    public func appModules() async throws -> [AppModule] {
        try await get("app-modules")
    }

    public func today() async throws -> TodayDashboard {
        try await get("today")
    }

    public func tasks(status: TaskStatus?, page: Int) async throws -> PaginatedEnvelope<LifeTask> {
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "timezone", value: timeZone.identifier)]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await authorized(makeRequest("GET", "tasks", query: query, body: Optional<String>.none))
    }

    public func createTask(_ task: NewTask) async throws -> LifeTask {
        try await authorizedData(makeRequest("POST", "tasks", body: task))
    }

    public func createNote(_ note: NewNote) async throws -> CreatedNote {
        try await authorizedData(makeRequest("POST", "notes", body: note))
    }

    public func transitionTask(id: String, to status: TaskStatus) async throws -> LifeTask {
        struct Body: Encodable { let status: TaskStatus }
        return try await authorizedData(makeRequest("PATCH", "tasks/\(id)/transition", body: Body(status: status)))
    }

    public func calendar(month: String) async throws -> CalendarResponse {
        try await authorized(makeRequest("GET", "calendar", query: [URLQueryItem(name: "month", value: month)], body: Optional<String>.none))
    }

    public func inbox() async throws -> InboxResponse {
        try await authorized(makeRequest("GET", "inbox", body: Optional<String>.none))
    }

    public func importHealth(_ batch: HealthImportBatch) async throws -> HealthImportResult {
        try await authorizedData(makeRequest("POST", "health/apple-health/import", body: batch))
    }

    public func deleteImportedHealth(type: String?) async throws -> Int {
        struct Deleted: Decodable { let deleted: Int }
        let query = type.map { [URLQueryItem(name: "type", value: $0)] } ?? []
        let result: Deleted = try await authorizedData(makeRequest("DELETE", "health/apple-health", query: query, body: Optional<String>.none))
        return result.deleted
    }

    public func pushConfig() async throws -> PushConfig {
        try await get("push/config")
    }

    public func registerPushDevice(_ registration: PushDeviceRegistration) async throws {
        struct Ignored: Decodable {}
        let _: DataEnvelope<Ignored> = try await authorized(makeRequest("POST", "push/devices", body: registration))
    }

    public func unregisterPushDevice(token: String) async throws {
        struct Body: Encodable { let deviceToken: String }
        try await authorizedNoContent(makeRequest("DELETE", "push/devices", body: Body(deviceToken: token)))
    }

    public func pushPreferences() async throws -> [String: Bool] {
        let raw: [String: Bool] = try await get("push/preferences")
        return Self.snakeCaseKeys(raw)
    }

    public func updatePushPreferences(_ preferences: [String: Bool]) async throws -> [String: Bool] {
        let raw: [String: Bool] = try await authorizedData(makeRequest("PATCH", "push/preferences", body: preferences))
        return Self.snakeCaseKeys(raw)
    }

    /// The decoder turns dictionary keys into camelCase (`tasks_due` →
    /// `tasksDue`); preference ids must stay as the server named them.
    static func snakeCaseKeys(_ dictionary: [String: Bool]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            (key.reduce(into: "") { result, character in
                if character.isUppercase {
                    result += "_" + character.lowercased()
                } else {
                    result.append(character)
                }
            }, value)
        })
    }

    public func sendTestPush() async throws -> Int {
        struct Sent: Decodable { let devices: Int }
        let sent: Sent = try await authorizedData(makeRequest("POST", "push/test", body: Optional<String>.none))
        return sent.devices
    }

    // MARK: - Vault

    public func vaultStatus() async throws -> VaultStatus {
        try await get("vault")
    }

    public func registerVaultDeviceKey(publicKey: String, deviceName: String) async throws -> String {
        struct Body: Encodable { let publicKey: String; let deviceName: String }
        struct Created: Decodable { let credentialId: String }
        let created: Created = try await authorizedData(makeRequest("POST", "vault/device-key", body: Body(publicKey: publicKey, deviceName: deviceName)))
        return created.credentialId
    }

    public func vaultChallenge(apps: [String]?) async throws -> VaultChallenge {
        struct Body: Encodable { let apps: [String]? }
        return try await authorizedData(makeRequest("POST", "vault/challenge", body: Body(apps: apps)))
    }

    public func unlockVault(challengeId: String, credentialId: String, signature: String) async throws -> [String: Date] {
        struct Body: Encodable { let challengeId: String; let credentialId: String; let signature: String }
        struct Unlocked: Decodable { let apps: [String: Date] }
        let unlocked: Unlocked = try await authorizedData(makeRequest("POST", "vault/unlock", body: Body(challengeId: challengeId, credentialId: credentialId, signature: signature)))
        return unlocked.apps
    }

    public func lockVault(app: String?) async throws {
        struct Body: Encodable { let app: String? }
        try await authorizedNoContent(makeRequest("POST", "vault/lock", body: Body(app: app)))
    }

    public func financeDocuments() async throws -> [FinanceDocument] {
        try await get("finance/documents")
    }

    public func labReports() async throws -> [LabReport] {
        try await get("health/lab-reports")
    }

    public func documents(app: String?, query: String?) async throws -> DocumentList {
        var items: [URLQueryItem] = []
        if let app { items.append(URLQueryItem(name: "app", value: app)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await authorized(makeRequest("GET", "documents", query: items, body: Optional<String>.none))
    }

    public func documentFileURL(documentId: String, versionId: String) async throws -> URL {
        let link: DocumentFileLink = try await get("documents/\(documentId)/versions/\(versionId)/file")
        return link.url
    }

    // MARK: - Plumbing

    /// For endpoints that answer `204 No Content`.
    private func authorizedNoContent(_ request: URLRequest) async throws {
        do {
            try await sendExpectingNoContent(request, token: try await refresher.validAccessToken())
        } catch APIError.unauthorized {
            try await sendExpectingNoContent(request, token: try await refresher.forceRefresh())
        }
    }

    private func sendExpectingNoContent(_ request: URLRequest, token: String) async throws {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Keine HTTP-Antwort") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, body: data, decoder: decoder)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await authorizedData(makeRequest("GET", path, body: Optional<String>.none))
    }

    /// Decodes `{ "data": T }`.
    private func authorizedData<T: Decodable>(_ request: URLRequest) async throws -> T {
        let envelope: DataEnvelope<T> = try await authorized(request)
        return envelope.data
    }

    private func authorized<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            return try await send(request, token: try await refresher.validAccessToken())
        } catch APIError.unauthorized {
            // The token may have been revoked or rotated elsewhere: refresh once.
            do {
                return try await send(request, token: try await refresher.forceRefresh())
            } catch APIError.unauthorized {
                tokens.save(nil)
                onSignedOut?()
                throw APIError.unauthorized
            }
        }
    }

    private func send<T: Decodable>(_ request: URLRequest, token: String? = nil) async throws -> T {
        var request = request
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Keine HTTP-Antwort") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, body: data, decoder: decoder)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func makeRequest<B: Encodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: B?
    ) throws -> URLRequest {
        let prefix = path.hasPrefix("auth/") ? "" : "api/v1/"
        var components = URLComponents(url: baseURL.appendingPathComponent(prefix + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

/// Serialises refreshes so concurrent requests share one rotation; with
/// rotating refresh tokens a second parallel refresh would fail.
actor TokenRefresher {
    private let baseURL: URL
    private let tokens: TokenStore
    private let session: URLSession
    private var inFlight: Task<TokenPair, Error>?

    init(baseURL: URL, tokens: TokenStore, session: URLSession) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
    }

    func validAccessToken() async throws -> String {
        guard let current = tokens.load() else { throw APIError.unauthorized }
        if current.needsRefresh() { return try await forceRefresh() }
        return current.accessToken
    }

    func forceRefresh() async throws -> String {
        if let inFlight { return try await inFlight.value.accessToken }
        guard let current = tokens.load() else { throw APIError.unauthorized }

        let task = Task { [baseURL, session, tokens] () async throws -> TokenPair in
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/native/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.unauthorized }
            let pair = try LifeOSJSON.makeDecoder().decode(TokenResponse.self, from: data).pair()
            tokens.save(pair)
            return pair
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value.accessToken
    }
}
