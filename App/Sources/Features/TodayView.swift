import LifeOSKit
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<TodayDashboard> = .loading

    var body: some View {
        AsyncContent(state: state, retry: load) { today in
            List {
                section("Termine heute", today.todaySessions, empty: "Heute keine Termine.") { session in
                    SessionRow(session: session)
                }
                if today.overdueTasks.state == .error || !today.overdueTasks.items.isEmpty {
                    section("Überfällig", today.overdueTasks, empty: "") { task in
                        TaskCardRow(card: task, onComplete: { await complete(task) })
                    }
                }
                section("Heute fällig", today.dueTodayTasks, empty: "Nichts fällig.") { task in
                    TaskCardRow(card: task, onComplete: { await complete(task) })
                }
                section("Demnächst", today.upcoming, empty: "Nichts geplant.") { item in
                    switch item {
                    case let .session(day, session):
                        SessionRow(session: session, day: day)
                    case let .task(day, task):
                        TaskCardRow(card: task, day: day, onComplete: { await complete(task) })
                    }
                }
                section("Zuletzt bearbeitet", today.recent, empty: "Noch nichts bearbeitet.") { item in
                    Label(item.title, systemImage: item.type == "note" ? "note.text" : item.type == "task" ? "checkmark.circle" : "number")
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
        .navigationTitle(greeting)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
        .task { await load() }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = model.user?.name ?? ""
        let salutation = hour < 11 ? "Guten Morgen" : hour < 18 ? "Hallo" : "Guten Abend"
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    @ViewBuilder
    private func section<Item: Decodable & Sendable & Identifiable, Row: View>(
        _ title: String,
        _ result: DashboardSection<Item>,
        empty: String,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        Section(title) {
            if result.state == .error {
                Label("Dieser Bereich konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if result.items.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(result.items) { row($0) }
            }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await model.service.today())
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func complete(_ card: TaskCard) async {
        _ = try? await model.service.transitionTask(id: card.id, to: .completed)
        await load()
    }
}

struct SessionRow: View {
    let session: SessionOccurrence
    var day: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.isAllDay ? "ganztägig" : Formatters.time.string(from: session.startAt))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if !session.isAllDay {
                    Text(Formatters.time.string(from: session.endAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.body.weight(.medium))
                Text([day.map(Formatters.relativeDay), session.sessionType.label, session.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentBar(Theme.brand)
    }
}

struct TaskCardRow: View {
    let card: TaskCard
    var day: String?
    let onComplete: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await onComplete() }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(card.priority.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Erledigt")

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                Text([card.dueDate.map(Formatters.relativeDay) ?? day.map(Formatters.relativeDay), card.priority.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(card.isOverdue ? Color.red : Color.secondary)
            }
        }
    }
}
