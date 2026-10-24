import SwiftUI

@main
struct WeightApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(refreshToken)
        }
        .onChange(of: scenePhase) { _, phase in
            // フォアグラウンドに戻ったら取り直す(HealthPlanet を開いた後にこのアプリを開く運用のため)
            if phase == .active { refreshToken += 1 }
        }
    }

    @State private var refreshToken = 0
}
