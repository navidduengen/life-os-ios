import LifeOSKit
import SwiftUI

/// iPhone: tab bar. iPad and Mac: sidebar like the web layout "Leiste links".
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            SidebarLayout()
        } else {
            TabLayout()
        }
    }
}

enum Destination: Hashable {
    case today, tasks, calendar, inbox, documents, apps
    case app(String)

    /// Where a notification's `route` leads.
    init?(route: String) {
        switch route {
        case "/today", "/": self = .today
        case "/productivity": self = .tasks
        case "/calendar": self = .calendar
        case "/inbox": self = .inbox
        case "/documents": self = .documents
        default:
            if route.hasPrefix("/health") { self = .app("health") } else { return nil }
        }
    }
}

private struct TabLayout: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Destination = .today

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView() }
                .tabItem { Label("Heute", systemImage: "sun.max") }
                .tag(Destination.today)
            NavigationStack { TasksView() }
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
                .tag(Destination.tasks)
            NavigationStack { CalendarView() }
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(Destination.calendar)
            NavigationStack { InboxView() }
                .tabItem { Label("Posteingang", systemImage: "tray") }
                .tag(Destination.inbox)
            NavigationStack { AppsView() }
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                .tag(Destination.apps)
        }
        .onChange(of: model.requestedRoute, initial: true) { _, route in
            guard let route, let destination = Destination(route: route) else { return }
            switch destination {
            case .app, .documents: selection = .apps
            default: selection = destination
            }
            model.requestedRoute = nil
        }
    }
}

private struct SidebarLayout: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Destination? = .today

    /// Apps that already have their own sidebar entry above.
    private let builtIn: Set<String> = ["today", "inbox", "documents", "productivity", "calendar"]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Heute", systemImage: "sun.max").tag(Destination.today)
                    Label("Posteingang", systemImage: "tray").tag(Destination.inbox)
                    Label("Dokumente", systemImage: "doc.on.doc").tag(Destination.documents)
                    Label("Aufgaben", systemImage: "checklist").tag(Destination.tasks)
                    Label("Kalender", systemImage: "calendar").tag(Destination.calendar)
                }
                Section("Apps") {
                    ForEach(model.apps.filter { !builtIn.contains($0.id) }) { app in
                        Label {
                            Text(app.label)
                        } icon: {
                            AppIconTile(module: app, size: 24)
                        }
                        .tag(Destination.app(app.id))
                    }
                }
            }
            .navigationTitle("Life OS")
            .toolbar { ToolbarItem(placement: .primaryAction) { QuickCaptureButton(withShortcut: true) } }
        } detail: {
            NavigationStack {
                switch selection ?? .today {
                case .today, .apps: TodayView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                case .inbox: InboxView()
                case .documents: DocumentsView()
                case let .app(id):
                    if let app = model.modules.first(where: { $0.id == id }) {
                        AppDestination(module: app)
                    }
                }
            }
        }
        .onChange(of: model.requestedRoute, initial: true) { _, route in
            guard let route, let destination = Destination(route: route) else { return }
            selection = destination
            model.requestedRoute = nil
        }
    }
}
