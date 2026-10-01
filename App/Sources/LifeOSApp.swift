import LifeOSKit
import SwiftUI

@main
struct LifeOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            // vault apps lock as soon as the app leaves the foreground
            if phase == .background {
                Task { await model.vault.lockAll() }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .task { await model.start() }
    }
}
