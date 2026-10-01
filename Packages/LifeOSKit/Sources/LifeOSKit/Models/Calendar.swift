import Foundation

/// `CalendarEventResource` from `GET /api/v1/calendar`.
public struct CalendarEvent: Decodable, Equatable, Identifiable, Sendable {
    public struct Module: Decodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let code: String?
        public let color: String?
    }

    public struct Source: Decodable, Equatable, Hashable, Sendable {
        public let key: String
        public let label: String
        public let kind: String
    }

    public let id: String
    /// `session` or `task`.
    public let type: String
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let isAllDay: Bool
    public let room: String?
    public let sessionId: String?
    public let sessionType: String?
    public let module: Module?
    public let status: String
    public let priority: String?
    public let isCompleted: Bool
    public let taskId: String?
    public let source: Source
}

public struct CalendarMeta: Decodable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let timezone: String
}

public struct CalendarResponse: Decodable, Sendable {
    public let data: [CalendarEvent]
    public let meta: CalendarMeta
}
