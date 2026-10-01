import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let user = model.user {
                    Section {
                        HStack(spacing: 12) {
                            Circle().fill(Theme.brand).frame(width: 48, height: 48)
                                .overlay { Text(String(user.displayName.prefix(1))).font(.title3.bold()).foregroundStyle(.white) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.headline)
                                Text(user.email).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if !user.roles.isEmpty {
                            LabeledContent("Rollen", value: user.roles.joined(separator: ", "))
                        }
                    }
                }

                Section("Daten") {
                    NavigationLink {
                        AppleHealthSettingsView()
                    } label: {
                        Label("Apple Health", systemImage: "heart.text.square")
                    }
                    if model.push.isAvailable {
                        NavigationLink {
                            PushSettingsView()
                        } label: {
                            Label("Mitteilungen", systemImage: "bell")
                        }
                    }
                }

                Section("Verbindung") {
                    LabeledContent("Server", value: model.isDemo ? "Demo-Daten" : (model.serverURL?.host ?? "–"))
                    LabeledContent("Apps", value: "\(model.apps.count)")
                }

                Section {
                    Button(model.isDemo ? "Demo beenden" : "Abmelden", role: .destructive) {
                        Task {
                            await model.signOut()
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Beim Abmelden wird der Geräte-Token auf dem Server widerrufen und vom iPhone gelöscht.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
            .navigationTitle("Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
