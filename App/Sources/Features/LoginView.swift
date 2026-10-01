import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.brand.gradient)
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        Text("Life OS")
                            .font(.largeTitle.bold())
                        Text("Studium, Aufgaben, Kalender, Gesundheit und Finanzen in einer App.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server")
                            .font(.subheadline.weight(.semibold))
                        TextField("https://lifeos.example.de", text: $model.serverURLString)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: Theme.controlHeight)
                            .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Color(.secondarySystemBackground)))
                    }

                    if let error = model.loginError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await model.signIn() }
                        } label: {
                            HStack {
                                if model.isSigningIn { ProgressView().tint(.white) }
                                Text("Anmelden")
                            }
                            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSigningIn)

                        Button {
                            Task { await model.enterDemo() }
                        } label: {
                            Text("Demo ohne Server ansehen")
                                .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Die Anmeldung läuft über das Anmeldefenster des Systems, mit deinem Passkey beim Life-OS-Login.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}
