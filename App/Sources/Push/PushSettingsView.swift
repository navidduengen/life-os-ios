import SwiftUI

/// Settings → Mitteilungen. Only reachable while the server has push on.
struct PushSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var push: PushManager { model.push }

    var body: some View {
        List {
            Section {
                switch push.authorization {
                case .authorized, .provisional:
                    Label("Mitteilungen sind erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied:
                    Label("In den iOS-Einstellungen abgeschaltet", systemImage: "bell.slash")
                    Button("iOS-Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                default:
                    Button {
                        Task { await push.requestPermission() }
                    } label: {
                        Label("Mitteilungen erlauben", systemImage: "bell.badge")
                    }
                }
            } footer: {
                Text("Mitteilungen nennen nie Werte oder Beträge, weil sie auch auf dem Sperrbildschirm erscheinen.")
            }

            if push.isAllowed {
                Section("Was soll dich erreichen?") {
                    ForEach(push.config.kinds) { kind in
                        Toggle(kind.label, isOn: Binding(
                            get: { push.preferences[kind.id] ?? true },
                            set: { value in Task { await push.setPreference(kind.id, value) } }
                        ))
                    }
                }
                Section {
                    Button("Testmitteilung senden") { Task { await push.sendTest() } }
                }
            }

            if let message = push.message {
                Section { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Mitteilungen")
    }
}
