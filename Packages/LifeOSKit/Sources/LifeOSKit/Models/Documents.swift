import Foundation

/// `GET /api/v1/documents`: documents of every app the vault does not lock.
public struct DocumentList: Decodable, Equatable, Sendable {
    public struct App: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let locked: Bool
    }

    public struct Meta: Decodable, Equatable, Sendable {
        public let apps: [App]
        public let total: Int
    }

    public let data: [DocumentSummary]
    public let meta: Meta
}

public struct DocumentSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let app: String
    public let title: String
    public let documentType: String?
    public let linksCount: Int
    public let currentVersion: DocumentVersion?
    /// Where the search term appears in the text; only set for searches.
    public let snippet: String?
}

public struct DocumentVersion: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let versionNumber: Int
    public let role: String
    public let originalFilename: String
    public let mimeType: String
    public let fileSizeBytes: Int
    public let checksumSha256: String
    public let status: String

    public var isAvailable: Bool { status == "available" }
}

/// `GET /api/v1/documents/{id}/versions/{version}/file` with JSON: a short-lived signed link.
struct DocumentFileLink: Decodable {
    let url: URL
}
