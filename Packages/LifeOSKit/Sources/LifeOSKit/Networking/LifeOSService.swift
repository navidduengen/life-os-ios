import Foundation

/// Everything the app reads and writes. `APIClient` talks to a real server,
/// `DemoService` serves fixed sample data for the simulator and previews.
public protocol LifeOSService: Sendable {
    func session() async throws -> UserSession
    func appModules() async throws -> [AppModule]
    func today() async throws -> TodayDashboard
    func tasks(status: TaskStatus?, page: Int) async throws -> PaginatedEnvelope<LifeTask>
    func createTask(_ task: NewTask) async throws -> LifeTask
    func transitionTask(id: String, to status: TaskStatus) async throws -> LifeTask
    /// `month` as `YYYY-MM`.
    func calendar(month: String) async throws -> CalendarResponse
    func inbox() async throws -> InboxResponse
    func signOut() async
}
