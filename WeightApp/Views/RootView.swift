import SwiftUI

/// 起動後の画面の振り分け(01-design.md 0.)。
struct RootView: View {
    let model: HomeModel

    var body: some View {
        switch RootRoute.route(for: model) {
        case .unavailable:
            UnavailableView(kind: model.unavailableReason == .planStore ? .planStore : .healthKit)
        case .loading:
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ProgressView()
            }
        case .failed:
            UnavailableView(kind: .firstReadFailed)
        case .setup:
            SetupView(model: model)
        case .home:
            MainTabView(model: model)
        }
    }
}

/// ホーム / ロードマップ / レポートのタブ。
struct MainTabView: View {
    enum Selection: Hashable { case home, roadmap, reports }

    let model: HomeModel
    @State private var selection: Selection = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("ホーム", systemImage: "house", value: .home) {
                HomeScreen(model: model) { selection = .reports }
            }
            Tab("ロードマップ", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: .roadmap) {
                RoadmapScreen(model: model)
            }
            Tab("レポート", systemImage: "doc.text", value: .reports) {
                ReportScreen(model: model)
            }
        }
        .tint(AppTheme.accent)
    }
}

/// 使えない・失敗したときの画面。文言だけで、色で警告しない。
struct UnavailableView: View {
    enum Kind {
        case healthKit, planStore, firstReadFailed

        var text: String {
            switch self {
            case .healthKit: "この端末ではヘルスケアが使えないため、体重を読み取れません。"
            case .planStore: "計画の保存先を用意できませんでした。App Group の設定を確認してください。"
            case .firstReadFailed: "ヘルスケアから体重を読み取れませんでした。もう一度開いてみてください。"
            }
        }
    }

    let kind: Kind

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Text(kind.text)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(32)
        }
    }
}

#Preview("ヘルスケアが使えない") {
    UnavailableView(kind: .healthKit)
}

#Preview("保存先が取れない") {
    UnavailableView(kind: .planStore)
}

#Preview("最初の読み取りに失敗") {
    UnavailableView(kind: .firstReadFailed)
}

#Preview("起動の振り分け: 読み込み中") {
    RootView(model: PreviewData.loadingModel())
}
