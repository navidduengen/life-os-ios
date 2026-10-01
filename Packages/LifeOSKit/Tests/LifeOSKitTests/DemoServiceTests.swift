import XCTest
@testable import LifeOSKit

final class DemoServiceTests: XCTestCase {
    func testAllDemoPayloadsDecode() async throws {
        let demo = DemoService()
        _ = try await demo.today()
        _ = try await demo.calendar(month: "2026-10")
        let inbox = try await demo.inbox()
        XCTAssertEqual(inbox.data.all.count, 3)
        let modules = try await demo.appModules()
        XCTAssertTrue(modules.contains { $0.sensitivity == .vault })
    }

    func testCreateAndCompleteTask() async throws {
        let demo = DemoService()
        let created = try await demo.createTask(NewTask(title: "Neu"))
        XCTAssertEqual(created.status, .inbox)
        let done = try await demo.transitionTask(id: created.id, to: .completed)
        XCTAssertEqual(done.status, .completed)
        XCTAssertNotNil(done.completedAt)
        let page = try await demo.tasks(status: .completed, page: 1)
        XCTAssertTrue(page.data.contains { $0.id == created.id })
    }

    func testRejectsForbiddenTransition() async throws {
        let demo = DemoService()
        let created = try await demo.createTask(NewTask(title: "Neu"))
        _ = try await demo.transitionTask(id: created.id, to: .cancelled)
        do {
            _ = try await demo.transitionTask(id: created.id, to: .completed)
            XCTFail("cancelled → completed is not allowed")
        } catch {
            guard case .validation = error as? APIError else { return XCTFail("wrong error \(error)") }
        }
    }
}
