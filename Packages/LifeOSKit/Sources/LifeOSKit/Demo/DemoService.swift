import Foundation

/// Sample data so the app runs in the simulator without a server and before
/// the backend has native token auth. Payloads are built as API JSON and
/// decoded with the real decoder, so the demo also exercises the models.
public actor DemoService: LifeOSService {
    private var taskRows: [JSONValue]

    public init() {
        taskRows = Self.initialTasks()
    }

    public func session() async throws -> UserSession {
        UserSession(id: "demo", name: "Demo", fullName: "Demo-Konto", email: "demo@lifeos.local", roles: ["admin"], onboardingCompleted: true)
    }

    public func appModules() async throws -> [AppModule] {
        [
            AppModule(id: "today", label: "Heute", description: "Dein Tag auf einen Blick.", basePath: "/today", defaultPath: "", kind: .system, sensitivity: .normal),
            AppModule(id: "inbox", label: "Posteingang", description: "Schnelles Erfassen und Einsortieren neuer Inhalte.", basePath: "/inbox", defaultPath: "", kind: .system, sensitivity: .normal),
            AppModule(id: "study", label: "Study Hub", description: "Kurrikulum, Sitzungen, Notizen, Ressourcen und Sammlungen.", basePath: "/study", defaultPath: "/start", kind: .app, sensitivity: .normal),
            AppModule(id: "productivity", label: "Aufgaben", description: "Aufgaben planen, erledigen und behalten.", basePath: "/productivity", defaultPath: "", kind: .app, sensitivity: .normal),
            AppModule(id: "calendar", label: "Kalender", description: "Termine, Abo-Kalender und Kalender-Verbindungen.", basePath: "/calendar", defaultPath: "", kind: .app, sensitivity: .normal),
            AppModule(id: "health", label: "Health", description: "Bluttests, Ernährung und Sport an einem Ort.", basePath: "/health", defaultPath: "", kind: .app, sensitivity: .vault),
            AppModule(id: "finance", label: "Finance", description: "Quittungen, Rechnungen und Verträge an einem Ort.", basePath: "/finance", defaultPath: "", kind: .app, sensitivity: .vault),
        ]
    }

    public func today() async throws -> TodayDashboard {
        let today = Self.localDate(0)
        let open = taskRows.filter { row in
            let status = row["status"]?.stringValue
            return status != "completed" && status != "cancelled"
        }
        let overdue = open.filter { $0["is_overdue"]?.boolValue == true }
        let dueToday = open.filter { $0["due_date"]?.stringValue == today && $0["is_overdue"]?.boolValue != true }
        let later = open.filter { ($0["due_date"]?.stringValue ?? "") > today }

        var upcoming: [JSONValue] = Self.sessions(dayOffset: 1).map { session in
            var item = session
            item["type"] = "session"
            item["local_date"] = .string(Self.localDate(1))
            return item
        }
        upcoming += later.map { row in
            var item = Self.card(row)
            item["type"] = "task"
            item["local_date"] = row["due_date"] ?? .null
            return item
        }

        let payload: JSONValue = [
            "timezone": "Europe/Berlin",
            "today": .string(today),
            "today_sessions": Self.section(Self.sessions(dayOffset: 0)),
            "overdue_tasks": Self.section(overdue.map(Self.card)),
            "due_today_tasks": Self.section(dueToday.map(Self.card)),
            "upcoming": Self.section(upcoming),
            "recent": Self.section([
                ["type": "note", "id": "n1", "title": "Zusammenfassung Herzzyklus", "updated_at": .string(Self.timestamp(hoursFromNow: -3))],
                ["type": "topic", "id": "tp1", "title": "Elektrolyte", "updated_at": .string(Self.timestamp(hoursFromNow: -20))],
            ]),
        ]
        return try payload.decode()
    }

    public func tasks(status: TaskStatus?, page: Int) async throws -> PaginatedEnvelope<LifeTask> {
        let rows = taskRows.filter { status == nil || $0["status"]?.stringValue == status?.rawValue }
        let payload: JSONValue = [
            "data": .array(rows),
            "meta": ["current_page": 1, "last_page": 1, "per_page": 100, "total": .int(rows.count)],
        ]
        return try payload.decode()
    }

    public func createTask(_ task: NewTask) async throws -> LifeTask {
        let row = Self.task(id: UUID().uuidString, title: task.title, status: .inbox, priority: task.priority, dueDate: task.dueDate)
        taskRows.insert(row, at: 0)
        return try row.decode()
    }

    public func transitionTask(id: String, to status: TaskStatus) async throws -> LifeTask {
        guard let index = taskRows.firstIndex(where: { $0["id"]?.stringValue == id }) else { throw APIError.notFound }
        guard let current = taskRows[index]["status"]?.stringValue.flatMap(TaskStatus.init(rawValue:)),
              current.allowedTransitions.contains(status)
        else { throw APIError.validation(message: "Dieser Statuswechsel ist nicht erlaubt.", errors: [:]) }

        var row = taskRows[index]
        row["status"] = .string(status.rawValue)
        row["completed_at"] = status == .completed ? .string(Self.timestamp(hoursFromNow: 0)) : .null
        if status == .completed { row["is_overdue"] = false }
        row["updated_at"] = .string(Self.timestamp(hoursFromNow: 0))
        taskRows[index] = row
        return try row.decode()
    }

    public func calendar(month: String) async throws -> CalendarResponse {
        var events: [JSONValue] = []
        for offset in -3...10 {
            for session in Self.sessions(dayOffset: offset) {
                let source: JSONValue = offset % 2 == 0
                    ? ["key": "study", "label": "Study Hub", "kind": "study"]
                    : ["key": "ics-1", "label": "Uni Stundenplan", "kind": "subscription"]
                events.append([
                    "id": session["id"] ?? .null, "type": "session", "title": session["title"] ?? .null,
                    "start_at": session["start_at"] ?? .null, "end_at": session["end_at"] ?? .null,
                    "is_all_day": false, "room": session["room"] ?? .null,
                    "session_id": session["session_id"] ?? .null, "session_type": session["session_type"] ?? .null,
                    "module": ["id": "m1", "name": "Physiologie", "code": "PHY", "color": "#4F46E5"],
                    "status": "scheduled", "priority": nil, "is_completed": false, "task_id": nil,
                    "source": source,
                ])
            }
        }
        for row in taskRows {
            guard let due = row["due_date"]?.stringValue, let id = row["id"]?.stringValue else { continue }
            events.append([
                "id": .string("task-\(id)"), "type": "task", "title": row["title"] ?? .null,
                "start_at": .string("\(due)T00:00:00Z"), "end_at": .string("\(due)T23:59:59Z"),
                "is_all_day": true, "room": nil, "session_id": nil, "session_type": nil, "module": nil,
                "status": row["status"] ?? .null, "priority": row["priority"] ?? .null,
                "is_completed": .bool(row["status"]?.stringValue == "completed"), "task_id": .string(id),
                "source": ["key": "tasks", "label": "Aufgaben", "kind": "tasks"],
            ])
        }
        let payload: JSONValue = [
            "data": .array(events),
            "meta": ["start": .string(Self.localDate(-3)), "end": .string(Self.localDate(10)), "timezone": "Europe/Berlin"],
        ]
        return try payload.decode()
    }

    public func inbox() async throws -> InboxResponse {
        let payload: JSONValue = [
            "data": [
                "notes": [["type": "note", "id": "in1", "title": "Idee: Karteikarten aus Vorlesung 4", "created_at": .string(Self.timestamp(hoursFromNow: -2))]],
                "tasks": [["type": "task", "id": "in2", "title": "Laborbefund nachfragen", "priority": "high", "status": "inbox", "created_at": .string(Self.timestamp(hoursFromNow: -5))]],
                "resources": [["type": "resource", "id": "in3", "title": "Skript Niere.pdf", "resource_type": "document", "created_at": .string(Self.timestamp(hoursFromNow: -26))]],
                "sessions": [],
            ],
            "meta": ["total_count": 3, "modules": [], "topics": []],
        ]
        return try payload.decode()
    }

    /// Demo mode keeps imported Apple Health samples in memory, keyed by HealthKit UUID.
    private var healthSamples: [String: HealthSamplePayload] = [:]

    public func importHealth(_ batch: HealthImportBatch) async throws -> HealthImportResult {
        for sample in batch.samples { healthSamples[sample.externalId] = sample }
        let deleted = batch.deleted.filter { healthSamples.removeValue(forKey: $0) != nil }.count
        return HealthImportResult(imported: batch.samples.count, deleted: deleted)
    }

    public func deleteImportedHealth(type: String?) async throws -> Int {
        let doomed = healthSamples.values.filter { type == nil || $0.type == type }.map(\.externalId)
        for id in doomed { healthSamples.removeValue(forKey: id) }
        return doomed.count
    }

    /// Push stays off in demo mode, like on a server without an APNs key.
    public func pushConfig() async throws -> PushConfig { .disabled }
    public func registerPushDevice(_ registration: PushDeviceRegistration) async throws {}
    public func unregisterPushDevice(token: String) async throws {}
    public func pushPreferences() async throws -> [String: Bool] { [:] }
    public func updatePushPreferences(_ preferences: [String: Bool]) async throws -> [String: Bool] { preferences }
    public func sendTestPush() async throws -> Int { 0 }

    public func signOut() async {}

    // MARK: - Fixtures

    private static func section(_ items: [JSONValue]) -> JSONValue {
        ["state": "ok", "items": .array(items), "error_code": nil, "retryable": false]
    }

    private static func card(_ row: JSONValue) -> JSONValue {
        var card: JSONValue = [:]
        for key in ["id", "title", "status", "priority", "due_date", "due_at", "updated_at", "is_overdue"] {
            card[key] = row[key] ?? .null
        }
        return card
    }

    private static func initialTasks() -> [JSONValue] {
        [
            task(id: "t1", title: "Altklausur Physiologie durchgehen", status: .next, priority: .high, dueDate: localDate(0)),
            task(id: "t2", title: "Protokoll Praktikum abgeben", status: .inProgress, priority: .urgent, dueDate: localDate(-1), overdue: true),
            task(id: "t3", title: "Bluttest-Termin vereinbaren", status: .inbox, priority: .normal, dueDate: localDate(2)),
            task(id: "t4", title: "Steuerunterlagen sortieren", status: .next, priority: .low, dueDate: localDate(5)),
            task(id: "t5", title: "Lerngruppe organisieren", status: .completed, priority: .normal, dueDate: nil),
        ]
    }

    private static func task(id: String, title: String, status: TaskStatus, priority: TaskPriority, dueDate: String?, overdue: Bool = false) -> JSONValue {
        [
            "id": .string(id), "title": .string(title), "description": nil,
            "status": .string(status.rawValue), "priority": .string(priority.rawValue),
            "due_date": .optional(dueDate), "due_at": nil,
            "completed_at": status == .completed ? .string(timestamp(hoursFromNow: -30)) : .null,
            "updated_at": .string(timestamp(hoursFromNow: -1)),
            "module": nil, "session": nil, "is_overdue": .bool(overdue),
        ]
    }

    /// Two weekday sessions; weekends stay empty.
    private static func sessions(dayOffset: Int) -> [JSONValue] {
        let day = Date().addingTimeInterval(Double(dayOffset) * 86_400)
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: day)
        guard weekday != 1 && weekday != 7 else { return [] }
        return [
            ["id": .string("sd-\(dayOffset)-1"), "session_id": "s1", "module_id": "m1",
             "title": "Physiologie: Herz-Kreislauf", "session_type": "lecture",
             "start_at": .string(timestamp(day: dayOffset, hour: 8)), "end_at": .string(timestamp(day: dayOffset, hour: 10)),
             "is_all_day": false, "room": "Hörsaal 2"],
            ["id": .string("sd-\(dayOffset)-2"), "session_id": "s2", "module_id": "m2",
             "title": "Biochemie Seminar", "session_type": "seminar",
             "start_at": .string(timestamp(day: dayOffset, hour: 13)), "end_at": .string(timestamp(day: dayOffset, hour: 14, minute: 30)),
             "is_all_day": false, "room": "R 1.04"],
        ]
    }

    private static func localDate(_ dayOffset: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(Double(dayOffset) * 86_400))
    }

    private static func timestamp(hoursFromNow: Double) -> String {
        iso.string(from: Date().addingTimeInterval(hoursFromNow * 3_600))
    }

    private static func timestamp(day: Int, hour: Int, minute: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let base = calendar.startOfDay(for: Date().addingTimeInterval(Double(day) * 86_400))
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        return iso.string(from: date)
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
