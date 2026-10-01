import LifeOSKit
import SwiftUI

/// Launcher grid of the apps the server has enabled.
struct AppsView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.spacing) {
                ForEach(model.launcherApps) { app in
                    NavigationLink(value: app.id) {
                        AppCard(module: app)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Apps")
        .navigationDestination(for: String.self) { id in
            if let app = model.modules.first(where: { $0.id == id }) {
                AppDestination(module: app)
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
    }
}

struct AppCard: View {
    let module: AppModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconTile(module: module, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.label).font(.headline)
                Text(module.style.tagline ?? module.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Where an app tile leads. Native screens exist for Aufgaben, Kalender,
/// Posteingang and Heute, plus the vault apps behind Face ID / Touch ID.
struct AppDestination: View {
    let module: AppModule

    var body: some View {
        switch module.id {
        case "productivity": TasksView()
        case "calendar": CalendarView()
        case "inbox": InboxView()
        case "today": TodayView()
        case "documents": DocumentsView()
        case "finance": VaultGate(module: module) { FinanceDocumentsView() }
        case "health": VaultGate(module: module) { LabReportsView() }
        default:
            if module.sensitivity == .vault {
                VaultGate(module: module) { ComingSoonView(module: module) }
            } else {
                ComingSoonView(module: module)
            }
        }
    }
}

struct ComingSoonView: View {
    @Environment(AppModel.self) private var model
    let module: AppModule

    var body: some View {
        ContentUnavailableView {
            Label { Text(module.label) } icon: { AppIconTile(module: module, size: 64) }
        } description: {
            Text("\(module.description)\n\nDie native Ansicht folgt. Bis dahin kannst du \(module.label) im Browser öffnen.")
        } actions: {
            if let url = webURL {
                Link("Im Browser öffnen", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(module.label)
    }

    private var webURL: URL? {
        guard !model.isDemo, let base = model.serverURL else { return nil }
        return base.appendingPathComponent(String((module.basePath + module.defaultPath).dropFirst()))
    }
}
