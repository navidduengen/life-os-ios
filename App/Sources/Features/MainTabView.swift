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
    case today, tasks, calendar, inbox
    case app(String)
}

private struct TabLayout: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Heute", systemImage: "sun.max") }
            NavigationStack { TasksView() }
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
            NavigationStack { CalendarView() }
                .tabItem { Label("Kalender", systemImage: "calendar") }
            NavigationStack { InboxView() }
                .tabItem { Label("Posteingang", systemImage: "tray") }
            NavigationStack { AppsView() }
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
    }
}

private struct SidebarLayout: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Destination? = .today

    /// Apps that already have their own sidebar entry above.
    private let builtIn: Set<String> = ["today", "inbox", "productivity", "calendar"]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Heute", systemImage: "sun.max").tag(Destination.today)
                    Label("Posteingang", systemImage: "tray").tag(Destination.inbox)
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
        } detail: {
            NavigationStack {
                switch selection ?? .today {
                case .today: TodayView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                case .inbox: InboxView()
                case let .app(id):
                    if let app = model.modules.first(where: { $0.id == id }) {
                        AppDestination(module: app)
                    }
                }
            }
        }
    }
}
