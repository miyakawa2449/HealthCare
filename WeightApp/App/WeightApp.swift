import SwiftUI

@main
struct WeightApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 起動時とフォアグラウンド復帰時に取り直す(HealthPlanet を開いた後にこのアプリを開く運用のため)。
            // モデルは作り直さないので、失敗しても前回の値が残る
            if phase == .active { Task { await model.refresh() } }
        }
    }
}
