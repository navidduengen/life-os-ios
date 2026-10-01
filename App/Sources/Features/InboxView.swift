import LifeOSKit
import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[InboxItem]> = .loading
    @State private var filter: InboxItem.ItemType?

    var body: some View {
        AsyncContent(state: state, retry: load) { items in
            let visible = items.filter { filter == nil || $0.type == filter }
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Alle", count: items.count, type: nil)
                        ForEach(InboxItem.ItemType.allCases, id: \.self) { type in
                            let count = items.filter { $0.type == type }.count
                            if count > 0 { chip(type.label, count: count, type: type) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)

                if visible.isEmpty {
                    ContentUnavailableView("Posteingang leer", systemImage: "tray", description: Text("Alles ist einsortiert."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.type.symbol)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text("\(item.type.label) · \(Formatters.shortDate.string(from: item.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: Theme.controlHeight)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
        .navigationTitle("Posteingang")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { QuickCaptureButton(compactOnly: true) }
            ToolbarItem(placement: .topBarTrailing) { AccountButton() }
        }
        .task(id: model.captureCount) { await load() }
    }

    private func chip(_ label: String, count: Int, type: InboxItem.ItemType?) -> some View {
        let isOn = filter == type
        return Button { filter = type } label: {
            HStack(spacing: 6) {
                Text(label)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? Theme.brand.opacity(0.14) : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        do {
            state = .loaded(try await model.service.inbox().data.all)
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

extension InboxItem.ItemType {
    var label: String {
        switch self {
        case .note: "Notiz"
        case .task: "Aufgabe"
        case .resource: "Ressource"
        case .session: "Sitzung"
        }
    }

    var symbol: String {
        switch self {
        case .note: "note.text"
        case .task: "checkmark.circle"
        case .resource: "doc"
        case .session: "person.2"
        }
    }
}
