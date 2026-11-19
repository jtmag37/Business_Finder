import SwiftUI

@main
struct CitySprintApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.onLaunch() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.onBackground() }
        }
    }
}
