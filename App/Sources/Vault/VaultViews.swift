import LifeOSKit
import SwiftUI

/// Shows `content` only while the server has the vault app unlocked for this
/// device; otherwise the lock screen with Face ID / Touch ID.
struct VaultGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    let module: AppModule
    @ViewBuilder let content: () -> Content

    var body: some View {
        if model.vault.isUnlocked(module.id) {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.vault.lockAll() }
                        } label: {
                            Label("Sperren", systemImage: "lock")
                        }
                    }
                }
        } else {
            VaultLockedView(module: module)
        }
    }
}

/// Health and Finance need a server-enforced unlock (ADR-031-004 §4): Face ID
/// signs a server challenge with the Secure Enclave key of this device.
struct VaultLockedView: View {
    @Environment(AppModel.self) private var model
    let module: AppModule

    var body: some View {
        ContentUnavailableView {
            Label { Text(module.label) } icon: { AppIconTile(module: module, size: 64) }
        } description: {
            VStack(spacing: 8) {
                Text("\(module.label) ist geschützt. Entsperre mit Face ID oder Touch ID; der Server prüft die Freigabe.")
                if let error = model.vault.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        } actions: {
            Button {
                Task { await model.vault.unlock() }
            } label: {
                Label("Entsperren", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.vault.isWorking)
        }
        .navigationTitle(module.label)
        .task { if model.vault.status == nil { await model.vault.refresh() } }
    }
}

struct FinanceDocumentsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[FinanceDocument]> = .loading

    var body: some View {
        AsyncContent(state: state, retry: load) { documents in
            if documents.isEmpty {
                ContentUnavailableView("Noch keine Belege", systemImage: "doc.text", description: Text("Belege lädst du im Moment im Web hoch."))
            } else {
                List(documents) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title).font(.headline)
                        HStack {
                            Text(document.kindLabel)
                            if let counterparty = document.counterparty { Text("· \(counterparty)") }
                            Spacer()
                            if let amount = document.amount {
                                Text(amount, format: .currency(code: document.currency))
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        if let date = document.documentDate {
                            Text(date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Belege")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            state = .loaded(try await model.service.financeDocuments())
        } catch APIError.locked {
            model.vault.markLocked("finance")
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

struct LabReportsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[LabReport]> = .loading

    var body: some View {
        AsyncContent(state: state, retry: load) { reports in
            if reports.isEmpty {
                ContentUnavailableView("Noch keine Befunde", systemImage: "drop", description: Text("Befunde lädst du im Moment im Web hoch."))
            } else {
                List(reports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.title).font(.headline)
                        HStack {
                            if let taken = report.takenOn { Text(taken) }
                            if let lab = report.labName { Text("· \(lab)") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(report.status == "extracted"
                            ? "\(report.valuesCount) Werte, \(report.flaggedCount) auffällig"
                            : report.status == "processing" ? "Wird ausgelesen…" : "Fehler beim Auslesen")
                            .font(.caption)
                            .foregroundStyle(report.flaggedCount > 0 ? Color.orange : Color.secondary)
                    }
                }
            }
        }
        .navigationTitle("Bluttests")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            state = .loaded(try await model.service.labReports())
        } catch APIError.locked {
            model.vault.markLocked("health")
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
