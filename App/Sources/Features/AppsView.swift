import LifeOSKit
import SwiftUI

/// Launcher grid of the apps the server has enabled.
struct AppsView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.spacing) {
                ForEach(model.apps) { app in
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

/// Where an app tile leads. Native screens exist for Aufgaben and Kalender;
/// vault apps are locked until device-key unlock exists on the server.
struct AppDestination: View {
    let module: AppModule

    var body: some View {
        switch module.id {
        case "productivity": TasksView()
        case "calendar": CalendarView()
        case "inbox": InboxView()
        case "today": TodayView()
        default:
            if module.sensitivity == .vault {
                VaultLockedView(module: module)
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

/// Health and Finance need a server-enforced unlock (ADR-031-004 §4): Face ID
/// signs a server challenge with a Secure Enclave key. Hiding the screen
/// behind Face ID alone is not allowed, so until the server side exists the
/// app does not show vault data at all.
struct VaultLockedView: View {
    let module: AppModule

    var body: some View {
        ContentUnavailableView {
            Label { Text(module.label) } icon: { AppIconTile(module: module, size: 64) }
        } description: {
            Text("\(module.label) ist eine Tresor-App. Entsperren per Face ID kommt, sobald der Server Geräteschlüssel prüfen kann.")
        } actions: {
            Button {} label: {
                Label("Mit Face ID entsperren", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .navigationTitle(module.label)
    }
}
