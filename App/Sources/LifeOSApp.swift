import LifeOSKit
import SwiftUI

@main
struct LifeOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.brand)
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
