import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inbox, next
    case inProgress = "in_progress"
    case blocked, completed, cancelled

    public var label: String {
        switch self {
        case .inbox: "Eingang"
        case .next: "Als Nächstes"
        case .inProgress: "In Arbeit"
        case .blocked: "Blockiert"
        case .completed: "Erledigt"
        case .cancelled: "Abgebrochen"
        }
    }

    /// Allowed transitions of the server-side state machine (openapi `TaskStatus`).
    public var allowedTransitions: [TaskStatus] {
        switch self {
        case .inbox: [.next, .inProgress, .blocked, .completed, .cancelled]
        case .next: [.inbox, .inProgress, .blocked, .completed, .cancelled]
        case .inProgress: [.next, .blocked, .completed, .cancelled]
        case .blocked: [.next, .inProgress, .completed, .cancelled]
        case .completed: [.inbox, .next, .inProgress, .cancelled]
        case .cancelled: [.inbox, .next]
        }
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low, normal, high, urgent

    public var label: String {
        switch self {
        case .low: "Niedrig"
        case .normal: "Normal"
        case .high: "Hoch"
        case .urgent: "Dringend"
        }
    }
}

public struct NamedRef: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
}

public struct TitledRef: Decodable, Equatable, Sendable {
    public let id: String
    public let title: String
}

/// `TaskResource` from `/api/v1/tasks`.
public struct LifeTask: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: TaskStatus
    public let priority: TaskPriority
    /// Local due date (`Y-m-d`), kept as text so it never shifts across time zones.
    public let dueDate: String?
    public let dueAt: Date?
    public let completedAt: Date?
    /// Optimistic-lock token for `PATCH /tasks/{id}`; send back unchanged.
    public let updatedAt: String
    public let module: NamedRef?
    public let session: TitledRef?
    public let isOverdue: Bool

    public var isDone: Bool { status == .completed || status == .cancelled }
}

/// Body for `POST /api/v1/tasks`.
public struct NewTask: Encodable, Sendable {
    public var title: String
    public var priority: TaskPriority
    public var dueDate: String?

    public init(title: String, priority: TaskPriority = .normal, dueDate: String? = nil) {
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
    }
}
