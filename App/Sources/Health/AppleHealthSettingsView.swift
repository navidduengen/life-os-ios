import LifeOSKit
import SwiftUI

/// Settings → Apple Health: choose which types to import, run a sync,
/// delete imported data on the server.
struct AppleHealthSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var search = ""

    private var health: HealthSyncManager { model.health }

    var body: some View {
        List {
            if !health.isAvailable {
                Section {
                    ContentUnavailableView(
                        "Apple Health nicht verfügbar",
                        systemImage: "heart.slash",
                        description: Text("Apple Health gibt es nur auf iPhone und iPad. Auf dem Mac werden die Daten angezeigt, die dein iPhone überträgt.")
                    )
                }
            } else {
                overview
                if health.settings.isEnabled {
                    groups
                    dangerZone
                }
            }
        }
        .navigationTitle("Apple Health")
        .searchable(text: $search, prompt: "Datentyp suchen")
        .confirmationDialog("Alle importierten Apple-Health-Daten auf dem Server löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { await health.deleteServerData() } }
        } message: {
            Text("In Apple Health auf dem iPhone bleibt alles erhalten. Beim nächsten Abgleich wird neu importiert.")
        }
    }

    private var overview: some View {
        Section {
            Toggle("Apple Health importieren", isOn: Binding(
                get: { health.settings.isEnabled },
                set: { value in health.update { $0.isEnabled = value } }
            ))
            if health.settings.isEnabled {
                Picker("Erster Import", selection: Binding(
                    get: { health.settings.initialRange },
                    set: { value in health.update { $0.initialRange = value } }
                )) {
                    ForEach(HealthInitialRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Im Hintergrund abgleichen", isOn: Binding(
                    get: { health.settings.backgroundSync },
                    set: { value in health.update { $0.backgroundSync = value } }
                ))
                syncRow
            }
        } footer: {
            Text("Die App liest nur und schreibt nichts in Apple Health. Übertragen wird nur, was du unten auswählst, an deinen eigenen Life-OS-Server. Freigaben kannst du jederzeit in der Health-App unter Profil › Apps ändern.")
        }
    }

    @ViewBuilder
    private var syncRow: some View {
        let selected = health.settings.enabledTypes.count
        Button {
            Task { await health.authorizeAndSync() }
        } label: {
            HStack {
                Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 80)
                }
            }
        }
        .disabled(selected == 0 || health.isSyncing)

        if let message = failure {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
        } else if let result = health.lastResult {
            Label(result, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
        }
        LabeledContent("Ausgewählt", value: "\(selected) von \(health.supportedTypes.count) Datentypen")
        if let last = health.settings.lastSyncAt {
            LabeledContent("Letzter Abgleich", value: last.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var groups: some View {
        Group {
            Section {
                Button("Alle auswählen") { health.enableAll(true) }
                Button("Keine auswählen") { health.enableAll(false) }
            }
            ForEach(HealthDataGroup.ordered, id: \.self) { group in
                let types = filtered(health.supportedTypes(in: group))
                if !types.isEmpty {
                    Section {
                        if search.isEmpty {
                            Toggle(isOn: Binding(get: { health.isEnabled(group) }, set: { health.setEnabled(group, $0) })) {
                                Label("Ganze Gruppe", systemImage: group.symbol).font(.body.weight(.semibold))
                            }
                        }
                        ForEach(types) { type in
                            Toggle(type.label, isOn: Binding(
                                get: { health.settings.enabledTypes.contains(type.id) },
                                set: { health.setEnabled(type, $0) }
                            ))
                        }
                    } header: {
                        Text(group.label)
                    } footer: {
                        if group == .records {
                            Text("Gesundheitsakten gibt es nur bei teilnehmenden Kliniken, in Deutschland kaum. iOS fragt dafür separat nach.")
                        }
                    }
                }
            }
        }
    }

    private var dangerZone: some View {
        Section {
            Button("Importierte Daten auf dem Server löschen", role: .destructive) { confirmDelete = true }
        }
    }

    private var progress: (done: Int, total: Int)? {
        if case let .syncing(done, total) = health.state { return (done, total) }
        return nil
    }

    private var failure: String? {
        if case let .failed(message) = health.state { return message }
        return nil
    }

    private func filtered(_ types: [HealthDataType]) -> [HealthDataType] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return types }
        return types.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }
}
