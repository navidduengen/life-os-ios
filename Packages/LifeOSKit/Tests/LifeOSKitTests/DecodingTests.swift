import XCTest
@testable import LifeOSKit

final class DecodingTests: XCTestCase {
    private let decoder = LifeOSJSON.makeDecoder()

    func testParsesLaravelTimestamps() throws {
        let micro = try XCTUnwrap(LifeOSJSON.parseTimestamp("2026-10-01T08:00:00.123456Z"))
        let plain = try XCTUnwrap(LifeOSJSON.parseTimestamp("2026-10-01T08:00:00Z"))
        let offset = try XCTUnwrap(LifeOSJSON.parseTimestamp("2026-10-01T10:00:00+02:00"))
        XCTAssertEqual(micro.timeIntervalSince(plain), 0.123, accuracy: 0.001)
        XCTAssertEqual(offset, plain)
        XCTAssertNil(LifeOSJSON.parseTimestamp("gestern"))
    }

    func testDecodesTask() throws {
        let json = """
        {"data":{"id":"9b1","title":"Protokoll","description":null,"status":"in_progress","priority":"urgent",
        "due_date":"2026-10-02","due_at":null,"completed_at":null,"updated_at":"2026-10-01T07:12:44.000000Z",
        "module":{"id":"m1","name":"Physiologie"},"session":null,"is_overdue":false}}
        """
        let task = try decoder.decode(DataEnvelope<LifeTask>.self, from: Data(json.utf8)).data
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.priority, .urgent)
        XCTAssertEqual(task.dueDate, "2026-10-02")
        XCTAssertEqual(task.module?.name, "Physiologie")
        XCTAssertEqual(task.updatedAt, "2026-10-01T07:12:44.000000Z", "lock token must round-trip unchanged")
    }

    func testDecodesTodayWithMixedUpcomingAndFailedSection() throws {
        let json = """
        {"data":{"timezone":"Europe/Berlin","today":"2026-10-01",
        "today_sessions":{"state":"ok","items":[{"id":"d1","session_id":"s1","module_id":null,"title":"Vorlesung",
          "session_type":"lecture","start_at":"2026-10-01T06:00:00Z","end_at":"2026-10-01T08:00:00Z","is_all_day":false,"room":"HS 2"}],
          "error_code":null,"retryable":false},
        "overdue_tasks":{"state":"error","items":[],"error_code":"tasks_unavailable","retryable":true},
        "due_today_tasks":{"state":"ok","items":[],"error_code":null,"retryable":false},
        "upcoming":{"state":"ok","items":[
          {"type":"task","local_date":"2026-10-03","id":"t1","title":"Abgabe","status":"next","priority":"high",
           "due_date":"2026-10-03","due_at":null,"updated_at":"2026-10-01T07:00:00Z","is_overdue":false},
          {"type":"session","local_date":"2026-10-02","id":"d2","session_id":"s2","module_id":"m1","title":"Seminar",
           "session_type":"study_session","start_at":"2026-10-02T11:00:00Z","end_at":"2026-10-02T12:00:00Z","is_all_day":false,"room":null}],
          "error_code":null,"retryable":false},
        "recent":{"state":"ok","items":[{"type":"note","id":"n1","title":"Notiz","updated_at":"2026-09-30T19:00:00.000000Z"}],
          "error_code":null,"retryable":false}}}
        """
        let today = try decoder.decode(DataEnvelope<TodayDashboard>.self, from: Data(json.utf8)).data
        XCTAssertEqual(today.todaySessions.items.first?.room, "HS 2")
        XCTAssertEqual(today.overdueTasks.state, .error)
        XCTAssertTrue(today.overdueTasks.retryable)
        XCTAssertEqual(today.upcoming.items.map(\.localDate), ["2026-10-03", "2026-10-02"])
        guard case let .session(_, session) = today.upcoming.items[1] else { return XCTFail("expected session") }
        XCTAssertEqual(session.sessionType, .studySession)
    }

    func testDecodesAppModulesWithCamelCasePaths() throws {
        let json = """
        {"data":[{"id":"health","label":"Health","description":"…","basePath":"/health","defaultPath":"","kind":"app","sensitivity":"vault"},
        {"id":"inbox","label":"Posteingang","description":"…","basePath":"/inbox","defaultPath":"","kind":"system","sensitivity":"normal"}]}
        """
        let modules = try decoder.decode(DataEnvelope<[AppModule]>.self, from: Data(json.utf8)).data
        XCTAssertEqual(modules[0].basePath, "/health")
        XCTAssertEqual(modules[0].sensitivity, .vault)
        XCTAssertEqual(AppModuleCatalog.sorted(modules).map(\.id), ["inbox", "health"])
    }

    func testDecodesCalendarAndInbox() throws {
        let calendar = """
        {"data":[{"id":"e1","type":"session","title":"Vorlesung","start_at":"2026-10-01T06:00:00Z","end_at":"2026-10-01T08:00:00Z",
        "is_all_day":false,"room":null,"session_id":"s1","session_type":"lecture","module":{"id":"m1","name":"Physio","code":null,"color":"#4F46E5"},
        "status":"scheduled","priority":null,"is_completed":false,"task_id":null,"source":{"key":"ics-3","label":"Uni Stundenplan","kind":"subscription"}}],
        "meta":{"start":"2026-09-28","end":"2026-11-01","timezone":"Europe/Berlin"}}
        """
        let events = try decoder.decode(CalendarResponse.self, from: Data(calendar.utf8))
        XCTAssertEqual(events.data.first?.source.label, "Uni Stundenplan")
        XCTAssertEqual(events.meta.timezone, "Europe/Berlin")

        let inbox = """
        {"data":{"notes":[{"type":"note","id":"n1","title":"A","created_at":"2026-09-30T10:00:00.000000Z"}],
        "tasks":[{"type":"task","priority":"high","status":"inbox","id":"t1","title":"B","created_at":"2026-10-01T10:00:00.000000Z"}],
        "resources":[],"sessions":[]},"meta":{"total_count":2,"modules":[],"topics":[]}}
        """
        let decoded = try decoder.decode(InboxResponse.self, from: Data(inbox.utf8))
        XCTAssertEqual(decoded.data.all.map(\.id), ["t1", "n1"], "newest first")
        XCTAssertEqual(decoded.meta.totalCount, 2)
    }

    func testEncodesNewTaskInSnakeCase() throws {
        let data = try LifeOSJSON.makeEncoder().encode(NewTask(title: "X", priority: .high, dueDate: "2026-10-05"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["due_date"] as? String, "2026-10-05")
        XCTAssertEqual(object["priority"] as? String, "high")
    }

    func testStatusMachineMatchesServer() {
        XCTAssertFalse(TaskStatus.cancelled.allowedTransitions.contains(.completed))
        XCTAssertTrue(TaskStatus.completed.allowedTransitions.contains(.next))
        for status in TaskStatus.allCases {
            XCTAssertFalse(status.allowedTransitions.contains(status))
        }
    }
}
