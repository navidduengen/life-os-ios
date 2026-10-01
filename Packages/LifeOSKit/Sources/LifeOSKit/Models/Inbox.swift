import Foundation

/// One unfiled item from `GET /api/v1/inbox`.
public struct InboxItem: Decodable, Equatable, Identifiable, Sendable {
    public enum ItemType: String, Decodable, CaseIterable, Sendable { case note, task, resource, session }

    public let type: ItemType
    public let id: String
    public let title: String
    public let createdAt: Date
    public let resourceType: String?
    public let sessionType: String?
    public let priority: String?
    public let status: String?
}

public struct InboxSections: Decodable, Sendable {
    public let notes: [InboxItem]
    public let tasks: [InboxItem]
    public let resources: [InboxItem]
    public let sessions: [InboxItem]

    /// Newest first, across all sections (like the web inbox list).
    public var all: [InboxItem] {
        (notes + tasks + resources + sessions).sorted { $0.createdAt > $1.createdAt }
    }
}

public struct InboxMeta: Decodable, Sendable {
    public let totalCount: Int
}

public struct InboxResponse: Decodable, Sendable {
    public let data: InboxSections
    public let meta: InboxMeta
}
