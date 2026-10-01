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
    /// Sends Apple Health samples and deletions (at most `HealthImportBatch.limit` each).
    func importHealth(_ batch: HealthImportBatch) async throws -> HealthImportResult
    /// Removes imported Apple Health data on the server, one type or all.
    func deleteImportedHealth(type: String?) async throws -> Int
    func pushConfig() async throws -> PushConfig
    func registerPushDevice(_ registration: PushDeviceRegistration) async throws
    func unregisterPushDevice(token: String) async throws
    /// Kind id → on/off.
    func pushPreferences() async throws -> [String: Bool]
    func updatePushPreferences(_ preferences: [String: Bool]) async throws -> [String: Bool]
    func sendTestPush() async throws -> Int
    func vaultStatus() async throws -> VaultStatus
    /// `publicKey`: base64 X9.63 P-256 point of the Secure Enclave key. Returns the credential id.
    func registerVaultDeviceKey(publicKey: String, deviceName: String) async throws -> String
    /// `apps` nil means every vault app.
    func vaultChallenge(apps: [String]?) async throws -> VaultChallenge
    /// `signature`: base64 DER ECDSA over `VaultChallenge.message`. Returns app id → unlocked until.
    func unlockVault(challengeId: String, credentialId: String, signature: String) async throws -> [String: Date]
    func lockVault(app: String?) async throws
    func financeDocuments() async throws -> [FinanceDocument]
    func labReports() async throws -> [LabReport]
    /// Documents of all apps; `query` also searches the extracted text.
    func documents(app: String?, query: String?) async throws -> DocumentList
    /// A short-lived signed link to the file of a version.
    func documentFileURL(documentId: String, versionId: String) async throws -> URL
    func signOut() async
}
