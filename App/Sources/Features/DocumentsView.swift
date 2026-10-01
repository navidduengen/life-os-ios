import LifeOSKit
import SwiftUI

/// Every document of every app the vault does not lock: search the text,
/// filter by app, open the original through a short-lived signed link.
struct DocumentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var state: Loadable<DocumentList> = .loading
    @State private var app: String?
    @State private var search = ""
    @State private var openError: String?

    var body: some View {
        AsyncContent(state: state, retry: load) { list in
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Alle", id: nil, locked: false)
                        ForEach(list.meta.apps) { entry in
                            chip(entry.label, id: entry.id, locked: entry.locked)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)

                if list.data.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Noch keine Dokumente" : "Nichts gefunden",
                        systemImage: search.isEmpty ? "doc.on.doc" : "magnifyingglass",
                        description: Text(search.isEmpty ? "Dokumente lädst du im Moment im Web hoch." : "Kein Dokument enthält „\(search)“.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(list.data) { document in
                    Button { Task { await open(document) } } label: {
                        row(document, appLabel: list.meta.apps.first { $0.id == document.app }?.label ?? document.app)
                    }
                    .buttonStyle(.plain)
                    .disabled(document.currentVersion?.isAvailable != true)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
        .navigationTitle("Dokumente")
        .searchable(text: $search, prompt: "In Titeln und Text suchen")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: search) { _, value in if value.isEmpty { Task { await load() } } }
        .task(id: app) { await load() }
        .alert("Öffnen nicht möglich", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }

    private func row(_ document: DocumentSummary, appLabel: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                Text(details(document, appLabel: appLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let snippet = document.snippet {
                    Text(snippet).font(.caption).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.controlHeight)
        .contentShape(Rectangle())
    }

    private func details(_ document: DocumentSummary, appLabel: String) -> String {
        var parts = [appLabel]
        if let type = document.documentType { parts.append(type) }
        if let version = document.currentVersion {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(version.fileSizeBytes), countStyle: .file))
        }
        if document.linksCount > 0 { parts.append(document.linksCount == 1 ? "1 Verknüpfung" : "\(document.linksCount) Verknüpfungen") }
        return parts.joined(separator: " · ")
    }

    private func chip(_ label: String, id: String?, locked: Bool) -> some View {
        let isOn = app == id
        return Button { app = id } label: {
            HStack(spacing: 6) {
                if locked { Image(systemName: "lock.fill").font(.caption) }
                Text(label)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? Theme.brand.opacity(0.14) : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityHint(locked ? "Gesperrt, erst in der App entsperren" : "")
    }

    private func load() async {
        do {
            state = .loaded(try await model.service.documents(app: app, query: search.trimmingCharacters(in: .whitespaces)))
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func open(_ document: DocumentSummary) async {
        guard let version = document.currentVersion else { return }
        do {
            openURL(try await model.service.documentFileURL(documentId: document.id, versionId: version.id))
        } catch APIError.locked(let lockedApp) {
            model.vault.markLocked(lockedApp)
            openError = "Dieser Bereich ist gesperrt. Entsperre ihn unter Apps."
        } catch {
            openError = error.userMessage
        }
    }
}
