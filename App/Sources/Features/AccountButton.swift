import SwiftUI

/// Avatar button for the toolbar that opens the account sheet.
struct AccountButton: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Text(initials)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.brand))
        }
        .accessibilityLabel("Konto und Einstellungen")
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var initials: String {
        let name = model.user?.displayName ?? "?"
        return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
