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

    // MARK: - Plumbing

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
