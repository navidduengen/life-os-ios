import Foundation

public enum SessionType: String, Decodable, Sendable {
    case lecture, seminar, exercise, practical, tutorial, exam
    case studySession = "study_session"
    case other

    public var label: String {
        switch self {
        case .lecture: "Vorlesung"
        case .seminar: "Seminar"
        case .exercise: "Übung"
        case .practical: "Praktikum"
        case .tutorial: "Tutorium"
        case .exam: "Prüfung"
        case .studySession: "Lernsitzung"
        case .other: "Termin"
        }
    }
}

/// One dashboard section. Sections fail independently (`state == .error`).
public struct DashboardSection<Item: Decodable & Sendable>: Decodable, Sendable {
    public enum State: String, Decodable, Sendable { case ok, error }

    public let state: State
    public let items: [Item]
    public let errorCode: String?
    public let retryable: Bool
}

public struct TaskCard: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: String?
    public let dueAt: Date?
    public let updatedAt: String
    public let isOverdue: Bool
}

public struct SessionOccurrence: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let moduleId: String?
    public let title: String
    public let sessionType: SessionType
    public let startAt: Date
    public let endAt: Date
    public let isAllDay: Bool
    public let room: String?
}

/// `upcoming` items are sessions or tasks, discriminated by `type`.
public enum UpcomingItem: Decodable, Identifiable, Sendable {
    case session(localDate: String, SessionOccurrence)
    case task(localDate: String, TaskCard)

    public var id: String {
        switch self {
        case let .session(_, s): "session-\(s.id)"
        case let .task(_, t): "task-\(t.id)"
        }
    }

    public var localDate: String {
        switch self {
        case let .session(d, _), let .task(d, _): d
        }
    }

    private enum CodingKeys: String, CodingKey { case type, localDate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date = try c.decode(String.self, forKey: .localDate)
        switch try c.decode(String.self, forKey: .type) {
        case "session": self = .session(localDate: date, try SessionOccurrence(from: decoder))
        case "task": self = .task(localDate: date, try TaskCard(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unbekannter Typ \(other)")
        }
    }
}

public struct RecentItem: Decodable, Equatable, Identifiable, Sendable {
    public let type: String
    public let id: String
    public let title: String
    public let updatedAt: Date
}

/// `GET /api/v1/today`.
public struct TodayDashboard: Decodable, Sendable {
    public let timezone: String
    public let today: String
    public let todaySessions: DashboardSection<SessionOccurrence>
    public let overdueTasks: DashboardSection<TaskCard>
    public let dueTodayTasks: DashboardSection<TaskCard>
    public let upcoming: DashboardSection<UpcomingItem>
    public let recent: DashboardSection<RecentItem>
}
