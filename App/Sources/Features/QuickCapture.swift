import LifeOSKit
import SwiftUI

/// The "+" of design variant A + D: catch a task or a note from anywhere
/// in a few taps. New entries land in the inbox to be filed later.
struct QuickCaptureButton: View {
    /// ⌘N belongs to one button per window: the sidebar's on iPad and Mac.
    var withShortcut = false
    /// Screens inside the iPhone tab bar show their own "+"; on iPad and Mac the sidebar has it.
    var compactOnly = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSheet = false

    var body: some View {
        if compactOnly && sizeClass == .regular {
            EmptyView()
        } else {
            capture
        }
    }

    @ViewBuilder private var capture: some View {
        let button = Button { showSheet = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            .accessibilityLabel("Schnell erfassen")
            .sheet(isPresented: $showSheet) { QuickCaptureSheet() }
        if withShortcut {
            button.keyboardShortcut("n", modifiers: .command)
        } else {
            button
        }
    }
}

struct QuickCaptureSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case task = "Aufgabe"
        case note = "Notiz"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .task
    @State private var title = ""
    @State private var noteText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var error: String?
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBody: String { noteText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !saving && (kind == .task ? !trimmedTitle.isEmpty : !(trimmedTitle.isEmpty && trimmedBody.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Art", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                TextField(kind == .task ? "Was ist zu tun?" : "Titel (optional)", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { if canSave { Task { await save() } } }

                if kind == .task {
                    Toggle("Fälligkeitsdatum", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                } else {
                    TextField("Notiz", text: $noteText, axis: .vertical)
                        .lineLimit(4...10)
                }

                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Schnell erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }.disabled(!canSave)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            switch kind {
            case .task:
                _ = try await model.service.createTask(NewTask(title: trimmedTitle, dueDate: hasDueDate ? Formatters.local(dueDate) : nil))
            case .note:
                _ = try await model.service.createNote(NewNote(title: trimmedTitle.isEmpty ? nil : trimmedTitle, body: trimmedBody))
            }
            model.captureCount += 1
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}
