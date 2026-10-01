import LifeOSKit
import SwiftUI

/// Agenda for one month with filter chips per source (Study Hub, each
/// subscription, Aufgaben), like the web calendar.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var state: Loadable<[CalendarEvent]> = .loading
    @State private var hiddenSources: Set<String> = []
    @State private var selected: CalendarEvent?

    var body: some View {
        AsyncContent(state: state, retry: load) { events in
            let sources = Self.sources(in: events)
            let visible = events.filter { !hiddenSources.contains($0.source.key) }
            let days = Self.groupByDay(visible)

            List {
                if sources.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sources, id: \.key) { source in
                                SourceChip(
                                    source: source,
                                    count: events.filter { $0.source.key == source.key }.count,
                                    isOn: !hiddenSources.contains(source.key)
                                ) {
                                    if hiddenSources.contains(source.key) { hiddenSources.remove(source.key) } else { hiddenSources.insert(source.key) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if days.isEmpty {
                    ContentUnavailableView("Keine Termine", systemImage: "calendar", description: Text("In diesem Monat steht nichts an."))
                        .listRowBackground(Color.clear)
                }

                ForEach(days, id: \.day) { group in
                    Section(Formatters.dayHeader.string(from: group.day)) {
                        ForEach(group.events) { event in
                            Button { selected = event } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Voriger Monat")
                Button("Heute") { month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date() }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Nächster Monat")
            }
        }
        .sheet(item: $selected) { EventDetailSheet(event: $0) }
        .task(id: month) { await load() }
    }

    private func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }

    private func load() async {
        let comps = Calendar.current.dateComponents([.year, .month], from: month)
        let key = String(format: "%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
        do {
            let response = try await model.service.calendar(month: key)
            state = .loaded(response.data.filter { Calendar.current.isDate($0.startAt, equalTo: month, toGranularity: .month) })
        } catch {
            state = .failed(error.userMessage)
        }
    }

    static func sources(in events: [CalendarEvent]) -> [CalendarEvent.Source] {
        var seen = Set<String>()
        return events.compactMap { seen.insert($0.source.key).inserted ? $0.source : nil }
    }

    struct DayGroup { let day: Date; let events: [CalendarEvent] }

    static func groupByDay(_ events: [CalendarEvent]) -> [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startAt) }
        return grouped.keys.sorted().map { day in
            DayGroup(day: day, events: grouped[day]!.sorted { ($0.isAllDay ? 0 : 1, $0.startAt) < ($1.isAllDay ? 0 : 1, $1.startAt) })
        }
    }
}

extension CalendarEvent.Source {
    var color: Color {
        switch kind {
        case "study": Theme.brand
        case "tasks": .orange
        default: Color(hex: AppModuleStyle.Accent.teal.hex)
        }
    }
}

struct SourceChip: View {
    let source: CalendarEvent.Source
    let count: Int
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle().fill(source.color).frame(width: 8, height: 8)
                Text(source.label)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? source.color.opacity(0.14) : Color(.tertiarySystemFill)))
            .opacity(isOn ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.isAllDay ? "ganztägig" : Formatters.time.string(from: event.startAt))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if event.type == "task" {
                        Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.orange)
                    }
                    Text(event.title).strikethrough(event.isCompleted)
                }
                Text([event.module?.name, event.room, event.source.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accentBar(Color(hexString: event.module?.color) ?? event.source.color)
    }
}

struct EventDetailSheet: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Datum", value: Formatters.dayHeader.string(from: event.startAt))
                if !event.isAllDay {
                    LabeledContent("Uhrzeit", value: "\(Formatters.time.string(from: event.startAt)) – \(Formatters.time.string(from: event.endAt))")
                }
                LabeledContent("Quelle", value: event.source.label)
                if let type = event.sessionType.flatMap(SessionType.init(rawValue:)) {
                    LabeledContent("Art", value: type.label)
                }
                if let module = event.module { LabeledContent("Modul", value: module.name) }
                if let room = event.room { LabeledContent("Raum", value: room) }
                if let priority = event.priority.flatMap(TaskPriority.init(rawValue:)) {
                    LabeledContent("Priorität", value: priority.label)
                }
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
