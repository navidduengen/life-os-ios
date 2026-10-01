import LifeOSKit
import SwiftUI

struct TasksView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case open = "Offen", done = "Erledigt", all = "Alle"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[LifeTask]> = .loading
    @State private var filter: Filter = .open
    @State private var showNew = false
    @State private var actionError: String?

    var body: some View {
        AsyncContent(state: state, retry: load) { tasks in
            let visible = tasks.filter(matches)
            List {
                if visible.isEmpty {
                    ContentUnavailableView("Keine Aufgaben", systemImage: "checkmark.circle", description: Text(filter == .open ? "Alles erledigt." : "Hier ist noch nichts."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { task in
                    TaskRow(task: task) { await toggle(task) }
                        .swipeActions(edge: .trailing) {
                            ForEach(task.status.allowedTransitions.filter { $0 != .completed }.prefix(2), id: \.self) { status in
                                Button(status.label) { Task { await transition(task, to: status) } }
                                    .tint(status == .cancelled ? .gray : .indigo)
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
        .navigationTitle("Aufgaben")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neue Aufgabe")
            }
        }
        .sheet(isPresented: $showNew) {
            NewTaskSheet { newTask in
                _ = try await model.service.createTask(newTask)
                await load()
            }
        }
        .alert("Aktion fehlgeschlagen", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task { await load() }
    }

    private func matches(_ task: LifeTask) -> Bool {
        switch filter {
        case .open: !task.isDone
        case .done: task.isDone
        case .all: true
        }
    }

    private func load() async {
        do {
            var page = 1
            var all: [LifeTask] = []
            // The API caps a page at 100; a personal list rarely needs more than a few pages.
            while page <= 5 {
                let result = try await model.service.tasks(status: nil, page: page)
                all += result.data
                if result.meta.currentPage >= result.meta.lastPage { break }
                page += 1
            }
            state = .loaded(all)
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func toggle(_ task: LifeTask) async {
        await transition(task, to: task.status == .completed ? .next : .completed)
    }

    private func transition(_ task: LifeTask, to status: TaskStatus) async {
        do {
            _ = try await model.service.transitionTask(id: task.id, to: status)
            await load()
        } catch {
            actionError = error.userMessage
        }
    }
}

struct TaskRow: View {
    let task: LifeTask
    let onToggle: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await onToggle() }
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == .completed ? Color.green : task.priority.color)
            }
            .buttonStyle(.plain)
            .disabled(task.status == .cancelled)
            .accessibilityLabel(task.status == .completed ? "Wieder öffnen" : "Erledigt")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                HStack(spacing: 6) {
                    Text(task.status.label)
                    if let due = task.dueDate {
                        Text("·")
                        Text(Formatters.relativeDay(due)).foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    }
                    if let module = task.module {
                        Text("·")
                        Text(module.name)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: Theme.controlHeight)
    }
}

struct NewTaskSheet: View {
    let onSave: (NewTask) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var priority: TaskPriority = .normal
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                Picker("Priorität", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Fälligkeitsdatum", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let task = NewTask(title: title.trimmingCharacters(in: .whitespaces), priority: priority, dueDate: hasDueDate ? Formatters.local(dueDate) : nil)
            try await onSave(task)
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}
