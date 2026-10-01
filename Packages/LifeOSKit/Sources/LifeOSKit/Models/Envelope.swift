import Foundation

/// Every Life OS API response wraps its payload in `{ "data": ... }`.
public struct DataEnvelope<T: Decodable>: Decodable {
    public let data: T
}

/// Paginated list responses add a `meta` block (tasks, notes, ...).
public struct PaginatedEnvelope<T: Decodable>: Decodable {
    public let data: [T]
    public let meta: PageMeta
}

public struct PageMeta: Decodable, Equatable, Sendable {
    public let currentPage: Int
    public let lastPage: Int
    public let perPage: Int
    public let total: Int
}

/// Error body: `{ "message": string, "errors"?: { field: [string] }, "code"?: string }`.
public struct ErrorEnvelope: Decodable, Equatable, Sendable {
    public let message: String
    public let errors: [String: [String]]?
    public let code: String?
}

extension DataEnvelope: Sendable where T: Sendable {}
extension PaginatedEnvelope: Sendable where T: Sendable {}
