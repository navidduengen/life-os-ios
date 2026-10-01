import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// 401: no or expired token. The client already tried one refresh.
    case unauthorized
    /// 403
    case forbidden(String)
    /// 404 (foreign IDs also answer 404, never 403).
    case notFound
    /// 409: optimistic lock — the object changed elsewhere.
    case conflict(String)
    /// 422 with field errors.
    case validation(message: String, errors: [String: [String]])
    /// 423 `step_up_required`: vault app must be unlocked first (ADR-031-004).
    case locked(String)
    /// 429
    case rateLimited
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    /// German, user-facing text.
    public var message: String {
        switch self {
        case .unauthorized: "Bitte melde dich erneut an."
        case let .forbidden(m), let .conflict(m), let .locked(m): m
        case .notFound: "Nicht gefunden."
        case let .validation(m, _): m
        case .rateLimited: "Zu viele Anfragen. Bitte kurz warten."
        case let .server(status, m): m ?? "Serverfehler (\(status))."
        case .transport: "Keine Verbindung zum Server."
        case .decoding: "Die Antwort des Servers konnte nicht gelesen werden."
        }
    }

    static func from(status: Int, body: Data, decoder: JSONDecoder) -> APIError {
        let envelope = try? decoder.decode(ErrorEnvelope.self, from: body)
        let message = envelope?.message ?? ""
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound
        case 409: return .conflict(message)
        case 422: return .validation(message: message, errors: envelope?.errors ?? [:])
        case 423: return .locked(message)
        case 429: return .rateLimited
        default: return .server(status: status, message: envelope?.message)
        }
    }
}
